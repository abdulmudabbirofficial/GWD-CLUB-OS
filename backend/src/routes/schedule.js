'use strict';

const express = require('express');
const { ObjectId } = require('mongodb');
const { col, C } = require('../db');
const { authenticate, requireApproved, fail } = require('../auth');
const {
  canCreateScheduleEntry, canEditSchedule, isSupervisor, taskVisibilityFilter,
} = require('../permissions');
const { audit } = require('../services/notify');
const { ensureSeeded } = require('./categories');

const router = express.Router();
router.use(authenticate, requireApproved);

const oid = (value, name) => {
  if (!ObjectId.isValid(value)) fail(`${name} is not valid.`);
  return new ObjectId(value);
};

/**
 * The club schedule.
 *
 * Entries carry a **category** rather than one of a few hardcoded kinds —
 * categories are managed data (see routes/categories.js), so a club can add
 * "Shoot", "Sponsor visit" or "Exam break" without a release.
 *
 * The one built-in, non-category lane is `deadline`, which is *derived* from
 * tasks with a due date. It is never written directly, so the task list and the
 * calendar can never drift apart.
 *
 * Reading is open to every approved member on purpose: the single most common
 * complaint about running a club is not knowing what is happening.
 */

const MARKETING_PLATFORMS = ['instagram', 'linkedin', 'youtube', 'x', 'whatsapp', 'other'];
const MARKETING_FORMATS = ['post', 'reel', 'story', 'carousel', 'video', 'article'];
const MARKETING_STAGES = ['planned', 'inProduction', 'ready', 'published'];

function serialise(entry, { names, categories } = {}) {
  const category = categories?.get(String(entry.categoryId));
  return {
    id: String(entry._id),
    kind: 'entry',
    categoryId: entry.categoryId ? String(entry.categoryId) : null,
    categoryName: category?.name ?? 'Entry',
    categoryIcon: category?.icon ?? 'flag',
    categoryColor: category?.color ?? '#DC2626',
    title: entry.title,
    description: entry.description ?? '',
    date: entry.date,
    endDate: entry.endDate ?? null,
    location: entry.location ?? '',
    meetingUrl: entry.meetingUrl ?? '',
    departmentId: entry.departmentId ? String(entry.departmentId) : null,
    createdBy: entry.createdBy ? String(entry.createdBy) : null,
    createdByName: names?.get(String(entry.createdBy)) ?? null,
    rsvps: (entry.rsvps ?? []).map(String),
    platform: entry.platform ?? null,
    format: entry.format ?? null,
    stage: entry.stage ?? null,
  };
}

/** A task with a due date, rendered as a schedule entry. */
function deadlineFromTask(task, names) {
  return {
    id: `task:${task._id}`,
    kind: 'deadline',
    categoryId: null,
    categoryName: 'Deadline',
    categoryIcon: 'deadline',
    categoryColor: '#B45309',
    title: task.title,
    description: task.description ?? '',
    date: task.dueDate,
    endDate: null,
    location: '',
    meetingUrl: '',
    departmentId: task.departmentId ? String(task.departmentId) : null,
    createdBy: task.assignedBy ? String(task.assignedBy) : null,
    createdByName: names?.get(String(task.assignedBy)) ?? null,
    // Whose deadline this actually is. The client needs it to answer "what do
    // *I* owe" without a second round trip — and a deadline with no name on it
    // reads as everybody's, which is how it becomes nobody's.
    assignedTo: task.assignedTo ? String(task.assignedTo) : null,
    assignedToName: task.assignedTo ? (names?.get(String(task.assignedTo)) ?? null) : null,
    rsvps: [],
    platform: null,
    format: null,
    stage: null,
    taskId: String(task._id),
    taskStatus: task.status,
    ownerName: names?.get(String(task.assignedTo)) ?? null,
  };
}

async function nameMap(ids) {
  const unique = [...new Set(ids.filter(Boolean).map(String))]
    .filter((id) => ObjectId.isValid(id))
    .map((id) => new ObjectId(id));
  if (unique.length === 0) return new Map();
  const users = await col(C.users)
    .find({ _id: { $in: unique } }, { projection: { name: 1 } })
    .toArray();
  return new Map(users.map((u) => [String(u._id), u.name]));
}

async function categoryMap() {
  await ensureSeeded();
  const categories = await col(C.scheduleCategories).find({}).toArray();
  return new Map(categories.map((c) => [String(c._id), c]));
}

router.get('/', async (request, response, next) => {
  try {
    const user = request.user;
    const categories = await categoryMap();

    const filter = {};
    if (request.query.categoryId && ObjectId.isValid(request.query.categoryId)) {
      filter.categoryId = new ObjectId(request.query.categoryId);
    }
    if (request.query.from || request.query.to) {
      filter.date = {};
      if (request.query.from) filter.date.$gte = new Date(request.query.from);
      if (request.query.to) filter.date.$lte = new Date(request.query.to);
    }

    // `?mine=1` — the personal calendar.
    //
    // The club schedule stays open to everyone, because the commonest complaint
    // about running a club is not knowing what is happening. But "what is the
    // club doing" and "what do *I* owe, and by when" are different questions,
    // and answering the second by making somebody scan the first is how
    // deadlines get missed. This is the same data, narrowed to the person
    // asking: the work assigned to them, and the things they said they would
    // be at.
    const mine = request.query.mine === '1' || request.query.mine === 'true';

    const wantsDeadlines = request.query.categoryId === 'deadline'
      || (!request.query.categoryId);

    const entryFilter = { ...filter };
    if (mine) {
      // Only what this person actually put their hand up for. A club-wide
      // entry they have not RSVP'd to is not on their calendar.
      entryFilter.rsvps = user._id;
    }

    const entries = request.query.categoryId === 'deadline'
      ? []
      : await col(C.calendarEvents).find(entryFilter).sort({ date: 1 }).limit(600).toArray();

    let deadlines = [];
    if (wantsDeadlines) {
      const taskFilter = {
        $and: [
          // Narrowing to `assignedTo` still sits inside the visibility filter
          // rather than replacing it — a scope parameter must never be able to
          // widen what somebody can see.
          mine ? { assignedTo: user._id } : taskVisibilityFilter(user),
          { dueDate: { $ne: null } },
          { status: { $nin: ['completed', 'cancelled'] } },
        ],
      };
      if (filter.date) taskFilter.$and.push({ dueDate: filter.date });
      deadlines = await col(C.tasks).find(taskFilter).sort({ dueDate: 1 }).limit(300).toArray();
    }

    const names = await nameMap([
      ...entries.map((e) => e.createdBy),
      ...deadlines.flatMap((t) => [t.assignedBy, t.assignedTo]),
    ]);

    response.json({
      entries: [
        ...entries.map((e) => serialise(e, { names, categories })),
        ...deadlines.map((t) => deadlineFromTask(t, names)),
      ],
      canEdit: canEditSchedule(user.role),
      canCreate: canCreateScheduleEntry(user.role),
    });
  } catch (error) {
    next(error);
  }
});

router.get('/:id', async (request, response, next) => {
  try {
    const entry = await col(C.calendarEvents).findOne({ _id: oid(request.params.id, 'Entry id') });
    if (!entry) fail('That entry no longer exists.', 404);
    const categories = await categoryMap();
    const names = await nameMap([entry.createdBy, ...(entry.rsvps ?? [])]);
    const attendees = (entry.rsvps ?? []).map((id) => ({
      id: String(id),
      name: names.get(String(id)) ?? 'Member',
    }));
    response.json({
      entry: serialise(entry, { names, categories }),
      attendees,
      canEdit: canCreateScheduleEntry(request.user.role),
    });
  } catch (error) {
    next(error);
  }
});

function readBody(request, { partial = false } = {}) {
  const body = request.body ?? {};
  const out = {};

  if (!partial || body.title !== undefined) {
    const title = typeof body.title === 'string' ? body.title.trim() : '';
    if (title.length < 2) fail('Give it a title.');
    out.title = title.slice(0, 200);
  }
  if (!partial || body.date !== undefined) {
    const date = new Date(body.date);
    if (Number.isNaN(date.getTime())) fail('Give it a valid date.');
    out.date = date;
  }
  if (body.endDate !== undefined) out.endDate = body.endDate ? new Date(body.endDate) : null;
  for (const key of ['description', 'location', 'meetingUrl']) {
    if (body[key] !== undefined) out[key] = String(body[key] ?? '').trim().slice(0, 2000);
  }
  if (MARKETING_PLATFORMS.includes(body.platform)) out.platform = body.platform;
  if (MARKETING_FORMATS.includes(body.format)) out.format = body.format;
  if (MARKETING_STAGES.includes(body.stage)) out.stage = body.stage;
  return out;
}

router.post('/', async (request, response, next) => {
  try {
    if (!canCreateScheduleEntry(request.user.role)) {
      fail('You do not have permission to add to the schedule.', 403);
    }
    const categoryId = oid(request.body.categoryId, 'Category');
    const category = await col(C.scheduleCategories).findOne({ _id: categoryId });
    if (!category) fail('Pick a category that exists.');
    if (category.active === false) fail('That category is no longer in use.');

    const doc = {
      categoryId,
      ...readBody(request),
      departmentId: request.user.role === 'clubLead' ? request.user.departmentId : null,
      createdBy: request.user._id,
      rsvps: [],
      createdAt: new Date(),
    };

    const inserted = await col(C.calendarEvents).insertOne(doc);
    doc._id = inserted.insertedId;
    await audit(request.user._id, 'schedule.create', { category: category.name, title: doc.title });

    const categories = await categoryMap();
    response.status(201).json({ entry: serialise(doc, { categories }) });
  } catch (error) {
    next(error);
  }
});

router.patch('/:id', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Entry id');
    const existing = await col(C.calendarEvents).findOne({ _id: id });
    if (!existing) fail('That entry no longer exists.', 404);

    const isOwner = String(existing.createdBy) === String(request.user._id);
    if (!canCreateScheduleEntry(request.user.role) && !isOwner) {
      fail('You do not have permission to change this.', 403);
    }

    const update = readBody(request, { partial: true });
    if (request.body.categoryId && ObjectId.isValid(request.body.categoryId)) {
      update.categoryId = new ObjectId(request.body.categoryId);
    }
    if (Object.keys(update).length === 0) fail('Nothing to change.');

    const updated = await col(C.calendarEvents).findOneAndUpdate(
      { _id: id }, { $set: update }, { returnDocument: 'after' },
    );
    const categories = await categoryMap();
    const names = await nameMap([updated.createdBy]);
    response.json({ entry: serialise(updated, { names, categories }) });
  } catch (error) {
    next(error);
  }
});

router.delete('/:id', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Entry id');
    const existing = await col(C.calendarEvents).findOne({ _id: id });
    if (!existing) fail('That entry no longer exists.', 404);
    const isOwner = String(existing.createdBy) === String(request.user._id);
    if (!isOwner && !isSupervisor(request.user.role)
        && !canCreateScheduleEntry(request.user.role)) {
      fail('You do not have permission to remove this.', 403);
    }
    await col(C.calendarEvents).deleteOne({ _id: id });
    await audit(request.user._id, 'schedule.delete', { id: String(id) });
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

router.post('/:id/rsvp', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Entry id');
    const going = request.body.going !== false;
    const updated = await col(C.calendarEvents).findOneAndUpdate(
      { _id: id },
      going ? { $addToSet: { rsvps: request.user._id } } : { $pull: { rsvps: request.user._id } },
      { returnDocument: 'after' },
    );
    if (!updated) fail('That entry no longer exists.', 404);
    const categories = await categoryMap();
    const names = await nameMap([updated.createdBy]);
    response.json({ entry: serialise(updated, { names, categories }) });
  } catch (error) {
    next(error);
  }
});

module.exports = router;

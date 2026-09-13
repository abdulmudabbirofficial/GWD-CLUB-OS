'use strict';

const express = require('express');
const { ObjectId } = require('mongodb');
const config = require('../config');
const { col, C } = require('../db');
const { authenticate, requireApproved, fail } = require('../auth');
const {
  EVENT_STATUSES, canCreateEvent, canManageEvent, canManageEventDepartment,
} = require('../permissions');
const { notify, audit } = require('../services/notify');

const router = express.Router();
router.use(authenticate, requireApproved);

/**
 * Events.
 *
 * An event is a *project*, not a calendar entry: it has a lead, an organising
 * department, supporting departments, a team, a set of per-department
 * responsibilities, the tasks under those, and its official paperwork.
 *
 * Deliberately separate from `calendarEvents`, which stays what it always was —
 * a date and a title on the schedule. Merging the two would either bloat every
 * schedule row with fields it never uses, or force a real event through a model
 * that cannot hold it.
 *
 * Reading is open to every approved member: the whole point is that anyone can
 * see what the club is doing. Writing is scoped (see permissions.js).
 */

const oid = (value, name) => {
  if (!ObjectId.isValid(value)) fail(`${name} is not valid.`);
  return new ObjectId(value);
};

const maybeOid = (value) => (value && ObjectId.isValid(value) ? new ObjectId(value) : null);

function text(value, name, { min = 1, max = 2000 } = {}) {
  if (typeof value !== 'string' || value.trim().length < min) fail(`${name} is required.`);
  return value.trim().slice(0, max);
}

/** Colours an event's banner when there is no image. Stable per event. */
const BANNERS = ['#DC2626', '#7C3AED', '#0891B2', '#B45309', '#15803D', '#4338CA', '#BE123C'];
function bannerFor(seed) {
  let hash = 0;
  for (let i = 0; i < seed.length; i += 1) hash = (hash * 31 + seed.charCodeAt(i)) >>> 0;
  return BANNERS[hash % BANNERS.length];
}

function serialiseEvent(event, extra = {}) {
  return {
    id: String(event._id),
    name: event.name,
    description: event.description ?? '',
    type: event.type ?? 'event',
    date: event.date,
    startTime: event.startTime ?? '',
    endTime: event.endTime ?? '',
    venue: event.venue ?? '',
    status: event.status ?? 'planning',
    banner: event.banner ?? bannerFor(String(event._id)),
    organizingDepartmentId: event.organizingDepartmentId
      ? String(event.organizingDepartmentId) : null,
    leadUserId: event.leadUserId ? String(event.leadUserId) : null,
    supportingDepartmentIds: (event.supportingDepartmentIds ?? []).map(String),
    teamUserIds: (event.teamUserIds ?? []).map(String),
    speakerName: event.speakerName ?? '',
    guestDetails: event.guestDetails ?? '',
    externalOrganisation: event.externalOrganisation ?? '',
    createdBy: event.createdBy ? String(event.createdBy) : null,
    createdAt: event.createdAt,
    updatedAt: event.updatedAt,
    ...extra,
  };
}

/** Task counts per event, in one aggregate rather than a query per card. */
async function progressByEvent(eventIds) {
  if (eventIds.length === 0) return new Map();
  const rows = await col(C.tasks).aggregate([
    { $match: { eventId: { $in: eventIds }, status: { $ne: 'cancelled' } } },
    {
      $group: {
        _id: '$eventId',
        total: { $sum: 1 },
        done: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] } },
      },
    },
  ]).toArray();
  return new Map(rows.map((r) => [String(r._id), r]));
}

const rate = (done, total) => (total === 0 ? 0 : Math.round((done / total) * 100));

/* ---------------------------------------------------------------- listing */

router.get('/', async (request, response, next) => {
  try {
    const events = await col(C.events)
      .find(request.query.includeCancelled === 'true' ? {} : { status: { $ne: 'cancelled' } })
      .sort({ date: 1 })
      .limit(300)
      .toArray();

    const progress = await progressByEvent(events.map((e) => e._id));
    const [departments, people] = await Promise.all([
      col(C.departments).find({}, { projection: { name: 1 } }).toArray(),
      col(C.users).find({}, { projection: { name: 1 } }).toArray(),
    ]);
    const deptName = new Map(departments.map((d) => [String(d._id), d.name]));
    const userName = new Map(people.map((p) => [String(p._id), p.name]));

    const decorated = events.map((e) => {
      const p = progress.get(String(e._id)) ?? { total: 0, done: 0 };
      return serialiseEvent(e, {
        organizingDepartmentName: deptName.get(String(e.organizingDepartmentId)) ?? null,
        leadName: userName.get(String(e.leadUserId)) ?? null,
        taskCount: p.total,
        taskCompleted: p.done,
        progress: rate(p.done, p.total),
      });
    });

    // Grouped the way the Events page reads them, so the client does not have
    // to re-derive "ongoing" from dates and statuses.
    const now = new Date();
    const isOngoing = (e) =>
      e.status === 'ongoing'
      || (e.status === 'approved' && new Date(e.date).toDateString() === now.toDateString());

    response.json({
      upcoming: decorated.filter(
        (e) => !isOngoing(e) && e.status !== 'completed' && new Date(e.date) >= now,
      ),
      ongoing: decorated.filter(isOngoing),
      completed: decorated
        .filter((e) => e.status === 'completed'
          || (e.status !== 'cancelled' && new Date(e.date) < now && !isOngoing(e)))
        .sort((a, b) => new Date(b.date) - new Date(a.date)),
      canCreate: canCreateEvent(request.user.role),
    });
  } catch (error) {
    next(error);
  }
});

/* --------------------------------------------------------------- creation */

/**
 * Create an event, its team, its department responsibilities and their opening
 * tasks in one call.
 *
 * The wizard collects all of it before committing, so splitting this into five
 * round trips would mean a half-made event sitting in the database whenever
 * somebody backs out at step four.
 */
router.post('/', async (request, response, next) => {
  try {
    const actor = request.user;
    if (!canCreateEvent(actor.role)) fail('Your role cannot create events.', 403);

    const name = text(request.body.name, 'Event name', { min: 2, max: 160 });
    const date = new Date(request.body.date);
    if (Number.isNaN(date.getTime())) fail('Give the event a valid date.');

    const status = EVENT_STATUSES.includes(request.body.status)
      && ['draft', 'planning'].includes(request.body.status)
      ? request.body.status
      : 'planning';

    const organizingDepartmentId = maybeOid(request.body.organizingDepartmentId);
    if (!organizingDepartmentId) fail('Choose an organising department.');
    const leadUserId = maybeOid(request.body.leadUserId) ?? actor._id;

    const now = new Date();
    const event = {
      name,
      description: typeof request.body.description === 'string'
        ? request.body.description.trim().slice(0, 4000) : '',
      type: typeof request.body.type === 'string' ? request.body.type.trim().slice(0, 60) : 'event',
      date,
      startTime: typeof request.body.startTime === 'string' ? request.body.startTime.slice(0, 10) : '',
      endTime: typeof request.body.endTime === 'string' ? request.body.endTime.slice(0, 10) : '',
      venue: typeof request.body.venue === 'string' ? request.body.venue.trim().slice(0, 200) : '',
      status,
      organizingDepartmentId,
      leadUserId,
      supportingDepartmentIds: (request.body.supportingDepartmentIds ?? [])
        .map(maybeOid).filter(Boolean),
      teamUserIds: (request.body.teamUserIds ?? []).map(maybeOid).filter(Boolean),
      speakerName: typeof request.body.speakerName === 'string'
        ? request.body.speakerName.trim().slice(0, 160) : '',
      guestDetails: typeof request.body.guestDetails === 'string'
        ? request.body.guestDetails.trim().slice(0, 1000) : '',
      externalOrganisation: typeof request.body.externalOrganisation === 'string'
        ? request.body.externalOrganisation.trim().slice(0, 160) : '',
      createdBy: actor._id,
      createdAt: now,
      updatedAt: now,
    };
    const inserted = await col(C.events).insertOne(event);
    event._id = inserted.insertedId;
    await col(C.events).updateOne(
      { _id: event._id },
      { $set: { banner: bannerFor(String(event._id)) } },
    );

    // --- responsibilities and their opening tasks --------------------------
    const responsibilities = Array.isArray(request.body.responsibilities)
      ? request.body.responsibilities : [];
    let taskCount = 0;

    for (const entry of responsibilities) {
      const departmentId = maybeOid(entry.departmentId);
      if (!departmentId) continue;

      await col(C.eventResponsibilities).updateOne(
        { eventId: event._id, departmentId },
        {
          $set: { notes: typeof entry.notes === 'string' ? entry.notes.trim().slice(0, 500) : '' },
          $setOnInsert: { eventId: event._id, departmentId, createdBy: actor._id, createdAt: now },
        },
        { upsert: true },
      );

      const tasks = Array.isArray(entry.tasks) ? entry.tasks : [];
      const docs = [];
      for (const t of tasks) {
        const title = typeof t.title === 'string' ? t.title.trim() : '';
        if (title.length < 2) continue;
        const due = t.dueDate ? new Date(t.dueDate) : null;
        docs.push({
          title: title.slice(0, 200),
          description: typeof t.description === 'string' ? t.description.trim().slice(0, 2000) : '',
          eventId: event._id,
          departmentId,
          // Unassigned is a legitimate state here: the wizard captures *what*
          // needs doing; the department Lead decides who later.
          assignedTo: maybeOid(t.assignedTo),
          assignedBy: actor._id,
          status: 'pending',
          dueDate: due && !Number.isNaN(due.getTime()) ? due : null,
          points: config.pointsPerTask,
          priority: ['low', 'normal', 'high'].includes(t.priority) ? t.priority : 'normal',
          createdAt: now,
          updatedAt: now,
          completedAt: null,
        });
      }
      if (docs.length > 0) {
        await col(C.tasks).insertMany(docs);
        taskCount += docs.length;
        // Tell the people who actually got something.
        const assignees = docs.map((d) => d.assignedTo).filter(Boolean);
        for (const who of assignees) {
          if (String(who) === String(actor._id)) continue;
          await notify(who, 'taskAssigned', { taskTitle: name, byName: actor.name });
        }
      }
    }

    // Everyone on the team should know the event exists.
    const audience = [...new Set([
      ...event.teamUserIds.map(String),
      String(event.leadUserId),
    ])].filter((id) => id !== String(actor._id));
    if (audience.length > 0) {
      await notify(audience.map((id) => new ObjectId(id)), 'eventCreated', {
        eventTitle: name, byName: actor.name,
      });
    }

    await audit(actor._id, 'event.create', {
      eventId: String(event._id), name, departments: responsibilities.length, tasks: taskCount,
    });

    response.status(201).json({
      event: serialiseEvent({ ...event, banner: bannerFor(String(event._id)) }, {
        taskCount, taskCompleted: 0, progress: 0,
      }),
    });
  } catch (error) {
    next(error);
  }
});

/* -------------------------------------------------------------- workspace */

/** Everything the event Overview tab needs, in one request. */
router.get('/:id', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const event = await col(C.events).findOne({ _id: id });
    if (!event) fail('That event no longer exists.', 404);

    const [tasks, responsibilities, documents, departments, people] = await Promise.all([
      col(C.tasks).find({ eventId: id, status: { $ne: 'cancelled' } }).toArray(),
      col(C.eventResponsibilities).find({ eventId: id }).toArray(),
      col(C.eventDocuments).find({ eventId: id }).toArray(),
      col(C.departments).find({}, { projection: { name: 1 } }).toArray(),
      col(C.users).find({}, { projection: { name: 1, avatarColor: 1, role: 1 } }).toArray(),
    ]);

    const deptName = new Map(departments.map((d) => [String(d._id), d.name]));
    const userById = new Map(people.map((p) => [String(p._id), p]));
    const done = tasks.filter((t) => t.status === 'completed').length;

    // Per-department progress, which is the honest unit here: this is the
    // event's work, not a comparison between people.
    const byDepartment = new Map();
    for (const r of responsibilities) {
      byDepartment.set(String(r.departmentId), {
        departmentId: String(r.departmentId),
        name: deptName.get(String(r.departmentId)) ?? 'Department',
        notes: r.notes ?? '',
        total: 0,
        done: 0,
      });
    }
    for (const t of tasks) {
      const key = String(t.departmentId);
      if (!byDepartment.has(key)) {
        byDepartment.set(key, {
          departmentId: key,
          name: deptName.get(key) ?? 'Department',
          notes: '',
          total: 0,
          done: 0,
        });
      }
      const bucket = byDepartment.get(key);
      bucket.total += 1;
      if (t.status === 'completed') bucket.done += 1;
    }

    const now = new Date();
    const upcomingDeadlines = tasks
      .filter((t) => t.dueDate && t.status !== 'completed')
      .sort((a, b) => new Date(a.dueDate) - new Date(b.dueDate))
      .slice(0, 5)
      .map((t) => ({
        id: String(t._id),
        title: t.title,
        dueDate: t.dueDate,
        departmentName: deptName.get(String(t.departmentId)) ?? null,
        overdue: new Date(t.dueDate) < now,
      }));

    const approvals = documents.filter((d) => d.kind === 'approval');

    response.json({
      event: serialiseEvent(event, {
        organizingDepartmentName: deptName.get(String(event.organizingDepartmentId)) ?? null,
        leadName: userById.get(String(event.leadUserId))?.name ?? null,
        taskCount: tasks.length,
        taskCompleted: done,
        progress: rate(done, tasks.length),
      }),
      team: [...new Set([
        String(event.leadUserId),
        ...(event.teamUserIds ?? []).map(String),
      ])].filter(Boolean).map((uid) => {
        const u = userById.get(uid);
        return {
          id: uid,
          name: u?.name ?? 'Member',
          role: u?.role ?? 'clubMember',
          avatarColor: u?.avatarColor ?? null,
          isLead: uid === String(event.leadUserId),
        };
      }),
      departments: [...byDepartment.values()].map((d) => ({
        ...d,
        progress: rate(d.done, d.total),
      })),
      upcomingDeadlines,
      documents: {
        total: documents.length,
        approvalsApproved: approvals.filter((d) => d.status === 'approved').length,
        approvalsPending: approvals.filter((d) => d.status === 'pending').length,
      },
      canManage: canManageEvent(request.user, event),
    });
  } catch (error) {
    next(error);
  }
});

/* ------------------------------------------------------------------- work */

/** The Kanban board for one event. */
router.get('/:id/work', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const filter = { eventId: id, status: { $ne: 'cancelled' } };
    if (request.query.departmentId && ObjectId.isValid(request.query.departmentId)) {
      filter.departmentId = new ObjectId(request.query.departmentId);
    }

    const tasks = await col(C.tasks).find(filter).sort({ dueDate: 1, createdAt: 1 }).toArray();
    const [departments, people, commentCounts] = await Promise.all([
      col(C.departments).find({}, { projection: { name: 1 } }).toArray(),
      col(C.users).find({}, { projection: { name: 1, avatarColor: 1 } }).toArray(),
      col(C.comments).aggregate([
        { $match: { taskId: { $in: tasks.map((t) => t._id) } } },
        { $group: { _id: '$taskId', n: { $sum: 1 } } },
      ]).toArray(),
    ]);
    const deptName = new Map(departments.map((d) => [String(d._id), d.name]));
    const userById = new Map(people.map((p) => [String(p._id), p]));
    const comments = new Map(commentCounts.map((c) => [String(c._id), c.n]));

    response.json({
      tasks: tasks.map((t) => ({
        id: String(t._id),
        title: t.title,
        description: t.description ?? '',
        status: t.status,
        departmentId: t.departmentId ? String(t.departmentId) : null,
        departmentName: deptName.get(String(t.departmentId)) ?? null,
        assignedTo: t.assignedTo ? String(t.assignedTo) : null,
        assigneeName: userById.get(String(t.assignedTo))?.name ?? null,
        assigneeColor: userById.get(String(t.assignedTo))?.avatarColor ?? null,
        dueDate: t.dueDate ?? null,
        priority: t.priority ?? 'normal',
        commentCount: comments.get(String(t._id)) ?? 0,
      })),
    });
  } catch (error) {
    next(error);
  }
});

/** Add a task to one department's responsibilities. */
router.post('/:id/tasks', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const event = await col(C.events).findOne({ _id: id });
    if (!event) fail('That event no longer exists.', 404);

    const departmentId = oid(request.body.departmentId, 'Department');
    if (!canManageEventDepartment(request.user, event, departmentId)) {
      fail('You can only add work to your own department on this event.', 403);
    }

    const title = text(request.body.title, 'Task title', { min: 2, max: 200 });
    const due = request.body.dueDate ? new Date(request.body.dueDate) : null;
    if (due && Number.isNaN(due.getTime())) fail('Give the task a valid due date.');

    const now = new Date();
    const task = {
      title,
      description: typeof request.body.description === 'string'
        ? request.body.description.trim().slice(0, 2000) : '',
      eventId: id,
      departmentId,
      assignedTo: maybeOid(request.body.assignedTo),
      assignedBy: request.user._id,
      status: 'pending',
      dueDate: due,
      points: config.pointsPerTask,
      priority: ['low', 'normal', 'high'].includes(request.body.priority)
        ? request.body.priority : 'normal',
      createdAt: now,
      updatedAt: now,
      completedAt: null,
    };
    const inserted = await col(C.tasks).insertOne(task);

    if (task.assignedTo && String(task.assignedTo) !== String(request.user._id)) {
      await notify(task.assignedTo, 'taskAssigned', {
        taskTitle: title, byName: request.user.name,
      });
    }
    await audit(request.user._id, 'event.task.create', {
      eventId: String(id), title,
    });

    response.status(201).json({ id: String(inserted.insertedId) });
  } catch (error) {
    next(error);
  }
});

/**
 * Pick up an unassigned piece of event work.
 *
 * The wizard captures *what* needs doing before anyone knows who is free, so
 * unassigned tasks are a normal state, not a gap. A member of the responsible
 * department can claim one; anyone who manages the event can hand one out.
 */
router.post('/:id/tasks/:taskId/claim', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const taskId = oid(request.params.taskId, 'Task id');
    const [event, task] = await Promise.all([
      col(C.events).findOne({ _id: id }),
      col(C.tasks).findOne({ _id: taskId, eventId: id }),
    ]);
    if (!event || !task) fail('That work no longer exists.', 404);

    const target = request.body.userId
      ? oid(request.body.userId, 'Member')
      : request.user._id;

    const claimingForSelf = String(target) === String(request.user._id);
    if (!claimingForSelf && !canManageEventDepartment(request.user, event, task.departmentId)) {
      fail('You can only take on work yourself, not hand it to someone else.', 403);
    }
    if (claimingForSelf
      && task.departmentId
      && String(request.user.departmentId ?? '') !== String(task.departmentId)
      && !canManageEvent(request.user, event)) {
      fail('That work belongs to another department.', 403);
    }
    if (task.assignedTo && String(task.assignedTo) !== String(request.user._id)
      && !canManageEventDepartment(request.user, event, task.departmentId)) {
      fail('Somebody has already taken this on.', 409);
    }

    await col(C.tasks).updateOne({ _id: taskId }, {
      $set: { assignedTo: target, updatedAt: new Date() },
    });
    if (!claimingForSelf) {
      await notify(target, 'taskAssigned', { taskTitle: task.title, byName: request.user.name });
    }
    await audit(request.user._id, 'event.task.claim', {
      eventId: String(id), taskId: String(taskId), userId: String(target),
    });
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

/* --------------------------------------------------------- responsibilities */

router.post('/:id/departments', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const event = await col(C.events).findOne({ _id: id });
    if (!event) fail('That event no longer exists.', 404);
    if (!canManageEvent(request.user, event)) {
      fail('Only the event lead and club leadership can add departments.', 403);
    }
    const departmentId = oid(request.body.departmentId, 'Department');

    await col(C.eventResponsibilities).updateOne(
      { eventId: id, departmentId },
      {
        $set: {
          notes: typeof request.body.notes === 'string'
            ? request.body.notes.trim().slice(0, 500) : '',
        },
        $setOnInsert: {
          eventId: id, departmentId, createdBy: request.user._id, createdAt: new Date(),
        },
      },
      { upsert: true },
    );
    await audit(request.user._id, 'event.department.add', {
      eventId: String(id), departmentId: String(departmentId),
    });
    response.status(201).json({ ok: true });
  } catch (error) {
    next(error);
  }
});

/* ----------------------------------------------------------------- editing */

router.patch('/:id', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const event = await col(C.events).findOne({ _id: id });
    if (!event) fail('That event no longer exists.', 404);
    if (!canManageEvent(request.user, event)) {
      fail('Only the event lead and club leadership can edit this event.', 403);
    }

    const update = { updatedAt: new Date() };
    const changes = [];

    if (typeof request.body.name === 'string') {
      update.name = text(request.body.name, 'Event name', { min: 2, max: 160 });
    }
    for (const key of ['description', 'venue', 'speakerName', 'guestDetails',
      'externalOrganisation', 'type', 'startTime', 'endTime']) {
      if (typeof request.body[key] === 'string') {
        update[key] = request.body[key].trim().slice(0, 4000);
      }
    }
    if (request.body.date) {
      const date = new Date(request.body.date);
      if (Number.isNaN(date.getTime())) fail('Give the event a valid date.');
      update.date = date;
    }
    if (request.body.leadUserId !== undefined) update.leadUserId = maybeOid(request.body.leadUserId);
    if (Array.isArray(request.body.teamUserIds)) {
      update.teamUserIds = request.body.teamUserIds.map(maybeOid).filter(Boolean);
    }
    if (Array.isArray(request.body.supportingDepartmentIds)) {
      update.supportingDepartmentIds = request.body.supportingDepartmentIds
        .map(maybeOid).filter(Boolean);
    }

    // Section 17: when something people plan around moves, say so.
    if (update.venue && update.venue !== event.venue) changes.push(`venue is now ${update.venue}`);
    if (update.date && new Date(update.date).getTime() !== new Date(event.date).getTime()) {
      changes.push('the date has changed');
    }

    const updated = await col(C.events).findOneAndUpdate(
      { _id: id }, { $set: update }, { returnDocument: 'after' },
    );

    if (changes.length > 0) {
      const audience = [...new Set([
        String(updated.leadUserId),
        ...(updated.teamUserIds ?? []).map(String),
      ])].filter((uid) => uid && uid !== String(request.user._id));
      if (audience.length > 0) {
        await notify(audience.map((uid) => new ObjectId(uid)), 'eventUpdated', {
          eventTitle: updated.name, change: changes.join(', '),
        });
      }
    }

    await audit(request.user._id, 'event.update', { eventId: String(id), fields: Object.keys(update) });
    response.json({ event: serialiseEvent(updated) });
  } catch (error) {
    next(error);
  }
});

/**
 * Status changes, with the completion checklist enforced where it matters.
 *
 * The checklist is advisory for everything except completion: marking an event
 * done while half its work is open is the one case worth blocking, because the
 * record is what people look back on.
 */
router.post('/:id/status', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const event = await col(C.events).findOne({ _id: id });
    if (!event) fail('That event no longer exists.', 404);
    if (!canManageEvent(request.user, event)) {
      fail('Only the event lead and club leadership can change the status.', 403);
    }

    const next_ = request.body.status;
    if (!EVENT_STATUSES.includes(next_)) fail('Unknown event status.');

    if (next_ === 'completed' && request.body.force !== true) {
      const [open, pendingApprovals] = await Promise.all([
        col(C.tasks).countDocuments({
          eventId: id, status: { $nin: ['completed', 'cancelled'] },
        }),
        col(C.eventDocuments).countDocuments({ eventId: id, kind: 'approval', status: 'pending' }),
      ]);
      if (open > 0 || pendingApprovals > 0) {
        return response.status(409).json({
          error: 'Some of this event is still open.',
          checklist: {
            openTasks: open,
            pendingApprovals,
            // The client offers "complete anyway" — a club's reality is that
            // the last two tasks often never get ticked.
            canForce: true,
          },
        });
      }
    }

    const updated = await col(C.events).findOneAndUpdate(
      { _id: id },
      { $set: { status: next_, updatedAt: new Date() } },
      { returnDocument: 'after' },
    );
    await audit(request.user._id, 'event.status', { eventId: String(id), status: next_ });
    return response.json({ event: serialiseEvent(updated) });
  } catch (error) {
    return next(error);
  }
});

/** The completion checklist, so the UI can show it before anyone presses. */
router.get('/:id/checklist', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const [open, total, approvals, pendingApprovals] = await Promise.all([
      col(C.tasks).countDocuments({ eventId: id, status: { $nin: ['completed', 'cancelled'] } }),
      col(C.tasks).countDocuments({ eventId: id, status: { $ne: 'cancelled' } }),
      col(C.eventDocuments).countDocuments({ eventId: id, kind: 'approval', status: 'approved' }),
      col(C.eventDocuments).countDocuments({ eventId: id, kind: 'approval', status: 'pending' }),
    ]);
    response.json({
      tasksComplete: open === 0,
      openTasks: open,
      totalTasks: total,
      approvalsOnFile: approvals,
      pendingApprovals,
    });
  } catch (error) {
    next(error);
  }
});

/* --------------------------------------------------------------- timeline */

/**
 * What has happened on this event.
 *
 * Built from the audit log plus task completions — history of the project, not
 * a record of who was slow. Names appear because "Marketing finished the
 * poster" is useful; nothing here counts misses.
 */
router.get('/:id/timeline', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');

    const [entries, completions, documents] = await Promise.all([
      col(C.auditLog).find({ 'detail.eventId': String(id) }).sort({ createdAt: -1 }).limit(60).toArray(),
      col(C.tasks).find({ eventId: id, status: 'completed', completedAt: { $ne: null } })
        .sort({ completedAt: -1 }).limit(40).toArray(),
      col(C.eventDocuments).find({ eventId: id }).sort({ createdAt: -1 }).limit(20).toArray(),
    ]);

    const ids = [
      ...entries.map((e) => e.actorId),
      ...completions.map((t) => t.assignedTo),
      ...documents.map((d) => d.createdBy),
    ].filter(Boolean);
    const [people, departments] = await Promise.all([
      col(C.users).find({ _id: { $in: ids } }, { projection: { name: 1 } }).toArray(),
      col(C.departments).find({}, { projection: { name: 1 } }).toArray(),
    ]);
    const userName = new Map(people.map((p) => [String(p._id), p.name]));
    const deptName = new Map(departments.map((d) => [String(d._id), d.name]));

    const timeline = [
      ...completions.map((t) => ({
        at: t.completedAt,
        kind: 'taskCompleted',
        text: `${deptName.get(String(t.departmentId)) ?? 'Someone'} completed ${t.title}`,
        who: userName.get(String(t.assignedTo)) ?? null,
      })),
      ...documents.map((d) => ({
        at: d.createdAt,
        kind: 'document',
        text: `${d.title} uploaded`,
        who: userName.get(String(d.createdBy)) ?? null,
      })),
      ...entries
        .filter((e) => ['event.create', 'event.update', 'event.status', 'document.decision']
          .includes(e.action))
        .map((e) => ({
          at: e.createdAt,
          kind: e.action,
          text: describeAudit(e),
          who: userName.get(String(e.actorId)) ?? null,
        })),
    ].sort((a, b) => new Date(b.at) - new Date(a.at)).slice(0, 50);

    response.json({ timeline });
  } catch (error) {
    next(error);
  }
});

function describeAudit(entry) {
  switch (entry.action) {
    case 'event.create': return 'Event created';
    case 'event.update': return 'Event details updated';
    case 'event.status': return `Status changed to ${entry.detail?.status ?? 'updated'}`;
    case 'document.decision':
      return `${entry.detail?.title ?? 'A document'} marked ${entry.detail?.status ?? 'updated'}`;
    default: return entry.action;
  }
}

router.delete('/:id', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const event = await col(C.events).findOne({ _id: id });
    if (!event) fail('That event no longer exists.', 404);
    if (!canManageEvent(request.user, event)) {
      fail('Only the event lead and club leadership can remove this event.', 403);
    }
    // Cancel rather than delete: the tasks people did still happened, and the
    // paperwork may still be needed.
    await col(C.events).updateOne({ _id: id }, { $set: { status: 'cancelled', updatedAt: new Date() } });
    await audit(request.user._id, 'event.cancel', { eventId: String(id), name: event.name });
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

module.exports = router;
module.exports.serialiseEvent = serialiseEvent;

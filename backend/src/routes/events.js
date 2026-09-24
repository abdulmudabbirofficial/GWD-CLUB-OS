'use strict';

const express = require('express');
const { ObjectId } = require('mongodb');
const config = require('../config');
const { accentFor } = require('../palette');
const { col, C } = require('../db');
const { authenticate, requireApproved, fail } = require('../auth');
const {
  EVENT_STATUSES, canCreateEvent, canManageEvent, canManageEventDepartment,
  ROLES, isDirector,
} = require('../permissions');
const { displayNameOf } = require('../people');
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
/** An event's accent stripe. Same list as everything else the app colours. */
const bannerFor = accentFor;

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
    templateId: event.templateId ? String(event.templateId) : null,
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
      col(C.users).find({}, { projection: { name: 1, role: 1, knownAs: 1, superAdmin: 1, mustSetName: 1 } }).toArray(),
    ]);
    const deptName = new Map(departments.map((d) => [String(d._id), d.name]));
    const userName = new Map(people.map((p) => [String(p._id), displayNameOf(p)]));

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
    //
    // Compared by **calendar day**, never by timestamp. An event's `date` is a
    // day — the time of day lives separately in startTime/endTime — so it is
    // stored at midnight. Comparing that against `new Date()` meant an event
    // was "in the past" from one minute after midnight on the day it ran, and
    // because a freshly created event is `planning` rather than `ongoing` or
    // `approved`, it did not qualify as ongoing either. The result: an event
    // vanished from Upcoming into Past on the very morning it was happening,
    // which reads exactly like the app having deleted it.
    const startOfDay = (value) => {
      const d = new Date(value);
      d.setHours(0, 0, 0, 0);
      return d.getTime();
    };
    const today = startOfDay(new Date());
    const dayOf = (e) => startOfDay(e.date);

    const isDone = (e) => e.status === 'completed';
    const isOngoing = (e) =>
      !isDone(e) && (e.status === 'ongoing' || dayOf(e) === today);

    response.json({
      // Strictly after today. Anything happening today is ongoing, not upcoming.
      upcoming: decorated.filter((e) => !isDone(e) && !isOngoing(e) && dayOf(e) > today),
      ongoing: decorated.filter(isOngoing),
      completed: decorated
        .filter((e) => isDone(e) || (!isOngoing(e) && dayOf(e) < today))
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
      // Which template this was started from, if any.
      //
      // The template is applied *client-side*, in the wizard: it prefills the
      // fields and resolves each task's offset into a real date, and the person
      // then edits the result before committing. That keeps one creation path
      // instead of two that would drift, and it makes the template a starting
      // point rather than a contract — which is the only kind anybody trusts.
      // This field is attribution, not a live link.
      templateId: maybeOid(request.body.templateId),
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
        const inserted = await col(C.tasks).insertMany(docs);
        docs.forEach((d, i) => { d._id = inserted.insertedIds[i]; });
        taskCount += docs.length;
        // Tell the people who actually got something, and carry the id of the
        // task each of them got so the notification opens it.
        for (const doc of docs) {
          if (!doc.assignedTo || String(doc.assignedTo) === String(actor._id)) continue;
          await notify(doc.assignedTo, 'taskAssigned', {
            taskTitle: doc.title ?? name,
            byName: displayNameOf(actor),
            taskId: String(doc._id),
            eventId: String(event._id),
          });
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
        eventTitle: name, byName: displayNameOf(actor),
      });
    }

    // A template earns its place in the list by being used, so the ordering
    // reflects what the club actually runs rather than what somebody once
    // imagined it might. Failing to count a use must never fail the event, so
    // this is deliberately not awaited into the response path.
    if (event.templateId) {
      await col(C.eventTemplates).updateOne(
        { _id: event.templateId },
        { $inc: { usageCount: 1 }, $set: { lastUsedAt: now } },
      ).catch(() => {});
    }

    await audit(actor._id, 'event.create', {
      eventId: String(event._id),
      name,
      departments: responsibilities.length,
      tasks: taskCount,
      ...(event.templateId ? { templateId: String(event.templateId) } : {}),
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
      col(C.users).find({}, { projection: { name: 1, avatarColor: 1, role: 1, knownAs: 1, superAdmin: 1, mustSetName: 1 } }).toArray(),
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
          name: u ? displayNameOf(u) : 'Member',
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
      col(C.users).find({}, { projection: { name: 1, avatarColor: 1, role: 1, knownAs: 1, superAdmin: 1, mustSetName: 1 } }).toArray(),
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
    task._id = inserted.insertedId;

    if (task.assignedTo && String(task.assignedTo) !== String(request.user._id)) {
      await notify(task.assignedTo, 'taskAssigned', {
        taskTitle: title, byName: displayNameOf(request.user),
        taskId: String(task._id), eventId: String(id),
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
      await notify(target, 'taskAssigned', {
        taskTitle: task.title, byName: displayNameOf(request.user),
        taskId: String(taskId), eventId: String(id),
      });
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

    // Section 17: when something people plan around moves, say so. A name or a
    // description tidied up is not news; where and when are.
    if (update.venue !== undefined && update.venue !== (event.venue ?? '')) {
      changes.push(update.venue ? `venue is now ${update.venue}` : 'the venue has been cleared');
    }
    if (update.date && new Date(update.date).getTime() !== new Date(event.date).getTime()) {
      changes.push('the date has changed');
    }
    const timeMoved = (update.startTime !== undefined && update.startTime !== (event.startTime ?? ''))
      || (update.endTime !== undefined && update.endTime !== (event.endTime ?? ''));
    if (timeMoved) changes.push('the time has changed');

    const updated = await col(C.events).findOneAndUpdate(
      { _id: id }, { $set: update }, { returnDocument: 'after' },
    );

    if (changes.length > 0) {
      // Everybody who plans around this event: its lead and team, the Lead of
      // every department with a responsibility on it, and anybody holding open
      // work on it. Telling only the named team meant the Marketing Lead whose
      // posters carry the date found out it had moved from the posters.
      const [responsibilities, openWork] = await Promise.all([
        col(C.eventResponsibilities).find({ eventId: id }, { projection: { departmentId: 1 } }).toArray(),
        col(C.tasks).find(
          { eventId: id, status: { $nin: ['completed', 'cancelled'] }, assignedTo: { $ne: null } },
          { projection: { assignedTo: 1 } },
        ).toArray(),
      ]);
      const departmentIds = [...new Set([
        ...responsibilities.map((r) => String(r.departmentId)),
        String(updated.organizingDepartmentId ?? ''),
      ])].filter((d) => d && ObjectId.isValid(d)).map((d) => new ObjectId(d));
      const departmentLeads = departmentIds.length === 0 ? [] : await col(C.departments)
        .find({ _id: { $in: departmentIds } }, { projection: { leadUserId: 1 } }).toArray();

      const audience = [...new Set([
        String(updated.leadUserId ?? ''),
        ...(updated.teamUserIds ?? []).map(String),
        ...departmentLeads.map((d) => String(d.leadUserId ?? '')),
        ...openWork.map((t) => String(t.assignedTo)),
      ])].filter((uid) => uid && ObjectId.isValid(uid) && uid !== String(request.user._id));
      if (audience.length > 0) {
        await notify(audience.map((uid) => new ObjectId(uid)), 'eventUpdated', {
          eventTitle: updated.name,
          change: changes.join(', '),
          // So tapping the notice opens the event it is about.
          eventId: String(id),
          byName: displayNameOf(request.user),
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
      col(C.users).find({ _id: { $in: ids } }, { projection: { name: 1, role: 1, knownAs: 1, superAdmin: 1, mustSetName: 1 } }).toArray(),
      col(C.departments).find({}, { projection: { name: 1 } }).toArray(),
    ]);
    const userName = new Map(people.map((p) => [String(p._id), displayNameOf(p)]));
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

/* --------------------------------------------------------------- day mode */

/**
 * Running the event on the day.
 *
 * Every other event screen answers "is this on track?", which is a planning
 * question asked at a desk. On the day itself nobody is planning: somebody is
 * standing in a corridor with fifteen minutes to go, and the questions are
 * "what is happening right now", "what is next", and "who do I ring about the
 * projector". The workspace answers none of those, and a tab that made them
 * scroll past a burndown chart to find a phone number would go unused.
 *
 * The run sheet lives **on the event document** rather than in a collection of
 * its own. It is a dozen or so rows, it is never read without the event, and
 * nothing ever queries across the run sheets of different events. A collection
 * would buy a join and nothing else.
 */

/** Times are stored as `HH:MM` so they sort lexicographically without parsing. */
function clockTime(value) {
  if (typeof value !== 'string') return '';
  const match = value.trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return '';
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (hours > 23 || minutes > 59) return '';
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
}

/** Untimed rows sort last: they are the "at some point" jobs, not the schedule. */
const byTime = (a, b) => (a.time || '99:99').localeCompare(b.time || '99:99');

function serialiseRunSheet(event, userById) {
  return [...(event.runSheet ?? [])].sort(byTime).map((item) => ({
    id: String(item.id),
    time: item.time ?? '',
    title: item.title,
    note: item.note ?? '',
    ownerUserId: item.ownerUserId ? String(item.ownerUserId) : null,
    ownerName: item.ownerUserId
      ? (userById?.get(String(item.ownerUserId))?.name ?? null) : null,
    done: Boolean(item.done),
    doneAt: item.doneAt ?? null,
    doneBy: item.doneBy ? String(item.doneBy) : null,
  }));
}

/**
 * Everything the day view needs, in one request.
 *
 * Deliberately **not** computing "what is on now" server-side. The person
 * holding the phone is the one standing in the room, their clock is the one
 * that matters, and a `currentItem` baked into a response goes stale the
 * moment it is cached or the screen is left open. The client derives it from
 * the sorted list, which is one source of truth rather than two that disagree
 * five minutes apart.
 */
router.get('/:id/day', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const event = await col(C.events).findOne({ _id: id });
    if (!event) fail('That event no longer exists.', 404);

    const actor = request.user;
    // Phone numbers are the useful half of this screen and also the only
    // private thing on it, so they go to the people who would actually be
    // ringing somebody: whoever can manage the event. Everybody else gets the
    // same run sheet without them. A club directory that quietly hands every
    // member's number to every member is not something anyone asked for.
    const mayCall = canManageEvent(actor, event);

    const teamIds = [...new Set([
      String(event.leadUserId ?? ''),
      ...(event.teamUserIds ?? []).map(String),
      ...(event.runSheet ?? []).map((i) => String(i.ownerUserId ?? '')),
    // `.filter(ObjectId.isValid)` would pass the static detached from its class
    // and hand it an index and an array as extra arguments. It happens to work
    // today; an arrow keeps it working whatever the driver does next.
    ])].filter((uid) => ObjectId.isValid(uid)).map((uid) => new ObjectId(uid));

    const [people, openTasks, pendingApprovals] = await Promise.all([
      col(C.users).find(
        { _id: { $in: teamIds } },
        { projection: { name: 1, role: 1, avatarColor: 1, phone: 1, mustSetName: 1, departmentId: 1, knownAs: 1, superAdmin: 1 } },
      ).toArray(),
      col(C.tasks).find({ eventId: id, status: { $nin: ['completed', 'cancelled'] } })
        .sort({ dueDate: 1 }).limit(50).toArray(),
      col(C.eventDocuments)
        .countDocuments({ eventId: id, kind: 'approval', status: 'pending' }),
    ]);
    const userById = new Map(people.map((p) => [String(p._id), p]));

    const runSheet = serialiseRunSheet(event, userById);
    response.json({
      event: serialiseEvent(event),
      runSheet,
      runSheetDone: runSheet.filter((i) => i.done).length,
      canEdit: mayCall,
      team: [...new Set([
        String(event.leadUserId ?? ''),
        ...(event.teamUserIds ?? []).map(String),
      ])].filter(Boolean).map((uid) => {
        const u = userById.get(uid);
        return {
          id: uid,
          name: u ? displayNameOf(u) : 'Member',
          role: u?.role ?? 'clubMember',
          departmentId: u?.departmentId ? String(u.departmentId) : null,
          avatarColor: u?.avatarColor ?? null,
          mustSetName: Boolean(u?.mustSetName),
          phone: mayCall ? (u?.phone ?? '') : '',
          isLead: uid === String(event.leadUserId),
        };
      }),
      openTasks: openTasks.map((t) => ({
        id: String(t._id),
        title: t.title,
        status: t.status,
        dueDate: t.dueDate ?? null,
        departmentId: t.departmentId ? String(t.departmentId) : null,
        assignedTo: t.assignedTo ? String(t.assignedTo) : null,
      })),
      openTaskCount: openTasks.length,
      pendingApprovals,
    });
  } catch (error) {
    next(error);
  }
});

router.post('/:id/runsheet', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const event = await col(C.events).findOne({ _id: id });
    if (!event) fail('That event no longer exists.', 404);
    const actor = request.user;
    if (!canManageEvent(actor, event)) {
      fail('Only the event lead can change the run sheet.', 403);
    }
    // A run sheet is a page of a clipboard, not a work-breakdown structure. A
    // cap keeps one runaway paste from producing a screen nobody can scroll.
    if ((event.runSheet ?? []).length >= 100) {
      fail('That run sheet is full. Ninety-nine things is already more than a day holds.', 409);
    }

    const item = {
      id: new ObjectId(),
      time: clockTime(request.body.time),
      title: text(request.body.title, 'What happens', { min: 2, max: 200 }),
      note: typeof request.body.note === 'string' ? request.body.note.trim().slice(0, 500) : '',
      ownerUserId: maybeOid(request.body.ownerUserId),
      done: false,
      doneAt: null,
      doneBy: null,
    };
    await col(C.events).updateOne(
      { _id: id },
      { $push: { runSheet: item }, $set: { updatedAt: new Date() } },
    );
    await audit(actor._id, 'event.runsheet.add', {
      eventId: String(id), title: item.title,
    });
    response.status(201).json({ item: serialiseRunSheet({ runSheet: [item] })[0] });
  } catch (error) {
    next(error);
  }
});

/**
 * Tick a run-sheet row off, or edit it.
 *
 * **Ticking is open to anyone on the team**, editing is not. On the day the
 * person who finishes setting the stage is whoever was nearest, and making
 * them find the event lead to have it marked done is how a run sheet stops
 * being updated by eleven in the morning.
 */
router.patch('/:id/runsheet/:itemId', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const itemId = oid(request.params.itemId, 'Run sheet item id');
    const event = await col(C.events).findOne({ _id: id });
    if (!event) fail('That event no longer exists.', 404);
    const existing = (event.runSheet ?? []).find((i) => String(i.id) === String(itemId));
    if (!existing) fail('That run sheet item no longer exists.', 404);

    const actor = request.user;
    const onTeam = [
      String(event.leadUserId ?? ''),
      ...(event.teamUserIds ?? []).map(String),
      String(existing.ownerUserId ?? ''),
    ].includes(String(actor._id));
    const mayEdit = canManageEvent(actor, event);
    const body = request.body ?? {};
    const onlyTicking = Object.keys(body).every((key) => key === 'done');

    if (!mayEdit && !(onlyTicking && onTeam)) {
      fail('Only the event lead can change the run sheet.', 403);
    }

    const set = { updatedAt: new Date() };
    if (body.done !== undefined) {
      const done = Boolean(body.done);
      set['runSheet.$[row].done'] = done;
      set['runSheet.$[row].doneAt'] = done ? new Date() : null;
      set['runSheet.$[row].doneBy'] = done ? actor._id : null;
    }
    if (mayEdit) {
      if (body.time !== undefined) set['runSheet.$[row].time'] = clockTime(body.time);
      if (body.title !== undefined) {
        set['runSheet.$[row].title'] = text(body.title, 'What happens', { min: 2, max: 200 });
      }
      if (body.note !== undefined) {
        set['runSheet.$[row].note'] = typeof body.note === 'string'
          ? body.note.trim().slice(0, 500) : '';
      }
      if (body.ownerUserId !== undefined) {
        set['runSheet.$[row].ownerUserId'] = maybeOid(body.ownerUserId);
      }
    }

    // Only pass `arrayFilters` when something in `$set` actually uses it.
    //
    // Mongo rejects an update that declares a filter identifier no positional
    // operator references — "the array filter for identifier 'row' was not
    // used" — so a request carrying no recognised field would have come back a
    // 500 rather than doing nothing. An empty change is not an error.
    const touchesRow = Object.keys(set).some((key) => key.startsWith('runSheet.'));
    if (touchesRow) {
      await col(C.events).updateOne(
        { _id: id },
        { $set: set },
        { arrayFilters: [{ 'row.id': itemId }] },
      );
    }
    const updated = await col(C.events).findOne({ _id: id });
    const item = serialiseRunSheet(updated).find((i) => i.id === String(itemId));
    response.json({ item });
  } catch (error) {
    next(error);
  }
});

router.delete('/:id/runsheet/:itemId', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const itemId = oid(request.params.itemId, 'Run sheet item id');
    const event = await col(C.events).findOne({ _id: id });
    if (!event) fail('That event no longer exists.', 404);
    const actor = request.user;
    if (!canManageEvent(actor, event)) {
      fail('Only the event lead can change the run sheet.', 403);
    }
    await col(C.events).updateOne(
      { _id: id },
      { $pull: { runSheet: { id: itemId } }, $set: { updatedAt: new Date() } },
    );
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

/* ----------------------------------------------------------------- report */

/**
 * What happened, and what to do differently.
 *
 * Half of this is **derived and never typed**: how many tasks were completed,
 * what it cost, how many people were on it, what paperwork is on file. Asking
 * somebody to fill those in by hand produces numbers that are wrong, and a
 * report with one wrong number in it is a report nobody reads the rest of.
 *
 * The typed half is three questions, deliberately not ten: what went well,
 * what did not, and what the next person should know. A form long enough to
 * feel like homework is a form that gets submitted empty, and an empty report
 * is worse than none — it looks like the event went fine.
 */
router.get('/:id/report', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const event = await col(C.events).findOne({ _id: id });
    if (!event) fail('That event no longer exists.', 404);

    const [taskRows, bills, documents, responsibilities] = await Promise.all([
      col(C.tasks).aggregate([
        { $match: { eventId: id, status: { $ne: 'cancelled' } } },
        {
          $group: {
            _id: null,
            total: { $sum: 1 },
            done: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] } },
            points: {
              $sum: { $cond: [{ $eq: ['$status', 'completed'] }, { $ifNull: ['$points', 0] }, 0] },
            },
          },
        },
      ]).toArray(),
      col(C.eventBills).find({ eventId: id }).toArray(),
      col(C.eventDocuments).find({ eventId: id }, { projection: { kind: 1, status: 1 } }).toArray(),
      col(C.eventResponsibilities).countDocuments({ eventId: id }),
    ]);

    const tasks = taskRows[0] ?? { total: 0, done: 0, points: 0 };
    // Cancelled bills are not spending. Everything else was money out of
    // somebody's pocket whether or not it has been signed off yet, which is
    // the figure anybody asking "what did it cost" means.
    const counted = bills.filter((b) => b.status !== 'rejected');
    const spentPaise = counted.reduce((sum, b) => sum + (b.amountPaise ?? 0), 0);
    const owedPaise = counted
      .filter((b) => b.status !== 'paid')
      .reduce((sum, b) => sum + (b.amountPaise ?? 0), 0);

    const stored = event.report ?? null;
    const submittedBy = stored?.submittedBy
      ? await col(C.users).findOne(
        { _id: stored.submittedBy }, { projection: { name: 1, role: 1, knownAs: 1, superAdmin: 1, mustSetName: 1 } },
      )
      : null;

    response.json({
      event: serialiseEvent(event),
      canEdit: canManageEvent(request.user, event),
      report: stored ? {
        attendance: stored.attendance ?? null,
        highlights: stored.highlights ?? '',
        challenges: stored.challenges ?? '',
        learnings: stored.learnings ?? '',
        submittedBy: stored.submittedBy ? String(stored.submittedBy) : null,
        submittedByName: submittedBy ? displayNameOf(submittedBy) : null,
        submittedAt: stored.submittedAt ?? null,
        updatedAt: stored.updatedAt ?? null,
      } : null,
      derived: {
        taskCount: tasks.total,
        taskCompleted: tasks.done,
        pointsEarned: tasks.points,
        departmentCount: responsibilities,
        teamSize: [...new Set([
          String(event.leadUserId ?? ''),
          ...(event.teamUserIds ?? []).map(String),
        ])].filter(Boolean).length,
        spentPaise,
        owedPaise,
        billCount: counted.length,
        documentCount: documents.length,
        approvalsApproved: documents
          .filter((d) => d.kind === 'approval' && d.status === 'approved').length,
        runSheetTotal: (event.runSheet ?? []).length,
        runSheetDone: (event.runSheet ?? []).filter((i) => i.done).length,
      },
    });
  } catch (error) {
    next(error);
  }
});

router.put('/:id/report', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const event = await col(C.events).findOne({ _id: id });
    if (!event) fail('That event no longer exists.', 404);
    const actor = request.user;
    if (!canManageEvent(actor, event)) {
      fail('Only the event lead can write the report.', 403);
    }

    const body = request.body ?? {};
    let attendance = null;
    if (body.attendance !== undefined && body.attendance !== null && body.attendance !== '') {
      const n = Number(body.attendance);
      if (!Number.isFinite(n) || n < 0) fail('Attendance has to be a number, or left blank.');
      attendance = Math.min(1_000_000, Math.round(n));
    }

    const now = new Date();
    const report = {
      attendance,
      highlights: typeof body.highlights === 'string' ? body.highlights.trim().slice(0, 4000) : '',
      challenges: typeof body.challenges === 'string' ? body.challenges.trim().slice(0, 4000) : '',
      learnings: typeof body.learnings === 'string' ? body.learnings.trim().slice(0, 4000) : '',
      // Who wrote it first stays who wrote it, so a later tidy-up by somebody
      // else does not quietly reassign authorship of the account.
      submittedBy: event.report?.submittedBy ?? actor._id,
      submittedAt: event.report?.submittedAt ?? now,
      updatedAt: now,
    };
    await col(C.events).updateOne({ _id: id }, { $set: { report, updatedAt: now } });
    await audit(actor._id, 'event.report', { eventId: String(id), name: event.name });

    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

router.delete('/:id', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Event id');
    const event = await col(C.events).findOne({ _id: id });
    if (!event) fail('That event no longer exists.', 404);
    // Cancelling an event throws away work a lot of people did, so it is not
    // the event lead's call — Directors and the President only.
    const actor = request.user;
    const mayCancel = isDirector(actor.role)
      || actor.role === ROLES.facultyCoordinator
      || actor.role === ROLES.president;
    if (!mayCancel) {
      fail('Only a Director, the Faculty Coordinator or the President can cancel an event.', 403);
    }

    // `?purge=true` removes it outright. Only for an event already cancelled —
    // so getting rid of one is always two deliberate steps, and a live event
    // can never be deleted by a single mistaken tap.
    const purge = request.query.purge === 'true';
    if (purge) {
      if (event.status !== 'cancelled') {
        fail('Cancel the event first. Deleting outright would take its work with it.', 409);
      }
      await Promise.all([
        col(C.events).deleteOne({ _id: id }),
        col(C.eventResponsibilities).deleteMany({ eventId: id }),
        // Event work is only reachable through the event, so it goes too.
        col(C.tasks).deleteMany({ eventId: id }),
        col(C.eventDocuments).deleteMany({ eventId: id }),
        col(C.eventBills).deleteMany({ eventId: id }),
      ]);
      await audit(actor._id, 'event.delete', { eventId: String(id), name: event.name });
      return response.json({ ok: true, deleted: true });
    }

    // Cancel rather than delete: the tasks people did still happened, and the
    // paperwork may still be needed.
    await col(C.events).updateOne({ _id: id }, { $set: { status: 'cancelled', updatedAt: new Date() } });
    await audit(actor._id, 'event.cancel', { eventId: String(id), name: event.name });

    // Tell everyone who was working on it. Cancelling means "stop", and the
    // event simply vanishing from the list is not how somebody halfway through
    // building a set should find out. The audience is deliberately wider than
    // at creation: anybody still carrying an open task on this event is
    // included even if they were never named on the team, because they are
    // exactly the person about to waste an afternoon.
    const stillWorking = await col(C.tasks)
      .find(
        { eventId: id, status: { $nin: ['completed', 'cancelled'] }, assignedTo: { $ne: null } },
        { projection: { assignedTo: 1 } },
      )
      .toArray();

    const audience = [...new Set([
      ...(event.teamUserIds ?? []).map(String),
      ...(event.leadUserId ? [String(event.leadUserId)] : []),
      ...stillWorking.map((t) => String(t.assignedTo)),
    ])].filter((who) => who !== String(actor._id));

    if (audience.length > 0) {
      await notify(audience.map((who) => new ObjectId(who)), 'eventCancelled', {
        eventName: event.name,
        eventId: String(id),
        byName: displayNameOf(actor),
      });
    }

    return response.json({ ok: true, deleted: false });
  } catch (error) {
    next(error);
  }
});

module.exports = router;
module.exports.serialiseEvent = serialiseEvent;

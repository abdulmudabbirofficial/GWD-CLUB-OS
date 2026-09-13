'use strict';

const express = require('express');
const { ObjectId } = require('mongodb');
const config = require('../config');
const { col, C } = require('../db');
const { authenticate, requireApproved, fail } = require('../auth');
const {
  canAssign, canAssignTo, taskVisibilityFilter, canChangeTaskStatus,
  isDirector, isSupervisor, earnsPoints, TASK_STATUSES,
  canAssignToDepartment, canDistributeDepartmentTask, isValidTaskPoints,
  ROLES,
} = require('../permissions');
const { notify, audit } = require('../services/notify');
const { serialiseTask } = require('../realtime');

const router = express.Router();
router.use(authenticate, requireApproved);

const oid = (value, name) => {
  if (!ObjectId.isValid(value)) fail(`${name} is not valid.`);
  return new ObjectId(value);
};

function text(value, name, { min = 1, max = 2000 } = {}) {
  if (typeof value !== 'string' || value.trim().length < min) fail(`${name} is required.`);
  const trimmed = value.trim();
  if (trimmed.length > max) fail(`${name} is too long.`);
  return trimmed;
}

/**
 * List tasks.
 *
 * `scope=mine`     → the My Task tab
 * `scope=assigned` → the Assigned Task tab (only for roles that can assign)
 * `scope=all`      → everything this user is entitled to see
 *
 * Every branch is intersected with taskVisibilityFilter, so a crafted query
 * string can never widen what a Member is allowed to read.
 */
router.get('/', async (request, response, next) => {
  try {
    const user = request.user;
    const scope = request.query.scope ?? 'all';
    const visibility = taskVisibilityFilter(user);

    let scopeFilter;
    if (scope === 'mine') {
      scopeFilter = { assignedTo: user._id };
    } else if (scope === 'assigned') {
      if (!canAssign(user.role)) return response.json({ tasks: [] });
      scopeFilter = { assignedBy: user._id, assignedTo: { $ne: user._id } };
    } else if (scope === 'incoming') {
      // Work addressed to this Lead's department that nobody has been given
      // yet — the triage pile that makes the two-step hierarchy work.
      if (!user.departmentId) return response.json({ tasks: [] });
      scopeFilter = {
        departmentId: user.departmentId,
        $or: [{ assignedTo: null }, { assignedTo: { $exists: false } }],
        status: { $nin: ['completed', 'cancelled'] },
      };
    } else {
      scopeFilter = {};
    }

    const filter = { $and: [visibility, scopeFilter] };

    // Event work lives on its event's board, not in the general task list —
    // otherwise one festival buries everybody's own to-do list. `scope=mine`
    // is the exception: a task assigned to you is yours wherever it came from.
    if (scope !== 'mine' && request.query.includeEvents !== 'true') {
      filter.$and.push({ $or: [{ eventId: null }, { eventId: { $exists: false } }] });
    }

    if (request.query.status && TASK_STATUSES.includes(request.query.status)) {
      filter.$and.push({ status: request.query.status });
    }
    if (request.query.departmentId && ObjectId.isValid(request.query.departmentId)) {
      filter.$and.push({ departmentId: new ObjectId(request.query.departmentId) });
    }

    const tasks = await col(C.tasks)
      .find(filter)
      .sort({ updatedAt: -1 })
      .limit(Math.min(Number(request.query.limit) || 300, 500))
      .toArray();

    response.json({ tasks: tasks.map(serialiseTask) });
  } catch (error) {
    next(error);
  }
});

router.get('/:id', async (request, response, next) => {
  try {
    const task = await col(C.tasks).findOne({
      $and: [{ _id: oid(request.params.id, 'Task id') }, taskVisibilityFilter(request.user)],
    });
    if (!task) fail('Task not found.', 404);
    const comments = await col(C.comments)
      .find({ taskId: task._id })
      .sort({ createdAt: 1 })
      .toArray();
    response.json({
      task: serialiseTask(task),
      comments: comments.map((c) => ({
        id: String(c._id),
        taskId: String(c.taskId),
        authorId: String(c.authorId),
        authorName: c.authorName,
        body: c.body,
        createdAt: c.createdAt,
      })),
    });
  } catch (error) {
    next(error);
  }
});

/**
 * Create a task.
 *
 * Two shapes, because the club has two kinds of assigner:
 *
 *   `{ departmentId }`  — the leadership addressing a **department**. Lands
 *                         unassigned; its Lead is notified and decides who
 *                         does it. This is the normal path for a Director,
 *                         the Faculty Coordinator, the President, the VP or
 *                         the Secretary General.
 *   `{ assignedTo }`    — a **Lead** handing work to their own member, or
 *                         anybody taking something on themselves. One task
 *                         document per assignee, so each person owns their
 *                         own state.
 *
 * The point of the split is that an executive picking one name out of forty is
 * a decision they are not equipped to make. A Lead knows who is free.
 */
router.post('/', async (request, response, next) => {
  try {
    const actor = request.user;
    if (!canAssign(actor.role)) fail('Your role cannot assign tasks.', 403);

    const title = text(request.body.title, 'Title', { max: 200 });
    const description = typeof request.body.description === 'string' ? request.body.description.trim() : '';
    const dueDate = request.body.dueDate ? new Date(request.body.dueDate) : null;
    if (dueDate && Number.isNaN(dueDate.getTime())) fail('Due date is not a valid date.');
    const priority = ['low', 'normal', 'high'].includes(request.body.priority) ? request.body.priority : 'normal';

    // Points are the Lead's call — they are the only person who knows whether
    // this is twenty minutes or a weekend. A department task arrives unpriced
    // and is valued when it is handed out.
    const points = isValidTaskPoints(request.body.points)
      ? Number(request.body.points)
      : config.pointsPerTask;

    const now = new Date();

    // ---- addressed to a department -------------------------------------
    if (request.body.departmentId) {
      if (!canAssignToDepartment(actor.role)) {
        fail('Your role assigns to people, not to whole departments.', 403);
      }
      const departmentId = oid(request.body.departmentId, 'Department');
      const department = await col(C.departments).findOne({ _id: departmentId });
      if (!department || department.active === false) fail('That department is not available.');

      const doc = {
        title,
        description,
        assignedBy: actor._id,
        assignedTo: null,
        departmentId,
        status: 'pending',
        dueDate,
        points,
        priority,
        createdAt: now,
        updatedAt: now,
        completedAt: null,
      };
      const inserted = await col(C.tasks).insertOne(doc);
      doc._id = inserted.insertedId;

      // The Lead is the recipient. Without one the department cannot act, so
      // the President is told instead rather than the task sitting unseen.
      if (department.leadUserId) {
        await notify(department.leadUserId, 'departmentTaskAssigned', {
          taskTitle: title, byName: actor.name, departmentName: department.name,
        });
      } else {
        const president = await col(C.users).findOne({ role: ROLES.president, approvalStatus: 'approved' });
        if (president) {
          await notify(president._id, 'departmentTaskUnclaimed', {
            taskTitle: title, departmentName: department.name,
          });
        }
      }

      await audit(actor._id, 'task.create.department', {
        title, departmentId: String(departmentId), departmentName: department.name,
      });
      return response.status(201).json({ tasks: [serialiseTask(doc)] });
    }

    // ---- addressed to people -------------------------------------------
    const rawTargets = Array.isArray(request.body.assignedTo)
      ? request.body.assignedTo
      : [request.body.assignedTo];
    const targetIds = rawTargets.filter(Boolean).map((v) => oid(v, 'Assignee'));
    if (targetIds.length === 0) {
      fail(canAssignToDepartment(actor.role)
        ? 'Choose the department this is for.'
        : 'Choose who this task is for.');
    }

    const targets = await col(C.users)
      .find({ _id: { $in: targetIds }, approvalStatus: 'approved' })
      .toArray();
    if (targets.length !== targetIds.length) fail('One or more assignees are not available.');

    // The permission matrix decides every single assignment, individually.
    for (const target of targets) {
      if (!canAssignTo(actor, target)) {
        fail(`You cannot assign tasks to ${target.name} directly. `
          + 'Send it to their department and their Lead will pass it on.', 403);
      }
    }

    const docs = targets.map((target) => ({
      title,
      description,
      assignedBy: actor._id,
      assignedTo: target._id,
      // The task belongs to the assignee's department, which is what makes
      // department-scoped visibility work for Leads.
      departmentId: target.departmentId ?? actor.departmentId ?? null,
      status: 'pending',
      dueDate,
      points,
      priority,
      createdAt: now,
      updatedAt: now,
      completedAt: null,
    }));

    const result = await col(C.tasks).insertMany(docs);
    docs.forEach((doc, i) => { doc._id = result.insertedIds[i]; });

    await Promise.all(
      targets
        .filter((t) => String(t._id) !== String(actor._id))
        .map((t) => notify(t._id, 'taskAssigned', { taskTitle: title, byName: actor.name })),
    );
    await audit(actor._id, 'task.create', { count: docs.length, title });

    return response.status(201).json({ tasks: docs.map(serialiseTask) });
  } catch (error) {
    return next(error);
  }
});

/**
 * Hand out a department task — the second half of the hierarchy.
 *
 * The Lead of the department this landed on either names a member or takes it
 * themselves, and prices it at the same moment, because that is the point at
 * which somebody actually knows what it is worth.
 */
router.post('/:id/assign', async (request, response, next) => {
  try {
    const actor = request.user;
    const id = oid(request.params.id, 'Task id');
    const task = await col(C.tasks).findOne({ _id: id });
    if (!task) fail('Task not found.', 404);

    if (!canDistributeDepartmentTask(actor, task.departmentId)) {
      fail('Only this department\'s Lead can hand this out.', 403);
    }
    if (task.status === 'completed' || task.status === 'cancelled') {
      fail('That one is already finished.');
    }

    const targetId = oid(request.body.assignedTo, 'Member');
    const target = await col(C.users).findOne({ _id: targetId, approvalStatus: 'approved' });
    if (!target) fail('That member is not available.');

    // A Lead may name themselves or one of their own. Nobody else.
    const isSelf = String(target._id) === String(actor._id);
    const inDepartment = target.departmentId
      && String(target.departmentId) === String(task.departmentId);
    if (!isSelf && !inDepartment) {
      fail(`${target.name} is not in that department.`, 403);
    }

    const update = { assignedTo: target._id, updatedAt: new Date() };
    if (isValidTaskPoints(request.body.points)) update.points = Number(request.body.points);
    if (request.body.dueDate !== undefined) {
      const due = request.body.dueDate ? new Date(request.body.dueDate) : null;
      if (due && Number.isNaN(due.getTime())) fail('Due date is not a valid date.');
      update.dueDate = due;
    }

    const updated = await col(C.tasks).findOneAndUpdate(
      { _id: id }, { $set: update }, { returnDocument: 'after' },
    );

    if (!isSelf) {
      await notify(target._id, 'taskAssigned', {
        taskTitle: task.title, byName: actor.name,
      });
    }
    await audit(actor._id, 'task.distribute', {
      taskId: String(id), to: String(target._id), points: updated.points,
    });

    response.json({ task: serialiseTask(updated) });
  } catch (error) {
    next(error);
  }
});

/** Update status, or edit fields if you are the assigner. */
router.patch('/:id', async (request, response, next) => {
  try {
    const actor = request.user;
    const id = oid(request.params.id, 'Task id');
    const task = await col(C.tasks).findOne({ $and: [{ _id: id }, taskVisibilityFilter(actor)] });
    if (!task) fail('Task not found.', 404);

    const update = { updatedAt: new Date() };
    let pointsAwarded = 0;

    if (request.body.status && request.body.status !== task.status) {
      const verdict = canChangeTaskStatus(actor, task, request.body.status);
      if (!verdict.ok) fail(verdict.reason, 403);
      update.status = request.body.status;

      if (request.body.status === 'completed') {
        update.completedAt = new Date();
        // Points land once. Reopening and re-completing must not farm them.
        // Supervisors (Directors, Faculty Coordinator) oversee rather than
        // compete, so work they complete themselves credits nothing.
        if (!task.completedAt && earnsPoints(actor.role)) {
          pointsAwarded = task.points ?? config.pointsPerTask;
        }
      }
      if (request.body.status === 'blocked') {
        update.blockedReason = typeof request.body.blockedReason === 'string'
          ? request.body.blockedReason.trim()
          : '';
      }
    }

    // Who may rewrite the task itself: whoever raised it, a supervisor, and —
    // for work addressed to a department — that department's Lead. The Lead is
    // the one who priced it and handed it out, so they have to be able to
    // correct it; without this a task created by the President is frozen the
    // moment it reaches the person actually managing it.
    const isAssigner = String(task.assignedBy) === String(actor._id)
      || isSupervisor(actor.role)
      || canDistributeDepartmentTask(actor, task.departmentId);
    if (isAssigner) {
      if (typeof request.body.title === 'string') update.title = text(request.body.title, 'Title', { max: 200 });
      if (typeof request.body.description === 'string') update.description = request.body.description.trim();
      if (request.body.dueDate !== undefined) {
        const due = request.body.dueDate ? new Date(request.body.dueDate) : null;
        if (due && Number.isNaN(due.getTime())) fail('Due date is not a valid date.');
        update.dueDate = due;
      }
      if (['low', 'normal', 'high'].includes(request.body.priority)) update.priority = request.body.priority;
      // Repricing is allowed until it is done — after that the number is part
      // of the record and changing it rewrites history.
      if (request.body.points !== undefined && task.status !== 'completed') {
        if (!isValidTaskPoints(request.body.points)) fail('A task is worth 1, 3 or 5 points.');
        update.points = Number(request.body.points);
      }
    }

    const updated = await col(C.tasks).findOneAndUpdate(
      { _id: id },
      { $set: update },
      { returnDocument: 'after' },
    );

    if (pointsAwarded > 0) {
      await col(C.users).updateOne({ _id: task.assignedTo }, { $inc: { points: pointsAwarded } });
      await notify(task.assignedTo, 'pointsEarned', { points: pointsAwarded, reason: task.title });

      // The department Lead is credited too.
      //
      // Their job is getting their team's work done, so a department that
      // delivers is a Lead who delivered — crediting only the pair of hands
      // makes running a department look like doing nothing. Never twice: a
      // Lead who did the task themselves earns it once.
      if (task.departmentId) {
        const department = await col(C.departments).findOne(
          { _id: task.departmentId }, { projection: { leadUserId: 1 } },
        );
        const leadId = department?.leadUserId;
        if (leadId && String(leadId) !== String(task.assignedTo)) {
          const lead = await col(C.users).findOne({ _id: leadId }, { projection: { role: 1 } });
          if (lead && earnsPoints(lead.role)) {
            await col(C.users).updateOne({ _id: leadId }, { $inc: { points: pointsAwarded } });
            await notify(leadId, 'pointsEarned', {
              points: pointsAwarded,
              reason: `Your department finished "${task.title}"`,
            });
          }
        }
      }

      if (String(task.assignedBy) !== String(task.assignedTo)) {
        await notify(task.assignedBy, 'taskCompleted', { taskTitle: task.title, byName: actor.name });
      }
    }

    await audit(actor._id, 'task.update', { taskId: String(id), status: update.status ?? task.status });
    response.json({ task: serialiseTask(updated) });
  } catch (error) {
    next(error);
  }
});

/** Threaded discussion, so context stays attached to the work (Section 10). */
router.post('/:id/comments', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Task id');
    const task = await col(C.tasks).findOne({ $and: [{ _id: id }, taskVisibilityFilter(request.user)] });
    if (!task) fail('Task not found.', 404);
    const body = text(request.body.body, 'Comment', { max: 2000 });

    const comment = {
      taskId: id,
      authorId: request.user._id,
      authorName: request.user.name,
      body,
      createdAt: new Date(),
    };
    const inserted = await col(C.comments).insertOne(comment);

    // Tell the other party, never yourself.
    const others = [task.assignedTo, task.assignedBy]
      .filter((u) => u && String(u) !== String(request.user._id))
      .map(String);
    await notify([...new Set(others)].map((s) => new ObjectId(s)), 'taskComment', {
      taskTitle: task.title,
      byName: request.user.name,
    });

    response.status(201).json({
      comment: { id: String(inserted.insertedId), ...comment, taskId: String(id), authorId: String(request.user._id) },
    });
  } catch (error) {
    next(error);
  }
});

router.delete('/:id', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Task id');
    const task = await col(C.tasks).findOne({ _id: id });
    if (!task) fail('Task not found.', 404);
    // Who can withdraw a task: whoever set it, the club's oversight, the
    // President, and the Lead of the department it sits in — a Lead owns their
    // department's board, including tidying something off it that leadership
    // sent and then changed their mind about.
    const actor = request.user;
    const mayDelete = String(task.assignedBy) === String(actor._id)
      || isSupervisor(actor.role)
      || actor.role === ROLES.president
      || canDistributeDepartmentTask(actor, task.departmentId);
    if (!mayDelete) {
      fail('Only the person who set this task, its department Lead, or club leadership can remove it.', 403);
    }
    await col(C.tasks).deleteOne({ _id: id });
    // Take the conversation with it. Comments are addressed by task id and
    // reachable no other way, so leaving them behind accumulates rows nobody
    // can read or delete for the life of the database.
    await col(C.comments).deleteMany({ taskId: id });
    await audit(request.user._id, 'task.delete', { taskId: String(id) });
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

module.exports = router;

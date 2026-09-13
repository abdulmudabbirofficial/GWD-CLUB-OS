'use strict';

const express = require('express');
const { ObjectId } = require('mongodb');
const config = require('../config');
const { col, C } = require('../db');
const { authenticate, requireApproved, fail } = require('../auth');
const { canRequestTo } = require('../permissions');
const { notify, audit } = require('../services/notify');

const router = express.Router();
router.use(authenticate, requireApproved);

const oid = (value, name) => {
  if (!ObjectId.isValid(value)) fail(`${name} is not valid.`);
  return new ObjectId(value);
};

/**
 * Task requests (Section 3).
 *
 * The difference from a task: a request cannot be imposed. Leads use it
 * sideways to other Leads and upward to the executive tier, where they have no
 * authority to assign. Accepting one is what actually creates the task.
 */

function serialise(r) {
  return {
    id: String(r._id),
    fromUserId: String(r.fromUserId),
    fromName: r.fromName,
    toUserId: String(r.toUserId),
    toName: r.toName,
    title: r.title,
    description: r.description ?? '',
    dueDate: r.dueDate ?? null,
    status: r.status,
    createdAt: r.createdAt,
    decidedAt: r.decidedAt ?? null,
    // Which department is asking. The recipient reads "Technical needs a hand"
    // rather than a bare name they may not place. Null on requests raised
    // before this existed, and on anyone with no department.
    fromDepartmentId: r.fromDepartmentId ? String(r.fromDepartmentId) : null,
    fromDepartmentName: r.fromDepartmentName ?? null,
  };
}

/** The only values `status` may legitimately take. */
const REQUEST_STATUSES = ['pending', 'accepted', 'declined'];

router.get('/', async (request, response, next) => {
  try {
    const me = request.user._id;
    const direction = request.query.direction ?? 'incoming';
    const filter = direction === 'outgoing' ? { fromUserId: me } : { toUserId: me };
    // Checked against the known statuses, never passed through: an unchecked
    // query value lets a caller send an operator where a string belongs.
    if (REQUEST_STATUSES.includes(request.query.status)) {
      filter.status = request.query.status;
    }
    const requests = await col(C.taskRequests).find(filter).sort({ createdAt: -1 }).limit(200).toArray();
    response.json({ requests: requests.map(serialise) });
  } catch (error) {
    next(error);
  }
});

/**
 * Ask somebody — or a whole department — to take something on.
 *
 * Two shapes, same row:
 *
 *   { toUserId }        a named person
 *   { toDepartmentId }  a department, resolved to its Lead
 *
 * The second exists because that is how the work is actually described:
 * "Technical needs Production and Creative on the stage rig". The requesting
 * Lead knows which *department* they need, not which person in it is free —
 * the same reasoning that makes leadership address departments rather than
 * names. The receiving Lead decides whether to take it themselves or pass it on
 * once it becomes a task.
 */
router.post('/', async (request, response, next) => {
  try {
    const actor = request.user;

    let target = null;
    if (request.body.toDepartmentId) {
      const departmentId = oid(request.body.toDepartmentId, 'Department');
      const department = await col(C.departments)
        .findOne({ _id: departmentId, active: { $ne: false } });
      if (!department) fail('That department is not available.');
      if (String(departmentId) === String(actor.departmentId ?? '')) {
        fail('That is your own department — assign it rather than asking.');
      }
      if (!department.leadUserId) {
        fail(`${department.name} has no Lead yet, so there is nobody to receive this.`, 409);
      }
      target = await col(C.users)
        .findOne({ _id: department.leadUserId, approvalStatus: 'approved' });
      if (!target) fail(`${department.name}'s Lead is not available.`, 409);
    } else {
      const toUserId = oid(request.body.toUserId, 'Recipient');
      target = await col(C.users).findOne({ _id: toUserId, approvalStatus: 'approved' });
      if (!target) fail('That person is not available.');
    }

    if (!canRequestTo(actor, target)) fail(`You cannot send a task request to ${target.name}.`, 403);

    const title = typeof request.body.title === 'string' ? request.body.title.trim() : '';
    if (title.length < 2) fail('Give the request a title.');

    const dueDate = request.body.dueDate ? new Date(request.body.dueDate) : null;
    if (dueDate && Number.isNaN(dueDate.getTime())) fail('Due date is not a valid date.');

    // Which department is asking, so the recipient reads "Technical needs a
    // hand" rather than a bare name they may not place.
    const fromDepartment = actor.departmentId
      ? await col(C.departments).findOne({ _id: actor.departmentId }, { projection: { name: 1 } })
      : null;

    const doc = {
      fromUserId: actor._id,
      fromName: actor.name,
      fromDepartmentId: actor.departmentId ?? null,
      fromDepartmentName: fromDepartment?.name ?? null,
      toUserId: target._id,
      toName: target.name,
      toDepartmentId: target.departmentId ?? null,
      title: title.slice(0, 200),
      description: typeof request.body.description === 'string' ? request.body.description.trim() : '',
      dueDate,
      status: 'pending',
      createdAt: new Date(),
    };
    const inserted = await col(C.taskRequests).insertOne(doc);
    doc._id = inserted.insertedId;

    await notify(target._id, 'taskRequestReceived', {
      taskTitle: doc.title,
      fromName: fromDepartment ? `${actor.name} (${fromDepartment.name})` : actor.name,
    });
    await audit(actor._id, 'taskRequest.create', { toUserId: String(target._id), title: doc.title });

    response.status(201).json({ request: serialise(doc) });
  } catch (error) {
    next(error);
  }
});

/** Accepting converts the request into a real task owned by the recipient. */
router.post('/:id/accept', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Request id');
    const taskRequest = await col(C.taskRequests).findOne({ _id: id });
    if (!taskRequest) fail('Request not found.', 404);
    if (String(taskRequest.toUserId) !== String(request.user._id)) {
      fail('Only the recipient can accept this request.', 403);
    }
    if (taskRequest.status !== 'pending') fail('That request has already been decided.', 409);

    const now = new Date();
    const task = {
      title: taskRequest.title,
      description: taskRequest.description ?? '',
      assignedBy: taskRequest.fromUserId,
      assignedTo: taskRequest.toUserId,
      departmentId: request.user.departmentId ?? null,
      status: 'pending',
      dueDate: taskRequest.dueDate ?? null,
      points: config.pointsPerTask,
      priority: 'normal',
      originRequestId: id,
      // Kept so the accepting department can see who the work is for. A
      // cross-department job that loses track of who asked becomes orphaned
      // the moment the person who accepted it moves on.
      requestedByDepartmentId: taskRequest.fromDepartmentId ?? null,
      requestedByDepartmentName: taskRequest.fromDepartmentName ?? null,
      createdAt: now,
      updatedAt: now,
      completedAt: null,
    };
    await col(C.tasks).insertOne(task);
    await col(C.taskRequests).updateOne({ _id: id }, { $set: { status: 'accepted', decidedAt: now } });

    await notify(taskRequest.fromUserId, 'taskRequestAccepted', {
      taskTitle: taskRequest.title, byName: request.user.name,
    });
    await audit(request.user._id, 'taskRequest.accept', { requestId: String(id) });

    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

router.post('/:id/decline', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Request id');
    const taskRequest = await col(C.taskRequests).findOne({ _id: id });
    if (!taskRequest) fail('Request not found.', 404);
    if (String(taskRequest.toUserId) !== String(request.user._id)) {
      fail('Only the recipient can decline this request.', 403);
    }
    if (taskRequest.status !== 'pending') fail('That request has already been decided.', 409);

    await col(C.taskRequests).updateOne(
      { _id: id },
      { $set: { status: 'declined', decidedAt: new Date(), declineReason: (request.body.reason ?? '').toString().slice(0, 500) } },
    );
    await notify(taskRequest.fromUserId, 'taskRequestDeclined', {
      taskTitle: taskRequest.title, byName: request.user.name,
    });
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

module.exports = router;

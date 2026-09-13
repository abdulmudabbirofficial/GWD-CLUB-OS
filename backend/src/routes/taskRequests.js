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

router.post('/', async (request, response, next) => {
  try {
    const actor = request.user;
    const toUserId = oid(request.body.toUserId, 'Recipient');
    const target = await col(C.users).findOne({ _id: toUserId, approvalStatus: 'approved' });
    if (!target) fail('That person is not available.');
    if (!canRequestTo(actor, target)) fail(`You cannot send a task request to ${target.name}.`, 403);

    const title = typeof request.body.title === 'string' ? request.body.title.trim() : '';
    if (title.length < 2) fail('Give the request a title.');

    const dueDate = request.body.dueDate ? new Date(request.body.dueDate) : null;
    if (dueDate && Number.isNaN(dueDate.getTime())) fail('Due date is not a valid date.');

    const doc = {
      fromUserId: actor._id,
      fromName: actor.name,
      toUserId: target._id,
      toName: target.name,
      title: title.slice(0, 200),
      description: typeof request.body.description === 'string' ? request.body.description.trim() : '',
      dueDate,
      status: 'pending',
      createdAt: new Date(),
    };
    const inserted = await col(C.taskRequests).insertOne(doc);
    doc._id = inserted.insertedId;

    await notify(target._id, 'taskRequestReceived', { taskTitle: doc.title, fromName: actor.name });
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

'use strict';

const express = require('express');
const { ObjectId } = require('mongodb');
const { col, C } = require('../db');
const { authenticate, requireApproved, fail } = require('../auth');
const { canBroadcast, ROLES, isSupervisor, rankOf, RANK } = require('../permissions');
const { notify, audit } = require('../services/notify');

const router = express.Router();
router.use(authenticate, requireApproved);

/**
 * Broadcast alerts.
 *
 * The thing a club actually needs at 4pm on event day: "venue moved to Block C,
 * be there in 20 minutes", reaching everyone at once.
 *
 * Two deliberate constraints keep it from decaying into noise:
 *   1. Members cannot broadcast. Once everyone can page everyone, nobody reads
 *      any of it.
 *   2. Every broadcast is signed and kept. You can see who raised the club and
 *      when, which is the only thing that makes people use it sparingly.
 */

const URGENCIES = ['normal', 'important', 'urgent'];

/** Who is in scope for a given audience choice. */
async function resolveAudience(actor, audience, departmentId) {
  const base = { approvalStatus: 'approved', _id: { $ne: actor._id } };

  switch (audience) {
    case 'department': {
      // A Lead broadcasting to their own department is the common case.
      const target = departmentId && ObjectId.isValid(departmentId)
        ? new ObjectId(departmentId)
        : actor.departmentId;
      if (!target) fail('Choose a department to alert.');
      if (
        actor.role === ROLES.clubLead &&
        String(target) !== String(actor.departmentId)
      ) {
        fail('You can only alert your own department.', 403);
      }
      return { ...base, departmentId: target };
    }
    case 'leadership':
      return {
        ...base,
        role: {
          $in: [
            ROLES.clubDirector,
            ROLES.facultyCoordinator,
            ROLES.president,
            ROLES.vicePresident,
            ROLES.secretaryGeneral,
            ROLES.clubLead,
          ],
        },
      };
    case 'club':
    default:
      return base;
  }
}

router.get('/audiences', async (request, response, next) => {
  try {
    const actor = request.user;
    if (!canBroadcast(actor.role)) return response.json({ canBroadcast: false, audiences: [] });

    const audiences = [{ id: 'club', label: 'Everyone in the club' }];
    if (actor.departmentId) {
      const department = await col(C.departments).findOne({ _id: actor.departmentId });
      audiences.push({
        id: 'department',
        label: department ? `${department.name} only` : 'My department only',
      });
    }
    if (rankOf(actor.role) >= RANK.clubLead) {
      audiences.push({ id: 'leadership', label: 'Leadership team only' });
    }
    response.json({ canBroadcast: true, audiences });
  } catch (error) {
    next(error);
  }
});

router.post('/', async (request, response, next) => {
  try {
    const actor = request.user;
    if (!canBroadcast(actor.role)) {
      fail('Your role cannot send club alerts.', 403);
    }

    const title = typeof request.body.title === 'string' ? request.body.title.trim() : '';
    const message = typeof request.body.message === 'string' ? request.body.message.trim() : '';
    if (title.length < 3) fail('Give the alert a subject.');
    if (message.length < 3) fail('Write the alert message.');

    const urgency = URGENCIES.includes(request.body.urgency) ? request.body.urgency : 'normal';
    // Only supervisors and the President can mark something truly urgent, so
    // "urgent" keeps meaning something.
    if (urgency === 'urgent' && !isSupervisor(actor.role) && actor.role !== ROLES.president) {
      fail('Only the President and supervisors can send an urgent alert.', 403);
    }

    const audience = ['club', 'department', 'leadership'].includes(request.body.audience)
      ? request.body.audience
      : 'club';
    const filter = await resolveAudience(actor, audience, request.body.departmentId);

    const recipients = await col(C.users)
      .find(filter, { projection: { _id: 1 } })
      .toArray();
    if (recipients.length === 0) fail('There is nobody in that audience yet.');

    const broadcast = {
      title: title.slice(0, 120),
      message: message.slice(0, 1000),
      urgency,
      audience,
      departmentId: filter.departmentId ?? null,
      senderId: actor._id,
      senderName: actor.name,
      senderRole: actor.role,
      recipientCount: recipients.length,
      createdAt: new Date(),
    };
    const inserted = await col(C.broadcasts).insertOne(broadcast);

    await notify(recipients.map((r) => r._id), 'clubAlert', {
      alertTitle: broadcast.title,
      alertMessage: broadcast.message,
      urgency,
      senderName: actor.name,
      broadcastId: String(inserted.insertedId),
    });

    await audit(actor._id, 'alert.broadcast', {
      audience, urgency, reach: recipients.length, title: broadcast.title,
    });

    response.status(201).json({
      alert: { id: String(inserted.insertedId), ...broadcast, senderId: String(actor._id) },
      reach: recipients.length,
    });
  } catch (error) {
    next(error);
  }
});

/** Everything that has been broadcast, newest first. Visible to all members. */
router.get('/', async (request, response, next) => {
  try {
    const me = request.user;
    // A member sees club-wide alerts plus their own department's.
    const filter = rankOf(me.role) >= RANK.clubLead
      ? {}
      : {
          $or: [
            { audience: 'club' },
            { audience: 'leadership', ...(rankOf(me.role) >= RANK.clubLead ? {} : { _id: null }) },
            { audience: 'department', departmentId: me.departmentId },
          ],
        };

    const alerts = await col(C.broadcasts)
      .find(filter)
      .sort({ createdAt: -1 })
      .limit(100)
      .toArray();

    response.json({
      alerts: alerts.map((a) => ({
        id: String(a._id),
        title: a.title,
        message: a.message,
        urgency: a.urgency,
        audience: a.audience,
        senderName: a.senderName,
        senderRole: a.senderRole,
        recipientCount: a.recipientCount,
        createdAt: a.createdAt,
      })),
      canBroadcast: canBroadcast(me.role),
    });
  } catch (error) {
    next(error);
  }
});

module.exports = router;

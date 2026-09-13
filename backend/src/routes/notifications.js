'use strict';

const express = require('express');
const { ObjectId } = require('mongodb');
const { col, C } = require('../db');
const { authenticate, requireApproved, fail } = require('../auth');
const { render } = require('../services/notify');

const router = express.Router();
router.use(authenticate, requireApproved);

/**
 * Section 6.5 — the Notifications tab is also the in-app home for anything that
 * arrived as an FCM push while the app was closed, which is why the copy is
 * rendered server-side from the same COPY table push uses. One wording, both
 * surfaces.
 */
router.get('/', async (request, response, next) => {
  try {
    const filter = { userId: request.user._id };
    if (request.query.unread === 'true') filter.read = false;
    const notifications = await col(C.notifications)
      .find(filter)
      .sort({ createdAt: -1 })
      .limit(Math.min(Number(request.query.limit) || 100, 200))
      .toArray();

    const unread = await col(C.notifications).countDocuments({ userId: request.user._id, read: false });

    response.json({
      unread,
      notifications: notifications.map((n) => {
        const copy = render(n.type, n.payload);
        return {
          id: String(n._id),
          type: n.type,
          title: copy.title,
          body: copy.body,
          payload: n.payload ?? {},
          read: Boolean(n.read),
          createdAt: n.createdAt,
        };
      }),
    });
  } catch (error) {
    next(error);
  }
});

router.post('/:id/read', async (request, response, next) => {
  try {
    if (!ObjectId.isValid(request.params.id)) fail('Notification id is not valid.');
    await col(C.notifications).updateOne(
      { _id: new ObjectId(request.params.id), userId: request.user._id },
      { $set: { read: true } },
    );
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

router.post('/read-all', async (request, response, next) => {
  try {
    await col(C.notifications).updateMany(
      { userId: request.user._id, read: false },
      { $set: { read: true } },
    );
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

module.exports = router;

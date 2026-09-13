'use strict';

const express = require('express');
const { ObjectId } = require('mongodb');
const { col, C } = require('../db');
const { authenticate, requireApproved, fail } = require('../auth');
const { rankOf, RANK, isSupervisor } = require('../permissions');
const { notify, audit } = require('../services/notify');

const router = express.Router();
router.use(authenticate, requireApproved);

/**
 * Help & collaboration.
 *
 * Two verbs, deliberately: "I need help" and "I can help". A club's real
 * failure mode is not that nobody will pitch in — it is that the person stuck
 * on a poster at 11pm has no way to say so without it sounding like a
 * complaint, and the person free on Tuesday has no way to find them.
 *
 * So this is a board, not a ticketing system. No SLAs, no priority matrix, no
 * assignment authority: anybody can offer, anybody can step back, and the
 * person who asked decides when it is done.
 *
 * Visible club-wide on purpose — a Design member may well be the one who can
 * unstick Marketing, and that only happens if they can see the ask.
 */

const HELP_STATUSES = ['open', 'assigned', 'inProgress', 'resolved'];

const oid = (value, name) => {
  if (!ObjectId.isValid(value)) fail(`${name} is not valid.`);
  return new ObjectId(value);
};

const maybeOid = (value) => (value && ObjectId.isValid(value) ? new ObjectId(value) : null);

/** May this person close or edit someone else's request? */
const canModerate = (actor) => isSupervisor(actor.role) || rankOf(actor.role) >= RANK.vicePresident;

function serialise(request, { userName, deptName, actorId }) {
  const helpers = request.helpers ?? [];
  return {
    id: String(request._id),
    title: request.title,
    description: request.description ?? '',
    status: request.status,
    skills: request.skills ?? [],
    departmentId: request.departmentId ? String(request.departmentId) : null,
    departmentName: deptName.get(String(request.departmentId)) ?? null,
    eventId: request.eventId ? String(request.eventId) : null,
    eventName: request.eventName ?? null,
    createdBy: String(request.createdBy),
    createdByName: userName.get(String(request.createdBy)) ?? 'Member',
    createdAt: request.createdAt,
    resolvedAt: request.resolvedAt ?? null,
    helpers: helpers.map((h) => ({
      id: String(h.userId),
      name: userName.get(String(h.userId)) ?? 'Member',
      note: h.note ?? '',
      at: h.at,
    })),
    mine: String(request.createdBy) === String(actorId),
    helping: helpers.some((h) => String(h.userId) === String(actorId)),
  };
}

router.get('/', async (request, response, next) => {
  try {
    const filter = {};
    if (HELP_STATUSES.includes(request.query.status)) filter.status = request.query.status;
    if (request.query.open === 'true') filter.status = { $ne: 'resolved' };
    if (request.query.departmentId && ObjectId.isValid(request.query.departmentId)) {
      filter.departmentId = new ObjectId(request.query.departmentId);
    }
    if (request.query.mine === 'true') {
      filter.$or = [
        { createdBy: request.user._id },
        { 'helpers.userId': request.user._id },
      ];
    }

    const requests = await col(C.helpRequests)
      .find(filter).sort({ status: 1, createdAt: -1 }).limit(200).toArray();

    const ids = requests.flatMap((r) => [
      r.createdBy, ...(r.helpers ?? []).map((h) => h.userId),
    ]).filter(Boolean);
    const [people, departments] = await Promise.all([
      col(C.users).find({ _id: { $in: ids } }, { projection: { name: 1 } }).toArray(),
      col(C.departments).find({}, { projection: { name: 1 } }).toArray(),
    ]);
    const userName = new Map(people.map((p) => [String(p._id), p.name]));
    const deptName = new Map(departments.map((d) => [String(d._id), d.name]));

    const items = requests.map(
      (r) => serialise(r, { userName, deptName, actorId: request.user._id }),
    );
    response.json({
      requests: items,
      openCount: items.filter((r) => r.status !== 'resolved').length,
    });
  } catch (error) {
    next(error);
  }
});

/** "I need help." Open to everyone — that is the entire point. */
router.post('/', async (request, response, next) => {
  try {
    const title = typeof request.body.title === 'string' ? request.body.title.trim() : '';
    if (title.length < 4) fail('Say in a line what you need a hand with.');

    const eventId = maybeOid(request.body.eventId);
    let eventName = null;
    if (eventId) {
      const event = await col(C.events).findOne({ _id: eventId }, { projection: { name: 1 } });
      eventName = event?.name ?? null;
    }

    const doc = {
      title: title.slice(0, 160),
      description: typeof request.body.description === 'string'
        ? request.body.description.trim().slice(0, 2000) : '',
      status: 'open',
      skills: Array.isArray(request.body.skills)
        ? request.body.skills.filter((s) => typeof s === 'string' && s.trim())
          .slice(0, 6).map((s) => s.trim().slice(0, 40))
        : [],
      // Defaults to your own department, because that is nearly always the
      // right answer and one fewer field to fill in at 11pm.
      departmentId: maybeOid(request.body.departmentId) ?? request.user.departmentId ?? null,
      eventId,
      eventName,
      createdBy: request.user._id,
      createdAt: new Date(),
      helpers: [],
      resolvedAt: null,
    };
    const inserted = await col(C.helpRequests).insertOne(doc);

    // Tell the department this lands on — not the whole club. A club-wide ping
    // for every "can someone proofread this" is how people mute the app.
    if (doc.departmentId) {
      const colleagues = await col(C.users).find(
        { departmentId: doc.departmentId, approvalStatus: 'approved', _id: { $ne: request.user._id } },
        { projection: { _id: 1 } },
      ).toArray();
      await notify(colleagues.map((u) => u._id), 'helpRequested', {
        helpTitle: doc.title, byName: request.user.name, helpId: String(inserted.insertedId),
      });
    }

    await audit(request.user._id, 'help.create', { helpId: String(inserted.insertedId), title: doc.title });
    response.status(201).json({ id: String(inserted.insertedId) });
  } catch (error) {
    next(error);
  }
});

/** "I can help." */
router.post('/:id/offer', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Request id');
    const help = await col(C.helpRequests).findOne({ _id: id });
    if (!help) fail('That request no longer exists.', 404);
    if (help.status === 'resolved') fail('That one is already sorted.');
    if (String(help.createdBy) === String(request.user._id)) {
      fail('You raised this one yourself.');
    }
    if ((help.helpers ?? []).some((h) => String(h.userId) === String(request.user._id))) {
      fail('You are already on this one.');
    }

    await col(C.helpRequests).updateOne({ _id: id }, {
      $push: {
        helpers: {
          userId: request.user._id,
          note: typeof request.body.note === 'string' ? request.body.note.trim().slice(0, 300) : '',
          at: new Date(),
        },
      },
      $set: { status: help.status === 'open' ? 'assigned' : help.status },
    });

    await notify(help.createdBy, 'helpOffered', {
      helpTitle: help.title, byName: request.user.name, helpId: String(id),
    });
    await audit(request.user._id, 'help.offer', { helpId: String(id) });
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

/** Step back out. Offering to help must never be a trap. */
router.delete('/:id/offer', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Request id');
    const help = await col(C.helpRequests).findOne({ _id: id });
    if (!help) fail('That request no longer exists.', 404);

    const remaining = (help.helpers ?? [])
      .filter((h) => String(h.userId) !== String(request.user._id));
    await col(C.helpRequests).updateOne({ _id: id }, {
      $set: {
        helpers: remaining,
        status: remaining.length === 0 && help.status !== 'resolved' ? 'open' : help.status,
      },
    });
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

/**
 * Move it along.
 *
 * The person who asked decides when it is resolved — not a helper, and not a
 * Lead tidying the board. Someone else marking your problem solved is the
 * fastest way to make people stop asking.
 */
router.post('/:id/status', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Request id');
    const help = await col(C.helpRequests).findOne({ _id: id });
    if (!help) fail('That request no longer exists.', 404);

    const status = request.body.status;
    if (!HELP_STATUSES.includes(status)) fail('Unknown status.');

    const mine = String(help.createdBy) === String(request.user._id);
    const helping = (help.helpers ?? []).some((h) => String(h.userId) === String(request.user._id));

    if (status === 'resolved' && !mine && !canModerate(request.user)) {
      fail('Only the person who asked can mark this sorted.', 403);
    }
    if (!mine && !helping && !canModerate(request.user)) {
      fail('You are not part of this one.', 403);
    }

    await col(C.helpRequests).updateOne({ _id: id }, {
      $set: { status, resolvedAt: status === 'resolved' ? new Date() : null },
    });

    if (status === 'resolved') {
      const thank = (help.helpers ?? [])
        .map((h) => h.userId)
        .filter((uid) => String(uid) !== String(request.user._id));
      await notify(thank, 'helpResolved', { helpTitle: help.title, helpId: String(id) });
    }
    await audit(request.user._id, 'help.status', { helpId: String(id), status });
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

router.delete('/:id', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Request id');
    const help = await col(C.helpRequests).findOne({ _id: id });
    if (!help) fail('That request no longer exists.', 404);
    if (String(help.createdBy) !== String(request.user._id) && !canModerate(request.user)) {
      fail('Only the person who asked can withdraw this.', 403);
    }
    await col(C.helpRequests).deleteOne({ _id: id });
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

module.exports = router;

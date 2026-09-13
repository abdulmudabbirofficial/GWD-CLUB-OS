'use strict';

const express = require('express');
const { ObjectId } = require('mongodb');
const { col, C } = require('../db');
const { authenticate, requireApproved, fail } = require('../auth');
const { canManageDepartments } = require('../permissions');
const { audit } = require('../services/notify');

const router = express.Router();
router.use(authenticate, requireApproved);

/**
 * Schedule categories.
 *
 * The schedule used to have three fixed kinds of thing, which was the same
 * mistake departments started out with: a club's calendar holds rehearsals,
 * shoots, sponsor visits, exam breaks, orientation drives — whatever that club
 * actually does. So categories are data, created and renamed at runtime by the
 * same tier that manages departments.
 *
 * `deadline` is the one exception: it is derived from tasks and cannot be
 * created, renamed or deleted, because it does not describe a category of
 * *entry* — it describes work that already exists elsewhere.
 */

/** Icon names the client knows how to draw. Kept as a closed set so a typo
 *  cannot produce an entry that renders as a blank square. */
const ICONS = [
  'event', 'meeting', 'marketing', 'deadline', 'workshop', 'shoot',
  'rehearsal', 'sponsor', 'travel', 'social', 'deliverable', 'exam',
  'volunteer', 'budget', 'flag',
];

const PALETTE = [
  '#DC2626', '#334155', '#7C3AED', '#B45309', '#0891B2',
  '#15803D', '#BE123C', '#4338CA', '#A16207', '#0F766E',
];

/** Seeded on first run. Editable and removable like any other. */
const STARTER = [
  { name: 'Event', icon: 'event', color: '#DC2626', blurb: 'Fests, sessions and everything the club puts on' },
  { name: 'Meeting', icon: 'meeting', color: '#334155', blurb: 'Team syncs and department meetings' },
  { name: 'Marketing', icon: 'marketing', color: '#7C3AED', blurb: 'What goes out, where, and when' },
  { name: 'Shoot', icon: 'shoot', color: '#0891B2', blurb: 'Photo and video shoots' },
  { name: 'Rehearsal', icon: 'rehearsal', color: '#15803D', blurb: 'Run-throughs before the real thing' },
];

async function ensureSeeded() {
  const count = await col(C.scheduleCategories).countDocuments({});
  if (count > 0) return;
  await col(C.scheduleCategories).insertMany(
    STARTER.map((c, i) => ({
      ...c,
      active: true,
      order: i,
      builtIn: true,
      createdBy: null,
      createdAt: new Date(),
    })),
  );
}

function serialise(c) {
  return {
    id: String(c._id),
    name: c.name,
    icon: c.icon ?? 'flag',
    color: c.color ?? '#DC2626',
    blurb: c.blurb ?? '',
    active: c.active !== false,
    order: c.order ?? 0,
    builtIn: Boolean(c.builtIn),
  };
}

router.get('/schedule', async (request, response, next) => {
  try {
    await ensureSeeded();
    const includeInactive = request.query.includeInactive === 'true'
      && canManageDepartments(request.user.role);
    const categories = await col(C.scheduleCategories)
      .find(includeInactive ? {} : { active: { $ne: false } })
      .sort({ order: 1, name: 1 })
      .toArray();

    // How many upcoming entries each one holds, so the picker can show what is
    // actually in use rather than a wall of equal-looking options.
    const counts = await col(C.calendarEvents).aggregate([
      { $match: { date: { $gte: new Date(Date.now() - 86400000) } } },
      { $group: { _id: '$categoryId', n: { $sum: 1 } } },
    ]).toArray();
    const byId = new Map(counts.map((c) => [String(c._id), c.n]));

    response.json({
      categories: categories.map((c) => ({ ...serialise(c), count: byId.get(String(c._id)) ?? 0 })),
      canManage: canManageDepartments(request.user.role),
      icons: ICONS,
      palette: PALETTE,
    });
  } catch (error) {
    next(error);
  }
});

function requireManage(request, response, next) {
  if (!canManageDepartments(request.user.role)) {
    return next(Object.assign(
      new Error('Only the President and supervisors can manage categories.'),
      { status: 403 },
    ));
  }
  return next();
}

router.post('/schedule', requireManage, async (request, response, next) => {
  try {
    const name = typeof request.body.name === 'string' ? request.body.name.trim() : '';
    if (name.length < 2) fail('Give the category a name.');
    if (name.length > 30) fail('Keep the name short — it has to fit on a chip.');
    if (await col(C.scheduleCategories).findOne({ name })) {
      fail('A category with that name already exists.', 409);
    }

    const last = await col(C.scheduleCategories).find({}).sort({ order: -1 }).limit(1).toArray();
    const doc = {
      name,
      icon: ICONS.includes(request.body.icon) ? request.body.icon : 'flag',
      color: PALETTE.includes(request.body.color) ? request.body.color : PALETTE[0],
      blurb: typeof request.body.blurb === 'string' ? request.body.blurb.trim().slice(0, 120) : '',
      active: true,
      order: (last[0]?.order ?? 0) + 1,
      builtIn: false,
      createdBy: request.user._id,
      createdAt: new Date(),
    };
    const inserted = await col(C.scheduleCategories).insertOne(doc);
    doc._id = inserted.insertedId;
    await audit(request.user._id, 'category.create', { name });
    response.status(201).json({ category: serialise(doc) });
  } catch (error) {
    next(error);
  }
});

router.patch('/schedule/:id', requireManage, async (request, response, next) => {
  try {
    if (!ObjectId.isValid(request.params.id)) fail('Category id is not valid.');
    const id = new ObjectId(request.params.id);
    const update = {};
    if (typeof request.body.name === 'string') {
      const name = request.body.name.trim();
      if (name.length < 2) fail('Give the category a name.');
      const clash = await col(C.scheduleCategories).findOne({ name, _id: { $ne: id } });
      if (clash) fail('A category with that name already exists.', 409);
      update.name = name.slice(0, 30);
    }
    if (ICONS.includes(request.body.icon)) update.icon = request.body.icon;
    if (PALETTE.includes(request.body.color)) update.color = request.body.color;
    if (typeof request.body.blurb === 'string') update.blurb = request.body.blurb.trim().slice(0, 120);
    if (typeof request.body.active === 'boolean') update.active = request.body.active;
    if (Object.keys(update).length === 0) fail('Nothing to change.');

    const updated = await col(C.scheduleCategories).findOneAndUpdate(
      { _id: id }, { $set: update }, { returnDocument: 'after' },
    );
    if (!updated) fail('Category not found.', 404);
    await audit(request.user._id, 'category.update', { id: String(id), ...update });
    response.json({ category: serialise(updated) });
  } catch (error) {
    next(error);
  }
});

/**
 * Deactivate rather than delete while entries still reference it — otherwise
 * every past entry in that category becomes an orphan with no colour or name.
 */
router.delete('/schedule/:id', requireManage, async (request, response, next) => {
  try {
    if (!ObjectId.isValid(request.params.id)) fail('Category id is not valid.');
    const id = new ObjectId(request.params.id);
    const inUse = await col(C.calendarEvents).countDocuments({ categoryId: id });

    if (inUse > 0) {
      const updated = await col(C.scheduleCategories).findOneAndUpdate(
        { _id: id }, { $set: { active: false } }, { returnDocument: 'after' },
      );
      if (!updated) fail('Category not found.', 404);
      return response.json({
        category: serialise(updated),
        deactivated: true,
        message: `Hidden from new entries. ${inUse} existing ${inUse === 1 ? 'entry' : 'entries'} keep it.`,
      });
    }

    const result = await col(C.scheduleCategories).deleteOne({ _id: id });
    if (result.deletedCount === 0) fail('Category not found.', 404);
    await audit(request.user._id, 'category.delete', { id: String(id) });
    return response.json({ deleted: true });
  } catch (error) {
    return next(error);
  }
});

module.exports = router;
module.exports.ensureSeeded = ensureSeeded;
module.exports.ICONS = ICONS;
module.exports.PALETTE = PALETTE;

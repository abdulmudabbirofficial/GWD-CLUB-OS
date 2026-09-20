'use strict';

const express = require('express');
const { ObjectId } = require('mongodb');
const { col, C } = require('../db');
const { authenticate, requireApproved, fail } = require('../auth');
const { canCreateEvent, isSupervisor, ROLES } = require('../permissions');
const { audit } = require('../services/notify');

const router = express.Router();
router.use(authenticate, requireApproved);

/**
 * Event templates — the shape of an event the club runs more than once.
 *
 * Most of a club's calendar is repeats: a workshop a month, a guest lecture a
 * term, the same fest every year. Rebuilding the same departments and the same
 * twenty opening tasks by hand each time is tedious, and tedium is how things
 * get dropped — the poster brief that was in last year's plan and that nobody
 * remembered this year.
 *
 * **Tasks carry an offset, never a date.** `offsetDays: -14` means "fourteen
 * days before the event", and survives being used again next term. A stored
 * date would be wrong the second time it was used and every time after, which
 * is the failure that makes people stop trusting templates and go back to
 * typing everything out.
 *
 * A template is a *starting point*, not a contract. Applying one fills the
 * wizard in and the person then edits it; nothing here is locked, and changing
 * a template later never reaches back into events already created from it.
 * Events created from a template would otherwise mutate under their organisers
 * whenever somebody tidied the template up.
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

const str = (value, max) => (typeof value === 'string' ? value.trim().slice(0, max) : '');

/**
 * The offset a template task carries.
 *
 * Clamped to a year either side. Not because anybody would plan that far out,
 * but because an unbounded number here lands in `Date` arithmetic, and a task
 * dated the year 5000 is a row nobody can delete from a screen that will not
 * render.
 */
function offsetDays(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.max(-365, Math.min(365, Math.round(n)));
}

/** Points are the club's three values, not a free number. See CLAUDE.md. */
const POINTS = [1, 3, 5];
const pointsOf = (value) => (POINTS.includes(Number(value)) ? Number(value) : 1);

function cleanResponsibilities(input) {
  if (!Array.isArray(input)) return [];
  const seen = new Set();
  const out = [];
  for (const entry of input.slice(0, 30)) {
    const departmentId = maybeOid(entry?.departmentId);
    if (!departmentId) continue;
    // One row per department. Two rows for Marketing would produce two
    // responsibility upserts fighting over the same unique index at apply time.
    const key = String(departmentId);
    if (seen.has(key)) continue;
    seen.add(key);

    const tasks = [];
    for (const t of Array.isArray(entry.tasks) ? entry.tasks.slice(0, 50) : []) {
      const title = str(t?.title, 200);
      if (title.length < 2) continue;
      tasks.push({
        title,
        description: str(t?.description, 2000),
        offsetDays: offsetDays(t?.offsetDays),
        points: pointsOf(t?.points),
        priority: ['low', 'normal', 'high'].includes(t?.priority) ? t.priority : 'normal',
      });
    }
    out.push({ departmentId, notes: str(entry.notes, 500), tasks });
  }
  return out;
}

function serialise(template) {
  const responsibilities = (template.responsibilities ?? []).map((r) => ({
    departmentId: String(r.departmentId),
    notes: r.notes ?? '',
    tasks: (r.tasks ?? []).map((t) => ({
      title: t.title,
      description: t.description ?? '',
      offsetDays: t.offsetDays ?? null,
      points: t.points ?? 1,
      priority: t.priority ?? 'normal',
    })),
  }));
  return {
    id: String(template._id),
    name: template.name,
    description: template.description ?? '',
    type: template.type ?? 'event',
    venue: template.venue ?? '',
    startTime: template.startTime ?? '',
    endTime: template.endTime ?? '',
    organizingDepartmentId: template.organizingDepartmentId
      ? String(template.organizingDepartmentId) : null,
    supportingDepartmentIds: (template.supportingDepartmentIds ?? []).map(String),
    responsibilities,
    // Counts, so a card can say what applying this will actually do without
    // the client walking the whole tree to find out.
    departmentCount: responsibilities.length,
    taskCount: responsibilities.reduce((sum, r) => sum + r.tasks.length, 0),
    usageCount: template.usageCount ?? 0,
    lastUsedAt: template.lastUsedAt ?? null,
    createdBy: template.createdBy ? String(template.createdBy) : null,
    createdAt: template.createdAt,
    updatedAt: template.updatedAt,
  };
}

/**
 * Who may delete or edit one.
 *
 * The person who made it, or the executive tier. A template is shared club
 * property once it exists — a Lead who saved "Workshop" and left should not
 * take the club's workshop plan with them — but letting anybody at all edit
 * one means the plan changes under the people using it.
 */
const canEdit = (actor, template) => (
  isSupervisor(actor.role)
  || actor.role === ROLES.president
  || String(template.createdBy ?? '') === String(actor._id)
);

/* ---------------------------------------------------------------- reading */

/**
 * Every template, most-used first.
 *
 * Readable by everyone approved even though not everyone can create an event:
 * seeing that the club has a "Guest Lecture" plan is useful to the member being
 * asked to help run one, and there is nothing private in it.
 */
router.get('/', async (request, response, next) => {
  try {
    const templates = await col(C.eventTemplates)
      .find({ active: { $ne: false } })
      .sort({ usageCount: -1, name: 1 })
      .toArray();
    response.json({ templates: templates.map(serialise) });
  } catch (error) {
    next(error);
  }
});

router.get('/:id', async (request, response, next) => {
  try {
    const template = await col(C.eventTemplates)
      .findOne({ _id: oid(request.params.id, 'Template id') });
    if (!template) fail('That template no longer exists.', 404);
    response.json({ template: serialise(template) });
  } catch (error) {
    next(error);
  }
});

/* ---------------------------------------------------------------- writing */

router.post('/', async (request, response, next) => {
  try {
    const actor = request.user;
    if (!canCreateEvent(actor.role)) fail('Your role cannot create event templates.', 403);

    const now = new Date();
    const template = {
      name: text(request.body.name, 'Template name', { min: 2, max: 160 }),
      description: str(request.body.description, 4000),
      type: str(request.body.type, 60) || 'event',
      venue: str(request.body.venue, 200),
      startTime: str(request.body.startTime, 10),
      endTime: str(request.body.endTime, 10),
      organizingDepartmentId: maybeOid(request.body.organizingDepartmentId),
      supportingDepartmentIds: (request.body.supportingDepartmentIds ?? [])
        .map(maybeOid).filter(Boolean),
      responsibilities: cleanResponsibilities(request.body.responsibilities),
      active: true,
      usageCount: 0,
      lastUsedAt: null,
      createdBy: actor._id,
      createdAt: now,
      updatedAt: now,
    };
    const inserted = await col(C.eventTemplates).insertOne(template);
    template._id = inserted.insertedId;

    await audit(actor._id, 'eventTemplate.create', {
      templateId: String(template._id), name: template.name,
    });
    response.status(201).json({ template: serialise(template) });
  } catch (error) {
    next(error);
  }
});

/**
 * Save an event that already exists as a template.
 *
 * This is how most templates will actually be made. Nobody sits down to write
 * an abstract plan; they finish running a workshop, realise it went well, and
 * want the next one to start from the same place. Asking them to retype it
 * into a template form means it never happens.
 *
 * The event's task dates become offsets from the event date, which is the
 * whole translation: "poster due 1 March" for an event on the 15th becomes
 * "poster due fourteen days before".
 */
router.post('/from-event/:eventId', async (request, response, next) => {
  try {
    const actor = request.user;
    if (!canCreateEvent(actor.role)) fail('Your role cannot create event templates.', 403);

    const eventId = oid(request.params.eventId, 'Event id');
    const event = await col(C.events).findOne({ _id: eventId });
    if (!event) fail('That event no longer exists.', 404);

    const [responsibilities, tasks] = await Promise.all([
      col(C.eventResponsibilities).find({ eventId }).toArray(),
      col(C.tasks).find({ eventId, status: { $ne: 'cancelled' } }).toArray(),
    ]);

    const eventDay = new Date(event.date);
    const dayMs = 24 * 60 * 60 * 1000;
    const byDepartment = new Map();
    for (const r of responsibilities) {
      byDepartment.set(String(r.departmentId), {
        departmentId: r.departmentId, notes: r.notes ?? '', tasks: [],
      });
    }
    for (const t of tasks) {
      const key = String(t.departmentId ?? '');
      if (!byDepartment.has(key)) {
        if (!t.departmentId) continue;
        byDepartment.set(key, { departmentId: t.departmentId, notes: '', tasks: [] });
      }
      // A task with no due date keeps none — inventing "the day of" for it
      // would put a deadline on work that deliberately had none.
      let offset = null;
      if (t.dueDate) {
        const due = new Date(t.dueDate);
        if (!Number.isNaN(due.getTime()) && !Number.isNaN(eventDay.getTime())) {
          offset = offsetDays(Math.round((due - eventDay) / dayMs));
        }
      }
      byDepartment.get(key).tasks.push({
        title: String(t.title ?? '').slice(0, 200),
        description: str(t.description, 2000),
        offsetDays: offset,
        points: pointsOf(t.points),
        priority: ['low', 'normal', 'high'].includes(t.priority) ? t.priority : 'normal',
      });
    }

    const now = new Date();
    const template = {
      name: str(request.body.name, 160) || `${event.name} (template)`,
      description: str(request.body.description, 4000) || (event.description ?? ''),
      type: event.type ?? 'event',
      venue: event.venue ?? '',
      startTime: event.startTime ?? '',
      endTime: event.endTime ?? '',
      organizingDepartmentId: event.organizingDepartmentId ?? null,
      supportingDepartmentIds: event.supportingDepartmentIds ?? [],
      responsibilities: [...byDepartment.values()],
      active: true,
      usageCount: 0,
      lastUsedAt: null,
      createdBy: actor._id,
      createdAt: now,
      updatedAt: now,
    };
    const inserted = await col(C.eventTemplates).insertOne(template);
    template._id = inserted.insertedId;

    await audit(actor._id, 'eventTemplate.create', {
      templateId: String(template._id), name: template.name, fromEvent: String(eventId),
    });
    response.status(201).json({ template: serialise(template) });
  } catch (error) {
    next(error);
  }
});

router.patch('/:id', async (request, response, next) => {
  try {
    const actor = request.user;
    const id = oid(request.params.id, 'Template id');
    const template = await col(C.eventTemplates).findOne({ _id: id });
    if (!template) fail('That template no longer exists.', 404);
    if (!canEdit(actor, template)) fail('Only whoever saved this template can change it.', 403);

    const patch = { updatedAt: new Date() };
    const body = request.body ?? {};
    if (body.name !== undefined) patch.name = text(body.name, 'Template name', { min: 2, max: 160 });
    if (body.description !== undefined) patch.description = str(body.description, 4000);
    if (body.type !== undefined) patch.type = str(body.type, 60) || 'event';
    if (body.venue !== undefined) patch.venue = str(body.venue, 200);
    if (body.startTime !== undefined) patch.startTime = str(body.startTime, 10);
    if (body.endTime !== undefined) patch.endTime = str(body.endTime, 10);
    if (body.organizingDepartmentId !== undefined) {
      patch.organizingDepartmentId = maybeOid(body.organizingDepartmentId);
    }
    if (body.supportingDepartmentIds !== undefined) {
      patch.supportingDepartmentIds = (body.supportingDepartmentIds ?? [])
        .map(maybeOid).filter(Boolean);
    }
    if (body.responsibilities !== undefined) {
      patch.responsibilities = cleanResponsibilities(body.responsibilities);
    }

    await col(C.eventTemplates).updateOne({ _id: id }, { $set: patch });
    const updated = await col(C.eventTemplates).findOne({ _id: id });
    await audit(actor._id, 'eventTemplate.update', {
      templateId: String(id), name: updated.name,
    });
    response.json({ template: serialise(updated) });
  } catch (error) {
    next(error);
  }
});

/**
 * Retire a template.
 *
 * Deactivated rather than removed, matching departments and schedule
 * categories: `usageCount` and the audit trail both point at it, and a hard
 * delete would leave "created from template X" in the log with no X.
 */
router.delete('/:id', async (request, response, next) => {
  try {
    const actor = request.user;
    const id = oid(request.params.id, 'Template id');
    const template = await col(C.eventTemplates).findOne({ _id: id });
    if (!template) fail('That template no longer exists.', 404);
    if (!canEdit(actor, template)) fail('Only whoever saved this template can remove it.', 403);

    await col(C.eventTemplates).updateOne(
      { _id: id },
      { $set: { active: false, updatedAt: new Date() } },
    );
    await audit(actor._id, 'eventTemplate.delete', {
      templateId: String(id), name: template.name,
    });
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

module.exports = router;

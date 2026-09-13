'use strict';

const express = require('express');
const { ObjectId } = require('mongodb');
const { col, C } = require('../db');
const { authenticate, requireApproved, publicUser, fail } = require('../auth');
const {
  canManageDepartments, canViewMemberDetail, canViewDepartmentRoster, ROLES,
} = require('../permissions');
const { notify, audit } = require('../services/notify');

const router = express.Router();

const oid = (value, name) => {
  if (!ObjectId.isValid(value)) fail(`${name} is not valid.`);
  return new ObjectId(value);
};

function serialise(d, memberCount) {
  return {
    id: String(d._id),
    name: d.name,
    description: d.description ?? '',
    leadUserId: d.leadUserId ? String(d.leadUserId) : null,
    active: d.active !== false,
    colorSeed: d.colorSeed ?? null,
    memberCount: memberCount ?? undefined,
    createdAt: d.createdAt,
  };
}

/**
 * Public list — signup needs this *before* the user has an account, so it is
 * the one department route that does not require authentication. It exposes
 * only names and ids of active departments, nothing about people.
 */
router.get('/public', async (request, response, next) => {
  try {
    const departments = await col(C.departments)
      .find({ active: { $ne: false } }, { projection: { name: 1, description: 1, colorSeed: 1 } })
      .sort({ name: 1 })
      .toArray();
    response.json({
      departments: departments.map((d) => ({
        id: String(d._id),
        name: d.name,
        description: d.description ?? '',
        colorSeed: d.colorSeed ?? null,
      })),
    });
  } catch (error) {
    next(error);
  }
});

router.use(authenticate, requireApproved);

router.get('/', async (request, response, next) => {
  try {
    const includeInactive = request.query.includeInactive === 'true'
      && canManageDepartments(request.user.role);
    const filter = includeInactive ? {} : { active: { $ne: false } };
    const departments = await col(C.departments).find(filter).sort({ name: 1 }).toArray();

    const counts = await col(C.users).aggregate([
      { $match: { approvalStatus: 'approved', departmentId: { $ne: null } } },
      { $group: { _id: '$departmentId', n: { $sum: 1 } } },
    ]).toArray();
    const byId = new Map(counts.map((c) => [String(c._id), c.n]));

    // Headline progress travels with every department, so Home and the
    // structure page do not need a second round trip to say anything useful.
    const taskStats = await col(C.tasks).aggregate([
      { $match: { status: { $ne: 'cancelled' } } },
      {
        $group: {
          _id: '$departmentId',
          assigned: { $sum: 1 },
          completed: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] } },
        },
      },
    ]).toArray();
    const statsById = new Map(taskStats.map((s) => [String(s._id), s]));

    response.json({
      departments: departments.map((d) => {
        const s = statsById.get(String(d._id)) ?? { assigned: 0, completed: 0 };
        return {
          ...serialise(d, byId.get(String(d._id)) ?? 0),
          assigned: s.assigned,
          completed: s.completed,
          completionRate:
            s.assigned === 0 ? 0 : Math.round((s.completed / s.assigned) * 100),
        };
      }),
      canManage: canManageDepartments(request.user.role),
    });
  } catch (error) {
    next(error);
  }
});

/**
 * The club, as an org chart.
 *
 * Executive tier first (President, then VP and Secretary General), then every
 * department with its Lead and headline progress. Supervisors are omitted on
 * purpose: Directors and the Faculty Coordinator oversee the club rather than
 * sit inside its structure, and their records are not part of the roster
 * people browse.
 *
 * `canViewRoster` tells the client whether this person may drill into the
 * individual members of that department, or only see its progress.
 */
router.get('/structure', async (request, response, next) => {
  try {
    const actor = request.user;

    const [departments, people, taskStats] = await Promise.all([
      col(C.departments).find({ active: { $ne: false } }).sort({ name: 1 }).toArray(),
      col(C.users).find({ approvalStatus: 'approved' }).toArray(),
      col(C.tasks).aggregate([
        { $match: { status: { $ne: 'cancelled' } } },
        {
          $group: {
            _id: '$departmentId',
            assigned: { $sum: 1 },
            completed: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] } },
            overdue: {
              $sum: {
                $cond: [
                  {
                    $and: [
                      { $in: ['$status', ['pending', 'inProgress', 'blocked']] },
                      { $ne: ['$dueDate', null] },
                      { $lt: ['$dueDate', new Date()] },
                    ],
                  },
                  1, 0,
                ],
              },
            },
          },
        },
      ]).toArray(),
    ]);

    const statsById = new Map(taskStats.map((s) => [String(s._id), s]));
    const byId = new Map(people.map((p) => [String(p._id), p]));

    const brief = (user) => user && ({
      id: String(user._id),
      name: user.name,
      role: user.role,
      avatarColor: user.avatarColor ?? null,
      points: user.points ?? 0,
      canOpen: canViewMemberDetail(actor, user),
    });

    const executive = [ROLES.president, ROLES.vicePresident, ROLES.secretaryGeneral]
      .map((role) => {
        const holder = people.find((p) => p.role === role);
        return {
          role,
          // The seat exists whether or not anybody holds it — an empty
          // Vice President slot is information, not something to hide.
          holder: holder ? brief(holder) : null,
        };
      });

    response.json({
      executive,
      departments: departments.map((d) => {
        const s = statsById.get(String(d._id)) ?? { assigned: 0, completed: 0, overdue: 0 };
        const members = people.filter(
          (p) => p.departmentId && String(p.departmentId) === String(d._id),
        );
        return {
          id: String(d._id),
          name: d.name,
          description: d.description ?? '',
          lead: brief(byId.get(String(d.leadUserId ?? ''))) ?? null,
          memberCount: members.length,
          progress: {
            assigned: s.assigned,
            completed: s.completed,
            overdue: s.overdue,
            completionRate: s.assigned === 0 ? 0 : Math.round((s.completed / s.assigned) * 100),
          },
          canViewRoster: canViewDepartmentRoster(actor, d._id),
        };
      }),
    });
  } catch (error) {
    next(error);
  }
});

/** The people in one department. Gated — a Member only gets their own. */
router.get('/:id/roster', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Department id');
    const department = await col(C.departments).findOne({ _id: id });
    if (!department) fail('Department not found.', 404);
    if (!canViewDepartmentRoster(request.user, id)) {
      fail('You can only open the members of your own department.', 403);
    }

    const members = await col(C.users)
      .find({ departmentId: id, approvalStatus: 'approved' })
      .sort({ name: 1 })
      .toArray();

    const stats = await col(C.tasks).aggregate([
      { $match: { departmentId: id, status: { $ne: 'cancelled' } } },
      {
        $group: {
          _id: '$assignedTo',
          assigned: { $sum: 1 },
          completed: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] } },
        },
      },
    ]).toArray();
    const byId = new Map(stats.map((s) => [String(s._id), s]));

    response.json({
      department: {
        id: String(department._id),
        name: department.name,
        description: department.description ?? '',
        leadUserId: department.leadUserId ? String(department.leadUserId) : null,
      },
      members: members.map((m) => {
        const s = byId.get(String(m._id)) ?? { assigned: 0, completed: 0 };
        return {
          ...publicUser(m),
          isLead: String(department.leadUserId ?? '') === String(m._id),
          assignedTasks: s.assigned,
          completedTasks: s.completed,
          completionRate: s.assigned === 0 ? 0 : Math.round((s.completed / s.assigned) * 100),
        };
      }),
    });
  } catch (error) {
    next(error);
  }
});

/**
 * The department workspace.
 *
 * Section 24: one place per department showing its people, its current work,
 * the events it is on the hook for, and anyone asking it for help.
 *
 * Section 25 is the part that matters: a department's view of an event shows
 * only *that department's* responsibilities. A Marketing member opening this
 * should see Marketing's three tasks, not the festival's forty.
 *
 * Readable by everyone, because a club where you cannot see what another
 * department is working on is a club that duplicates work. What is *not* open
 * is the person-by-person breakdown — that stays behind
 * `canViewDepartmentRoster`, exactly as the roster route does.
 */
router.get('/:id/workspace', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Department id');
    const department = await col(C.departments).findOne({ _id: id });
    if (!department) fail('Department not found.', 404);

    const canSeePeople = canViewDepartmentRoster(request.user, id);
    const isLead = request.user.role === ROLES.clubLead
      && String(request.user.departmentId ?? '') === String(id);

    const [tasks, responsibilities, help, members, lead] = await Promise.all([
      col(C.tasks).find({ departmentId: id, status: { $ne: 'cancelled' } })
        .sort({ dueDate: 1, updatedAt: -1 }).limit(200).toArray(),
      col(C.eventResponsibilities).find({ departmentId: id }).toArray(),
      col(C.helpRequests).find({ departmentId: id, status: { $ne: 'resolved' } })
        .sort({ createdAt: -1 }).limit(20).toArray(),
      canSeePeople
        ? col(C.users).find({ departmentId: id, approvalStatus: 'approved' })
          .sort({ name: 1 }).toArray()
        : Promise.resolve([]),
      department.leadUserId
        ? col(C.users).findOne({ _id: department.leadUserId })
        : Promise.resolve(null),
    ]);

    const memberCount = canSeePeople
      ? members.length
      : await col(C.users).countDocuments({ departmentId: id, approvalStatus: 'approved' });

    const done = tasks.filter((t) => t.status === 'completed').length;
    const eventIds = responsibilities.map((r) => r.eventId);
    const events = eventIds.length === 0 ? [] : await col(C.events)
      .find({ _id: { $in: eventIds }, status: { $nin: ['cancelled', 'completed'] } })
      .sort({ date: 1 })
      .toArray();

    // Per-event, this department's slice only.
    const byEvent = new Map();
    for (const task of tasks) {
      if (!task.eventId) continue;
      const key = String(task.eventId);
      const bucket = byEvent.get(key) ?? { total: 0, done: 0 };
      bucket.total += 1;
      if (task.status === 'completed') bucket.done += 1;
      byEvent.set(key, bucket);
    }

    const notesByEvent = new Map(
      responsibilities.map((r) => [String(r.eventId), r.notes ?? '']),
    );

    const people = await col(C.users).find(
      { _id: { $in: tasks.map((t) => t.assignedTo).filter(Boolean) } },
      { projection: { name: 1 } },
    ).toArray();
    const userName = new Map(people.map((p) => [String(p._id), p.name]));

    response.json({
      department: {
        id: String(department._id),
        name: department.name,
        description: department.description ?? '',
        leadUserId: department.leadUserId ? String(department.leadUserId) : null,
        colorSeed: department.colorSeed ?? null,
        memberCount,
      },
      lead: lead ? publicUser(lead) : null,
      progress: {
        assigned: tasks.length,
        completed: done,
        completionRate: tasks.length === 0 ? 0 : Math.round((done / tasks.length) * 100),
        open: tasks.filter((t) => t.status !== 'completed').length,
        // Overdue is surfaced so a Lead can act on it — never counted per
        // person, which is where progress turns into a performance file.
        overdue: tasks.filter(
          (t) => t.status !== 'completed' && t.dueDate && new Date(t.dueDate) < new Date(),
        ).length,
      },
      events: events.map((e) => {
        const slice = byEvent.get(String(e._id)) ?? { total: 0, done: 0 };
        return {
          id: String(e._id),
          name: e.name,
          date: e.date,
          status: e.status,
          banner: e.banner ?? null,
          isOrganiser: String(e.organizingDepartmentId ?? '') === String(id),
          notes: notesByEvent.get(String(e._id)) ?? '',
          myTotal: slice.total,
          myDone: slice.done,
          myProgress: slice.total === 0 ? 0 : Math.round((slice.done / slice.total) * 100),
        };
      }),
      work: tasks
        .filter((t) => t.status !== 'completed')
        .slice(0, 60)
        .map((t) => ({
          id: String(t._id),
          title: t.title,
          status: t.status,
          eventId: t.eventId ? String(t.eventId) : null,
          dueDate: t.dueDate ?? null,
          // Names of people in this department are already gated by
          // canSeePeople; without it the work shows as unattributed.
          assigneeName: canSeePeople ? (userName.get(String(t.assignedTo)) ?? null) : null,
          overdue: Boolean(t.dueDate && t.status !== 'completed'
            && new Date(t.dueDate) < new Date()),
        })),
      helpRequests: help.map((h) => ({
        id: String(h._id),
        title: h.title,
        status: h.status,
        helpers: (h.helpers ?? []).length,
      })),
      members: canSeePeople
        ? members.map((m) => ({
          ...publicUser(m),
          isLead: String(department.leadUserId ?? '') === String(m._id),
        }))
        : [],
      canViewRoster: canSeePeople,
      // Section 26: granular. Being a Lead lets you run your department's work.
      // It does not make you an administrator of anything else.
      canManageWork: isLead || canManageDepartments(request.user.role),
    });
  } catch (error) {
    next(error);
  }
});

/** Section 6.6 — President and Directors only, from here down. */
function requireManage(request, response, next) {
  if (!canManageDepartments(request.user.role)) {
    return next(Object.assign(new Error('Only the President and Club Directors manage departments.'), { status: 403 }));
  }
  return next();
}

router.post('/', requireManage, async (request, response, next) => {
  try {
    const name = typeof request.body.name === 'string' ? request.body.name.trim() : '';
    if (name.length < 2) fail('Give the department a name.');
    if (name.length > 60) fail('That department name is too long.');
    if (await col(C.departments).findOne({ name })) fail('A department with that name already exists.', 409);

    const doc = {
      name,
      description: typeof request.body.description === 'string' ? request.body.description.trim() : '',
      leadUserId: null,
      active: true,
      colorSeed: request.body.colorSeed ?? null,
      createdBy: request.user._id,
      createdAt: new Date(),
    };
    const inserted = await col(C.departments).insertOne(doc);
    doc._id = inserted.insertedId;
    await audit(request.user._id, 'department.create', { name });
    response.status(201).json({ department: serialise(doc, 0) });
  } catch (error) {
    next(error);
  }
});

router.patch('/:id', requireManage, async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Department id');
    const department = await col(C.departments).findOne({ _id: id });
    if (!department) fail('Department not found.', 404);

    const update = {};
    if (typeof request.body.name === 'string') {
      const name = request.body.name.trim();
      if (name.length < 2) fail('Give the department a name.');
      const clash = await col(C.departments).findOne({ name, _id: { $ne: id } });
      if (clash) fail('A department with that name already exists.', 409);
      update.name = name;
    }
    if (typeof request.body.description === 'string') update.description = request.body.description.trim();
    if (typeof request.body.active === 'boolean') update.active = request.body.active;
    if (request.body.colorSeed !== undefined) update.colorSeed = request.body.colorSeed;

    if (Object.keys(update).length === 0) fail('Nothing to change.');

    const updated = await col(C.departments).findOneAndUpdate(
      { _id: id }, { $set: update }, { returnDocument: 'after' },
    );
    await audit(request.user._id, 'department.update', { id: String(id), ...update });
    response.json({ department: serialise(updated) });
  } catch (error) {
    next(error);
  }
});

/**
 * Assign or reassign a department's Lead.
 *
 * Promoting a Member to Lead also moves their role, and demotes the outgoing
 * Lead back to Member so the club never ends up with two Leads on one desk.
 */
router.put('/:id/lead', requireManage, async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Department id');
    const department = await col(C.departments).findOne({ _id: id });
    if (!department) fail('Department not found.', 404);

    const userId = request.body.userId ? oid(request.body.userId, 'User id') : null;

    if (userId) {
      const candidate = await col(C.users).findOne({ _id: userId, approvalStatus: 'approved' });
      if (!candidate) fail('That member is not available.');
      if (candidate.role !== ROLES.clubMember && candidate.role !== ROLES.clubLead) {
        fail('Only a Member or an existing Lead can lead a department.');
      }
      // Step down whoever currently holds it.
      if (department.leadUserId && String(department.leadUserId) !== String(userId)) {
        await col(C.users).updateOne(
          { _id: department.leadUserId },
          { $set: { role: ROLES.clubMember } },
        );
        await notify(department.leadUserId, 'departmentChanged', {
          message: `You are no longer the Lead of ${department.name}.`,
        });
      }
      await col(C.users).updateOne(
        { _id: userId },
        { $set: { role: ROLES.clubLead, departmentId: id } },
      );
      await notify(userId, 'departmentChanged', {
        message: `You are now the Lead of ${department.name}.`,
      });
    } else if (department.leadUserId) {
      await col(C.users).updateOne({ _id: department.leadUserId }, { $set: { role: ROLES.clubMember } });
    }

    const updated = await col(C.departments).findOneAndUpdate(
      { _id: id }, { $set: { leadUserId: userId } }, { returnDocument: 'after' },
    );
    await audit(request.user._id, 'department.setLead', { id: String(id), userId: userId ? String(userId) : null });
    response.json({ department: serialise(updated) });
  } catch (error) {
    next(error);
  }
});

/**
 * Deactivate rather than delete: tasks and history stay intact and auditable.
 * A department holding members cannot be deactivated until they are moved.
 */
router.delete('/:id', requireManage, async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Department id');
    const members = await col(C.users).countDocuments({ departmentId: id, approvalStatus: 'approved' });
    if (members > 0) {
      fail(`Move the ${members} member${members === 1 ? '' : 's'} out of this department first.`, 409);
    }
    const updated = await col(C.departments).findOneAndUpdate(
      { _id: id }, { $set: { active: false, leadUserId: null } }, { returnDocument: 'after' },
    );
    if (!updated) fail('Department not found.', 404);
    await audit(request.user._id, 'department.deactivate', { id: String(id) });
    response.json({ department: serialise(updated) });
  } catch (error) {
    next(error);
  }
});

module.exports = router;

'use strict';

const crypto = require('node:crypto');
const express = require('express');
const { ObjectId } = require('mongodb');
const { col, C } = require('../db');
const {
  authenticate, requireApproved, publicUser, fail, hashPassword,
} = require('../auth');
const {
  userVisibilityFilter, canAssignTo, canRequestTo, canAssign,
  canManageDepartments, ROLES, isDirector, isSupervisor,
  canAwardPoints, canViewMemberDetail, SUPERVISOR_ROLES,
  canAssignToDepartment, TASK_POINT_VALUES, canRenameMember, isRole,
} = require('../permissions');
const { notify, audit } = require('../services/notify');

const router = express.Router();
router.use(authenticate, requireApproved);

const oid = (value, name) => {
  if (!ObjectId.isValid(value)) fail(`${name} is not valid.`);
  return new ObjectId(value);
};

/** Member directory, scoped to what this role may see. */
router.get('/', async (request, response, next) => {
  try {
    const filter = { $and: [{ approvalStatus: 'approved' }, userVisibilityFilter(request.user)] };
    if (request.query.departmentId && ObjectId.isValid(request.query.departmentId)) {
      filter.$and.push({ departmentId: new ObjectId(request.query.departmentId) });
    }
    // Validated against the known roles rather than passed through. An
    // unchecked query value lets a caller send an operator instead of a string
    // and filter on something the route never meant to offer.
    if (isRole(request.query.role)) filter.$and.push({ role: request.query.role });

    const users = await col(C.users).find(filter).sort({ name: 1 }).limit(500).toArray();
    response.json({ users: users.map(publicUser) });
  } catch (error) {
    next(error);
  }
});

/**
 * Everything the compose sheet needs to know, answered by the server so the
 * client never guesses and can never offer an option that would be refused.
 *
 * The shape mirrors the two-step hierarchy:
 *   `departments` — for the leadership tier, who address a department and let
 *                   its Lead decide who does it
 *   `assignable`  — for a Lead, their own members, by name
 *   `requestable` — anyone you may *ask* but not instruct
 */
router.get('/assignable', async (request, response, next) => {
  try {
    const actor = request.user;
    const toDepartment = canAssignToDepartment(actor.role);

    if (!canAssign(actor.role)) {
      return response.json({
        assignable: [],
        requestable: [],
        departments: [],
        canAssignToDepartment: false,
        pointValues: TASK_POINT_VALUES,
      });
    }

    const [candidates, departments] = await Promise.all([
      col(C.users).find({ approvalStatus: 'approved' }).sort({ name: 1 }).toArray(),
      toDepartment
        ? col(C.departments).find({ active: { $ne: false } }).sort({ name: 1 }).toArray()
        : Promise.resolve([]),
    ]);

    const leadNames = new Map(
      candidates
        .filter((c) => c.role === ROLES.clubLead && c.departmentId)
        .map((c) => [String(c.departmentId), c.name]),
    );

    return response.json({
      assignable: candidates.filter((c) => canAssignTo(actor, c)).map(publicUser),
      requestable: candidates.filter((c) => canRequestTo(actor, c)).map(publicUser),
      departments: departments.map((d) => ({
        id: String(d._id),
        name: d.name,
        colorSeed: d.colorSeed ?? null,
        // Named so the sender knows who is about to be woken up — and sees
        // when the answer is "nobody yet".
        leadName: leadNames.get(String(d._id)) ?? null,
      })),
      canAssignToDepartment: toDepartment,
      pointValues: TASK_POINT_VALUES,
    });
  } catch (error) {
    return next(error);
  }
});

/** Below this many assigned tasks, a completion rate is noise, not a standing. */
const RANKING_THRESHOLD = 3;

/**
 * Recognition — **per department, never club-wide**.
 *
 * A single club-wide board compares a Cinematography member who shoots two
 * films a term against a Marketing member posting daily. They are not doing the
 * same job and the comparison tells nobody anything. Within a department the
 * work is at least alike, so the numbers mean something — and the group is
 * small enough that it reads as a team, not a ranking.
 *
 * Each department comes back as its own list, ordered by points earned. Points
 * are 1, 3 or 5 per task, set by the Lead when they hand it out, so a hard job
 * counts for more than an easy one.
 *
 * The **Lead is reported separately**, not as a row competing with their own
 * team. They earn a point for everything their department finishes, so putting
 * them in the list would mean they always top it — which would say nothing and
 * would quietly discourage everyone below.
 *
 * Supervisors are absent entirely: they oversee the club rather than take part.
 */
router.get('/leaderboard', async (request, response, next) => {
  try {
    const [users, departments, taskStats] = await Promise.all([
      col(C.users).find({
        $and: [
          { approvalStatus: 'approved' },
          { role: { $nin: [...SUPERVISOR_ROLES] } },
          userVisibilityFilter(request.user),
        ],
      }).limit(500).toArray(),
      col(C.departments).find({ active: { $ne: false } }).sort({ name: 1 }).toArray(),
      col(C.tasks).aggregate([
        { $match: { status: { $ne: 'cancelled' } } },
        {
          $group: {
            _id: '$assignedTo',
            assigned: { $sum: 1 },
            completed: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] } },
          },
        },
      ]).toArray(),
    ]);

    const byId = new Map(taskStats.map((s) => [String(s._id), s]));

    const decorate = (u) => {
      const s = byId.get(String(u._id)) ?? { assigned: 0, completed: 0 };
      return {
        ...publicUser(u),
        assignedTasks: s.assigned,
        completedTasks: s.completed,
        completionRate: s.assigned === 0 ? 0 : Math.round((s.completed / s.assigned) * 100),
        ranked: s.assigned >= RANKING_THRESHOLD,
      };
    };

    // Points first — that is the thing the Lead actually calibrated. Volume,
    // then rate, then name break ties, so the order is stable rather than
    // shuffling every time somebody finishes something.
    const order = (a, b) => {
      if (b.points !== a.points) return b.points - a.points;
      if (b.completedTasks !== a.completedTasks) return b.completedTasks - a.completedTasks;
      if (b.completionRate !== a.completionRate) return b.completionRate - a.completionRate;
      return a.name.localeCompare(b.name);
    };

    const groups = departments.map((d) => {
      const inDept = users.filter(
        (u) => u.departmentId && String(u.departmentId) === String(d._id),
      );
      const leadId = d.leadUserId ? String(d.leadUserId) : null;
      const lead = inDept.find((u) => String(u._id) === leadId);
      const members = inDept
        .filter((u) => String(u._id) !== leadId)
        .map(decorate)
        .sort(order);

      const assigned = members.reduce((n, m) => n + m.assignedTasks, 0);
      const completed = members.reduce((n, m) => n + m.completedTasks, 0);

      return {
        departmentId: String(d._id),
        name: d.name,
        colorSeed: d.colorSeed ?? null,
        lead: lead ? decorate(lead) : null,
        members,
        totals: {
          people: inDept.length,
          assigned,
          completed,
          points: members.reduce((n, m) => n + m.points, 0),
          completionRate: assigned === 0 ? 0 : Math.round((completed / assigned) * 100),
        },
      };
    });

    // People with no department — the executive tier. Shown plainly so they are
    // not silently missing, but never mixed into a department's list.
    const unaffiliated = users
      .filter((u) => !u.departmentId)
      .map(decorate)
      .sort(order);

    response.json({
      departments: groups,
      unaffiliated,
      rankingThreshold: RANKING_THRESHOLD,
      explanation:
        'Each department keeps its own list, because a Cinematography member and '
        + 'a Marketing member are not doing the same job. Points are 1, 3 or 5 per '
        + 'task, set by the Lead when they hand it out.',
    });
  } catch (error) {
    next(error);
  }
});

/**
 * The club at a glance: how much work each department was given, and how much
 * of it landed.
 *
 * Open to everyone, deliberately. Section 31's line holds — aggregate numbers
 * about a *department* give away nothing about any individual, and knowing
 * where the club is stretched is exactly the context members are usually
 * missing. Ordered alphabetically, never by performance.
 */
router.get('/department-overview', async (request, response, next) => {
  try {
    const [departments, stats] = await Promise.all([
      col(C.departments).find({ active: { $ne: false } }).sort({ name: 1 }).toArray(),
      col(C.tasks).aggregate([
        { $match: { status: { $ne: 'cancelled' } } },
        {
          $group: {
            _id: '$departmentId',
            assigned: { $sum: 1 },
            completed: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] } },
            unassigned: {
              $sum: { $cond: [{ $eq: [{ $ifNull: ['$assignedTo', null] }, null] }, 1, 0] },
            },
            points: {
              $sum: { $cond: [{ $eq: ['$status', 'completed'] }, '$points', 0] },
            },
          },
        },
      ]).toArray(),
    ]);

    const headcount = await col(C.users).aggregate([
      { $match: { approvalStatus: 'approved', departmentId: { $ne: null } } },
      { $group: { _id: '$departmentId', n: { $sum: 1 } } },
    ]).toArray();

    const byDept = new Map(stats.map((s) => [String(s._id), s]));
    const people = new Map(headcount.map((h) => [String(h._id), h.n]));

    const rows = departments.map((d) => {
      const s = byDept.get(String(d._id))
        ?? { assigned: 0, completed: 0, unassigned: 0, points: 0 };
      return {
        departmentId: String(d._id),
        name: d.name,
        colorSeed: d.colorSeed ?? null,
        hasLead: Boolean(d.leadUserId),
        people: people.get(String(d._id)) ?? 0,
        assigned: s.assigned,
        completed: s.completed,
        open: s.assigned - s.completed,
        // Work sent to the department that its Lead has not passed on yet.
        awaitingHandout: s.unassigned,
        points: s.points,
        completionRate: s.assigned === 0 ? 0 : Math.round((s.completed / s.assigned) * 100),
      };
    });

    response.json({
      departments: rows,
      totals: {
        assigned: rows.reduce((n, r) => n + r.assigned, 0),
        completed: rows.reduce((n, r) => n + r.completed, 0),
        open: rows.reduce((n, r) => n + r.open, 0),
        awaitingHandout: rows.reduce((n, r) => n + r.awaitingHandout, 0),
      },
    });
  } catch (error) {
    next(error);
  }
});

/**
 * One member's full record — contact details, workload, history.
 *
 * Gated by canViewMemberDetail: leadership and Leads see anyone; a Member sees
 * their own department and the executive above them, and gets department-level
 * progress for everyone else. A supervisor's own record is visible only to
 * other supervisors.
 */
router.get('/:id/stats', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'User id');
    const user = await col(C.users).findOne({ _id: id });
    if (!user) fail('Member not found.', 404);
    if (!canViewMemberDetail(request.user, user)) {
      fail('You can only open members of your own department.', 403);
    }

    const [agg] = await col(C.tasks).aggregate([
      { $match: { assignedTo: id, status: { $ne: 'cancelled' } } },
      {
        $group: {
          _id: null,
          assigned: { $sum: 1 },
          completed: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] } },
          inProgress: { $sum: { $cond: [{ $eq: ['$status', 'inProgress'] }, 1, 0] } },
          pending: { $sum: { $cond: [{ $eq: ['$status', 'pending'] }, 1, 0] } },
          blocked: { $sum: { $cond: [{ $eq: ['$status', 'blocked'] }, 1, 0] } },
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
          avgCompletionMs: {
            $avg: {
              $cond: [
                { $and: [{ $eq: ['$status', 'completed'] }, { $ne: ['$completedAt', null] }] },
                { $subtract: ['$completedAt', '$createdAt'] },
                null,
              ],
            },
          },
        },
      },
    ]).toArray();

    const assigned = agg?.assigned ?? 0;
    const completed = agg?.completed ?? 0;

    const recent = await col(C.tasks)
      .find({ assignedTo: id, status: { $ne: 'cancelled' } })
      .sort({ updatedAt: -1 })
      .limit(8)
      .toArray();

    const department = user.departmentId
      ? await col(C.departments).findOne({ _id: user.departmentId })
      : null;
    const lead = department?.leadUserId
      ? await col(C.users).findOne({ _id: department.leadUserId }, { projection: { name: 1 } })
      : null;

    // Who assigns this person work, and what they have handed out themselves.
    const assignedByThem = await col(C.tasks).countDocuments({ assignedBy: id });

    response.json({
      user: publicUser(user),
      department: department
        ? {
            id: String(department._id),
            name: department.name,
            leadName: lead?.name ?? null,
            isLead: String(department.leadUserId ?? '') === String(id),
          }
        : null,
      stats: {
        assigned,
        completed,
        assignedByThem,
        inProgress: agg?.inProgress ?? 0,
        pending: agg?.pending ?? 0,
        blocked: agg?.blocked ?? 0,
        overdue: agg?.overdue ?? 0,
        completionRate: assigned === 0 ? 0 : Math.round((completed / assigned) * 100),
        ranked: assigned >= RANKING_THRESHOLD,
        avgCompletionHours: agg?.avgCompletionMs
          ? Math.round(agg.avgCompletionMs / 3600000)
          : null,
      },
      recentTasks: recent.map((t) => ({
        id: String(t._id),
        title: t.title,
        status: t.status,
        dueDate: t.dueDate ?? null,
        updatedAt: t.updatedAt ?? null,
      })),
    });
  } catch (error) {
    next(error);
  }
});

router.get('/:id', async (request, response, next) => {
  try {
    const user = await col(C.users).findOne({
      $and: [{ _id: oid(request.params.id, 'User id') }, userVisibilityFilter(request.user)],
    });
    if (!user) fail('Member not found.', 404);
    response.json({ user: publicUser(user) });
  } catch (error) {
    next(error);
  }
});

/** Update your own profile. Role and points are never self-editable. */
router.patch('/me', async (request, response, next) => {
  try {
    const update = {};
    if (typeof request.body.name === 'string' && request.body.name.trim().length >= 2) {
      update.name = request.body.name.trim().slice(0, 80);
      // Giving your own name is the definitive answer to "is this a
      // placeholder?", so it always clears the flag.
      update.mustSetName = false;
    }
    if (typeof request.body.phone === 'string') update.phone = request.body.phone.trim().slice(0, 20);
    if (Object.keys(update).length === 0) fail('Nothing to change.');
    const updated = await col(C.users).findOneAndUpdate(
      { _id: request.user._id }, { $set: update }, { returnDocument: 'after' },
    );
    response.json({ user: publicUser(updated) });
  } catch (error) {
    next(error);
  }
});

/**
 * Put a real name on somebody else's account.
 *
 * Accounts get created *for* people — the six seeded Lead accounts arrive with
 * a placeholder — and the person handing the credentials over is the one who
 * knows whose account it is. Without this the approval queue would be asking
 * the President to admit an account with no name on it.
 *
 * Narrow and audited: renaming somebody is an identity change, not an admin
 * convenience. `canRenameMember` is the authority.
 */
router.patch('/:id/name', async (request, response, next) => {
  try {
    const actor = request.user;
    const id = oid(request.params.id, 'User id');
    const target = await col(C.users).findOne({ _id: id });
    if (!target) fail('Member not found.', 404);
    if (!canRenameMember(actor, target)) {
      fail('Your role cannot rename other members.', 403);
    }

    const name = typeof request.body.name === 'string' ? request.body.name.trim() : '';
    if (name.length < 2) fail('A name needs at least two characters.');
    if (name.length > 80) fail('That name is too long.');

    const previous = target.name;
    const updated = await col(C.users).findOneAndUpdate(
      { _id: id },
      { $set: { name: name.slice(0, 80), mustSetName: false } },
      { returnDocument: 'after' },
    );

    // Tell them their account was renamed. Finding out later that somebody
    // changed what you are called, silently, is worse than the rename itself.
    if (String(actor._id) !== String(id)) {
      await notify(id, 'profileRenamed', { by: actor.name, from: previous, to: updated.name });
    }
    await audit(actor._id, 'user.rename', {
      targetId: String(id), from: previous, to: updated.name,
    });

    response.json({ user: publicUser(updated) });
  } catch (error) {
    next(error);
  }
});

/**
 * Award points by hand.
 *
 * Tasks are worth one point each, flat. This exists for the things a flat rate
 * cannot capture — someone who rescued an event, or carried a week nobody
 * logged. Supervisors and the President can award; supervisors themselves can
 * never receive.
 */
router.post('/:id/award', async (request, response, next) => {
  try {
    const actor = request.user;
    if (!canAwardPoints(actor.role)) {
      fail('Your role cannot award points.', 403);
    }
    const id = oid(request.params.id, 'User id');
    const target = await col(C.users).findOne({ _id: id, approvalStatus: 'approved' });
    if (!target) fail('Member not found.', 404);
    if (isSupervisor(target.role)) {
      fail('Supervisors do not collect points.', 400);
    }
    if (String(target._id) === String(actor._id)) {
      fail('You cannot award points to yourself.', 403);
    }

    const points = Number(request.body.points);
    if (!Number.isInteger(points) || points < 1 || points > 20) {
      fail('Award between 1 and 20 points.');
    }
    const reason = typeof request.body.reason === 'string'
      ? request.body.reason.trim().slice(0, 200)
      : '';

    const updated = await col(C.users).findOneAndUpdate(
      { _id: id }, { $inc: { points } }, { returnDocument: 'after' },
    );
    await notify(id, 'pointsAwarded', { points, reason, byName: actor.name });
    await audit(actor._id, 'points.award', { userId: String(id), points, reason });

    response.json({ user: publicUser(updated) });
  } catch (error) {
    next(error);
  }
});

/**
 * Reset somebody's password to a fresh temporary one.
 *
 * The club's answer to "I forgot my password", chosen over an emailed reset
 * link because that needs an SMTP account the club does not have — and because
 * every member can find the President in a corridor, which is a stronger
 * identity check than an inbox anyway.
 *
 * The temporary password is returned **once**, to the approver, to pass on
 * however they normally would. It is never stored in readable form and the
 * account is flagged `mustChangePassword`, so it survives exactly one sign-in.
 */
router.post('/:id/reset-password', async (request, response, next) => {
  try {
    const actor = request.user;
    if (!canManageDepartments(actor.role)) {
      fail('Only the President and Directors can reset a password.', 403);
    }
    const id = oid(request.params.id, 'User id');
    const target = await col(C.users).findOne({ _id: id });
    if (!target) fail('Member not found.', 404);
    if (isSupervisor(target.role) && !isSupervisor(actor.role)) {
      fail('A supervisor\'s password can only be reset by another supervisor.', 403);
    }

    // Readable on purpose — this gets said out loud or typed into a chat, so
    // ambiguous characters (O/0, l/1/I) are left out entirely.
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    const temporary = 'gwd-' + Array.from(
      crypto.randomBytes(8),
      (b) => alphabet[b % alphabet.length],
    ).join('');

    // Stamping the moment revokes every token already issued to this account.
    // This is the "I have lost my phone" path, so leaving the old session alive
    // for up to thirty days would defeat the whole point of the reset.
    await col(C.users).updateOne({ _id: id }, {
      $set: {
        passwordHash: await hashPassword(temporary),
        mustChangePassword: true,
        passwordChangedAt: new Date(),
      },
      $unset: { passwordResetRequestedAt: '' },
    });

    await notify(id, 'passwordReset', { byName: actor.name });
    await audit(actor._id, 'password.reset', { userId: String(id), name: target.name });

    response.json({
      temporaryPassword: temporary,
      message: `Give this to ${target.name}. They will be asked to choose their own `
        + 'password when they sign in. It is not shown again.',
    });
  } catch (error) {
    next(error);
  }
});

/**
 * Change someone's role or department.
 * Restricted to President and supervisors — the tier that owns department admin.
 */
router.patch('/:id/role', async (request, response, next) => {
  try {
    if (!canManageDepartments(request.user.role)) {
      fail('Only the President and Club Directors can change roles.', 403);
    }
    const id = oid(request.params.id, 'User id');
    const target = await col(C.users).findOne({ _id: id });
    if (!target) fail('Member not found.', 404);

    const update = {};
    if (request.body.role) {
      // Only a Director can appoint into the supervisor tier — otherwise the
      // President could promote themselves above their own oversight.
      if (isSupervisor(request.body.role) && !isDirector(request.user.role)) {
        fail('Only a Club Director can appoint a Director or Faculty Coordinator.', 403);
      }
      update.role = request.body.role;
    }
    if (request.body.departmentId !== undefined) {
      update.departmentId = request.body.departmentId ? oid(request.body.departmentId, 'Department id') : null;
    }
    if (Object.keys(update).length === 0) fail('Nothing to change.');

    const updated = await col(C.users).findOneAndUpdate({ _id: id }, { $set: update }, { returnDocument: 'after' });
    await audit(request.user._id, 'user.roleChange', { userId: String(id), ...update });
    response.json({ user: publicUser(updated) });
  } catch (error) {
    next(error);
  }
});

module.exports = router;

'use strict';

const express = require('express');
const config = require('../config');
const { col, C } = require('../db');
const { authenticate, requireApproved } = require('../auth');
const {
  taskVisibilityFilter, canAssign, canViewAudit, canManageDepartments,
  canEditSchedule, canCreateScheduleEntry, canBroadcast, canAwardPoints,
  earnsPoints, appearsOnLeaderboard,
} = require('../permissions');
const { serialiseTask } = require('../realtime');

const router = express.Router();
router.use(authenticate, requireApproved);

const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

/**
 * Everything Home needs, in one request.
 *
 * Home carries more than it used to — today's schedule, weekly progress,
 * departments — but still exactly **one** focal decision (`whatsNext`).
 * The rest are scannable rows, not competing cards. More information, same
 * number of decisions.
 */
router.get('/home', async (request, response, next) => {
  try {
    const user = request.user;
    const now = new Date();
    const today = startOfDay(now);
    const tomorrow = new Date(today.getTime() + 86400000);
    const weekAgo = new Date(today.getTime() - 7 * 86400000);

    const [
      pending, inProgress, completedThisWeek, nextTask, unread,
      pendingApprovals, todaySchedule, departments, upcomingCount, unreadAlerts,
    ] = await Promise.all([
      col(C.tasks).countDocuments({ assignedTo: user._id, status: 'pending' }),
      col(C.tasks).countDocuments({ assignedTo: user._id, status: 'inProgress' }),
      col(C.tasks).countDocuments({
        assignedTo: user._id, status: 'completed', completedAt: { $gte: weekAgo },
      }),
      col(C.tasks)
        .find({ assignedTo: user._id, status: { $in: ['pending', 'inProgress'] } })
        .sort({ dueDate: 1, createdAt: 1 })
        .limit(1)
        .toArray(),
      col(C.notifications).countDocuments({ userId: user._id, read: false }),
      col(C.accessRequests).countDocuments({ status: 'pending' }),
      // Everything on the schedule today, whatever the lane.
      col(C.calendarEvents)
        .find({ date: { $gte: today, $lt: tomorrow } })
        .sort({ date: 1 })
        .limit(12)
        .toArray(),
      col(C.departments).find({ active: { $ne: false } }).sort({ name: 1 }).toArray(),
      col(C.calendarEvents).countDocuments({ date: { $gte: now } }),
      col(C.broadcasts).countDocuments({ createdAt: { $gte: weekAgo } }),
    ]);

    // Task deadlines falling today belong on the same strip.
    const todayDeadlines = await col(C.tasks)
      .find({
        $and: [
          taskVisibilityFilter(user),
          { dueDate: { $gte: today, $lt: tomorrow } },
          { status: { $nin: ['completed', 'cancelled'] } },
        ],
      })
      .limit(8)
      .toArray();

    const task = nextTask[0] ?? null;
    const nextEntry = await col(C.calendarEvents)
      .find({ date: { $gte: now } })
      .sort({ date: 1 })
      .limit(1)
      .toArray();
    const entry = nextEntry[0] ?? null;

    // The single focal point: whichever lands sooner.
    let whatsNext = null;
    if (task && (!entry || !task.dueDate || new Date(task.dueDate) <= new Date(entry.date))) {
      whatsNext = { kind: 'task', task: serialiseTask(task) };
    }

    // Categories are managed data, so their colour and icon have to be looked
    // up rather than derived from a hardcoded kind.
    const categoryDocs = await col(C.scheduleCategories).find({}).toArray();
    const categoryById = new Map(categoryDocs.map((c) => [String(c._id), c]));
    const describe = (e) => {
      const c = categoryById.get(String(e.categoryId));
      return {
        categoryName: c?.name ?? 'Entry',
        categoryIcon: c?.icon ?? 'flag',
        categoryColor: c?.color ?? '#DC2626',
      };
    };

    if (whatsNext == null && entry) {
      whatsNext = {
        kind: 'schedule',
        entry: {
          id: String(entry._id),
          ...describe(entry),
          title: entry.title,
          date: entry.date,
          location: entry.location ?? '',
        },
      };
    }

    const memberCounts = await col(C.users).aggregate([
      { $match: { approvalStatus: 'approved', departmentId: { $ne: null } } },
      { $group: { _id: '$departmentId', n: { $sum: 1 } } },
    ]).toArray();
    const countById = new Map(memberCounts.map((c) => [String(c._id), c.n]));

    const deptTasks = await col(C.tasks).aggregate([
      { $match: { status: { $ne: 'cancelled' } } },
      {
        $group: {
          _id: '$departmentId',
          assigned: { $sum: 1 },
          completed: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] } },
        },
      },
    ]).toArray();
    const deptTaskStats = new Map(deptTasks.map((s) => [String(s._id), s]));

    const openTotal = pending + inProgress;
    const weekTotal = openTotal + completedThisWeek;

    response.json({
      user: {
        id: String(user._id),
        name: user.name,
        role: user.role,
        points: user.points ?? 0,
        avatarColor: user.avatarColor ?? null,
        departmentId: user.departmentId ? String(user.departmentId) : null,
      },
      counts: {
        pending,
        inProgress,
        completedThisWeek,
        unreadNotifications: unread,
        upcoming: upcomingCount,
        alertsThisWeek: unreadAlerts,
      },
      // Weekly momentum, as a single ratio. One number, not a chart.
      progress: {
        done: completedThisWeek,
        total: weekTotal,
        ratio: weekTotal === 0 ? 0 : completedThisWeek / weekTotal,
      },
      whatsNext,
      today: [
        ...todaySchedule.map((e) => ({
          id: String(e._id),
          kind: 'schedule',
          ...describe(e),
          title: e.title,
          date: e.date,
          location: e.location ?? '',
        })),
        ...todayDeadlines.map((t) => ({
          id: `task:${t._id}`,
          kind: 'task',
          categoryName: 'Deadline',
          categoryIcon: 'deadline',
          categoryColor: '#B45309',
          title: t.title,
          date: t.dueDate,
          taskId: String(t._id),
          status: t.status,
        })),
      ].sort((a, b) => new Date(a.date) - new Date(b.date)),
      // Departments carry their headline progress, not just a member count — a
      // row of initials tells nobody anything, and department progress is open
      // to every member by design.
      departments: departments.map((d) => {
        const s = deptTaskStats.get(String(d._id)) ?? { assigned: 0, completed: 0 };
        return {
          id: String(d._id),
          name: d.name,
          leadUserId: d.leadUserId ? String(d.leadUserId) : null,
          memberCount: countById.get(String(d._id)) ?? 0,
          assigned: s.assigned,
          completed: s.completed,
          completionRate: s.assigned === 0 ? 0 : Math.round((s.completed / s.assigned) * 100),
        };
      }),
      // The client mirrors these to hide actions that would be refused. The
      // server stays the authority.
      capabilities: {
        canAssign: canAssign(user.role),
        canEditSchedule: canEditSchedule(user.role),
        canCreateScheduleEntry: canCreateScheduleEntry(user.role),
        canBroadcast: canBroadcast(user.role),
        canManageDepartments: canManageDepartments(user.role),
        canViewAudit: canViewAudit(user.role),
        canAwardPoints: canAwardPoints(user.role),
        earnsPoints: earnsPoints(user.role),
        onLeaderboard: appearsOnLeaderboard(user.role),
        pendingApprovals:
          canViewAudit(user.role) || user.role === 'clubLead' ? pendingApprovals : 0,
      },
      config: { pointsPerTask: config.pointsPerTask, clubName: config.clubName },
    });
  } catch (error) {
    next(error);
  }
});

/** Compact payload for the native home-screen widget. */
router.get('/widget', async (request, response, next) => {
  try {
    const user = request.user;
    const [pending, next] = await Promise.all([
      col(C.tasks).countDocuments({ assignedTo: user._id, status: { $in: ['pending', 'inProgress'] } }),
      col(C.tasks)
        .find({ assignedTo: user._id, status: { $in: ['pending', 'inProgress'] }, dueDate: { $ne: null } })
        .sort({ dueDate: 1 })
        .limit(1)
        .toArray(),
    ]);
    response.json({
      pendingCount: pending,
      nextTitle: next[0]?.title ?? null,
      nextDue: next[0]?.dueDate ?? null,
      updatedAt: new Date().toISOString(),
    });
  } catch (error) {
    next(error);
  }
});

/** One clean chart screen — not a BI dashboard. */
router.get('/analytics', async (request, response, next) => {
  try {
    if (!canViewAudit(request.user.role)) {
      return response.status(403).json({ error: 'You do not have permission to view analytics.' });
    }
    const byDepartment = await col(C.tasks).aggregate([
      {
        $group: {
          _id: '$departmentId',
          total: { $sum: 1 },
          completed: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] } },
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

    const departments = await col(C.departments).find({}).toArray();
    const nameById = new Map(departments.map((d) => [String(d._id), d.name]));

    response.json({
      departments: byDepartment.map((d) => ({
        departmentId: d._id ? String(d._id) : null,
        name: d._id ? nameById.get(String(d._id)) ?? 'Unassigned' : 'Unassigned',
        total: d.total,
        completed: d.completed,
        completionRate: d.total > 0 ? Math.round((d.completed / d.total) * 100) : 0,
        avgCompletionHours: d.avgCompletionMs ? Math.round(d.avgCompletionMs / 3600000) : null,
      })),
    });
  } catch (error) {
    next(error);
  }
});

/** Activity / audit log. */
router.get('/audit', async (request, response, next) => {
  try {
    if (!canViewAudit(request.user.role)) {
      return response.status(403).json({ error: 'You do not have permission to view the audit log.' });
    }
    const entries = await col(C.auditLog).find({}).sort({ createdAt: -1 }).limit(200).toArray();
    const actors = await col(C.users)
      .find({ _id: { $in: entries.map((e) => e.actorId).filter(Boolean) } }, { projection: { name: 1 } })
      .toArray();
    const nameById = new Map(actors.map((a) => [String(a._id), a.name]));
    response.json({
      entries: entries.map((e) => ({
        id: String(e._id),
        actorId: e.actorId ? String(e.actorId) : null,
        actorName: e.actorId ? nameById.get(String(e.actorId)) ?? 'Unknown' : 'System',
        action: e.action,
        detail: e.detail ?? {},
        createdAt: e.createdAt,
      })),
    });
  } catch (error) {
    next(error);
  }
});

module.exports = router;

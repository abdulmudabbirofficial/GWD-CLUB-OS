'use strict';

const express = require('express');
const config = require('../config');
const { col, C } = require('../db');
const { authenticate, requireApproved } = require('../auth');
const {
  taskVisibilityFilter, canAssign, canViewAudit, canManageDepartments,
  canEditSchedule, canCreateScheduleEntry, canBroadcast, canAwardPoints,
  earnsPoints, appearsOnLeaderboard,
  canChangeRole,
  isSuperAdmin,
} = require('../permissions');
const { serialiseTask } = require('../realtime');

const router = express.Router();
router.use(authenticate, requireApproved);

const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

/**
 * Fold a stored "HH:MM" onto a date.
 *
 * Meetings keep the day and the time in separate fields, so a meeting at 17:00
 * has a `date` of midnight. Home sorts its strip by date, so without this every
 * meeting sorts to the top of the day and shows "00:00".
 */
const withTime = (date, hhmm) => {
  const base = new Date(date);
  const match = /^(\d{1,2}):(\d{2})$/.exec(hhmm ?? '');
  if (!match) return base;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (hours > 23 || minutes > 59) return base;
  base.setHours(hours, minutes, 0, 0);
  return base;
};

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

    // Meetings this person is actually expected at today.
    //
    // Deliberately narrowed to their own invitations even for leadership, who
    // can see every meeting on the Meetings screen: Home answers "what should
    // *I* do now", and a President's Home filling up with three departments'
    // internal catch-ups is how the strip stops being read.
    const todayMeetings = await col(C.meetings)
      .find({
        date: { $gte: today, $lt: tomorrow },
        status: { $ne: 'cancelled' },
        'participants.userId': user._id,
      })
      .sort({ date: 1 })
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
        ...todayMeetings.map((m) => ({
          id: `meeting:${m._id}`,
          kind: 'meeting',
          categoryName: 'Meeting',
          categoryIcon: 'meeting',
          categoryColor: '#2563EB',
          title: m.title,
          // The start time is what somebody needs off this row, and it is
          // stored separately from the date — so it is folded in here rather
          // than left to the client to notice the date is midnight.
          date: withTime(m.date, m.startTime),
          location: m.venue ?? '',
          meetingId: String(m._id),
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
        // Appointing people. Narrower than canManageDepartments on purpose --
        // a VP may reorganise the club's structure and may not decide who
        // holds which office, including their own.
        canChangeRole: canChangeRole(user.role),
        // Only a Director may appoint into the supervisor tier, so the client
        // needs to know which of the two it is to offer the right list rather
        // than a choice the server will refuse.
        // The Super Admin alone governs the supervisor tier.
        canAppointSupervisors: isSuperAdmin(user),
        isSuperAdmin: isSuperAdmin(user),
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

    // What state the club's work is in, as one set of counts. The per-department
    // rows above cannot answer this: summing "completed" across them tells you
    // nothing about how much of the rest is in progress versus untouched, which
    // is the difference between a club that is behind and one that is moving.
    const byStatus = await col(C.tasks).aggregate([
      { $group: { _id: '$status', count: { $sum: 1 } } },
    ]).toArray();
    const statusCount = (name) => {
      const row = byStatus.find((s) => s._id === name);
      return row ? row.count : 0;
    };

    // Completions per day for the last fortnight, oldest first.
    //
    // Grouped in the server's own local time rather than UTC, because the
    // question being asked is "what did we get done on Tuesday" and a club in
    // IST would otherwise see Tuesday evening's work land on Wednesday.
    const DAYS = 14;
    const since = new Date();
    since.setHours(0, 0, 0, 0);
    since.setDate(since.getDate() - (DAYS - 1));

    const finished = await col(C.tasks)
      .find(
        { status: 'completed', completedAt: { $gte: since } },
        { projection: { completedAt: 1 } },
      )
      .toArray();

    const key = (date) => {
      const d = new Date(date);
      return [
        d.getFullYear(),
        String(d.getMonth() + 1).padStart(2, '0'),
        String(d.getDate()).padStart(2, '0'),
      ].join('-');
    };
    const perDay = new Map();
    for (const task of finished) {
      const k = key(task.completedAt);
      perDay.set(k, (perDay.get(k) ?? 0) + 1);
    }
    const completions = [];
    for (let i = 0; i < DAYS; i += 1) {
      const day = new Date(since);
      day.setDate(since.getDate() + i);
      const k = key(day);
      completions.push({ day: k, count: perDay.get(k) ?? 0 });
    }

    const now = new Date();
    const [people, activeDepartments, openEvents, overdue] = await Promise.all([
      col(C.users).countDocuments({ approvalStatus: 'approved' }),
      col(C.departments).countDocuments({ active: { $ne: false } }),
      col(C.events).countDocuments({ status: { $nin: ['completed', 'cancelled'] } }),
      col(C.tasks).countDocuments({
        status: { $in: ['pending', 'inProgress', 'review', 'blocked'] },
        dueDate: { $lt: now },
      }),
    ]);

    response.json({
      departments: byDepartment.map((d) => ({
        departmentId: d._id ? String(d._id) : null,
        name: d._id ? nameById.get(String(d._id)) ?? 'Unassigned' : 'Unassigned',
        total: d.total,
        completed: d.completed,
        completionRate: d.total > 0 ? Math.round((d.completed / d.total) * 100) : 0,
        avgCompletionHours: d.avgCompletionMs ? Math.round(d.avgCompletionMs / 3600000) : null,
      })),
      status: {
        pending: statusCount('pending'),
        inProgress: statusCount('inProgress'),
        review: statusCount('review'),
        blocked: statusCount('blocked'),
        completed: statusCount('completed'),
        cancelled: statusCount('cancelled'),
      },
      completions,
      totals: {
        people,
        departments: activeDepartments,
        openEvents,
        overdue,
      },
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

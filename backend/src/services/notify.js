'use strict';

const { col, C } = require('../db');
const { ROLES } = require('../permissions');
const fcm = require('./fcm');

/**
 * Notification fan-out.
 *
 * Writing to the `notifications` collection is all a route has to do. The
 * Change Stream on that collection delivers it over Socket.IO to whoever is
 * connected; this module additionally hands it to FCM so it still lands as a
 * system notification for anyone whose app is closed.
 *
 * Section 5: same event types, two delivery paths.
 */

/** Human-readable copy for each event type, used by both toast and push. */
const COPY = {
  taskAssigned: (p) => ({
    title: 'New task assigned',
    body: p.taskTitle ?? 'You have a new task.',
  }),
  // Work addressed to a whole department. The Lead decides who does it — the
  // copy says so, because "new task" would read as "you personally".
  departmentTaskAssigned: (p) => ({
    title: `Work for ${p.departmentName ?? 'your department'}`,
    body: `${p.byName ?? 'Leadership'} sent "${p.taskTitle ?? 'a task'}". `
      + 'Pass it on or take it yourself.',
  }),
  departmentTaskUnclaimed: (p) => ({
    title: 'A department has no Lead',
    body: `"${p.taskTitle ?? 'A task'}" went to ${p.departmentName ?? 'a department'}, `
      + 'which has nobody to receive it.',
  }),
  taskRequestReceived: (p) => ({
    title: 'Task request received',
    body: `${p.fromName ?? 'Someone'} asked you to take on "${p.taskTitle ?? 'a task'}".`,
  }),
  taskRequestAccepted: (p) => ({
    title: 'Request accepted',
    body: `${p.byName ?? 'They'} accepted "${p.taskTitle ?? 'your request'}".`,
  }),
  taskRequestDeclined: (p) => ({
    title: 'Request declined',
    body: `${p.byName ?? 'They'} declined "${p.taskTitle ?? 'your request'}".`,
  }),
  taskCompleted: (p) => ({
    title: 'Task completed',
    body: `${p.byName ?? 'Someone'} completed "${p.taskTitle ?? 'a task'}".`,
  }),
  approvalNeeded: (p) => ({
    title: 'Approval needed',
    body: `${p.applicantName ?? 'A new member'} is waiting to join ${p.departmentName ?? 'the club'}.`,
  }),
  approvalGranted: () => ({
    title: 'You are in',
    body: 'Your account has been approved. Welcome to the club.',
  }),
  approvalRejected: () => ({
    title: 'Access declined',
    body: 'Your request to join was not approved.',
  }),
  // One message a day, however much is open. Counts rather than a list: six
  // separate notifications is how an app teaches people to swipe it away.
  taskDueReminder: (p) => {
    const total = Number(p.total ?? 0);
    const overdue = Number(p.overdue ?? 0);
    const thing = total === 1 ? 'task' : 'tasks';
    if (overdue > 0 && overdue === total) {
      return {
        title: total === 1 ? 'Overdue' : `${total} overdue`,
        body: total === 1
          ? `"${p.taskTitle ?? 'A task'}" was due and is still open.`
          : `${total} ${thing} are past their due date and still open.`,
      };
    }
    if (overdue > 0) {
      return {
        title: `${total} still open`,
        body: `${overdue} past due, ${total - overdue} due today.`,
      };
    }
    return {
      title: total === 1 ? 'Due today' : `${total} due today`,
      body: total === 1
        ? `"${p.taskTitle ?? 'A task'}" is due today.`
        : `You have ${total} ${thing} due today.`,
    };
  },
  profileRenamed: (p) => ({
    title: 'Your name was updated',
    body: `${p.by ?? 'An administrator'} set your name to "${p.to ?? ''}". Change it yourself in More if that is not right.`,
  }),
  // Directors are told about Lead approvals for visibility, not to act.
  approvalObserved: (p) => ({
    title: 'Lead approval pending',
    body: `${p.applicantName ?? 'A Lead'} is awaiting approval from the President.`,
  }),
  eventReminder: (p) => ({
    title: p.eventTitle ?? 'Upcoming event',
    body: p.when ?? 'Coming up soon.',
  }),
  pointsEarned: (p) => ({
    title: `+${p.points ?? 0} points`,
    body: p.reason ?? 'Nice work.',
  }),
  departmentChanged: (p) => ({
    title: 'Department updated',
    body: p.message ?? 'Your department details changed.',
  }),
  taskComment: (p) => ({
    title: 'New comment',
    body: `${p.byName ?? 'Someone'} commented on "${p.taskTitle ?? 'a task'}".`,
  }),
  // A broadcast raised by leadership. The sender's name is part of the body on
  // purpose — an unsigned club-wide alert is how this feature gets abused.
  clubAlert: (p) => ({
    title: p.urgency === 'urgent'
      ? `Urgent — ${p.alertTitle ?? 'Club alert'}`
      : (p.alertTitle ?? 'Club alert'),
    body: `${p.alertMessage ?? ''}${p.senderName ? ` — ${p.senderName}` : ''}`,
  }),
  pointsAwarded: (p) => ({
    title: `+${p.points ?? 0} points`,
    body: `${p.byName ?? 'Someone'} recognised you${p.reason ? `: ${p.reason}` : '.'}`,
  }),
  scheduleAdded: (p) => ({
    title: 'Added to the schedule',
    body: p.entryTitle ?? 'Something new is on the club schedule.',
  }),

  // --- events --------------------------------------------------------------
  eventCreated: (p) => ({
    title: 'You are on an event team',
    body: `${p.byName ?? 'Someone'} added you to ${p.eventTitle ?? 'an event'}.`,
  }),
  // Only fired for the things people plan around — a moved date, a new venue.
  eventUpdated: (p) => ({
    title: p.eventTitle ?? 'Event updated',
    body: p.change ?? 'Some details changed.',
  }),
  documentDecision: (p) => ({
    title: p.status === 'approved' ? 'Document approved' : 'Document needs another look',
    body: `${p.title ?? 'A document'} was marked ${p.status ?? 'updated'}${
      p.byName ? ` by ${p.byName}` : ''}.`,
  }),
  documentPending: (p) => ({
    title: 'Approval waiting',
    body: `${p.title ?? 'A document'} for ${p.eventTitle ?? 'an event'} needs a decision.`,
  }),

  // --- event finance --------------------------------------------------------
  billFiled: (p) => ({
    title: 'Expense to approve',
    body: `${p.byName ?? 'Someone'} filed ₹${p.amount ?? '0'} for `
      + `"${p.billTitle ?? 'an expense'}" on ${p.eventTitle ?? 'an event'}.`,
  }),
  billDecision: (p) => ({
    title: p.status === 'approved' ? 'Expense approved' : 'Expense not approved',
    body: `₹${p.amount ?? '0'} for "${p.billTitle ?? 'your expense'}" was `
      + `${p.status ?? 'updated'}${p.byName ? ` by ${p.byName}` : ''}.`,
  }),
  billSettled: (p) => ({
    title: 'You have been repaid',
    body: `₹${p.amount ?? '0'} for "${p.billTitle ?? 'your expense'}" is marked settled.`,
  }),

  // --- accounts -------------------------------------------------------------
  passwordResetRequested: (p) => ({
    title: 'Password reset needed',
    body: `${p.applicantName ?? 'Someone'} (${p.applicantEmail ?? ''}) cannot sign in. `
      + 'Reset it from the member directory.',
  }),
  passwordReset: (p) => ({
    title: 'Your password was reset',
    body: `${p.byName ?? 'An administrator'} set a temporary password. `
      + 'Choose your own when you sign in.',
  }),

  // --- help & collaboration -------------------------------------------------
  helpRequested: (p) => ({
    title: 'Someone needs a hand',
    body: `${p.byName ?? 'A member'}: ${p.helpTitle ?? 'asked for help'}`,
  }),
  helpOffered: (p) => ({
    title: 'Help is on the way',
    body: `${p.byName ?? 'Someone'} offered to help with "${p.helpTitle ?? 'your request'}".`,
  }),
  helpResolved: (p) => ({
    title: 'Sorted',
    body: `"${p.helpTitle ?? 'Your request'}" was marked resolved.`,
  }),
  // Confirms to the helper that offering put something on their own list, so
  // the new task is not a surprise they find later.
  helpJoined: (p) => ({
    title: 'Added to your work',
    body: `You offered to help with "${p.helpTitle ?? 'a request'}". `
      + 'It is on your task list with the deadline they asked for.',
  }),

  // --- people ---------------------------------------------------------------
  memberRemoved: (p) => ({
    title: 'Membership ended',
    body: `${p.byName ?? 'A Director'} removed your account from ${p.clubName ?? 'the club'}.`,
  }),
  departmentCreated: (p) => ({
    title: 'New department',
    body: `${p.byName ?? 'Leadership'} added ${p.departmentName ?? 'a department'}.`,
  }),
  eventCancelled: (p) => ({
    title: 'Event cancelled',
    body: `"${p.eventName ?? 'An event'}" was cancelled by ${p.byName ?? 'leadership'}.`,
  }),
};

function render(type, payload) {
  const fn = COPY[type];
  return fn ? fn(payload ?? {}) : { title: 'GWD Club', body: '' };
}

/**
 * Create notifications for one or more users.
 * Silently ignores an empty recipient list so callers need no guard.
 */
async function notify(userIds, type, payload = {}) {
  const ids = (Array.isArray(userIds) ? userIds : [userIds]).filter(Boolean);
  if (ids.length === 0) return [];

  const now = new Date();
  const docs = ids.map((userId) => ({
    userId,
    type,
    payload,
    read: false,
    createdAt: now,
  }));

  await col(C.notifications).insertMany(docs);

  // Push is best-effort and must never fail the originating request.
  const { title, body } = render(type, payload);
  fcm
    .sendToUsers(ids, { title, body, data: { type, ...flatten(payload) } })
    .catch((error) => console.error('[notify] push failed:', error.message));

  return docs;
}

/** FCM data payloads must be flat strings. */
function flatten(payload) {
  const out = {};
  for (const [key, value] of Object.entries(payload ?? {})) {
    if (value === null || value === undefined) continue;
    out[key] = typeof value === 'object' ? JSON.stringify(value) : String(value);
  }
  return out;
}

/** Every user holding a given role — used for Director visibility fan-out. */
async function usersWithRole(role) {
  const users = await col(C.users)
    .find({ role, approvalStatus: 'approved' }, { projection: { _id: 1 } })
    .toArray();
  return users.map((u) => u._id);
}

/** Convenience: notify all Club Directors (Section 4.4 visibility rule). */
async function notifyDirectors(type, payload) {
  return notify(await usersWithRole(ROLES.clubDirector), type, payload);
}

/** Append to the audit log. Directors rely on this for oversight. */
async function audit(actorId, action, detail = {}) {
  await col(C.auditLog).insertOne({
    actorId,
    action,
    detail,
    createdAt: new Date(),
  });
}

module.exports = { notify, notifyDirectors, usersWithRole, audit, render };

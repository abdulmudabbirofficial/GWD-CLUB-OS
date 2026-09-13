'use strict';

/**
 * The daily reminder sweep, tested against a throwaway database.
 *
 * Not part of smoke.js because that suite is deliberately pure HTTP, and this
 * is a scheduled job with no route in front of it. The rule worth protecting is
 * the one that is invisible when it breaks: **one message per person per day**.
 * A regression there does not throw — it just quietly turns the app into
 * something people mute.
 *
 * Run with MONGODB_DB pointed at a scratch database. smoke-isolated.ps1 does
 * that and drops it afterwards.
 */

const { ObjectId } = require('mongodb');
const db = require('../src/db');
const { col, C } = require('../src/db');
const reminders = require('../src/services/reminders');

let passed = 0;
let failed = 0;
const ok = (label, condition, detail = '') => {
  if (condition) { passed += 1; console.log(`  \x1b[32mPASS\x1b[0m  ${label}`); }
  else { failed += 1; console.log(`  \x1b[31mFAIL\x1b[0m  ${label}${detail ? ` — ${detail}` : ''}`); }
};

const daysFromNow = (n) => {
  const d = new Date();
  d.setDate(d.getDate() + n);
  d.setHours(12, 0, 0, 0);
  return d;
};

async function main() {
  await db.connect();
  console.log('\nreminders');

  // A clean slate inside the scratch database.
  await Promise.all([
    col(C.users).deleteMany({ email: /reminder-test/ }),
    col(C.tasks).deleteMany({ title: /^REMINDER TEST/ }),
    col(C.notifications).deleteMany({ type: 'taskDueReminder' }),
  ]);

  const mk = async (email) => {
    const r = await col(C.users).insertOne({
      name: email, email, role: 'clubMember', approvalStatus: 'approved',
      points: 0, departmentId: null, createdAt: new Date(),
    });
    return r.insertedId;
  };

  const busy = await mk('reminder-test-busy@gwd.club');
  const clear = await mk('reminder-test-clear@gwd.club');
  const future = await mk('reminder-test-future@gwd.club');
  const pending = await col(C.users).insertOne({
    name: 'not approved', email: 'reminder-test-pending@gwd.club',
    role: 'clubMember', approvalStatus: 'pending', points: 0, createdAt: new Date(),
  });

  const task = (assignedTo, dueDate, status = 'pending', extra = {}) => ({
    title: `REMINDER TEST ${Math.random().toString(36).slice(2, 7)}`,
    assignedTo, dueDate, status, assignedBy: assignedTo,
    departmentId: null, points: 1, createdAt: new Date(), updatedAt: new Date(),
    ...extra,
  });

  await col(C.tasks).insertMany([
    task(busy, daysFromNow(-3)),               // overdue
    task(busy, daysFromNow(0)),                // due today
    task(busy, daysFromNow(-1), 'inProgress'), // overdue, started
    task(busy, daysFromNow(-2), 'completed'),  // finished — must not count
    task(busy, null),                          // no due date — not late
    task(future, daysFromNow(9)),              // not due yet
    task(clear, daysFromNow(-1), 'cancelled'), // cancelled — must not count
    // Addressed to a department and not yet handed out: nobody owes it.
    task(null, daysFromNow(-4), 'pending', { departmentId: new ObjectId() }),
    task(pending.insertedId, daysFromNow(-1)), // not approved into the club
  ]);

  const first = await reminders.sendDueReminders();
  ok('Only people with something actually due are told',
    first.people === 1, `told ${first.people}`);

  const got = await col(C.notifications)
    .find({ userId: busy, type: 'taskDueReminder' }).toArray();
  ok('And they get exactly one message, not one per task',
    got.length === 1, `got ${got.length}`);

  const payload = got[0]?.payload ?? {};
  ok('Which counts everything open and due', payload.total === 3,
    `total ${payload.total}`);
  ok('Separating what is late from what is due today',
    payload.overdue === 2 && payload.dueToday === 1,
    `overdue ${payload.overdue}, today ${payload.dueToday}`);

  const noneForFuture = await col(C.notifications)
    .countDocuments({ userId: future, type: 'taskDueReminder' });
  ok('Work due next week is not chased today', noneForFuture === 0);

  const noneForClear = await col(C.notifications)
    .countDocuments({ userId: clear, type: 'taskDueReminder' });
  ok('Nobody is pinged to be told they have nothing', noneForClear === 0);

  const noneForPending = await col(C.notifications)
    .countDocuments({ userId: pending.insertedId, type: 'taskDueReminder' });
  ok('Somebody still awaiting approval is not chased for work',
    noneForPending === 0);

  // The rule that matters: running it again the same day must do nothing. A
  // server restarted four times in a morning still sends one reminder.
  const second = await reminders.sendDueReminders();
  ok('Running it again the same day sends nothing',
    second.people === 0 && second.skipped === 1,
    `people ${second.people}, skipped ${second.skipped}`);

  const stillOne = await col(C.notifications)
    .countDocuments({ userId: busy, type: 'taskDueReminder' });
  ok('So the count does not creep up on every restart', stillOne === 1,
    `got ${stillOne}`);

  // Tomorrow it may speak again.
  await col(C.users).updateOne({ _id: busy }, { $set: { lastRemindedOn: '1999-01-01' } });
  const nextDay = await reminders.sendDueReminders();
  ok('But the next day it does', nextDay.people === 1, `told ${nextDay.people}`);

  console.log(`\n  ${passed} passed, ${failed} failed\n`);
  await db.close();
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error('\nReminder test crashed:', error);
  process.exit(1);
});

'use strict';

/**
 * The daily nudge: "you still have this open, and it was due yesterday."
 *
 * A club runs on people remembering things between meetings, and the failure
 * mode is never that somebody refused — it is that a task handed out on Tuesday
 * is genuinely forgotten by Friday. A calendar answers that only if you open
 * it; a reminder finds you.
 *
 * Three rules keep it from becoming noise people mute:
 *
 *  1. **One message per person per day, ever.** Not one per task. Somebody with
 *     six things open gets a single line saying six, because six separate
 *     notifications is how an app teaches people to swipe it away unread.
 *  2. **Only when there is something to say.** No "you have nothing due"
 *     reminders. An app that pings you to tell you nothing has happened is an
 *     app you turn off.
 *  3. **Only what is actually due.** Work with no due date is not late, and
 *     something due next month is not urgent today.
 *
 * Idempotent across restarts: the date of the last reminder is stamped on the
 * user, so a server restarted four times in a morning still sends one.
 */

const { ObjectId } = require('mongodb');
const { col, C } = require('../db');
const { notify } = require('./notify');

/** Local calendar day as `YYYY-MM-DD` — the unit people actually think in. */
function dayKey(date = new Date()) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function endOfToday() {
  const d = new Date();
  d.setHours(23, 59, 59, 999);
  return d;
}

function startOfToday() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}

/**
 * Send today's reminders.
 *
 * Exported on its own so it can be triggered by hand and asserted in tests
 * without waiting for a clock.
 */
async function sendDueReminders({ now = new Date() } = {}) {
  const today = dayKey(now);
  const cutoff = endOfToday();

  // Everything open with a due date at or before the end of today, grouped by
  // the person who owes it. Work addressed to a department but not yet handed
  // out has `assignedTo: null` and is nobody's to be reminded about — that is
  // the Lead's triage pile, which the department page already surfaces.
  const due = await col(C.tasks).find({
    assignedTo: { $ne: null },
    dueDate: { $ne: null, $lte: cutoff },
    status: { $nin: ['completed', 'cancelled'] },
  }, {
    projection: { assignedTo: 1, title: 1, dueDate: 1 },
  }).toArray();

  if (due.length === 0) return { people: 0, tasks: 0, skipped: 0 };

  const byPerson = new Map();
  for (const task of due) {
    const key = String(task.assignedTo);
    if (!byPerson.has(key)) byPerson.set(key, []);
    byPerson.get(key).push(task);
  }

  const startToday = startOfToday();
  const ids = [...byPerson.keys()]
    .filter((id) => ObjectId.isValid(id))
    .map((id) => new ObjectId(id));

  const users = await col(C.users).find(
    { _id: { $in: ids }, approvalStatus: 'approved' },
    { projection: { lastRemindedOn: 1 } },
  ).toArray();

  let sent = 0;
  let skipped = 0;

  for (const user of users) {
    if (user.lastRemindedOn === today) { skipped += 1; continue; }

    const tasks = byPerson.get(String(user._id)) ?? [];
    if (tasks.length === 0) continue;

    const overdue = tasks.filter((t) => new Date(t.dueDate) < startToday);
    const dueToday = tasks.length - overdue.length;

    await notify(user._id, 'taskDueReminder', {
      total: tasks.length,
      overdue: overdue.length,
      dueToday,
      // Naming one gives the notification something to be about; the count
      // carries the rest.
      taskTitle: tasks[0].title,
      taskId: String(tasks[0]._id),
    });

    await col(C.users).updateOne(
      { _id: user._id },
      { $set: { lastRemindedOn: today } },
    );
    sent += 1;
  }

  return { people: sent, tasks: due.length, skipped };
}

/**
 * Check once an hour and send when the local hour matches.
 *
 * An hourly tick rather than a precise daily timer because a laptop that sleeps
 * through 09:00 would otherwise skip the day entirely — on the next tick after
 * waking, the day's reminder has still not gone out and the stamp says so, so
 * it goes then. Late is much better than never for this.
 */
function start({ hour = Number(process.env.REMINDER_HOUR ?? 9) } = {}) {
  const tick = async () => {
    try {
      if (new Date().getHours() < hour) return;
      const result = await sendDueReminders();
      if (result.people > 0) {
        console.log(`  Reminders: told ${result.people} ${result.people === 1 ? 'person' : 'people'} about work due.`);
      }
    } catch (error) {
      // A failed reminder must never take the API down with it.
      console.error('  Reminder sweep failed:', error.message);
    }
  };

  // Not on the very first tick at boot: a server restarted at 09:05 should not
  // race its own startup, and an hour's delay costs nothing on a daily job.
  const timer = setInterval(tick, 60 * 60 * 1000);
  timer.unref?.();

  // One catch-up shortly after boot, for the case where the machine was asleep
  // at the appointed hour and has only just come back.
  const warmup = setTimeout(tick, 60 * 1000);
  warmup.unref?.();

  return () => { clearInterval(timer); clearTimeout(warmup); };
}

module.exports = { start, sendDueReminders, dayKey };

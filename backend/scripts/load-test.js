'use strict';

/**
 * What happens when the whole club opens the app at once.
 *
 * The brief asks for 80-100 people concurrently, and that number has a shape:
 * a club does not trickle in, it arrives. Everyone opens the app in the same
 * thirty seconds at the start of a meeting, each one firing the fifteen
 * requests `ClubStore.loadAll` makes, and every one of them then holds a
 * Socket.IO connection open for the rest of the hour.
 *
 * So this measures the burst, not a steady rate:
 *
 *   1. N accounts sign in at once
 *   2. all N run a full `loadAll` fan-out simultaneously
 *   3. all N hold live sockets while one write fans out to every one of them
 *
 * Reports p50/p95/p99 and the worst case, because an average hides exactly the
 * thing that makes an app feel broken - the one person in twenty who waits
 * four seconds.
 *
 *   node scripts/load-test.js --users 100 --base http://127.0.0.1:4300
 */

const { io } = require('socket.io-client');

const arg = (name, fallback) => {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? fallback : process.argv[i + 1];
};

const BASE = arg('base', 'http://127.0.0.1:4300');
const USERS = Number(arg('users', '100'));
const PASSWORD = arg('password', 'LoadPass2026');
const SKIP_SOCKETS = process.argv.includes('--no-sockets');

/** The exact fan-out ClubStore.loadAll performs when a screen opens. */
const LOAD_ALL = [
  '/api/home', '/api/tasks', '/api/departments', '/api/notifications',
  '/api/categories/schedule', '/api/schedule', '/api/alerts', '/api/task-requests',
  '/api/users', '/api/users/leaderboard', '/api/users/department-overview',
  '/api/events', '/api/help', '/api/tasks?scope=incoming', '/api/meetings',
];

function percentile(sorted, p) {
  if (sorted.length === 0) return 0;
  const i = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1);
  return sorted[i];
}

function report(label, times, failures) {
  const s = [...times].sort((a, b) => a - b);
  const mean = s.reduce((a, b) => a + b, 0) / (s.length || 1);
  console.log(
    `  ${label.padEnd(28)} n=${String(s.length).padStart(5)}  `
    + `p50 ${String(Math.round(percentile(s, 50))).padStart(5)}ms  `
    + `p95 ${String(Math.round(percentile(s, 95))).padStart(5)}ms  `
    + `p99 ${String(Math.round(percentile(s, 99))).padStart(5)}ms  `
    + `max ${String(Math.round(s[s.length - 1] ?? 0)).padStart(5)}ms  `
    + `mean ${String(Math.round(mean)).padStart(5)}ms`
    + (failures ? `  FAILED ${failures}` : ''),
  );
  return { p95: percentile(s, 95), p99: percentile(s, 99), max: s[s.length - 1] ?? 0, failures };
}

async function timed(fn) {
  const t = process.hrtime.bigint();
  const ok = await fn();
  return { ms: Number(process.hrtime.bigint() - t) / 1e6, ok };
}

(async () => {
  console.log(`\n  ${USERS} people, all at once, against ${BASE}\n`);

  // --- sign in -------------------------------------------------------------
  const loginTimes = [];
  let loginFailures = 0;
  const sessions = [];

  const logins = await Promise.all(
    Array.from({ length: USERS }, (_, i) => timed(async () => {
      const res = await fetch(`${BASE}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: `load${i}@gwd.club`, password: PASSWORD }),
      });
      if (!res.ok) return null;
      return (await res.json()).token;
    })),
  );
  for (const { ms, ok } of logins) {
    loginTimes.push(ms);
    if (ok) sessions.push(ok); else loginFailures += 1;
  }
  const loginStat = report('sign in (concurrent)', loginTimes, loginFailures);

  if (sessions.length === 0) {
    console.log('\n  No accounts signed in. Seed them first with --seed.\n');
    process.exit(1);
  }

  // --- the opening fan-out -------------------------------------------------
  const reqTimes = [];
  let reqFailures = 0;
  const perUser = [];
  // Per endpoint, so a failure or a slow one can be named rather than hidden
  // inside an aggregate. "100 calls failed" is useless; "/api/users failed for
  // everyone" is a bug report.
  const byPath = new Map();
  for (const path of LOAD_ALL) byPath.set(path, { times: [], failures: 0, status: new Set() });

  await Promise.all(sessions.map(async (token) => {
    const started = process.hrtime.bigint();
    await Promise.all(LOAD_ALL.map(async (path) => {
      const entry = byPath.get(path);
      const { ms, ok } = await timed(async () => {
        const res = await fetch(BASE + path, { headers: { Authorization: `Bearer ${token}` } });
        // Drain the body: leaving it unread hides deserialisation cost and
        // keeps sockets in a half-read state that skews everything after it.
        await res.text();
        entry.status.add(res.status);
        return res.ok;
      });
      reqTimes.push(ms);
      entry.times.push(ms);
      if (!ok) { reqFailures += 1; entry.failures += 1; }
    }));
    perUser.push(Number(process.hrtime.bigint() - started) / 1e6);
  }));

  const reqStat = report('each API call', reqTimes, reqFailures);

  console.log('');
  console.log('  slowest endpoints under the burst');
  const rows = [...byPath.entries()]
    .map(([path, e]) => ({ path, p95: percentile([...e.times].sort((a, b) => a - b), 95), ...e }))
    .sort((a, b) => b.p95 - a.p95);
  for (const r of rows.slice(0, 8)) {
    console.log(`    ${r.path.padEnd(34)} p95 ${String(Math.round(r.p95)).padStart(5)}ms`
      + (r.failures ? `  FAILED ${r.failures} (${[...r.status].join(',')})` : ''));
  }
  console.log('');
  const screenStat = report('full screen load, per person', perUser, 0);

  // --- everyone holding a live socket -------------------------------------
  let socketStat = null;
  if (!SKIP_SOCKETS) {
    const connects = [];
    const sockets = [];
    await Promise.all(sessions.map((token) => new Promise((resolve) => {
      const t = process.hrtime.bigint();
      const socket = io(BASE, {
        auth: { token },
        transports: ['websocket'],
        reconnection: false,
        timeout: 20000,
      });
      const done = (ok) => {
        connects.push({ ms: Number(process.hrtime.bigint() - t) / 1e6, ok });
        resolve();
      };
      socket.on('connect', () => { sockets.push(socket); done(true); });
      socket.on('connect_error', () => done(false));
      setTimeout(() => done(false), 20000);
    })));

    const failed = connects.filter((c) => !c.ok).length;
    socketStat = report('live socket connect', connects.map((c) => c.ms), failed);
    console.log(`  ${'sockets held open'.padEnd(28)} ${sockets.length} of ${sessions.length}`);
    for (const s of sockets) s.close();
  }

  // --- the verdict ---------------------------------------------------------
  //
  // 1s at p95 for a whole screen is the line: past that a person has time to
  // notice they are waiting, which is the difference between an app that feels
  // instant and one that feels slow even though nothing is broken.
  console.log('');
  const problems = [];
  if (loginStat.failures) problems.push(`${loginStat.failures} sign-ins failed`);
  if (reqStat.failures) problems.push(`${reqStat.failures} API calls failed`);
  if (socketStat?.failures) problems.push(`${socketStat.failures} sockets failed to connect`);
  if (screenStat.p95 > 1000) problems.push(`screen load p95 ${Math.round(screenStat.p95)}ms is over 1s`);

  if (problems.length === 0) {
    console.log(`  PASS - ${sessions.length} people at once, screen load p95 `
      + `${Math.round(screenStat.p95)}ms, nothing dropped.\n`);
    process.exit(0);
  }
  console.log('  PROBLEMS');
  for (const p of problems) console.log(`    - ${p}`);
  console.log('');
  process.exit(1);
})().catch((e) => { console.error(e); process.exit(1); });

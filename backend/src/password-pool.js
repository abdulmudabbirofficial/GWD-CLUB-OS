'use strict';

const os = require('node:os');
const path = require('node:path');
const { Worker } = require('node:worker_threads');

/**
 * bcrypt, moved off the event loop and across every core.
 *
 * bcrypt is *meant* to be slow — that is the whole point of it — but `bcryptjs`
 * is the pure-JavaScript build, which makes it slow in the wrong way as well:
 * a single cost-12 comparison takes ~435ms of pure JS on one thread.
 *
 * A measured hundred-person sign-in burst took **28 seconds at p50 and dropped
 * 16 requests**, because every comparison queued behind the last one on the
 * only thread Node has, while eleven other cores sat idle. Worse, the work is
 * CPU-bound JavaScript, so it starved everything else on the loop with it:
 * during the burst all fifteen change streams timed out checking a connection
 * out of the Mongo pool, and live sync went down across the whole club.
 *
 * So hashing runs here instead — a fixed pool of workers, one per core, with a
 * queue in front. The cost factor is untouched: an attacker's cost is what that
 * number is for, and lowering it to buy throughput would be trading the actual
 * security property for a problem that is really just scheduling. What changes
 * is that the work now uses the machine it is running on, and the event loop
 * stays free to answer everybody else.
 */

// One per core, minus the main thread's own, and never fewer than two. Beyond
// the core count this only adds context switching: the work is pure CPU.
const SIZE = Math.max(2, Math.min(8, (os.cpus()?.length ?? 4) - 1));

// A hash that cannot be produced by any password, for the constant-time dummy
// comparison the login route runs when no account matches. Generated once at
// startup rather than being a literal, so it can never be recognised.
let dummyHash = null;

const workers = [];
const idle = [];
const queue = [];
let nextId = 1;
const pending = new Map();

function spawn() {
  const worker = new Worker(path.join(__dirname, 'password-worker.js'));
  worker.on('message', ({ id, value, error }) => {
    const job = pending.get(id);
    if (!job) return;
    pending.delete(id);
    if (error) job.reject(new Error(error));
    else job.resolve(value);
    idle.push(worker);
    pump();
  });
  // A worker that dies takes its in-flight job with it. Fail that one job and
  // replace the worker, rather than leaving the caller hanging forever.
  worker.on('error', (error) => {
    for (const [id, job] of pending) {
      if (job.worker === worker) { job.reject(error); pending.delete(id); }
    }
    const i = workers.indexOf(worker);
    if (i !== -1) workers.splice(i, 1);
    const j = idle.indexOf(worker);
    if (j !== -1) idle.splice(j, 1);
    if (!closing) { const fresh = spawn(); idle.push(fresh); pump(); }
  });
  // Deliberately *not* unref'd. An unref'd worker does not keep the process
  // alive, so a short-lived script — a seed, a migration — could exit with a
  // hash still in flight and silently write nothing. The server closes the
  // pool on shutdown instead, which is the honest way to let the process end.
  workers.push(worker);
  return worker;
}

let started = false;
let closing = false;

function start() {
  if (started) return;
  started = true;
  for (let i = 0; i < SIZE; i += 1) idle.push(spawn());
}

function pump() {
  while (queue.length > 0 && idle.length > 0) {
    const job = queue.shift();
    const worker = idle.pop();
    job.worker = worker;
    pending.set(job.id, job);
    worker.postMessage({ id: job.id, op: job.op, args: job.args });
  }
}

function run(op, args) {
  start();
  return new Promise((resolve, reject) => {
    queue.push({ id: nextId++, op, args, resolve, reject });
    pump();
  });
}

const hashPassword = (plain, rounds = 12) => run('hash', [plain, rounds]);
const verifyPassword = (plain, hash) => run('compare', [plain, hash]);

/**
 * The login route compares against this when no account matches, so an unknown
 * address does not answer measurably faster than a wrong password. It has to
 * cost the same as a real comparison, which means it must be a real hash.
 */
async function dummy() {
  dummyHash ??= await hashPassword(`no-such-account-${Math.random()}`);
  return dummyHash;
}

async function close() {
  closing = true;
  await Promise.all(workers.map((w) => w.terminate()));
  workers.length = 0;
  idle.length = 0;
}

module.exports = { hashPassword, verifyPassword, dummy, close, size: SIZE };

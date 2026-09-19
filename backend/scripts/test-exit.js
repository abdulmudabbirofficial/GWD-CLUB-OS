'use strict';

/**
 * Does a script that touches a password still exit?
 *
 * The bcrypt worker pool once kept every short-lived script alive forever:
 * `seed-club.js` wrote the whole roster, printed the passwords, and then hung
 * on an idle worker instead of returning to the shell. It is a nasty failure
 * because nothing is *wrong* — the work is done, the output is correct, the
 * process simply never ends — so it survives any test that only checks output.
 *
 * Both directions are checked, because the obvious fix breaks the other one:
 *   - work still in flight must hold the process open
 *   - an idle pool must let it go
 */

const { spawnSync } = require('node:child_process');
const path = require('node:path');

const BACKEND = path.join(__dirname, '..');
let pass = 0;
let fail = 0;
const ok = (label, cond, extra = '') => {
  if (cond) { pass += 1; console.log(`  PASS  ${label}`); }
  else { fail += 1; console.log(`  FAIL  ${label}${extra ? ` - ${extra}` : ''}`); }
};

const run = (source, timeoutMs = 25000) => spawnSync(
  process.execPath, ['-e', source],
  { cwd: BACKEND, timeout: timeoutMs, encoding: 'utf8' },
);

console.log('\nprocess exit\n');

// 1. An idle pool must not hold the process open.
const idle = run(`
  const { hashPassword } = require('./src/auth');
  hashPassword('probe').then((h) => console.log('HASHED', h.length));
`);
ok('a script that hashes a password still exits',
  idle.status === 0 && !idle.error,
  idle.error ? idle.error.message : `status ${idle.status}`);
ok('and the hash actually completed first',
  (idle.stdout ?? '').includes('HASHED 60'), JSON.stringify(idle.stdout));

// 2. Work in flight must keep it alive: if the pool were unconditionally
//    unref'd, Node would exit before the comparison came back and the second
//    line would never print.
const inFlight = run(`
  const { hashPassword, verifyPassword } = require('./src/auth');
  (async () => {
    const h = await hashPassword('probe');
    const ok = await verifyPassword('probe', h);
    console.log('VERIFIED', ok);
  })();
`);
ok('work still in flight keeps the process alive to finish',
  (inFlight.stdout ?? '').includes('VERIFIED true'),
  JSON.stringify(inFlight.stdout));

console.log(`\n  ${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);

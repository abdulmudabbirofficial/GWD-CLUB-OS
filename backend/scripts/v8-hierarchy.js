'use strict';

/**
 * V8 hierarchy, applied to a database that already exists.
 *
 *   node scripts/v8-hierarchy.js            # dry run: says what it would do
 *   node scripts/v8-hierarchy.js --apply    # does it, after writing a backup
 *
 * Three things, each idempotent — running it twice changes nothing the second
 * time:
 *
 *   1. **The Directors, by name.** The club's three Director seats are held by
 *      Abdul Mudabbir, Rehman Pasha and Mohammed Moin, addressed as Director
 *      Mudabbir, Director Rehman and Director Moin. The third seat was still
 *      called "Club Director Three".
 *   2. **One Super Admin.** Director Mudabbir. The flag is written here and by
 *      no route, which is what makes it impossible to mint through the API.
 *   3. **The spare bootstrap accounts go**, under the rule in
 *      `src/placeholders.js`: never used, and the seat is held by somebody real.
 *      Anything that fails either test is kept and the reason printed.
 *
 * Nothing is written without `--apply`, and nothing is written before every
 * document it touches has been saved to `backups/` (gitignored — it holds
 * password hashes, so it stays on the machine that made it).
 *
 * The Director list is the club's decision, given in the V8 brief. It lives in
 * this script and not in app code for the same reason the roster lives in
 * seed-club.js: who holds a post is data about this club, not a rule of the
 * software.
 */

const fs = require('node:fs');
const path = require('node:path');
const config = require('../src/config');
const { connect, close, col, C } = require('../src/db');
const { ROLES } = require('../src/permissions');
const { planPlaceholderRetirement, retireAccounts } = require('../src/placeholders');

const APPLY = process.argv.includes('--apply');

const DIRECTORS = [
  { email: 'cmo@gwd.global', name: 'Abdul Mudabbir', knownAs: 'Mudabbir', superAdmin: true },
  { email: 'ceo@gwd.global', name: 'Rehman Pasha', knownAs: 'Rehman', superAdmin: false },
  { email: 'director3@gwd.global', name: 'Mohammed Moin', knownAs: 'Moin', superAdmin: false },
];

function where() {
  const uri = config.mongoUri;
  if (/127\.0\.0\.1|localhost/.test(uri)) return 'local';
  const host = (uri.match(/@([^/?]+)/) || [])[1] || 'remote';
  return `REMOTE (${host.replace(/^[^.]+/, '***')})`;
}

(async () => {
  await connect();
  console.log(`\n  V8 hierarchy — ${APPLY ? 'APPLYING' : 'dry run (nothing will be written)'}`);
  console.log(`  Target: ${where()} / ${config.mongoDb}\n`);

  // --- 1 & 2: the Directors ---------------------------------------------
  const plan = [];
  for (const want of DIRECTORS) {
    const user = await col(C.users).findOne({ email: want.email });
    if (!user) {
      console.log(`  !  ${want.email} not found — left for the club to create`);
      continue;
    }
    if (user.role !== ROLES.clubDirector) {
      console.log(`  !  ${want.email} is a ${user.role}, not a Director — not touched`);
      continue;
    }
    const set = {};
    if (user.name !== want.name) set.name = want.name;
    if (user.knownAs !== want.knownAs) set.knownAs = want.knownAs;
    if ((user.superAdmin === true) !== want.superAdmin) set.superAdmin = want.superAdmin;
    if (user.mustSetName) set.mustSetName = false;
    if (Object.keys(set).length === 0) {
      console.log(`     ${want.email.padEnd(24)} already right: Director ${want.knownAs}`);
      continue;
    }
    plan.push({ user, set });
    const changes = Object.entries(set)
      .map(([k, v]) => `${k}: ${JSON.stringify(user[k] ?? null)} → ${JSON.stringify(v)}`)
      .join(', ');
    console.log(`  ~  ${want.email.padEnd(24)} ${changes}`);
  }

  // Exactly one Super Admin. Anybody else carrying the flag loses it.
  const superEmail = DIRECTORS.find((d) => d.superAdmin).email;
  const strays = await col(C.users)
    .find({ superAdmin: true, email: { $ne: superEmail } }).toArray();
  for (const user of strays) {
    plan.push({ user, set: { superAdmin: false } });
    console.log(`  ~  ${user.email.padEnd(24)} superAdmin: true → false (only one Super Admin)`);
  }

  // --- 3: spare bootstrap accounts ------------------------------------------
  const { retire, keep } = await planPlaceholderRetirement();
  console.log('');
  for (const user of retire) {
    console.log(`  -  ${user.email.padEnd(28)} ${user.role.padEnd(18)} retire (never used, seat held)`);
  }
  for (const { user, reason } of keep) {
    console.log(`     ${user.email.padEnd(28)} ${user.role.padEnd(18)} keep — ${reason}`);
  }

  if (plan.length === 0 && retire.length === 0) {
    console.log('\n  Nothing to do. The hierarchy is already V8.\n');
    await close();
    return;
  }

  if (!APPLY) {
    console.log(`\n  ${plan.length} account(s) to correct, ${retire.length} to retire.`);
    console.log('  Run again with --apply to do it.\n');
    await close();
    return;
  }

  // --- backup, then write -----------------------------------------------------
  const touched = [...plan.map((p) => p.user), ...retire];
  const ids = touched.map((u) => u._id);
  const backup = {
    at: new Date().toISOString(),
    target: where(),
    database: config.mongoDb,
    users: touched,
    // What a retired account was attached to, so it can be put back exactly.
    departmentsLedByRetired: await col(C.departments)
      .find({ leadUserId: { $in: retire.map((u) => u._id) } }).toArray(),
    accessRequests: await col(C.accessRequests).find({ userId: { $in: ids } }).toArray(),
  };
  const dir = path.join(__dirname, '..', 'backups');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `v8-hierarchy-${backup.at.replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(file, JSON.stringify(backup, null, 2));
  console.log(`\n  Backup written: ${path.relative(process.cwd(), file)}`);

  const now = new Date();
  for (const { user, set } of plan) {
    await col(C.users).updateOne({ _id: user._id }, { $set: set });
    await col(C.auditLog).insertOne({
      actorId: null,
      action: 'user.rename',
      detail: {
        targetId: String(user._id),
        from: user.name,
        to: set.name ?? user.name,
        ...(set.knownAs !== undefined ? { knownAs: set.knownAs } : {}),
        ...(set.superAdmin !== undefined ? { superAdmin: set.superAdmin } : {}),
        reason: 'V8 hierarchy',
      },
      createdAt: now,
    });
  }
  const { removed, reassigned } = await retireAccounts(retire);
  for (const user of retire) {
    await col(C.auditLog).insertOne({
      actorId: null,
      action: 'user.remove',
      detail: {
        userId: String(user._id), name: user.name, email: user.email, role: user.role,
        reason: 'Spare bootstrap account: never used, seat held by somebody real',
      },
      createdAt: now,
    });
  }

  console.log(`  Corrected ${plan.length} account(s). Retired ${removed}; `
    + `${reassigned} department seat(s) passed to the real Lead.\n`);
  await close();
})().catch(async (error) => {
  console.error(`\n  Failed: ${error.message}\n`);
  try { await close(); } catch { /* already closed */ }
  process.exit(1);
});

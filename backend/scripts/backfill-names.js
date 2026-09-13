'use strict';

/**
 * Flag accounts that still carry a seeded placeholder instead of a person's name.
 *
 * `mustSetName` was added after these accounts were created, so an existing
 * database has six Leads called "<Department> Lead" and an executive tier called
 * "Director One" / "President" with nothing marking them as provisional. New
 * databases get the flag from the seed; this brings an old one in line without
 * destroying the Lead passwords that were printed once and written down.
 *
 * Idempotent, and deliberately conservative: it only touches accounts whose name
 * is *exactly* one of the placeholders this project is known to have shipped. A
 * member who genuinely chose to be called something similar is left alone, and
 * anyone who has already set `mustSetName: false` is never re-flagged.
 *
 *   node scripts/backfill-names.js          # report only
 *   node scripts/backfill-names.js --apply  # write
 */

const { connect, col, C, close } = require('../src/db');
const { STARTING_DEPARTMENTS } = require('../src/seed');

// The names the seed has historically written. Anything not on this list is
// assumed to be a real person's name and is never touched.
const PLACEHOLDERS = new Set([
  ...STARTING_DEPARTMENTS.map((d) => `${d.name} Lead`),
  'Director One',
  'Director Two',
  'Faculty Coordinator',
  'President',
  'Vice President',
  'Secretary General',
]);

async function main() {
  const apply = process.argv.includes('--apply');
  await connect();

  const users = await col(C.users)
    .find({}, { projection: { name: 1, email: 1, role: 1, mustSetName: 1 } })
    .toArray();

  const candidates = users.filter(
    (u) => u.mustSetName !== true && u.mustSetName !== false && PLACEHOLDERS.has(u.name),
  );

  if (candidates.length === 0) {
    console.log('Nothing to do — no account is carrying a known placeholder name.');
    await close();
    return;
  }

  console.log(`${candidates.length} account(s) still named after a position:\n`);
  for (const u of candidates) {
    console.log(`  ${String(u.email).padEnd(34)} "${u.name}"`);
  }

  if (!apply) {
    console.log('\nRe-run with --apply to flag these, so the app asks for a real name.');
    await close();
    return;
  }

  const result = await col(C.users).updateMany(
    { _id: { $in: candidates.map((u) => u._id) } },
    { $set: { mustSetName: true } },
  );
  console.log(`\nFlagged ${result.modifiedCount}.`);
  console.log('Each will be asked for their real name on next sign-in, and the');
  console.log('President can name them from the approvals queue before then.');
  await close();
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

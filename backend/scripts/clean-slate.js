'use strict';

/**
 * Clear the club's accumulated working data, keeping the people and the
 * structure.
 *
 * This is not `reset.js`. That one empties everything so the next start
 * reseeds from scratch, which would also delete the club's real roster and its
 * departments. This is the other thing you usually want: the tasks, events,
 * meetings, notifications and audit trail that pile up while a system is being
 * tested, cleared out, so the club starts its term with a clean board and the
 * same people in it.
 *
 * It also retires the bootstrap accounts. A database that has had both seed
 * paths run ends up with the `@gwd.club` placeholders *and* the real
 * `@gwd.global` roster - four Club Directors against a cap of three, two
 * Presidents, and six Lead accounts nobody holds. Those placeholders are
 * deleted; anybody real is left alone.
 *
 * Every collection is written to a timestamped JSON backup first. Nothing here
 * is recoverable otherwise.
 *
 *   node scripts/clean-slate.js                 # show what would happen
 *   node scripts/clean-slate.js --yes           # do it
 *   node scripts/clean-slate.js --yes --i-know-this-is-live   # ...on a hosted cluster
 */

const fs = require('node:fs');
const path = require('node:path');
const db = require('../src/db');
const { col, C } = require('../src/db');
const config = require('../src/config');

/** Work that accumulates. Emptied. */
const TRANSACTIONAL = [
  C.tasks,
  C.taskRequests,
  C.events,
  C.eventResponsibilities,
  C.eventDocuments,
  C.eventBills,
  C.meetings,
  C.helpRequests,
  C.calendarEvents,
  C.notifications,
  C.comments,
  C.auditLog,
  C.accessRequests,
  C.broadcasts,
  C.devices,
];

/** Who and what the club *is*. Kept. */
const STRUCTURAL = [C.users, C.departments, C.scheduleCategories];

/**
 * The accounts `src/seed.js` creates so an empty database can be signed into.
 * Once the real roster exists they are duplicates, and worse than duplicates:
 * they push the club past the Director and President caps.
 */
const PLACEHOLDER_EMAILS = [
  'director1@gwd.club', 'director2@gwd.club', 'faculty@gwd.club', 'president@gwd.club',
  'lead.tech@gwd.club', 'lead.production@gwd.club', 'lead.marketing@gwd.club',
  'lead.events@gwd.club', 'lead.technical@gwd.club', 'lead.creative@gwd.club',
  'lead.cinematography@gwd.club', 'lead.pr@gwd.club',
];

const isRemote = (uri) => /^mongodb\+srv:\/\//i.test(uri)
  || !/^(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/i
    .test(uri.replace(/^mongodb:\/\//i, '').split('/')[0].split('@').pop().split(',')[0]);

(async () => {
  const confirmed = process.argv.includes('--yes');
  const remote = isRemote(config.mongoUri);

  await db.connect();
  const database = db.database();

  console.log('');
  console.log(`  Database: ${config.mongoDb}  (${remote ? 'HOSTED CLUSTER' : 'local'})`);
  console.log('');

  // --- what is here -------------------------------------------------------
  const counts = {};
  for (const name of [...TRANSACTIONAL, ...STRUCTURAL]) {
    counts[name] = await database.collection(name).countDocuments();
  }
  const placeholders = await col(C.users)
    .find({ email: { $in: PLACEHOLDER_EMAILS } }, { projection: { email: 1, role: 1 } })
    .toArray();

  console.log('  Would EMPTY:');
  for (const name of TRANSACTIONAL) {
    if (counts[name]) console.log(`    ${name.padEnd(24)} ${counts[name]}`);
  }
  console.log('');
  console.log('  Would KEEP:');
  for (const name of STRUCTURAL) {
    console.log(`    ${name.padEnd(24)} ${counts[name]}`);
  }
  console.log('');
  if (placeholders.length) {
    console.log(`  Would REMOVE ${placeholders.length} bootstrap account(s):`);
    for (const p of placeholders) console.log(`    ${p.email}  [${p.role}]`);
    console.log('');
  }

  if (!confirmed) {
    console.log('  Nothing changed. Re-run with --yes to go ahead.');
    console.log('');
    await db.close();
    return;
  }

  if (remote && !process.argv.includes('--i-know-this-is-live')) {
    console.log('  REFUSING: that is a hosted cluster, not a local database.');
    console.log('  If you genuinely mean it:');
    console.log('    node scripts/clean-slate.js --yes --i-know-this-is-live');
    console.log('');
    await db.close();
    process.exit(1);
  }

  // --- back everything up, first -----------------------------------------
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const dir = path.join(__dirname, '..', 'backups', `${config.mongoDb}-${stamp}`);
  fs.mkdirSync(dir, { recursive: true });

  let saved = 0;
  for (const { name } of await database.listCollections().toArray()) {
    if (name.startsWith('system.')) continue;
    const docs = await database.collection(name).find({}).toArray();
    fs.writeFileSync(path.join(dir, `${name}.json`), JSON.stringify(docs, null, 2), 'utf8');
    saved += docs.length;
  }
  console.log(`  Backed up ${saved} document(s) to`);
  console.log(`    ${dir}`);
  console.log('');

  // --- clear ---------------------------------------------------------------
  let cleared = 0;
  for (const name of TRANSACTIONAL) {
    const { deletedCount } = await database.collection(name).deleteMany({});
    cleared += deletedCount;
  }

  const { deletedCount: removedPeople } = await col(C.users)
    .deleteMany({ email: { $in: PLACEHOLDER_EMAILS } });

  // A department must never be left pointing at somebody who is gone.
  const remaining = new Set(
    (await col(C.users).find({}, { projection: { _id: 1 } }).toArray()).map((u) => String(u._id)),
  );
  const orphaned = await col(C.departments)
    .find({ leadUserId: { $ne: null } }, { projection: { leadUserId: 1, name: 1 } })
    .toArray();
  let vacated = 0;
  for (const d of orphaned) {
    if (remaining.has(String(d.leadUserId))) continue;
    await col(C.departments).updateOne({ _id: d._id }, { $set: { leadUserId: null } });
    vacated += 1;
  }

  // Uploaded files belonged to the documents and receipts just deleted.
  let files = 0;
  if (fs.existsSync(config.uploadDir)) {
    for (const entry of fs.readdirSync(config.uploadDir)) {
      const target = path.join(config.uploadDir, entry);
      if (fs.statSync(target).isFile()) {
        fs.unlinkSync(target);
        files += 1;
      }
    }
  }

  const people = await col(C.users).countDocuments();
  const departments = await col(C.departments).countDocuments();

  console.log(`  Cleared ${cleared} working record(s) and ${files} uploaded file(s).`);
  console.log(`  Removed ${removedPeople} bootstrap account(s).`);
  if (vacated) console.log(`  Vacated ${vacated} department seat(s) whose Lead is gone.`);
  console.log('');
  console.log(`  The club still has ${people} people and ${departments} departments.`);
  console.log('');

  await db.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});

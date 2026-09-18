'use strict';

/**
 * Create N approved members for the load test, straight into the database.
 *
 * Deliberately not through the signup route: that is rate limited on purpose,
 * and the point of the load test is to measure the app's normal traffic, not
 * to punch a hole in a protection that exists for good reason.
 *
 *   node scripts/seed-load-users.js --users 100
 */

const db = require('../src/db');
const { col, C } = require('../src/db');
const { hashPassword } = require('../src/auth');
const { ROLES } = require('../src/permissions');

const arg = (n, d) => {
  const i = process.argv.indexOf(`--${n}`);
  return i === -1 ? d : process.argv[i + 1];
};

(async () => {
  const count = Number(arg('users', '100'));
  const password = arg('password', 'LoadPass2026');
  await db.connect();

  const uri = process.env.MONGODB_URI ?? '';
  if (/mongodb\+srv/i.test(uri)) {
    console.error('\n  REFUSING: that is a hosted cluster, not a local test database.\n');
    process.exit(1);
  }

  const departments = await col(C.departments).find({}).toArray();
  if (departments.length === 0) {
    console.error('  No departments yet - start the API once so it seeds them.');
    process.exit(1);
  }

  const hash = await hashPassword(password);
  const now = new Date();
  const docs = [];
  for (let i = 0; i < count; i += 1) {
    const email = `load${i}@gwd.club`;
    if (await col(C.users).findOne({ email })) continue;
    docs.push({
      name: `Load Tester ${i}`,
      email,
      phone: '',
      role: ROLES.clubMember,
      departmentId: departments[i % departments.length]._id,
      points: 0,
      approvalStatus: 'approved',
      passwordHash: hash,
      mustSetName: false,
      avatarColor: '#334155',
      createdAt: now,
      lastLoginAt: null,
    });
  }
  if (docs.length) await col(C.users).insertMany(docs);
  console.log(`  ${docs.length} created, ${count - docs.length} already there.`);
  await db.close();
})();

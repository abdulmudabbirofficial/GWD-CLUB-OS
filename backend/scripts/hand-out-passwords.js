'use strict';

/**
 * Give every account a fresh temporary password, and print the sheet once.
 *
 * For the moment a club is handed the app: nobody knows their password yet,
 * or the database has just been cleared and the old ones are gone. Each person
 * gets a readable one-time password, flagged `mustChangePassword`, so it
 * survives exactly one sign-in and then they choose their own.
 *
 * Printed once and never recoverable - the hashes are one-way. Copy the table
 * before closing the window.
 *
 *   node scripts/hand-out-passwords.js                    # show who would get one
 *   node scripts/hand-out-passwords.js --yes
 *   node scripts/hand-out-passwords.js --yes --only president@gwd.global
 */

const crypto = require('node:crypto');
const db = require('../src/db');
const { col, C } = require('../src/db');
const { hashPassword } = require('../src/auth');
const config = require('../src/config');

/**
 * Readable on purpose. These get read aloud and typed into a chat, so the
 * characters people confuse (O/0, l/1/I) are left out entirely.
 */
function temporaryPassword() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return 'gwd-' + Array.from(crypto.randomBytes(8), (b) => alphabet[b % alphabet.length]).join('');
}

const arg = (name) => {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? null : process.argv[i + 1];
};

/** Club order, so the printed sheet reads like the org chart. */
const ORDER = [
  'clubDirector', 'facultyCoordinator', 'president', 'vicePresident',
  'secretaryGeneral', 'clubLead', 'clubMember',
];

(async () => {
  const confirmed = process.argv.includes('--yes');
  const only = arg('only');

  await db.connect();

  const filter = only ? { email: only.toLowerCase() } : {};
  const people = await col(C.users).find(filter).toArray();
  people.sort((a, b) => {
    const byRole = ORDER.indexOf(a.role) - ORDER.indexOf(b.role);
    return byRole !== 0 ? byRole : (a.name || '').localeCompare(b.name || '');
  });

  if (people.length === 0) {
    console.log('\n  Nobody matched.\n');
    await db.close();
    process.exit(1);
  }

  console.log('');
  console.log(`  Database: ${config.mongoDb}`);
  console.log(`  ${people.length} account(s) would get a new temporary password:`);
  for (const p of people) console.log(`    ${p.email}  [${p.role}]`);
  console.log('');

  if (!confirmed) {
    console.log('  Nothing changed. Re-run with --yes to issue them.');
    console.log('');
    await db.close();
    return;
  }

  const issued = [];
  for (const person of people) {
    const password = temporaryPassword();
    await col(C.users).updateOne(
      { _id: person._id },
      {
        $set: {
          passwordHash: await hashPassword(password),
          mustChangePassword: true,
          // Kills every token already issued to this account, so an old
          // session on a phone somewhere cannot carry on.
          passwordChangedAt: new Date(),
        },
        $unset: { passwordResetRequestedAt: '' },
      },
    );
    issued.push({ ...person, password });
  }

  const line = '  ' + '='.repeat(92);
  console.log(line);
  console.log('  HAND THESE OUT. Shown once - the passwords are hashed and not recoverable.');
  console.log('  Everyone is asked to choose their own the first time they sign in.');
  console.log(line);
  console.log('');
  console.log(
    '  ' + 'NAME'.padEnd(30) + 'EMAIL'.padEnd(30) + 'ROLE'.padEnd(20) + 'PASSWORD',
  );
  console.log('  ' + '-'.repeat(92));
  for (const p of issued) {
    console.log(
      '  '
      + String(p.name || '').padEnd(30)
      + String(p.email).padEnd(30)
      + String(p.role).padEnd(20)
      + p.password,
    );
  }
  console.log('');

  await db.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});

'use strict';

const crypto = require('node:crypto');
const config = require('./config');
const { col, C } = require('./db');
const { hashPassword } = require('./auth');
const { ROLES, ROLE_CAPS } = require('./permissions');

/**
 * Roots of trust (Section 4.5).
 *
 * The 2 Club Directors and the President are verified once, out of band, and
 * pre-seeded here. They never sit in an approval queue — without them there
 * would be nobody able to approve the first Lead, and the club could never
 * bootstrap itself.
 *
 * Format in .env:  SEED_DIRECTORS="Name:email@x.com:password,Name2:e2@x.com:pw2"
 */
function parsePeople(raw) {
  return String(raw || '')
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const parts = entry.split(':');
      if (parts.length < 3) return null;
      const [name, email, ...rest] = parts;
      return { name: name.trim(), email: email.trim().toLowerCase(), password: rest.join(':').trim() };
    })
    .filter((p) => p && p.name && p.email && p.password);
}

const { accentFor: avatarColorFor } = require('./palette');

async function upsertPerson({ name, email, password }, role) {
  const existing = await col(C.users).findOne({ email });

  // A seat that is already filled is not seeded again.
  //
  // Two seed paths write people: this one, which creates the bootstrap
  // accounts from .env so a brand-new database can be signed into at all, and
  // `scripts/seed-club.js`, which puts the club's real roster in. Neither
  // checked the caps, so running both - which is exactly what happens when the
  // server starts after the roster is seeded - left the club with **five**
  // Club Directors against a cap of three, and two Presidents. The cap is
  // enforced at signup and at role changes, so seeding was the one way in.
  //
  // Skipping only applies to *new* accounts: an existing bootstrap account is
  // still corrected below, so nothing that is already in use is disturbed.
  if (!existing) {
    const cap = ROLE_CAPS[role];
    if (cap) {
      const held = await col(C.users).countDocuments({ role, approvalStatus: 'approved' });
      if (held >= cap) return { email, action: 'skipped (seat already filled)' };
    }
  }

  if (existing) {
    // Never silently overwrite a live account's password on restart — and
    // never its role or standing either.
    //
    // This used to put any bootstrap account back to `approved` in its seeded
    // role on every start. That turned every restart into an undo: a Director
    // the Super Admin had demoted, or a placeholder somebody had retired, came
    // back the next time the laptop woke up — and on a hosted server that
    // spins down when idle, that is every few minutes. An account that differs
    // from its seed was changed by a person on purpose, and the seed defers.
    return {
      email,
      action: existing.role === role && existing.approvalStatus === 'approved'
        ? 'unchanged'
        : 'left alone (changed since it was seeded)',
    };
  }
  await col(C.users).insertOne({
    name,
    // Seeded names come out of a config file, which means nobody has confirmed
    // this is what they are actually called — and the shipped defaults are job
    // titles ("Director One", "President"). Asking once, on first sign-in,
    // costs a tap and clears forever. Only set on insert, so somebody who has
    // already given their real name is never asked again on restart.
    mustSetName: true,
    email,
    phone: '',
    role,
    departmentId: null,
    points: 0,
    approvalStatus: 'approved',
    passwordHash: await hashPassword(password),
    // The password came out of a config file, so it is a *handover* credential,
    // not a private one: .env gets copied to a laptop, pasted into a hosting
    // dashboard, and read aloud when the account changes hands. Treating it as
    // permanent left the club's most privileged accounts — three Directors, the
    // Faculty Coordinator and the President — standing on a secret that several
    // people have seen, indefinitely. The department Leads were already handled
    // this way; these were not.
    //
    // Only on insert, like `mustSetName`: somebody who has already chosen their
    // own password must not be asked again every time the server restarts.
    mustChangePassword: true,
    avatarColor: avatarColorFor(email),
    createdAt: new Date(),
    lastLoginAt: null,
  });
  return { email, action: 'created' };
}

/**
 * The two departments a fresh database starts with.
 *
 * Still managed data, not a fixture — the President, VP and Directors add,
 * rename and retire departments at runtime, which is exactly what v1's
 * hardcoded Dart enum made impossible. This is only the starting point, and a
 * database that already has departments is left alone.
 */
const STARTING_DEPARTMENTS = [
  {
    name: 'Tech',
    description: 'Sound, lighting, projection, streaming and registration systems.',
    leadEmail: 'lead.tech@gwd.club',
  },
  {
    name: 'Production',
    description: 'Stage, rigging, LED walls, equipment and on-the-day production.',
    leadEmail: 'lead.production@gwd.club',
  },
];

/**
 * Readable on purpose — a temporary password gets read aloud or typed into a
 * chat, so the characters people confuse (O/0, l/1/I) are left out entirely.
 */
function temporaryPassword() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return 'gwd-' + Array.from(
    crypto.randomBytes(8),
    (b) => alphabet[b % alphabet.length],
  ).join('');
}

/**
 * A Lead account per department, parked as **pending**.
 *
 * The club asked for these to exist up front so the credentials can be handed
 * out — but arriving in the approval queue rather than live, because a login
 * that works before anyone has said yes is not an approval chain. A Director or
 * the President lets each one in.
 *
 * Each is flagged `mustChangePassword`, so the seeded password survives exactly
 * one sign-in. The passwords are returned to the caller and printed once at
 * startup; they are never recoverable afterwards.
 */
async function seedDepartmentLeads(departments) {
  const created = [];

  for (const department of departments) {
    const spec = STARTING_DEPARTMENTS.find((d) => d.name === department.name);
    if (!spec?.leadEmail) continue;
    if (await col(C.users).findOne({ email: spec.leadEmail })) continue;

    const password = temporaryPassword();
    const now = new Date();
    const user = {
      // A placeholder, flagged as one. These accounts are created *before*
      // anybody holds them, so there is no name to put here yet — and naming
      // the account after the job ("Creative Lead") is how a club ends up with
      // six people called after their position and none called anything.
      //
      // `mustSetName` is what makes it provisional: the President can put the
      // real name on when handing the credentials over, and the holder is asked
      // to confirm it the first time they sign in. Either clears the flag.
      name: `${department.name} Lead`,
      mustSetName: true,
      email: spec.leadEmail,
      phone: '',
      role: ROLES.clubLead,
      departmentId: department._id,
      points: 0,
      approvalStatus: 'pending',
      passwordHash: await hashPassword(password),
      mustChangePassword: true,
      avatarColor: avatarColorFor(spec.leadEmail),
      createdAt: now,
      lastLoginAt: null,
    };
    const inserted = await col(C.users).insertOne(user);

    // The same queue a real signup lands in, so approving one is the ordinary
    // flow rather than a special case.
    await col(C.accessRequests).insertOne({
      userId: inserted.insertedId,
      departmentId: department._id,
      requestedRole: ROLES.clubLead,
      approverId: null,
      status: 'pending',
      createdAt: now,
    });

    created.push({ department: department.name, email: spec.leadEmail, password });
  }

  return created;
}

async function seedDepartments() {
  const existing = await col(C.departments).countDocuments({});
  if (existing > 0) return { action: 'skipped', count: existing };
  await col(C.departments).insertMany(
    STARTING_DEPARTMENTS.map(({ leadEmail, ...d }) => ({
      ...d,
      leadUserId: null,
      active: true,
      colorSeed: null,
      createdBy: null,
      createdAt: new Date(),
    })),
  );
  return { action: 'created', count: STARTING_DEPARTMENTS.length };
}

async function run() {
  const report = {
    directors: [], faculty: [], president: [], departments: null, leads: [],
  };

  const directors = parsePeople(config.seedDirectors).slice(0, 2);
  for (const person of directors) {
    report.directors.push(await upsertPerson(person, ROLES.clubDirector));
  }

  // The Faculty Coordinator is the college's representative over the club.
  // Like the Directors she is verified out of band and never queued — there is
  // nobody inside the club with the standing to approve her.
  const faculty = parsePeople(config.seedFaculty).slice(0, 1);
  for (const person of faculty) {
    report.faculty.push(await upsertPerson(person, ROLES.facultyCoordinator));
  }

  const president = parsePeople(config.seedPresident).slice(0, 1);
  for (const person of president) {
    report.president.push(await upsertPerson(person, ROLES.president));
  }

  report.departments = await seedDepartments();

  const departments = await col(C.departments).find({}).toArray();
  report.leads = await seedDepartmentLeads(departments);

  return report;
}

module.exports = {
  run, STARTING_DEPARTMENTS, parsePeople, temporaryPassword,
};

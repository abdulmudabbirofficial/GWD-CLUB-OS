'use strict';

/**
 * Seed the real GWD Global roster, plus some work to look at.
 *
 * Separate from `src/seed.js`, which only creates the roots of trust and the
 * starting departments a fresh database needs to function. This one puts actual
 * people in, with their actual names and posts.
 *
 * Idempotent and additive. Everybody is matched on email:
 *   - an account that does not exist is created with a fresh password
 *   - an account that does exist has its name, role and department corrected,
 *     and its password left alone
 *
 * so re-running it after somebody has chosen their own password does not lock
 * them out. It never deletes anything.
 *
 *   node scripts/seed-club.js            # people only
 *   node scripts/seed-club.js --demo     # people plus sample events and tasks
 *   node scripts/seed-club.js --reset-passwords
 *   node scripts/seed-club.js --keep-placeholders   # leave the bootstrap logins
 *
 * Passwords are printed ONCE. They are hashed, so there is no second chance.
 */

const crypto = require('node:crypto');
const db = require('../src/db');
const { col, C } = require('../src/db');
const { hashPassword } = require('../src/auth');
const { ROLES } = require('../src/permissions');

const DEMO = process.argv.includes('--demo');
const RESET_PASSWORDS = process.argv.includes('--reset-passwords');
// Retiring the bootstrap accounts is the default, not an extra.
//
// Two seed paths create people: `src/seed.js` makes the `@gwd.club` bootstrap
// accounts from .env every time the server starts, so a brand-new database can
// be signed into at all, and this script puts the club's real `@gwd.global`
// roster in. Leaving both is not a tidiness problem, it is a *correctness*
// one: the club ends up with five Club Directors against a cap of three, and
// two Presidents. The caps are enforced at signup and at role changes, so
// seeding was the one way past them.
//
// `--keep-placeholders` opts out, for the rare case of wanting the bootstrap
// logins alive alongside the roster while setting a machine up.
const REPLACE_PLACEHOLDERS = !process.argv.includes('--keep-placeholders');

/**
 * The bootstrap accounts `src/seed.js` creates are retired here once the real
 * roster exists — but only the ones that are provably spare. The rule, and why
 * it is careful, lives in `src/placeholders.js`: the first version of this
 * deleted everything on its list, which includes the only Faculty Coordinator
 * a live club may have. `--keep-placeholders` skips the step entirely.
 */
const { planPlaceholderRetirement, retireAccounts } = require('../src/placeholders');

/**
 * Readable on purpose. These get read aloud and typed into a chat, so the
 * characters people confuse (O/0, l/1/I) are left out entirely.
 */
const WORDS = [
  'Amber', 'Anchor', 'Arrow', 'Aspen', 'Aurora', 'Banyan', 'Beacon', 'Birch',
  'Blaze', 'Breeze', 'Brook', 'Canyon', 'Cedar', 'Cobalt', 'Comet', 'Coral',
  'Crimson', 'Crystal', 'Delta', 'Ember', 'Falcon', 'Fern', 'Forest', 'Galaxy',
  'Garnet', 'Glacier', 'Harbor', 'Hawk', 'Horizon', 'Indigo', 'Island', 'Jasmine',
  'Jungle', 'Lagoon', 'Lotus', 'Maple', 'Meadow', 'Meteor', 'Monsoon', 'Nebula',
  'Oasis', 'Orbit', 'Orchid', 'Pebble', 'Phoenix', 'Pine', 'Planet', 'Prism',
  'Quartz', 'Rain', 'Raven', 'River', 'Saffron', 'Sierra', 'Summit', 'Sunrise',
  'Thunder', 'Tiger', 'Topaz', 'Valley', 'Violet', 'Willow', 'Winter', 'Zephyr',
];

/**
 * Two words and four digits - "Maple-Falcon-4821". Readable aloud and easy to
 * type on a phone, which is how a first password actually gets handed over,
 * and generated fresh every run: never written into the code, which is on
 * GitHub. It survives exactly one sign-in (`mustChangePassword`).
 */
function temporaryPassword() {
  const word = () => WORDS[crypto.randomInt(WORDS.length)];
  return `${word()}-${word()}-${crypto.randomInt(1000, 10000)}`;
}

// The one palette (src/palette.js). This script used to carry its own list —
// with a violet, a blue, a green and a near-black in it — so everybody seeded
// from the roster wore a colour from outside the app's own family.
const { accentFor: avatarColorFor } = require('../src/palette');

/**
 * The roster, as given by the club.
 *
 * `post` is the club's own wording, kept for the printout so the handover sheet
 * reads the way the club talks. The app derives what it shows from `role` plus
 * the department — "Dikshit / Tech Lead".
 */
const ROSTER = [
  // --- oversight -------------------------------------------------------
  // Three Director seats, which is the cap in ROLE_CAPS. `knownAs` is how the
  // club addresses each one — "Director Mudabbir" — and cannot be derived from
  // the full name. Exactly one seat is the Super Admin (see permissions.js).
  {
    post: 'Club Director', name: 'Abdul Mudabbir', knownAs: 'Mudabbir',
    superAdmin: true, email: 'clubdirector@gwd.global', role: ROLES.clubDirector,
  },
  {
    post: 'Director', name: 'Rehman Pasha', knownAs: 'Rehman',
    email: 'director1@gwd.global', role: ROLES.clubDirector,
  },
  {
    post: 'Director', name: 'Mohammed Moin', knownAs: 'Moin',
    email: 'director2@gwd.global', role: ROLES.clubDirector,
  },

  // --- the college's representative -------------------------------------
  // Her name is hers to give, so the account says so and she is asked on
  // first sign-in rather than seeded as a job title.
  {
    post: 'Faculty Coordinator', name: 'Faculty Coordinator', mustSetName: true,
    email: 'facultycoordinator@gwd.global', role: ROLES.facultyCoordinator,
  },

  // --- the executive tier ----------------------------------------------
  { post: 'President', name: 'Aldrin Paul', email: 'president@gwd.global', role: ROLES.president },
  { post: 'Vice President', name: 'Mohd Ismail', email: 'vicepresident@gwd.global', role: ROLES.vicePresident },
  { post: 'General Secretary', name: 'Sravya', email: 'generalsecretary@gwd.global', role: ROLES.secretaryGeneral },

  // --- department Leads -------------------------------------------------
  // Two departments to start with; the rest are created in the app by the
  // President, VP or a Director rather than being seeded.
  { post: 'Production Lead', name: 'Rehman', email: 'production@gwd.global', role: ROLES.clubLead, department: 'Production' },
  { post: 'Tech Lead', name: 'Dikshit', email: 'tech@gwd.global', role: ROLES.clubLead, department: 'Tech' },
];

async function departmentsByName() {
  const all = await col(C.departments).find({}).toArray();
  return new Map(all.map((d) => [d.name, d]));
}

async function seedPeople() {
  const departments = await departmentsByName();
  const created = [];
  const updated = [];
  const missingDepartments = new Set();

  for (const person of ROSTER) {
    let departmentId = null;
    if (person.department) {
      const department = departments.get(person.department);
      if (!department) { missingDepartments.add(person.department); continue; }
      departmentId = department._id;
    }

    const existing = await col(C.users).findOne({ email: person.email });

    if (existing) {
      // Correct who they are and where they sit; never touch their password.
      // A seat seeded without a real name keeps whatever name its holder has
      // since given; the placeholder never overwrites it.
      const naming = person.mustSetName ? {} : { name: person.name, mustSetName: false };
      await col(C.users).updateOne({ _id: existing._id }, {
        $set: {
          ...naming,
          role: person.role,
          departmentId,
          approvalStatus: 'approved',
          knownAs: person.knownAs ?? null,
          superAdmin: person.superAdmin === true,
        },
      });
      updated.push({ ...person, id: existing._id });
      continue;
    }

    const password = temporaryPassword();
    const now = new Date();
    const inserted = await col(C.users).insertOne({
      name: person.name,
      email: person.email,
      phone: '',
      role: person.role,
      departmentId,
      points: 0,
      approvalStatus: 'approved',
      passwordHash: await hashPassword(password),
      // A real name, given by the club - except where the club gave none.
      mustSetName: person.mustSetName === true,
      knownAs: person.knownAs ?? null,
      // Set here and by scripts/v8-hierarchy.js, and by no route: the API has
      // no way to mint a Super Admin.
      superAdmin: person.superAdmin === true,
      // They were handed this password, so it is not private until they change
      // it. The app asks on first sign-in.
      mustChangePassword: true,
      avatarColor: avatarColorFor(person.email),
      createdAt: now,
      lastLoginAt: null,
    });
    created.push({ ...person, id: inserted.insertedId, password });
  }

  // Leads take their department's seat, or a department task has nobody to
  // land on and escalates to the President instead.
  for (const person of [...created, ...updated]) {
    if (person.role !== ROLES.clubLead || !person.department) continue;
    const department = departments.get(person.department);
    if (!department) continue;
    await col(C.departments).updateOne(
      { _id: department._id }, { $set: { leadUserId: person.id } },
    );
  }

  return { created, updated, missingDepartments: [...missingDepartments] };
}

async function resetPasswords() {
  const reset = [];
  for (const person of ROSTER) {
    const user = await col(C.users).findOne({ email: person.email });
    if (!user) continue;
    const password = temporaryPassword();
    await col(C.users).updateOne({ _id: user._id }, {
      $set: {
        passwordHash: await hashPassword(password),
        mustChangePassword: true,
        // Kills every token already issued to this account.
        passwordChangedAt: new Date(),
      },
    });
    reset.push({ ...person, password });
  }
  return reset;
}

/**
 * Retire the bootstrap accounts now that real people hold every post.
 *
 * Only touches the exact emails `src/seed.js` writes, and only after the real
 * roster is in — so a department is never left without a Lead partway through.
 * Anything those accounts were still holding (a department seat, work assigned
 * to them) is handed over rather than orphaned.
 */
async function replacePlaceholders() {
  const { retire, keep } = await planPlaceholderRetirement();
  const { removed, reassigned } = await retireAccounts(retire);
  return {
    removed,
    reassigned,
    emails: retire.map((u) => u.email),
    kept: keep.map(({ user, reason }) => `${user.email} (${reason})`),
  };
}

/* ------------------------------------------------------------------ demo */

const daysOut = (n) => {
  const d = new Date();
  d.setDate(d.getDate() + n);
  d.setHours(17, 0, 0, 0);
  return d;
};

/**
 * Enough work and events that every screen has something in it — the board,
 * the recognition charts, the schedule, the reminder sweep.
 *
 * Tagged `demoSeed: true` so it can be told apart from real club work later.
 */
async function seedDemo() {
  const departments = await departmentsByName();
  const people = await col(C.users).find({}).toArray();
  const byEmail = new Map(people.map((u) => [u.email, u]));

  const president = byEmail.get('president@gwd.global');
  const vp = byEmail.get('vicepresident@gwd.global');
  const gensec = byEmail.get('generalsecretary@gwd.global');
  if (!president) throw new Error('President missing — run without --demo first.');

  const lead = (name) => {
    const d = departments.get(name);
    return d?.leadUserId ? people.find((u) => String(u._id) === String(d.leadUserId)) : null;
  };
  const member = byEmail.get('member@gwd.global');

  // --- events -----------------------------------------------------------
  const eventSpecs = [
    {
      name: 'Campus to Corporate Summit',
      description: 'Flagship summit: CXO panel, recruiter booths and a closing keynote.',
      type: 'summit',
      date: daysOut(21),
      startTime: '09:30', endTime: '17:30',
      venue: 'Main Auditorium',
      status: 'planning',
      organizing: 'Production',
      supporting: ['Tech'],
      speakerName: 'Industry CXO panel',
    },
    {
      name: 'Design Sprint Workshop',
      description: 'Two-day hands-on workshop on product thinking and rapid prototyping.',
      type: 'workshop',
      date: daysOut(9),
      startTime: '10:00', endTime: '16:00',
      venue: 'Seminar Hall 2',
      status: 'planning',
      organizing: 'Tech',
      supporting: ['Production'],
    },
  ];

  const events = [];
  for (const spec of eventSpecs) {
    const organizing = departments.get(spec.organizing);
    if (!organizing) continue;
    if (await col(C.events).findOne({ name: spec.name })) continue;

    const now = new Date();
    const organisingLead = lead(spec.organizing);
    const doc = {
      name: spec.name,
      description: spec.description,
      type: spec.type,
      date: spec.date,
      startTime: spec.startTime,
      endTime: spec.endTime,
      venue: spec.venue,
      status: spec.status,
      organizingDepartmentId: organizing._id,
      leadUserId: organisingLead?._id ?? president._id,
      supportingDepartmentIds: spec.supporting
        .map((n) => departments.get(n)?._id).filter(Boolean),
      teamUserIds: [president._id, vp?._id, gensec?._id].filter(Boolean),
      speakerName: spec.speakerName ?? '',
      guestDetails: '',
      externalOrganisation: '',
      createdBy: president._id,
      createdAt: now,
      updatedAt: now,
      demoSeed: true,
    };
    const inserted = await col(C.events).insertOne(doc);
    doc._id = inserted.insertedId;
    await col(C.events).updateOne({ _id: doc._id },
      { $set: { banner: `#${(Math.abs(doc.name.length * 2654435761) % 0xFFFFFF).toString(16).padStart(6, '0')}` } });

    for (const name of [spec.organizing, ...spec.supporting]) {
      const d = departments.get(name);
      if (!d) continue;
      await col(C.eventResponsibilities).updateOne(
        { eventId: doc._id, departmentId: d._id },
        { $setOnInsert: { eventId: doc._id, departmentId: d._id, notes: '', createdBy: president._id, createdAt: now } },
        { upsert: true },
      );
    }
    events.push(doc);
  }

  // --- work -------------------------------------------------------------
  // A spread of statuses and point values on purpose: the recognition charts
  // and the "still open" reminder only say anything with a mix.
  const taskSpecs = [
    ['Tech', 'Livestream and sound test', 'Full dry run a day before.', 'completed', 5, -4],
    ['Tech', 'Registration desk systems', 'Two laptops, scanner, offline fallback.', 'inProgress', 3, 5],
    // Deliberately past its due date and still open, so the daily reminder
    // sweep and the overdue styling both have something real to show.
    ['Tech', 'Projection and lighting cues', 'Cue sheet agreed with the stage team.', 'inProgress', 3, -1],
    ['Tech', 'Wi-Fi and power plan', 'Load check for the whole auditorium.', 'pending', 1, 12],
    ['Production', 'LED wall and stage rig', 'Vendor quote, load-in plan, power check.', 'completed', 5, -6],
    ['Production', 'Stage layout and backdrop', 'Dimensions, standee positions, safe walkways.', 'inProgress', 5, 4],
    ['Production', 'Equipment checklist', 'Everything in, everything back.', 'pending', 3, 9],
  ];

  let taskCount = 0;
  for (const [deptName, title, description, status, points, dueIn] of taskSpecs) {
    const d = departments.get(deptName);
    if (!d) continue;
    if (await col(C.tasks).findOne({ title })) continue;

    const deptLead = lead(deptName);
    // Everything lands on the department Lead: the starting roster has no
    // general members yet, and they join through the app rather than a seed.
    const assignee = deptLead;

    const now = new Date();
    await col(C.tasks).insertOne({
      title,
      description,
      assignedBy: president._id,
      assignedTo: assignee?._id ?? null,
      departmentId: d._id,
      eventId: events[0]?._id ?? null,
      status,
      dueDate: daysOut(dueIn),
      points,
      priority: points === 5 ? 'high' : 'normal',
      createdAt: now,
      updatedAt: now,
      completedAt: status === 'completed' ? now : null,
      demoSeed: true,
    });
    taskCount += 1;
  }

  // One department task nobody has handed out yet, so a Lead's triage pile and
  // the "waiting to be handed out" badge are not empty.
  if (!(await col(C.tasks).findOne({ title: 'Recruiter booth layout' }))) {
    const d = departments.get('Production');
    if (d) {
      const now = new Date();
      await col(C.tasks).insertOne({
        title: 'Recruiter booth layout',
        description: 'Floor plan for twelve booths plus queuing space.',
        assignedBy: president._id,
        assignedTo: null,
        departmentId: d._id,
        eventId: events[0]?._id ?? null,
        status: 'pending',
        dueDate: daysOut(11),
        points: 3,
        priority: 'normal',
        createdAt: now,
        updatedAt: now,
        completedAt: null,
        demoSeed: true,
      });
      taskCount += 1;
    }
  }

  // Points follow completed work, or the recognition boards read as empty.
  const completed = await col(C.tasks)
    .find({ status: 'completed', assignedTo: { $ne: null } }).toArray();
  for (const task of completed) {
    await col(C.users).updateOne({ _id: task.assignedTo }, { $inc: { points: task.points ?? 1 } });
    const d = await col(C.departments).findOne({ _id: task.departmentId });
    if (d?.leadUserId && String(d.leadUserId) !== String(task.assignedTo)) {
      await col(C.users).updateOne({ _id: d.leadUserId }, { $inc: { points: task.points ?? 1 } });
    }
  }

  return { events: events.length, tasks: taskCount };
}

/* ----------------------------------------------------------------- main */

async function main() {
  await db.connect();
  const uri = process.env.MONGODB_URI ?? '';
  const where = uri.includes('mongodb+srv') ? 'MongoDB Atlas (shared with the live site)' : 'local MongoDB';
  console.log(`\n  Target: ${where}`);
  console.log(`  Database: ${process.env.MONGODB_DB ?? 'gwd_club_os'}\n`);

  if (RESET_PASSWORDS) {
    const reset = await resetPasswords();
    console.log(`  Reset ${reset.length} password(s).\n`);
    printCredentials(reset);
    await db.close();
    return;
  }

  const { created, updated, missingDepartments } = await seedPeople();

  console.log(`  Created ${created.length} account(s), corrected ${updated.length}.`);
  if (missingDepartments.length) {
    console.log(`  SKIPPED - no such department: ${missingDepartments.join(', ')}`);
  }

  // After the roster, so no department is ever briefly without a Lead.
  if (REPLACE_PLACEHOLDERS) {
    const gone = await replacePlaceholders();
    if (gone.removed) {
      console.log(`  Retired ${gone.removed} bootstrap account(s); `
        + `${gone.reassigned} department seat(s) handed to the real Lead.`);
      for (const e of gone.emails) console.log(`    removed  ${e}`);
    } else {
      console.log('  No bootstrap accounts left to retire.');
    }
    for (const k of gone.kept ?? []) console.log(`    kept     ${k}`);
  }

  if (DEMO) {
    const demo = await seedDemo();
    console.log(`  Added ${demo.events} event(s) and ${demo.tasks} task(s).`);
  }

  console.log('');
  if (created.length) printCredentials(created);
  else console.log('  No new accounts, so no passwords to print.\n');

  if (updated.length) {
    console.log('  Already existed (name/role/department corrected, password untouched):');
    for (const p of updated) console.log(`    ${p.email.padEnd(34)} ${p.name}`);
    console.log('');
  }

  await db.close();
}

function printCredentials(list) {
  console.log('  ' + '='.repeat(76));
  console.log('  HAND THESE OUT. Shown once - the passwords are hashed and not recoverable.');
  console.log('  Everyone is asked to choose their own on first sign-in.');
  console.log('  ' + '='.repeat(76));
  console.log('');
  console.log('  ' + 'POST'.padEnd(26) + 'NAME'.padEnd(32) + 'EMAIL'.padEnd(34) + 'PASSWORD');
  console.log('  ' + '-'.repeat(96));
  for (const p of list) {
    console.log('  ' + String(p.post).padEnd(26) + String(p.name).padEnd(32)
      + String(p.email).padEnd(33) + ' ' + p.password);
  }
  console.log('');
}

main().catch((error) => {
  console.error('\nSeeding failed:', error);
  process.exit(1);
});

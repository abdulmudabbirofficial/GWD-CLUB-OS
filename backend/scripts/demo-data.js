'use strict';

/**
 * Optional demo data.
 *
 * Deliberately a separate script rather than part of seeding: a real club's
 * database should not silently fill with invented people. Run it only when you
 * want something to look at.
 *
 *   node scripts/demo-data.js          add demo members, tasks and events
 *   node scripts/demo-data.js --clear  remove everything it created
 *
 * Everything it writes is tagged `demo: true`, so --clear can take it all back
 * out without touching real records.
 */

const BASE = process.env.SMOKE_BASE || 'http://127.0.0.1:4000';
const PASSWORD = 'DemoPass123';

const PEOPLE = [
  { name: 'Aisha Khan', email: 'aisha@demo.gwd.club', dept: 'Creative' },
  { name: 'Rohan Mehta', email: 'rohan@demo.gwd.club', dept: 'Creative' },
  { name: 'Sana Iqbal', email: 'sana@demo.gwd.club', dept: 'Social Media & Marketing' },
  { name: 'Vikram Rao', email: 'vikram@demo.gwd.club', dept: 'PR' },
  { name: 'Neha Sharma', email: 'neha@demo.gwd.club', dept: 'Event Management' },
  { name: 'Arjun Patel', email: 'arjun@demo.gwd.club', dept: 'Cinematography' },
];

const TASKS = [
  ['Design the fest poster', 'Portrait and story sizes. Brand red on black.', 'Aisha Khan', 2],
  ['Shortlist three stage backdrops', 'Mock them against the stage dimensions.', 'Rohan Mehta', 5],
  ['Schedule the launch reel', 'Instagram + LinkedIn, Monday 6pm.', 'Sana Iqbal', 1],
  ['Draft the sponsor one-pager', 'Two tiers, with last year\'s footfall numbers.', 'Vikram Rao', 4],
  ['Confirm the auditorium booking', 'Need written confirmation from the Dean\'s office.', 'Neha Sharma', -1],
  ['Storyboard the aftermovie', '90 seconds. Open on the crowd shot.', 'Arjun Patel', 7],
  ['Collect speaker headshots', 'Minimum 1000px square.', 'Sana Iqbal', 3],
];

/** [title, categoryName, daysFromNow, location, extras] */
const SCHEDULE = [
  ['Core team sync', 'Meeting', 1, 'Room 204', {}],
  ['Sponsor pitch — Cloudbyte', 'Meeting', 3, 'Online', {
    meetingUrl: 'https://meet.google.com/abc-defg-hij',
  }],
  ['GWD TechConnect Summit', 'Event', 14, 'Main Auditorium', {}],
  ['Orientation night', 'Event', 6, 'Block C Lawn', {}],
  ['Industry session: Building a career in product', 'Meeting', 9, 'Online', {
    meetingUrl: 'https://meet.google.com/xyz-industry',
  }],
  // Marketing is the content calendar — platform, format and stage are what
  // make it useful rather than just more events.
  ['Summit teaser reel', 'Marketing', 2, '', {
    platform: 'instagram', format: 'reel', stage: 'inProduction',
  }],
  ['Speaker announcement carousel', 'Marketing', 4, '', {
    platform: 'instagram', format: 'carousel', stage: 'planned',
  }],
  ['Registration opens — LinkedIn post', 'Marketing', 5, '', {
    platform: 'linkedin', format: 'post', stage: 'ready',
  }],
  ['Behind the scenes story', 'Marketing', 8, '', {
    platform: 'instagram', format: 'story', stage: 'planned',
  }],
  ['Aftermovie drop', 'Marketing', 16, '', {
    platform: 'youtube', format: 'video', stage: 'planned',
  }],
  // Categories are club-defined, so the demo shows two beyond the starters.
  ['Promo shoot — campus walkthrough', 'Shoot', 7, 'Main Gate', {}],
  ['Stage run-through', 'Rehearsal', 13, 'Auditorium', {}],
];

const ALERTS = [
  ['Summit venue confirmed', 'The Main Auditorium is booked for the 14th. Plan around it.', 'normal'],
  ['Design assets due Friday', 'Marketing needs the poster set before the weekend push.', 'important'],
];

async function api(path, { method = 'GET', token, body } = {}) {
  const response = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  let json = null;
  try { json = await response.json(); } catch { /* no body */ }
  if (response.status >= 400) {
    throw new Error(`${method} ${path} → ${response.status} ${json?.error ?? ''}`);
  }
  return json;
}

const daysFromNow = (n) => {
  const d = new Date();
  d.setDate(d.getDate() + n);
  d.setHours(16, 0, 0, 0);
  return d.toISOString();
};

async function main() {
  const clear = process.argv.includes('--clear');

  const director = await api('/api/auth/login', {
    method: 'POST',
    body: { email: 'director1@gwd.club', password: 'DirectorPass1!' },
  }).catch(() => null);

  if (!director) {
    console.error(
      'Could not sign in as director1@gwd.club.\n' +
      'Start the server first, and check SEED_DIRECTORS in backend/.env.',
    );
    process.exit(1);
  }
  const token = director.token;

  const president = await api('/api/auth/login', {
    method: 'POST',
    body: { email: 'president@gwd.club', password: 'PresidentPass1!' },
  });

  if (clear) {
    // Only touches the demo accounts and what they own.
    const users = await api('/api/users', { token });
    const demoUsers = users.users.filter((u) => u.email.endsWith('@demo.gwd.club'));
    const tasks = await api('/api/tasks', { token });
    let removed = 0;
    for (const task of tasks.tasks) {
      if (demoUsers.some((u) => u.id === task.assignedTo)) {
        await api(`/api/tasks/${task.id}`, { method: 'DELETE', token }).catch(() => {});
        removed += 1;
      }
    }
    console.log(`Removed ${removed} demo tasks.`);
    console.log(
      `${demoUsers.length} demo accounts remain — delete them from MongoDB directly if you want them gone:\n` +
      `  db.users.deleteMany({ email: /@demo\\.gwd\\.club$/ })`,
    );
    return;
  }

  // ---------------------------------------------------------------- people
  const departments = (await api('/api/departments/public')).departments;
  const deptByName = new Map(departments.map((d) => [d.name, d]));

  const created = [];
  for (const person of PEOPLE) {
    const department = deptByName.get(person.dept);
    if (!department) {
      console.warn(`  skipped ${person.name} — no "${person.dept}" department`);
      continue;
    }
    try {
      await api('/api/auth/signup', {
        method: 'POST',
        body: {
          name: person.name,
          email: person.email,
          phone: '+919000000000',
          password: PASSWORD,
          role: 'clubMember',
          departmentId: department.id,
        },
      });
      created.push(person);
      console.log(`  + ${person.name} (${person.dept})`);
    } catch (error) {
      if (`${error}`.includes('already exists')) {
        console.log(`  = ${person.name} already exists`);
        created.push(person);
      } else {
        console.warn(`  ! ${person.name}: ${error.message}`);
      }
    }
  }

  // -------------------------------------------------------------- approvals
  const queue = await api('/api/access/pending', { token: president.token });
  let approved = 0;
  for (const request of queue.requests) {
    if (!request.applicant?.email?.endsWith('@demo.gwd.club')) continue;
    await api(`/api/access/${request.id}/approve`, { method: 'POST', token: president.token });
    approved += 1;
  }
  console.log(`Approved ${approved} demo members.`);

  // ------------------------------------------------------------------ tasks
  const members = (await api('/api/users', { token })).users;
  const idByName = new Map(members.map((m) => [m.name, m.id]));

  let taskCount = 0;
  for (const [title, description, assignee, dueIn] of TASKS) {
    const assignedTo = idByName.get(assignee);
    if (!assignedTo) continue;
    await api('/api/tasks', {
      method: 'POST',
      token,
      body: { title, description, assignedTo, dueDate: daysFromNow(dueIn) },
    });
    taskCount += 1;
  }
  console.log(`Created ${taskCount} tasks.`);

  // Move a couple along so the board isn't uniformly Pending.
  const all = await api('/api/tasks', { token });
  const movable = all.tasks.filter((t) => t.status === 'pending').slice(0, 3);
  for (const [i, task] of movable.entries()) {
    const owner = PEOPLE.find((p) => idByName.get(p.name) === task.assignedTo);
    if (!owner) continue;
    const session = await api('/api/auth/login', {
      method: 'POST',
      body: { email: owner.email, password: PASSWORD },
    });
    await api(`/api/tasks/${task.id}`, {
      method: 'PATCH', token: session.token, body: { status: 'inProgress' },
    });
    // Complete one of them, so points and the leaderboard have something in them.
    if (i === 0) {
      await api(`/api/tasks/${task.id}`, {
        method: 'PATCH', token: session.token, body: { status: 'completed' },
      });
    }
  }
  console.log('Advanced 3 tasks (1 completed).');

  // --------------------------------------------------------------- schedule
  const categories = (await api('/api/categories/schedule', { token: president.token }))
    .categories;
  const categoryByName = new Map(categories.map((c) => [c.name, c.id]));

  let scheduleCount = 0;
  for (const [title, categoryName, dueIn, location, extras] of SCHEDULE) {
    const categoryId = categoryByName.get(categoryName);
    if (!categoryId) {
      console.warn(`  ! no "${categoryName}" category — skipped ${title}`);
      continue;
    }
    await api('/api/schedule', {
      method: 'POST',
      token: president.token,
      body: { title, categoryId, location, date: daysFromNow(dueIn), ...extras },
    });
    scheduleCount += 1;
  }
  console.log(
    `Created ${scheduleCount} schedule entries across ${new Set(SCHEDULE.map((s) => s[1])).size} categories.`,
  );

  // ----------------------------------------------------------------- alerts
  let alertCount = 0;
  for (const [title, message, urgency] of ALERTS) {
    await api('/api/alerts', {
      method: 'POST',
      token: president.token,
      body: { title, message, urgency, audience: 'club' },
    });
    alertCount += 1;
  }
  console.log(`Sent ${alertCount} club alerts.`);

  console.log(`\nDone. Demo members sign in with password: ${PASSWORD}`);
  console.log('For example:  aisha@demo.gwd.club');
}

main().catch((error) => {
  console.error('\nDemo data failed:', error.message);
  process.exit(1);
});

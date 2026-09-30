// Records the API responses app/test/responsive_test.dart replays.
//
// Run against the throwaway QA server only (port 4700, database
// gwd_club_os_qa, seeded with `seed-club.js --demo`). It first fills that
// database with deliberately awkward data - long names, long titles - then saves
// every GET the app makes, per role, to app/test/fixtures/<role>.json.
// Refuses to touch any database but gwd_club_os_qa.
process.env.MONGODB_URI = 'mongodb://127.0.0.1:27018/?replicaSet=rs0&directConnection=true';
process.env.MONGODB_DB = 'gwd_club_os_qa';
const path = require('path');
const fs = require('fs');
const backend = path.join(__dirname, '..');
const db = require(path.join(backend, 'src/db'));
const { col, C } = db;
const { signToken } = require(path.join(backend, 'src/auth'));

const BASE = 'http://localhost:4700';
const OUT = path.join(__dirname, '..', '..', 'app', 'test', 'fixtures');

async function call(method, p, token, body) {
  const res = await fetch(BASE + p, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = {};
  try { json = await res.json(); } catch (_) { /* empty */ }
  return { status: res.status, json };
}

(async () => {
  await db.connect();
  if (db.database().databaseName !== 'gwd_club_os_qa') throw new Error('refusing: not the QA database');
  await col(C.users).updateMany({}, { $set: { mustChangePassword: false } });

  const mint = async (email) => signToken(await col(C.users).findOne({ email }));
  const tech = await col(C.departments).findOne({ name: 'Tech' });
  const production = await col(C.departments).findOne({ name: 'Production' });
  let lead = await mint('tech@gwd.global');
  const president = await mint('president@gwd.global');
  const superAdmin = await mint('clubdirector@gwd.global');

  // A member with a very long name, through the real signup + approval.
  const memberEmail = 'member.qa@gwd.club';
  if (!(await col(C.users).findOne({ email: memberEmail }))) {
    await call('POST', '/api/auth/signup', null, {
      name: 'Venkata Sai Krishna Chaitanya Subrahmanyam', email: memberEmail,
      phone: '9000000444', password: 'MemberQa1', role: 'clubMember', departmentId: String(tech._id),
    });
    const pending = await call('GET', '/api/access/pending', lead);
    const row = (pending.json.requests || []).find((r) => r.applicant && r.applicant.email === memberEmail);
    if (row) await call('POST', `/api/access/${row.id}/approve`, lead);
  }
  const member = await mint(memberEmail);

  // Awkward data: long department, person, event and task names.
  await col(C.departments).updateOne({ _id: production._id },
    { $set: { name: 'Production, Stage Design & Live Event Engineering' } });
  await col(C.users).updateOne({ email: 'tech@gwd.global' },
    { $set: { name: 'Mohammed Abdul Rahman Siddiqui' } });
  lead = await mint('tech@gwd.global');
  const firstEvent = await col(C.events).findOne({});
  if (firstEvent) {
    await col(C.events).updateOne({ _id: firstEvent._id }, {
      $set: { name: 'Annual Inter-College Technical Symposium and Cultural Festival Grand Finale Night' },
    });
  }
  await col(C.tasks).updateOne({}, {
    $set: { title: 'Coordinate with the auditorium management about the projector, sound console and backup generator' },
  });

  // Things only the API makes: a meeting, a help ask, an alert, an ask for work.
  const users = (await call('GET', '/api/users', superAdmin)).json.users || [];
  const memberId = (users.find((u) => u.email === memberEmail) || {}).id;
  const leadId = (users.find((u) => u.email === 'tech@gwd.global') || {}).id;
  await call('POST', '/api/meetings', president, {
    title: 'Sponsorship review and budget reconciliation for the winter festival season',
    date: new Date(Date.now() + 2 * 864e5).toISOString(), startTime: '16:30', venue: 'Seminar Hall 2, Block C',
    departmentIds: [String(tech._id)],
  });
  await call('POST', '/api/help', member, {
    title: 'Need someone who knows After Effects to help finish the opening titles tonight',
    description: 'The render keeps failing at 80% and the deadline is tomorrow morning.',
  });
  await call('POST', '/api/alerts', president, {
    title: 'Venue changed for tonight\u2019s rehearsal', message: 'We are in Block C instead of the main auditorium. Same time, bring the lighting cue sheets.',
    audience: 'club', urgency: 'important',
  });
  if (leadId) {
    await call('POST', '/api/task-requests', member, {
      toUserId: leadId, title: 'Design the poster series for the symposium social media countdown',
    });
  }

  fs.mkdirSync(OUT, { recursive: true });
  const roles = { super: superAdmin, lead, member };
  for (const [role, token] of Object.entries(roles)) {
    const out = {};
    const get = async (p) => {
      const r = await call('GET', p, token);
      if (r.status === 200) out[p] = r.json;
      return r.json;
    };
    const me = await get('/api/auth/me');
    for (const p of [
      '/api/home', '/api/tasks', '/api/tasks?scope=mine', '/api/tasks?scope=incoming',
      '/api/tasks?scope=assigned', '/api/task-requests?direction=incoming',
      '/api/task-requests?direction=outgoing', '/api/users', '/api/users/assignable',
      '/api/users/leaderboard', '/api/users/department-overview', '/api/users/my-overview',
      '/api/notifications', '/api/alerts', '/api/help', '/api/meetings', '/api/event-templates',
      '/api/categories/schedule', '/api/categories/schedule?includeInactive=true',
      '/api/schedule', '/api/schedule?mine=1', '/api/access/pending', '/api/departments',
      '/api/departments?includeInactive=true', '/api/departments/structure',
      '/api/departments/public', '/api/events', '/api/analytics', '/api/audit',
    ]) await get(p);

    const events = out['/api/events'] || {};
    for (const e of [...(events.upcoming || []), ...(events.ongoing || []), ...(events.past || []), ...(events.completed || [])]) {
      for (const sub of ['', '/work', '/timeline', '/documents', '/day', '/report', '/checklist', '/bills']) {
        await get(`/api/events/${e.id}${sub}`);
      }
    }
    for (const d of (out['/api/departments'] || {}).departments || []) {
      await get(`/api/departments/${d.id}/workspace`);
      await get(`/api/departments/${d.id}/roster`);
    }
    for (const u of ((out['/api/users'] || {}).users || [])) await get(`/api/users/${u.id}/stats`);
    const meetings = out['/api/meetings'] || {};
    for (const m of [...(meetings.upcoming || []), ...(meetings.past || [])]) {
      await get(`/api/meetings/${m.id}`);
      await get(`/api/meetings/${m.id}/actions`);
    }
    for (const t of ((out['/api/tasks?scope=mine'] || {}).tasks || []).concat((out['/api/tasks'] || {}).tasks || [])) {
      await get(`/api/tasks/${t.id}`);
    }
    fs.writeFileSync(path.join(OUT, `${role}.json`), JSON.stringify({ token: 'test-token', user: me.user, responses: out }));
    console.log(`${role.padEnd(7)} ${Object.keys(out).length} responses  (${me.user && me.user.role})`);
  }
  await db.close();
})().catch((e) => { console.error(e); process.exit(1); });

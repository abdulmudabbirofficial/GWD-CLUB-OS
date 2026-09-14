/* Meetings + attendance, end to end, against the throwaway v5 database. */
const BASE = process.env.MEET_BASE || 'http://127.0.0.1:4500';

let pass = 0;
let fail = 0;
const ok = (label, cond, extra = '') => {
  if (cond) { pass += 1; console.log(`  PASS  ${label}`); }
  else { fail += 1; console.log(`  FAIL  ${label}${extra ? ` - ${extra}` : ''}`); }
};

async function api(path, { method = 'GET', token, body } = {}) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  const txt = await res.text();
  try { json = JSON.parse(txt); } catch { /* not json */ }
  return { status: res.status, body: json, txt };
}

const login = async (email, password) => {
  const r = await api('/api/auth/login', { method: 'POST', body: { email, password } });
  if (!r.body?.token) throw new Error(`login failed ${email}: ${r.txt}`);
  return r.body;
};

(async () => {
  console.log('\nmeetings\n');
  const creds = JSON.parse(process.env.MEET_CREDS);

  const president = await login('president@gwd.global', creds.president);
  const techLead = await login('tech@gwd.global', creds.tech);
  const prodLead = await login('production@gwd.global', creds.production);

  const depts = await api('/api/departments', { token: president.token });
  const list = depts.body.departments ?? depts.body;
  const tech = list.find((d) => d.name === 'Tech');
  const production = list.find((d) => d.name === 'Production');

  // --- permission ---------------------------------------------------------
  const canSchedule = await api('/api/meetings', { token: president.token });
  ok('The President may schedule meetings', canSchedule.body?.canSchedule === true);

  // --- whole-department invite -------------------------------------------
  const created = await api('/api/meetings', {
    method: 'POST', token: president.token,
    body: {
      title: 'Pre-event sync',
      description: 'Run through the stage plan.',
      date: new Date(Date.now() + 2 * 864e5).toISOString(),
      startTime: '17:00', endTime: '18:00',
      venue: 'Seminar Hall 1',
      departmentIds: [tech.id, production.id],
    },
  });
  ok('A meeting can invite whole departments', created.status === 201, created.txt?.slice(0, 200));

  const meeting = created.body?.meeting;
  ok('Inviting a department expands to its people', (meeting?.invitedCount ?? 0) >= 3,
    `${meeting?.invitedCount} invited`);
  ok('Both Leads are on the sheet',
    (meeting?.participants ?? []).some((p) => p.name === 'Dikshit')
    && (meeting?.participants ?? []).some((p) => p.name === 'Rehman'),
    (meeting?.participants ?? []).map((p) => p.name).join(', '));
  ok('The organiser is in the room too',
    (meeting?.participants ?? []).some((p) => p.via === 'organiser'));
  ok('Nobody appears twice',
    new Set((meeting?.participants ?? []).map((p) => p.id)).size
      === (meeting?.participants ?? []).length);

  // --- it reaches the invitees -------------------------------------------
  const leadView = await api('/api/meetings', { token: techLead.token });
  ok('An invitee sees it without being leadership',
    (leadView.body?.upcoming ?? []).some((m) => m.id === meeting.id));
  ok('And a Lead may schedule one as well', leadView.body?.canSchedule === true);

  const notes = await api('/api/notifications', { token: techLead.token });
  ok('Invitees are notified',
    (notes.body?.notifications ?? []).some((n) => n.type === 'meetingInvited'),
    (notes.body?.notifications ?? []).map((n) => n.type).join(','));

  // --- attendance ---------------------------------------------------------
  const notMine = await api(`/api/meetings/${meeting.id}/attendance`, {
    method: 'POST', token: prodLead.token,
    body: { attendance: [{ userId: prodLead.user.id, status: 'attended' }] },
  });
  ok('An attendee cannot mark their own attendance', notMine.status === 403,
    `got ${notMine.status}`);

  const techId = (meeting.participants.find((p) => p.name === 'Dikshit') ?? {}).id;
  const prodId = (meeting.participants.find((p) => p.name === 'Rehman') ?? {}).id;

  const marked = await api(`/api/meetings/${meeting.id}/attendance`, {
    method: 'POST', token: president.token,
    body: {
      attendance: [
        { userId: techId, status: 'attended' },
        { userId: prodId, status: 'absent' },
      ],
    },
  });
  ok('The organiser records attendance', marked.status === 200, marked.txt?.slice(0, 200));
  ok('Marking it makes the meeting held', marked.body?.meeting?.status === 'held');
  ok('And the sheet knows it has been recorded',
    marked.body?.meeting?.attendanceRecorded === true);

  // --- the figures --------------------------------------------------------
  const attended = await api(`/api/meetings/attendance/${techId}`, { token: president.token });
  ok('Somebody who came reads 100%',
    attended.body?.attendance?.attended === 1 && attended.body?.attendance?.rate === 100,
    JSON.stringify(attended.body?.attendance));

  const missed = await api(`/api/meetings/attendance/${prodId}`, { token: president.token });
  ok('Somebody who did not reads 0%',
    missed.body?.attendance?.absent === 1 && missed.body?.attendance?.rate === 0,
    JSON.stringify(missed.body?.attendance));

  // Nobody recorded yet must not read as 0% - that looks like a failing grade.
  const untouched = await api(`/api/meetings/attendance/${president.user.id}`, {
    token: president.token,
  });
  ok('Nobody marked yet reads "no data", not zero',
    untouched.body?.attendance?.rate === null,
    JSON.stringify(untouched.body?.attendance));

  // --- it reaches the profile ---------------------------------------------
  const profile = await api(`/api/users/${techId}/stats`, { token: president.token });
  ok('Attendance shows on the member profile',
    profile.body?.attendance?.rate === 100,
    JSON.stringify(profile.body?.attendance));

  // --- cancelling ---------------------------------------------------------
  const cancelled = await api(`/api/meetings/${meeting.id}`, {
    method: 'PATCH', token: president.token, body: { status: 'cancelled' },
  });
  ok('A meeting can be called off', cancelled.status === 200);

  const afterCancel = await api(`/api/meetings/attendance/${techId}`, { token: president.token });
  ok('A cancelled meeting stops counting against anybody',
    afterCancel.body?.attendance?.invited === 0,
    JSON.stringify(afterCancel.body?.attendance));

  console.log(`\n  ${pass} passed, ${fail} failed\n`);
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });

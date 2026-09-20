'use strict';

/**
 * The mandatory requirements, checked against a running server.
 *
 * Not a unit test of any one module - this walks the whole product the way the
 * brief lists it, so "is requirement 7 actually done?" has a yes/no answer
 * instead of an opinion. Every check names the requirement it covers, and any
 * failures are reprinted at the end as a plain list of what is not done.
 *
 *   node scripts/test-requirements.js --base http://127.0.0.1:4600
 *
 * Credentials come in through REQ_CREDS as JSON, never from the file, so a
 * password is not sitting in the repository waiting to be shipped.
 */

const arg = (n, d) => {
  const i = process.argv.indexOf(`--${n}`);
  return i === -1 ? d : process.argv[i + 1];
};
const BASE = arg('base', 'http://127.0.0.1:4600');
const CREDS = JSON.parse(process.env.REQ_CREDS || '{}');

let pass = 0;
let fail = 0;
const failures = [];
const ok = (req, label, cond, extra = '') => {
  if (cond) {
    pass += 1;
    console.log(`  PASS  [${req}] ${label}`);
  } else {
    fail += 1;
    failures.push(`[${req}] ${label}${extra ? ` - ${extra}` : ''}`);
    console.log(`  FAIL  [${req}] ${label}${extra ? ` - ${extra}` : ''}`);
  }
};

async function api(path, opts = {}) {
  const { method = 'GET', token, body } = opts;
  const res = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const txt = await res.text();
  let json = null;
  try {
    json = JSON.parse(txt);
  } catch {
    /* not json */
  }
  return { status: res.status, body: json || {}, txt };
}

const login = async (email, password) => {
  const r = await api('/api/auth/login', { method: 'POST', body: { email, password } });
  return r.body && r.body.token ? r.body : null;
};

(async () => {
  console.log(`\nGWD Club OS - requirement check against ${BASE}\n`);

  const who = {};
  const accounts = {
    cmo: 'cmo@gwd.global',
    ceo: 'ceo@gwd.global',
    director3: 'director3@gwd.global',
    president: 'president@gwd.global',
    vp: 'vp@gwd.global',
    gensec: 'gensec@gwd.global',
    tech: 'tech@gwd.global',
    production: 'production@gwd.global',
  };
  for (const [key, email] of Object.entries(accounts)) {
    who[key] = await login(email, CREDS[key]);
    if (!who[key]) {
      console.error(`  could not sign in as ${email}`);
      process.exit(1);
    }
  }
  console.log('  signed in as all eight seeded accounts\n');

  // ------------------------------------------------------------- hierarchy
  console.log('hierarchy and roles');
  const everyone = (await api('/api/users', { token: who.cmo.token })).body.users || [];
  const directors = everyone.filter((u) => u.role === 'clubDirector');
  ok('R1', 'Three Club Director positions exist', directors.length === 3, `found ${directors.length}`);
  ok(
    'R2',
    'President, VP and Secretary General all exist',
    ['president', 'vicePresident', 'secretaryGeneral'].every((r) => everyone.some((u) => u.role === r)),
  );

  // ----------------------------------------------------------- departments
  console.log('\ndepartments');
  const depts = (await api('/api/departments', { token: who.president.token })).body.departments || [];
  const tech = depts.find((d) => d.name === 'Tech');
  const production = depts.find((d) => d.name === 'Production');
  ok('R4', 'Tech and Production both exist', Boolean(tech && production));

  const techLead = everyone.find((u) => u.id === (tech || {}).leadUserId);
  const prodLead = everyone.find((u) => u.id === (production || {}).leadUserId);
  ok('R6', 'Tech Lead is Dikshit', Boolean(techLead) && techLead.name === 'Dikshit', techLead && techLead.name);
  ok('R5', 'Production Lead is Rehman', Boolean(prodLead) && prodLead.name === 'Rehman', prodLead && prodLead.name);

  const made = await api('/api/departments', {
    method: 'POST',
    token: who.president.token,
    body: { name: `Marketing ${Date.now()}` },
  });
  ok('R3', 'A department can be created at runtime', made.status === 201, made.txt.slice(0, 120));
  const newDeptId = made.body.department && made.body.department.id;
  const afterCreate = (await api('/api/departments', { token: who.tech.token })).body.departments || [];
  ok('R3', 'and appears immediately for another user', afterCreate.some((d) => d.id === newDeptId));

  const vpDept = await api('/api/departments', {
    method: 'POST',
    token: who.vp.token,
    body: { name: `VP made ${Date.now()}` },
  });
  ok('R3', 'the Vice President can create departments too', vpDept.status === 201, `got ${vpDept.status}`);

  // -------------------------------------------------------- task hierarchy
  console.log('\ntask hierarchy');
  const toDept = await api('/api/tasks', {
    method: 'POST',
    token: who.president.token,
    body: { title: 'Stage rig check', departmentId: tech.id },
  });
  ok('R7', 'Executive assigns work to a department', toDept.status === 201, toDept.txt.slice(0, 120));
  const incoming = (await api('/api/tasks?scope=incoming', { token: who.tech.token })).body.tasks || [];
  ok('R7', 'and it lands in that Lead triage pile', incoming.some((t) => t.title === 'Stage rig check'));

  // The specific complaint: a Director assigning to the executive tier.
  const assignable = await api('/api/users/assignable', { token: who.cmo.token });
  const offered = (assignable.body.assignable || []).map((u) => u.role);
  ok(
    'R-DIR',
    'A Director is offered the President to assign to',
    offered.includes('president'),
    `offered: ${[...new Set(offered)].join(',') || 'nobody'}`,
  );
  ok('R-DIR', 'and the Vice President', offered.includes('vicePresident'));
  ok('R-DIR', 'and the Secretary General', offered.includes('secretaryGeneral'));

  const dirToPres = await api('/api/tasks', {
    method: 'POST',
    token: who.cmo.token,
    body: { title: 'Sign the venue letter', assignedTo: who.president.user.id },
  });
  ok(
    'R-DIR',
    'A Director can assign a task to the President',
    dirToPres.status === 201,
    `${dirToPres.status} ${dirToPres.txt.slice(0, 140)}`,
  );
  const presTasks = (await api('/api/tasks?scope=mine', { token: who.president.token })).body.tasks || [];
  ok('R-DIR', 'and the President sees it on their own list', presTasks.some((t) => t.title === 'Sign the venue letter'));

  const dirToVp = await api('/api/tasks', {
    method: 'POST',
    token: who.director3.token,
    body: { title: 'Confirm the guest list', assignedTo: who.vp.user.id },
  });
  ok('R-DIR', 'The third Director can assign to the Vice President', dirToVp.status === 201, `got ${dirToVp.status}`);

  const leadToPres = await api('/api/tasks', {
    method: 'POST',
    token: who.tech.token,
    body: { title: 'Lead orders the President about', assignedTo: who.president.user.id },
  });
  ok('R11', 'A Lead cannot assign a task to the President', leadToPres.status === 403, `got ${leadToPres.status}`);

  const leadToLead = await api('/api/tasks', {
    method: 'POST',
    token: who.tech.token,
    body: { title: 'Lead orders another Lead about', assignedTo: who.production.user.id },
  });
  ok('R11', 'nor to another Lead', leadToLead.status === 403, `got ${leadToLead.status}`);

  const leadRequest = await api('/api/task-requests', {
    method: 'POST',
    token: who.tech.token,
    body: { toUserId: who.president.user.id, title: 'Need a signature', description: 'For the venue' },
  });
  ok(
    'R8',
    'A Lead can request work from the President',
    leadRequest.status === 201,
    `${leadRequest.status} ${leadRequest.txt.slice(0, 120)}`,
  );

  const interDept = await api('/api/task-requests', {
    method: 'POST',
    token: who.production.token,
    body: { toDepartmentId: tech.id, title: 'Three people for the reel shoot', description: 'Saturday' },
  });
  ok(
    'R10',
    'A Lead can request support from another department',
    interDept.status === 201,
    `${interDept.status} ${interDept.txt.slice(0, 140)}`,
  );
  const techInbox = (await api('/api/task-requests', { token: who.tech.token })).body.requests || [];
  ok('R10', 'and the target Lead receives it', techInbox.some((r) => r.title === 'Three people for the reel shoot'));

  // ---------------------------------------------------------- task removal
  console.log('\ntask deletion');
  const doomed = await api('/api/tasks', {
    method: 'POST',
    token: who.president.token,
    body: { title: 'Delete me', departmentId: tech.id },
  });
  const doomedId = doomed.body.tasks[0].id;
  const wrongDelete = await api(`/api/tasks/${doomedId}`, { method: 'DELETE', token: who.production.token });
  ok('R12', 'A Lead cannot delete another department task', wrongDelete.status === 403, `got ${wrongDelete.status}`);
  const ownerDelete = await api(`/api/tasks/${doomedId}`, { method: 'DELETE', token: who.president.token });
  ok(
    'R12',
    'but whoever gave it out can',
    ownerDelete.status === 200,
    `${ownerDelete.status} ${ownerDelete.txt.slice(0, 120)}`,
  );

  // -------------------------------------------------------------- need help
  console.log('\nneed help');
  const deadline = new Date(Date.now() + 3 * 3600000).toISOString();
  const help = await api('/api/help', {
    method: 'POST',
    token: who.tech.token,
    body: { title: 'Proofread the poster', description: 'Before tonight', neededBy: deadline, maxHelpers: 2 },
  });
  ok('R14', 'A Need Help request can be raised', help.status === 201, help.txt.slice(0, 140));
  const helpId = help.body.id;
  // Read it back rather than trusting the create response: what matters is
  // what was *stored*, and the create route answers with an id alone.
  const helpList = (await api('/api/help', { token: who.tech.token })).body.requests || [];
  const helpRecord = helpList.find((h) => h.id === helpId) || {};
  ok(
    'R14',
    'and it stores a real deadline, not a phrase',
    !Number.isNaN(Date.parse(helpRecord.neededBy || '')),
    String(helpRecord.neededBy),
  );
  const noDeadline = await api('/api/help', {
    method: 'POST',
    token: who.tech.token,
    body: { title: 'No deadline given', description: 'x' },
  });
  ok('R14', 'and a request without a deadline is refused', noDeadline.status === 400, `got ${noDeadline.status}`);

  // The ask goes to the raiser's own department, not the whole club - a
  // club-wide ping for "can someone proofread this" is how people mute the
  // app. So the person who should hear it is a Tech member, and the check has
  // to create one rather than asking Production, who correctly hears nothing.
  const techMate = await api('/api/auth/signup', {
    method: 'POST',
    body: {
      name: `Tech Mate ${Date.now()}`,
      email: `techmate.${Date.now()}@gwd.club`,
      phone: '9000000111',
      password: 'TechMatePass1',
      role: 'clubMember',
      departmentId: tech.id,
    },
  });
  const mateId = techMate.body.user && techMate.body.user.id;
  // A member joining a department is approved by *that department's Lead* -
  // not the President, who is not the acting approver for this and so never
  // sees the request in their queue at all.
  const pending = (await api('/api/access/pending', { token: who.tech.token })).body.requests || [];
  const mateRow = pending.find((r) => r.userId === mateId);
  ok('R-JOIN', 'a new member lands in their own Lead approval queue', Boolean(mateRow),
    `${pending.length} pending for the Tech Lead`);
  if (mateRow) {
    const approved = await api(`/api/access/${mateRow.id}/approve`, {
      method: 'POST',
      token: who.tech.token,
    });
    ok('R-JOIN', 'and the Lead can approve them', approved.status === 200,
      `${approved.status} ${approved.txt.slice(0, 120)}`);
  }
  const mate = await login(techMate.body.user.email, 'TechMatePass1');

  const help2 = await api('/api/help', {
    method: 'POST',
    token: who.tech.token,
    body: { title: 'Second pair of eyes', description: 'Poster', neededBy: deadline, maxHelpers: 1 },
  });
  const notes = (await api('/api/notifications', { token: mate.token })).body.notifications || [];
  ok(
    'R13',
    'Need Help notifies the raiser department',
    notes.some((n) => n.type === 'helpRequested'),
    notes.map((n) => n.type).join(',') || 'none',
  );
  ok('R13', 'and the second request was accepted', help2.status === 201, help2.txt.slice(0, 120));

  const offer = await api(`/api/help/${helpId}/offer`, {
    method: 'POST',
    token: mate.token,
    body: { note: 'I can do it' },
  });
  ok('R15', 'Accepting a Need Help succeeds', offer.status === 200, offer.txt.slice(0, 140));
  const helperTasks = (await api('/api/tasks?scope=mine', { token: mate.token })).body.tasks || [];
  const linked = helperTasks.find((t) => (t.title || '').includes('Proofread the poster'));
  ok(
    'R15',
    'and a linked Task appears for the helper immediately',
    Boolean(linked),
    helperTasks.map((t) => t.title).join(' | ') || 'no tasks',
  );
  ok(
    'R15',
    'with the deadline inherited from the request',
    Boolean(linked && linked.dueDate) && Math.abs(Date.parse(linked.dueDate) - Date.parse(deadline)) < 60000,
    `task due ${linked && linked.dueDate} vs help ${deadline}`,
  );

  // ------------------------------------------------- meetings + attendance
  console.log('\nmeetings and attendance');
  const meeting = await api('/api/meetings', {
    method: 'POST',
    token: who.president.token,
    body: {
      title: 'Pre-event sync',
      date: new Date(Date.now() + 864e5).toISOString(),
      startTime: '17:00',
      departmentIds: [tech.id],
    },
  });
  ok('R22', 'A whole department can be invited in one go', meeting.status === 201, meeting.txt.slice(0, 140));
  const meetingRecord = meeting.body.meeting || {};
  ok(
    'R22',
    'and it expands to the department people',
    (meetingRecord.invitedCount || 0) >= 2,
    `${meetingRecord.invitedCount} invited`,
  );

  const leadMeeting = await api('/api/meetings', {
    method: 'POST',
    token: who.production.token,
    body: {
      title: 'Lead calls one',
      date: new Date(Date.now() + 864e5).toISOString(),
      userIds: [who.tech.user.id],
    },
  });
  ok('R21', 'A Lead may also schedule a meeting', leadMeeting.status === 201,
    `${leadMeeting.status} ${leadMeeting.txt.slice(0, 120)}`);
  const memberMeeting = await api('/api/meetings', {
    method: 'POST',
    token: mate.token,
    body: {
      title: 'A member should not manage this',
      date: new Date(Date.now() + 864e5).toISOString(),
      userIds: [who.tech.user.id],
    },
  });
  ok('R21', 'but an ordinary member cannot', memberMeeting.status === 403, `got ${memberMeeting.status}`);

  const techId = who.tech.user.id;
  const marked = await api(`/api/meetings/${meetingRecord.id}/attendance`, {
    method: 'POST',
    token: who.president.token,
    body: { attendance: [{ userId: techId, status: 'attended' }] },
  });
  ok('R23', 'Attendance can be recorded', marked.status === 200, marked.txt.slice(0, 140));

  const stats = await api(`/api/users/${techId}/stats`, { token: who.president.token });
  ok(
    'R24',
    'Attendance statistics are derived',
    (stats.body.attendance || {}).attended === 1,
    JSON.stringify(stats.body.attendance),
  );
  ok(
    'R25',
    'and appear on the member profile',
    (stats.body.attendance || {}).rate === 100,
    JSON.stringify(stats.body.attendance),
  );
  const noMeetings = await api(`/api/meetings/attendance/${who.gensec.user.id}`, { token: who.president.token });
  ok(
    'R24',
    'nobody invited yet reads as no data, never NaN',
    (noMeetings.body.attendance || {}).rate === null,
    JSON.stringify(noMeetings.body.attendance),
  );

  // ----------------------------------------------------------------- events
  console.log('\nevents');
  const event = await api('/api/events', {
    method: 'POST',
    token: who.president.token,
    body: {
      name: 'Campus Summit',
      date: new Date(Date.now() + 5 * 864e5).toISOString(),
      organizingDepartmentId: tech.id,
      leadUserId: who.tech.user.id,
    },
  });
  ok('R19', 'An event can be created', event.status === 201, event.txt.slice(0, 140));
  const eventId = event.body.event && event.body.event.id;
  const listed = (await api('/api/events', { token: who.production.token })).body || {};
  const allEvents = [...(listed.upcoming || []), ...(listed.ongoing || []), ...(listed.past || [])];
  ok('R19', 'and persists, visible to another member', allEvents.some((e) => e.id === eventId));

  const leadCancel = await api(`/api/events/${eventId}`, { method: 'DELETE', token: who.tech.token });
  ok('R20', 'A Lead cannot cancel an event', leadCancel.status === 403, `got ${leadCancel.status}`);
  const cancel = await api(`/api/events/${eventId}`, { method: 'DELETE', token: who.president.token });
  ok('R20', 'The President can cancel it', cancel.status === 200, cancel.txt.slice(0, 120));
  const purge = await api(`/api/events/${eventId}?purge=true`, { method: 'DELETE', token: who.president.token });
  ok('R20', 'and only then delete it outright', purge.status === 200, `${purge.status} ${purge.txt.slice(0, 120)}`);

  // -------------------------------------------- templates, day mode, report
  //
  // The three surfaces an event grows once a club runs the same thing twice:
  // a saved shape to start from, a run sheet for the day itself, and an
  // account of what happened afterwards.
  console.log('\ntemplates, day mode and the report');

  const template = await api('/api/event-templates', {
    method: 'POST',
    token: who.president.token,
    body: {
      name: 'Guest Lecture',
      type: 'lecture',
      venue: 'Seminar Hall',
      organizingDepartmentId: tech.id,
      responsibilities: [{
        departmentId: production.id,
        notes: 'Stage and sound',
        tasks: [
          { title: 'Book the hall', offsetDays: -14, points: 3 },
          { title: 'Sound check', offsetDays: -1, points: 1 },
          { title: 'Return the equipment', offsetDays: 2, points: 1 },
        ],
      }],
    },
  });
  ok('T1', 'An event template can be saved', template.status === 201, template.txt.slice(0, 160));
  const templateId = template.body.template && template.body.template.id;
  const tmpl = template.body.template || {};
  ok('T1', 'and it counts what applying it would create',
    tmpl.taskCount === 3 && tmpl.departmentCount === 1,
    `${tmpl.taskCount} tasks / ${tmpl.departmentCount} departments`);
  // The offset is the whole point: a stored date would be wrong the second
  // time the template was used.
  ok('T1', 'its tasks carry an offset from the event date, not a date',
    ((tmpl.responsibilities || [])[0] || {}).tasks
      .every((t) => typeof t.offsetDays === 'number'),
    JSON.stringify(((tmpl.responsibilities || [])[0] || {}).tasks || []).slice(0, 120));

  const readTemplates = await api('/api/event-templates', { token: who.production.token });
  ok('T1', 'and everybody can read the templates the club has',
    readTemplates.status === 200
    && (readTemplates.body.templates || []).some((t) => t.id === templateId));

  // An ordinary member cannot invent one - a template shapes what the club
  // does, which is the same standing it takes to create the event itself.
  const memberTemplate = await api('/api/event-templates', {
    method: 'POST',
    token: mate.token,
    body: { name: 'Nope', organizingDepartmentId: tech.id },
  });
  ok('T1', 'but an ordinary member cannot create one',
    memberTemplate.status === 403, `got ${memberTemplate.status}`);

  const fromTemplate = await api('/api/events', {
    method: 'POST',
    token: who.president.token,
    body: {
      name: 'Guest Lecture: Systems',
      date: new Date(Date.now() + 9 * 864e5).toISOString(),
      organizingDepartmentId: tech.id,
      leadUserId: who.tech.user.id,
      teamUserIds: [who.production.user.id],
      templateId,
    },
  });
  ok('T2', 'An event records the template it was started from',
    fromTemplate.status === 201 && fromTemplate.body.event.templateId === templateId,
    fromTemplate.txt.slice(0, 140));
  const liveId = fromTemplate.body.event && fromTemplate.body.event.id;

  const usage = (await api(`/api/event-templates/${templateId}`, { token: who.president.token }))
    .body.template || {};
  ok('T2', 'and using it moves the template up the list', usage.usageCount === 1,
    `usageCount ${usage.usageCount}`);

  // --- the day itself ------------------------------------------------------
  const row = await api(`/api/events/${liveId}/runsheet`, {
    method: 'POST',
    token: who.tech.token,
    body: { time: '9:05', title: 'Doors open', ownerUserId: who.production.user.id },
  });
  ok('T3', 'The event lead can put something on the run sheet',
    row.status === 201, row.txt.slice(0, 140));
  ok('T3', 'and the time is normalised so the sheet sorts without parsing',
    row.body.item && row.body.item.time === '09:05',
    (row.body.item || {}).time);
  const rowId = row.body.item && row.body.item.id;

  await api(`/api/events/${liveId}/runsheet`, {
    method: 'POST',
    token: who.tech.token,
    body: { title: 'Tidy the hall' },
  });
  const day = await api(`/api/events/${liveId}/day`, { token: who.tech.token });
  ok('T3', 'The day view returns the sheet in order, untimed rows last',
    day.status === 200
    && day.body.runSheet.length === 2
    && day.body.runSheet[0].time === '09:05'
    && day.body.runSheet[1].time === '',
    JSON.stringify((day.body.runSheet || []).map((i) => i.time)));
  ok('T3', 'with the team reachable by phone for whoever is running it',
    day.body.canEdit === true && day.body.team.length === 2);

  // Anyone on the team can tick a row off; only the lead can rewrite one.
  const tick = await api(`/api/events/${liveId}/runsheet/${rowId}`, {
    method: 'PATCH', token: who.production.token, body: { done: true },
  });
  ok('T3', 'Anyone on the team can tick a row off on the day',
    tick.status === 200 && tick.body.item.done === true, tick.txt.slice(0, 140));
  const rewrite = await api(`/api/events/${liveId}/runsheet/${rowId}`, {
    method: 'PATCH', token: who.production.token, body: { title: 'Something else' },
  });
  ok('T3', 'but rewriting one is the event lead’s call',
    rewrite.status === 403, `got ${rewrite.status}`);

  // A member with no part in the event still sees what is happening - the
  // club is not secret - but nobody's phone number comes with it.
  const outsider = await api(`/api/events/${liveId}/day`, { token: mate.token });
  ok('T3', 'Somebody outside the event still sees what is happening',
    outsider.status === 200 && outsider.body.runSheet.length === 2,
    `${outsider.status} / ${(outsider.body.runSheet || []).length} rows`);
  ok('T3', 'but phone numbers are only for whoever is running it',
    outsider.body.canEdit === false
    && (outsider.body.team || []).every((m) => m.phone === ''),
    JSON.stringify((outsider.body.team || []).map((m) => m.phone)));

  // --- afterwards ----------------------------------------------------------
  const saved = await api(`/api/events/${liveId}/report`, {
    method: 'PUT',
    token: who.tech.token,
    body: { attendance: 120, highlights: 'Full hall', challenges: 'Projector', learnings: 'Test it' },
  });
  ok('T4', 'The event lead can write the report', saved.status === 200, saved.txt.slice(0, 140));

  const report = await api(`/api/events/${liveId}/report`, { token: mate.token });
  ok('T4', 'and it reads back with what was typed',
    report.status === 200 && report.body.report.attendance === 120
    && report.body.report.highlights === 'Full hall',
    report.txt.slice(0, 140));
  // The half nobody types is the half that has to be right.
  ok('T4', 'alongside figures derived from the event, not typed in',
    report.body.derived
    && report.body.derived.teamSize === 2
    && report.body.derived.runSheetTotal === 2
    && report.body.derived.runSheetDone === 1,
    JSON.stringify(report.body.derived || {}).slice(0, 160));
  ok('T4', 'and a reader who cannot edit is told so',
    report.body.canEdit === false, `canEdit ${report.body.canEdit}`);

  const memberReport = await api(`/api/events/${liveId}/report`, {
    method: 'PUT', token: mate.token, body: { highlights: 'I was there' },
  });
  ok('T4', 'but an ordinary member cannot write it',
    memberReport.status === 403, `got ${memberReport.status}`);
  const badReport = await api(`/api/events/${liveId}/report`, {
    method: 'PUT', token: who.tech.token, body: { attendance: -4 },
  });
  ok('T4', 'and a negative attendance is refused rather than stored',
    badReport.status === 400, `got ${badReport.status}`);

  await api(`/api/events/${liveId}`, { method: 'DELETE', token: who.president.token });
  await api(`/api/events/${liveId}?purge=true`, { method: 'DELETE', token: who.president.token });
  await api(`/api/event-templates/${templateId}`, { method: 'DELETE', token: who.president.token });

  // --------------------------------------------------------------- schedule
  console.log('\nschedule');
  const categories = (await api('/api/categories/schedule', { token: who.president.token }))
    .body.categories || [];
  ok('R18', 'Schedule categories are managed data, not an enum', categories.length > 0,
    `${categories.length} categories`);
  const entry = await api('/api/schedule', {
    method: 'POST',
    token: who.president.token,
    body: {
      title: 'Rehearsal',
      date: new Date(Date.now() + 2 * 864e5).toISOString(),
      categoryId: (categories[0] || {}).id,
    },
  });
  ok('R18', 'Something can be added to the schedule', entry.status === 201, entry.txt.slice(0, 140));
  const schedule = (await api('/api/schedule', { token: who.production.token })).body.entries || [];
  ok(
    'R18',
    'and everyone can read it back',
    schedule.some((e) => e.title === 'Rehearsal'),
    `${schedule.length} entries`,
  );

  // ------------------------------------------------ visibility + privilege
  console.log('\nvisibility and privilege');
  const crossDept = await api(`/api/users/${who.tech.user.id}/stats`, { token: who.production.token });
  ok('R26', 'A Lead can view another department Lead', crossDept.status === 200, `got ${crossDept.status}`);

  const escalate = await api(`/api/users/${who.tech.user.id}/role`, {
    method: 'PATCH',
    token: who.tech.token,
    body: { role: 'president' },
  });
  ok('R28', 'A Lead cannot promote themselves', escalate.status === 403, `got ${escalate.status}`);

  const vpRole = await api(`/api/users/${who.gensec.user.id}/role`, {
    method: 'PATCH',
    token: who.vp.token,
    body: { role: 'president' },
  });
  ok('R28', 'nor can the Vice President edit roles', vpRole.status === 403, `got ${vpRole.status}`);

  const noToken = await api('/api/users');
  ok('R28', 'and nothing is readable without a token', noToken.status === 401, `got ${noToken.status}`);

  const fourth = await api(`/api/users/${who.gensec.user.id}/role`, {
    method: 'PATCH',
    token: who.cmo.token,
    body: { role: 'clubDirector' },
  });
  ok(
    'R1',
    'a fourth Director is refused - the cap is real',
    fourth.status === 409 || fourth.status === 400,
    `got ${fourth.status}`,
  );

  console.log(`\n  ${pass} passed, ${fail} failed\n`);
  if (failures.length) {
    console.log('  WHAT IS NOT DONE:');
    for (const f of failures) console.log(`    - ${f}`);
    console.log('');
  }
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});

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

  // ------------------------------------------ what comes out of a meeting
  //
  // The failure being closed: a decision gets made, somebody writes it in a
  // notes app, and it is next read when the same thing goes wrong at the
  // following meeting. An action item has to be a real task or it is a note.
  console.log('\nmeeting notes and action items');

  const planningMeeting = await api('/api/meetings', {
    method: 'POST',
    token: who.president.token,
    body: {
      title: 'Fest planning',
      date: new Date(Date.now() - 864e5).toISOString(),
      // Deliberately not the Tech Lead: the check below needs somebody who
      // can hand work out but was not in the room.
      userIds: [who.production.user.id, mateId],
    },
  });
  ok('M1', 'A meeting can be called', planningMeeting.status === 201, planningMeeting.txt.slice(0, 140));
  const meetingId = planningMeeting.body.meeting && planningMeeting.body.meeting.id;

  const noted = await api(`/api/meetings/${meetingId}`, {
    method: 'PATCH',
    token: who.president.token,
    body: { notes: 'Agreed to move the fest to the 20th.' },
  });
  ok('M1', 'and what was decided can be written down',
    noted.status === 200
    && noted.body.meeting.notes === 'Agreed to move the fest to the 20th.',
    noted.txt.slice(0, 140));

  const action = await api(`/api/meetings/${meetingId}/actions`, {
    method: 'POST',
    token: who.president.token,
    body: { title: 'Redo the poster with the new date', departmentId: production.id, points: 3 },
  });
  ok('M2', 'Something agreed in the room becomes work',
    action.status === 201, action.txt.slice(0, 160));
  const actionId = action.body.task && action.body.task.id;

  // The whole point: it is a task, not a note on a meeting page.
  const inWork = (await api('/api/tasks', { token: who.production.token })).body.tasks || [];
  ok('M2', 'and it is a real task, in the real task list',
    inWork.some((t) => t.id === actionId),
    `${inWork.length} tasks visible to the Production Lead`);
  ok('M2', 'carrying the meeting it came out of, so there is a way back',
    (inWork.find((t) => t.id === actionId) || {}).meetingId === meetingId);

  const actionsBefore = await api(`/api/meetings/${meetingId}/actions`, { token: who.tech.token });
  ok('M2', 'The meeting lists what came out of it',
    actionsBefore.status === 200 && (actionsBefore.body.actions || []).length === 1
    && actionsBefore.body.done === 0,
    actionsBefore.txt.slice(0, 140));

  // Completing it anywhere completes it everywhere, because there is only one
  // of it. A separate checklist would have the two disagree here.
  await api(`/api/tasks/${actionId}/assign`, {
    method: 'POST',
    token: who.production.token,
    body: { assignedTo: who.production.user.id, points: 3 },
  });
  await api(`/api/tasks/${actionId}`, {
    method: 'PATCH', token: who.production.token, body: { status: 'inProgress' },
  });
  const finished = await api(`/api/tasks/${actionId}`, {
    method: 'PATCH', token: who.production.token, body: { status: 'completed' },
  });
  ok('M2', 'The person it landed on can finish it', finished.status === 200,
    finished.txt.slice(0, 140));
  const after = await api(`/api/meetings/${meetingId}/actions`, { token: who.tech.token });
  ok('M2', 'and finishing it on the Work tab shows as done on the meeting',
    after.body.done === 1,
    `done ${after.body.done} of ${(after.body.actions || []).length}`);

  // Calling a meeting does not extend anybody's authority over who does what.
  const memberAction = await api(`/api/meetings/${meetingId}/actions`, {
    method: 'POST',
    token: mate.token,
    body: { title: 'Something for somebody else', departmentId: production.id },
  });
  ok('M3', 'An ordinary member still cannot hand work out',
    memberAction.status === 403, `got ${memberAction.status}`);

  // A Lead who was not in the room cannot record what came out of it either.
  const outsiderAction = await api(`/api/meetings/${meetingId}/actions`, {
    method: 'POST',
    token: who.tech.token,
    body: { title: 'I was not there', departmentId: tech.id },
  });
  ok('M3', 'nor can a Lead who was not at the meeting',
    outsiderAction.status === 403, `got ${outsiderAction.status}`);

  // The executive deliberately can, on the same footing as marking attendance:
  // somebody has to be able to tidy up after a meeting they did not attend.
  const execAction = await api(`/api/meetings/${meetingId}/actions`, {
    method: 'POST',
    token: who.gensec.token,
    body: { title: 'Tidying up after the meeting', departmentId: tech.id },
  });
  ok('M3', 'but the executive can, as with attendance',
    execAction.status === 201, `got ${execAction.status}`);

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

  // An empty change is not an error. This came back a 500 before: Mongo
  // rejects an update declaring an array filter that nothing in $set uses.
  const noChange = await api(`/api/events/${liveId}/runsheet/${rowId}`, {
    method: 'PATCH', token: who.tech.token, body: {},
  });
  ok('T3', 'A patch that changes nothing is a no-op, not a server error',
    noChange.status === 200, `got ${noChange.status} ${noChange.txt.slice(0, 100)}`);

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

  // ------------------------------------------------------------ V8 hierarchy
  //
  // One Director above the others, the Faculty Coordinator reaching the Leads,
  // and the three ways an account below could take over one above it.
  console.log('\nV8 hierarchy: Super Admin, Directors, Faculty Coordinator');

  const roster = (await api('/api/users', { token: who.cmo.token })).body.users || [];
  const byEmail = (e) => roster.find((u) => u.email === e) || {};
  ok('V8-H', 'Director Mudabbir is the Super Admin',
    byEmail('cmo@gwd.global').superAdmin === true
    && byEmail('cmo@gwd.global').knownAs === 'Mudabbir',
    JSON.stringify({ s: byEmail('cmo@gwd.global').superAdmin, k: byEmail('cmo@gwd.global').knownAs }));
  ok('V8-H', 'and Director Rehman and Director Moin are Directors, not Super Admins',
    byEmail('ceo@gwd.global').superAdmin === false && byEmail('ceo@gwd.global').knownAs === 'Rehman'
    && byEmail('director3@gwd.global').superAdmin === false
    && byEmail('director3@gwd.global').knownAs === 'Moin');
  ok('V8-H', 'Nobody is called "Club Director Three" any more',
    !roster.some((u) => /Director (One|Two|Three|\d)/i.test(u.name || '')),
    roster.filter((u) => /Director/i.test(u.name || '')).map((u) => u.name).join(', '));

  const capsFor = async (w) => ((await api('/api/home', { token: w.token })).body.capabilities || {});
  const superCaps = await capsFor(who.cmo);
  const rehmanCaps = await capsFor(who.ceo);
  ok('V8-H', 'Only the Super Admin is told they can appoint Directors',
    superCaps.canAppointSupervisors === true && rehmanCaps.canAppointSupervisors === false,
    `super ${superCaps.canAppointSupervisors} / rehman ${rehmanCaps.canAppointSupervisors}`);

  const rehmanAppoints = await api(`/api/users/${who.gensec.user.id}/role`, {
    method: 'PATCH', token: who.ceo.token, body: { role: 'facultyCoordinator' },
  });
  ok('V8-H', 'A Director who is not the Super Admin cannot appoint a supervisor',
    rehmanAppoints.status === 403, `got ${rehmanAppoints.status}`);

  // The hole: the route checked only appointments *into* the tier.
  const presidentDemotes = await api(`/api/users/${who.director3.user.id}/role`, {
    method: 'PATCH', token: who.president.token, body: { role: 'clubMember' },
  });
  ok('V8-H', 'The President cannot demote a Director',
    presidentDemotes.status === 403, `got ${presidentDemotes.status}`);
  const directorDemotes = await api(`/api/users/${who.director3.user.id}/role`, {
    method: 'PATCH', token: who.ceo.token, body: { role: 'clubMember' },
  });
  ok('V8-H', 'nor can one Director demote another',
    directorDemotes.status === 403, `got ${directorDemotes.status}`);
  const demoteSuper = await api(`/api/users/${who.cmo.user.id}/role`, {
    method: 'PATCH', token: who.ceo.token, body: { role: 'clubMember' },
  });
  ok('V8-H', 'and nobody can change the Super Admin\u2019s role',
    demoteSuper.status === 403, `got ${demoteSuper.status}`);

  // A password reset hands the resetter a working password. It must only
  // ever reach down.
  const vpResetsPresident = await api(`/api/users/${who.president.user.id}/reset-password`, {
    method: 'POST', token: who.vp.token,
  });
  ok('V8-S', 'The Vice President cannot reset the President\u2019s password',
    vpResetsPresident.status === 403 && !vpResetsPresident.body.temporaryPassword,
    `got ${vpResetsPresident.status}`);
  const rehmanResetsSuper = await api(`/api/users/${who.cmo.user.id}/reset-password`, {
    method: 'POST', token: who.ceo.token,
  });
  ok('V8-S', 'A Director cannot reset the Super Admin\u2019s password',
    rehmanResetsSuper.status === 403 && !rehmanResetsSuper.body.temporaryPassword,
    `got ${rehmanResetsSuper.status}`);
  const rehmanResetsMoin = await api(`/api/users/${who.director3.user.id}/reset-password`, {
    method: 'POST', token: who.ceo.token,
  });
  ok('V8-S', 'nor another Director\u2019s',
    rehmanResetsMoin.status === 403, `got ${rehmanResetsMoin.status}`);
  const presidentRenamesDirector = await api(`/api/users/${who.director3.user.id}/name`, {
    method: 'PATCH', token: who.president.token, body: { name: 'Somebody Else' },
  });
  ok('V8-S', 'and the President cannot rename a Director',
    presidentRenamesDirector.status === 403, `got ${presidentRenamesDirector.status}`);

  // --- the Faculty Coordinator ---------------------------------------------
  // Signed in the way the club would do it: the Super Admin resets the seat
  // and passes the temporary password on. Nothing about this test knows a
  // password in advance.
  const facultyRow = roster.find((u) => u.role === 'facultyCoordinator');
  let faculty = null;
  if (facultyRow) {
    const reset = await api(`/api/users/${facultyRow.id}/reset-password`, {
      method: 'POST', token: who.cmo.token,
    });
    ok('V8-S', 'The Super Admin can reset a supervisor\u2019s password',
      reset.status === 200 && Boolean(reset.body.temporaryPassword), `got ${reset.status}`);
    faculty = await login(facultyRow.email, reset.body.temporaryPassword);
  }
  ok('V8-F', 'The Faculty Coordinator can sign in', Boolean(faculty),
    facultyRow ? `found ${facultyRow.email}, sign-in failed` : `roles present: ${[...new Set(roster.map((u) => u.role))].join(',')}`);

  if (faculty) {
    const offered = (await api('/api/users/assignable', { token: faculty.token })).body.assignable || [];
    const offeredRoles = new Set(offered.map((u) => u.role));
    ok('V8-F', 'The Faculty Coordinator is offered the President, VP, General Secretary and every Lead',
      ['president', 'vicePresident', 'secretaryGeneral', 'clubLead'].every((r) => offeredRoles.has(r)),
      `offered: ${[...offeredRoles].join(',')}`);
    ok('V8-F', 'but never an individual member — they go through their Lead',
      !offeredRoles.has('clubMember'));

    const toLead = await api('/api/tasks', {
      method: 'POST', token: faculty.token,
      body: { title: 'Faculty sign-off on the lab booking', assignedTo: who.tech.user.id, priority: 'high' },
    });
    ok('V8-F', 'The Faculty Coordinator can assign straight to a Club Lead',
      toLead.status === 201, toLead.txt.slice(0, 140));
    const toMember = await api('/api/tasks', {
      method: 'POST', token: faculty.token,
      body: { title: 'Not through the Lead', assignedTo: mateId },
    });
    ok('V8-F', 'and still cannot reach past the Lead to a member',
      toMember.status === 403, `got ${toMember.status}`);

    // --- §31: across roles, and live --------------------------------------
    // Faculty Coordinator → President → completed → the Faculty Coordinator
    // sees it, on a socket, without asking.
    const { io } = require('socket.io-client');
    const facultySocket = io(BASE, { auth: { token: faculty.token }, transports: ['websocket'] });
    await new Promise((resolve) => {
      facultySocket.on('connect', resolve);
      setTimeout(resolve, 5000);
    });
    ok('V8-X', 'The Faculty Coordinator is connected live', facultySocket.connected);

    const seen = [];
    facultySocket.on('task:updated', (t) => seen.push(t));

    const due = new Date(Date.now() + 3 * 864e5).toISOString();
    const handed = await api('/api/tasks', {
      method: 'POST', token: faculty.token,
      body: {
        title: 'Countersign the sponsorship MoU', assignedTo: who.president.user.id,
        dueDate: due, priority: 'high', description: 'Needed before Friday.',
      },
    });
    ok('V8-X', 'The Faculty Coordinator assigns a task to the President',
      handed.status === 201, handed.txt.slice(0, 140));
    const handedId = handed.body.tasks && handed.body.tasks[0] && handed.body.tasks[0].id;

    const presMine = (await api('/api/tasks?scope=mine', { token: who.president.token })).body.tasks || [];
    ok('V8-X', 'The President sees it on their own list',
      presMine.some((t) => t.id === handedId && t.priority === 'high'));
    const presNotes = (await api('/api/notifications', { token: who.president.token })).body.notifications || [];
    const assignedNote = presNotes.find((n) => n.type === 'taskAssigned'
      && (n.payload || {}).taskId === handedId);
    ok('V8-X', 'and is told, with a notification that opens it', Boolean(assignedNote));

    await api(`/api/tasks/${handedId}`, {
      method: 'PATCH', token: who.president.token, body: { status: 'inProgress' },
    });
    const moved = await new Promise((resolve) => {
      const t0 = Date.now();
      const tick = () => {
        if (seen.some((t) => t.id === handedId && t.status === 'inProgress')) return resolve(true);
        if (Date.now() - t0 > 6000) return resolve(false);
        return setTimeout(tick, 100);
      };
      tick();
    });
    ok('V8-X', 'The Faculty Coordinator sees the President start it, live, without asking',
      moved, `${seen.length} live updates seen`);

    const done = await api(`/api/tasks/${handedId}`, {
      method: 'PATCH', token: who.president.token, body: { status: 'completed' },
    });
    ok('V8-X', 'The President completes it', done.status === 200, done.txt.slice(0, 120));
    const finishedLive = await new Promise((resolve) => {
      const t0 = Date.now();
      const tick = () => {
        if (seen.some((t) => t.id === handedId && t.status === 'completed')) return resolve(true);
        if (Date.now() - t0 > 6000) return resolve(false);
        return setTimeout(tick, 100);
      };
      tick();
    });
    ok('V8-X', 'and the Faculty Coordinator sees the completion live', finishedLive);

    const facultyNotes = (await api('/api/notifications', { token: faculty.token })).body.notifications || [];
    const completedNote = facultyNotes.find((n) => n.type === 'taskCompleted'
      && (n.payload || {}).taskId === handedId);
    ok('V8-X', 'with a completion notice that opens the task',
      Boolean(completedNote), completedNote ? '' : `${facultyNotes.length} notices`);
    facultySocket.close();
  }

  // --- the Super Admin is not stopped by the shape of the hierarchy ---------
  const superToMember = await api('/api/tasks', {
    method: 'POST', token: who.cmo.token,
    body: { title: 'A word, please', assignedTo: mateId },
  });
  ok('V8-H', 'The Super Admin can hand work to anybody by name',
    superToMember.status === 201, `got ${superToMember.status}`);
  const rehmanToMember = await api('/api/tasks', {
    method: 'POST', token: who.ceo.token,
    body: { title: 'Also a word', assignedTo: mateId },
  });
  ok('V8-H', 'where another Director still goes through the member\u2019s Lead',
    rehmanToMember.status === 403, `got ${rehmanToMember.status}`);
  const mateNotes = (await api('/api/notifications', { token: mate.token })).body.notifications || [];
  const fromSuper = mateNotes.find((n) => n.type === 'taskAssigned');
  ok('V8-H', 'and the notice names them the way the club does: "Club Director Mudabbir"',
    Boolean(fromSuper) && JSON.stringify(fromSuper).includes('Club Director Mudabbir'),
    fromSuper ? JSON.stringify(fromSuper.payload || fromSuper).slice(0, 120) : 'no notice');

  // ------------------------------------------ V8 records: edit, file, withdraw
  //
  // Three things the server supported and no screen offered, and one hole in
  // who may approve money.
  console.log('\nV8 records: editing events, removing documents, withdrawing bills');

  const plannedEvent = await api('/api/events', {
    method: 'POST',
    token: who.president.token,
    body: {
      name: 'Robotics Open Day',
      date: new Date(Date.now() + 12 * 864e5).toISOString(),
      venue: 'Main hall',
      organizingDepartmentId: tech.id,
      leadUserId: who.tech.user.id,
      responsibilities: [{ departmentId: production.id, tasks: [{ title: 'Stage for the demos' }] }],
    },
  });
  const plannedId = plannedEvent.body.event && plannedEvent.body.event.id;
  ok('V8-E', 'An event to edit', plannedEvent.status === 201, plannedEvent.txt.slice(0, 120));

  const movedEvent = await api(`/api/events/${plannedId}`, {
    method: 'PATCH', token: who.president.token, body: { venue: 'Seminar hall 2', startTime: '11:00' },
  });
  ok('V8-E', 'Its details can be changed after it exists', movedEvent.status === 200,
    movedEvent.txt.slice(0, 120));
  const prodNotes = (await api('/api/notifications', { token: who.production.token })).body.notifications || [];
  const movedNote = prodNotes.find((n) => n.type === 'eventUpdated'
    && (n.payload || {}).eventId === plannedId);
  ok('V8-E', 'and the Lead of a department working on it is told, with a notice that opens it',
    Boolean(movedNote), `${prodNotes.filter((n) => n.type === 'eventUpdated').length} event notices`);
  ok('V8-E', 'saying what moved',
    Boolean(movedNote) && /venue/.test(JSON.stringify(movedNote)) && /time/.test(JSON.stringify(movedNote)),
    movedNote ? JSON.stringify(movedNote.payload).slice(0, 140) : '');

  // --- documents --------------------------------------------------------------
  const linkedDoc = await api(`/api/events/${plannedId}/documents`, {
    method: 'POST', token: who.tech.token,
    body: { kind: 'file', title: 'Demo schedule', link: 'https://drive.google.com/demo-schedule' },
  });
  ok('V8-D', 'A document can be filed as a link', linkedDoc.status === 201, linkedDoc.txt.slice(0, 120));
  const docsForTech = (await api(`/api/events/${plannedId}/documents`, { token: who.tech.token })).body;
  const docsForMate = (await api(`/api/events/${plannedId}/documents`, { token: mate.token })).body;
  const techCopy = (docsForTech.files || []).find((d) => d.title === 'Demo schedule') || {};
  const mateCopy = (docsForMate.files || []).find((d) => d.title === 'Demo schedule') || {};
  ok('V8-D', 'Each document says whether the person looking may remove it',
    techCopy.canRemove === true && mateCopy.canRemove === false,
    `lead ${techCopy.canRemove} / member ${mateCopy.canRemove}`);
  const mateRemoves = await api(`/api/documents/${techCopy.id}`, { method: 'DELETE', token: mate.token });
  ok('V8-D', 'and the server agrees with the flag', mateRemoves.status === 403,
    `got ${mateRemoves.status}`);
  const techRemoves = await api(`/api/documents/${techCopy.id}`, { method: 'DELETE', token: who.tech.token });
  ok('V8-D', 'while the person who filed it can remove it', techRemoves.status === 200,
    `got ${techRemoves.status}`);

  // --- bills --------------------------------------------------------------------
  const rehmanBill = await api(`/api/events/${plannedId}/bills`, {
    method: 'POST', token: who.ceo.token,
    body: { title: 'Guest travel', amount: '1200', category: 'Travel' },
  });
  ok('V8-B', 'A Director can file an expense', rehmanBill.status === 201, rehmanBill.txt.slice(0, 120));
  const rehmanBillId = rehmanBill.body.id;

  const asRehman = (await api(`/api/events/${plannedId}/bills`, { token: who.ceo.token })).body;
  const ownCopy = (asRehman.bills || []).find((b) => b.id === rehmanBillId) || {};
  ok('V8-B', 'The filer is not offered Approve on their own expense',
    ownCopy.canDecide === false && ownCopy.canRemove === true,
    `canDecide ${ownCopy.canDecide} / canRemove ${ownCopy.canRemove}`);
  // The hole: supervisors cleared this check before anybody looked at the filer.
  const selfApprove = await api(`/api/bills/${rehmanBillId}/decision`, {
    method: 'POST', token: who.ceo.token, body: { status: 'approved' },
  });
  ok('V8-B', 'and a Director cannot approve their own expense',
    selfApprove.status === 403, `got ${selfApprove.status}`);

  const rejectedBill = await api(`/api/bills/${rehmanBillId}/decision`, {
    method: 'POST', token: who.cmo.token, body: { status: 'rejected', note: 'Covered by the college' },
  });
  ok('V8-B', 'Another Director can decide it', rejectedBill.status === 200, `got ${rejectedBill.status} ${rejectedBill.txt.slice(0, 160)}`);
  const afterReject = (await api(`/api/events/${plannedId}/bills`, { token: who.president.token })).body;
  const reportNow = (await api(`/api/events/${plannedId}/report`, { token: who.president.token })).body;
  ok('V8-B', 'A rejected claim is not counted as money the event spent',
    afterReject.totals && afterReject.totals.spent === 0,
    JSON.stringify(afterReject.totals || {}));
  ok('V8-B', 'so the Finance tab and the report agree',
    reportNow.derived && reportNow.derived.spentPaise === 0,
    `reportNow ${reportNow.derived && reportNow.derived.spentPaise}`);

  await api(`/api/events/${plannedId}`, { method: 'DELETE', token: who.president.token });
  await api(`/api/events/${plannedId}?purge=true`, { method: 'DELETE', token: who.president.token });

  // --------------------------------------------------------- V8 Home by role
  console.log('\nV8 Home: each role sees what its job turns on');
  const homeOf = async (w) => (await api('/api/home', { token: w.token })).body;
  const superHome = await homeOf(who.cmo);
  const presHome = await homeOf(who.president);
  const leadHome = await homeOf(who.tech);
  const mateHome = await homeOf(mate);
  ok('V8-HOME', 'The people running the club get the club in aggregate',
    superHome.overview && typeof superHome.overview.openWork === 'number'
    && presHome.overview && typeof presHome.overview.unassigned === 'number',
    JSON.stringify(superHome.overview || null).slice(0, 140));
  ok('V8-HOME', 'a Lead gets their department, triage pile first',
    !leadHome.overview && leadHome.myDepartment
    && typeof leadHome.myDepartment.incoming === 'number',
    JSON.stringify(leadHome.myDepartment || null));
  ok('V8-HOME', 'and a member gets neither — their own work is theirs to see',
    !mateHome.overview && !mateHome.myDepartment);

  // The triage count is real: send the Tech department something, and it moves.
  const incomingBefore = leadHome.myDepartment ? leadHome.myDepartment.incoming : 0;
  const sentToTech = await api('/api/tasks', {
    method: 'POST', token: who.president.token,
    body: { title: 'Wire the demo stage', departmentId: tech.id },
  });
  const deptAfter = (await homeOf(who.tech)).myDepartment || {};
  ok('V8-HOME', 'Work sent to a department lands in its Lead\u2019s count to hand out',
    sentToTech.status === 201 && deptAfter.incoming === incomingBefore + 1, `${incomingBefore} \u2192 ${deptAfter.incoming}`);

  // A Lead used to be shown the whole club's join queue, most of which they
  // could not action.
  const leadCaps = (await homeOf(who.tech)).capabilities || {};
  const clubJoins = (superHome.overview && superHome.overview.awaitingDecision
    && superHome.overview.awaitingDecision.joins) || 0;
  ok('V8-HOME', 'A Lead\u2019s join count is their own department\u2019s',
    leadCaps.pendingApprovals === (deptAfter.joins ?? -1),
    `lead sees ${leadCaps.pendingApprovals}, own dept ${deptAfter.joins}, club ${clubJoins}`);

  // ------------------------------------------------------------ V8.1 control
  //
  // The club's decision after V8: other people's names, passwords and roles
  // are the Club Director's alone; the other Directors remove Leads and
  // members and nobody above them; the Dashboard is the Club Director's.
  console.log('\nV8.1: the Club Director holds the keys');

  const stamp = Date.now();
  const spareSignup = await api('/api/auth/signup', {
    method: 'POST',
    body: {
      name: `Spare Member ${stamp}`, email: `spare.${stamp}@gwd.club`, phone: '9000000222',
      password: 'SparePass1', role: 'clubMember', departmentId: tech.id,
    },
  });
  const spareId = spareSignup.body.user && spareSignup.body.user.id;
  const sparePending = ((await api('/api/access/pending', { token: who.tech.token })).body.requests || [])
    .find((r) => r.userId === spareId);
  if (sparePending) {
    await api(`/api/access/${sparePending.id}/approve`, { method: 'POST', token: who.tech.token });
  }
  ok('V8.1', 'A throwaway member to act on', Boolean(spareId && sparePending));

  const rosterNow = (await api('/api/users', { token: who.cmo.token })).body.users || [];
  const mudabbir = rosterNow.find((u) => u.email === 'cmo@gwd.global') || {};
  ok('V8.1', 'He is "Club Director Mudabbir"; the others are Directors',
    mudabbir.superAdmin === true && mudabbir.knownAs === 'Mudabbir');

  // --- names --------------------------------------------------------------------
  const presRenames = await api(`/api/users/${spareId}/name`, {
    method: 'PATCH', token: who.president.token, body: { name: 'Renamed By The President' },
  });
  const rehmanRenames = await api(`/api/users/${spareId}/name`, {
    method: 'PATCH', token: who.ceo.token, body: { name: 'Renamed By Rehman' },
  });
  ok('V8.1', 'Neither the President nor another Director can change somebody\u2019s name',
    presRenames.status === 403 && rehmanRenames.status === 403,
    `${presRenames.status} / ${rehmanRenames.status}`);
  const superRenames = await api(`/api/users/${spareId}/name`, {
    method: 'PATCH', token: who.cmo.token, body: { name: 'Spare Member Renamed' },
  });
  ok('V8.1', 'The Club Director can', superRenames.status === 200, `got ${superRenames.status}`);

  // --- passwords --------------------------------------------------------------------
  const presResets = await api(`/api/users/${spareId}/reset-password`, {
    method: 'POST', token: who.president.token,
  });
  const rehmanResets = await api(`/api/users/${spareId}/reset-password`, {
    method: 'POST', token: who.ceo.token,
  });
  ok('V8.1', 'Neither the President nor another Director can reset somebody\u2019s password',
    presResets.status === 403 && rehmanResets.status === 403
    && !presResets.body.temporaryPassword && !rehmanResets.body.temporaryPassword,
    `${presResets.status} / ${rehmanResets.status}`);
  const superResets = await api(`/api/users/${spareId}/reset-password`, {
    method: 'POST', token: who.cmo.token,
  });
  ok('V8.1', 'The Club Director can, and is handed a temporary one',
    superResets.status === 200 && Boolean(superResets.body.temporaryPassword),
    `got ${superResets.status}`);

  // A forgotten password now reaches the one person who can act on it.
  await api('/api/auth/password/forgot', { method: 'POST', body: { email: `spare.${stamp}@gwd.club` } });
  const superHears = ((await api('/api/notifications', { token: who.cmo.token })).body.notifications || [])
    .some((n) => n.type === 'passwordResetRequested'
      && JSON.stringify(n.payload || {}).includes(`spare.${stamp}`));
  const presHears = ((await api('/api/notifications', { token: who.president.token })).body.notifications || [])
    .some((n) => n.type === 'passwordResetRequested'
      && JSON.stringify(n.payload || {}).includes(`spare.${stamp}`));
  ok('V8.1', '"Forgot password" asks the Club Director, not everybody who used to be able to',
    superHears && !presHears, `club director told: ${superHears}, president told: ${presHears}`);

  // --- roles, and a custom title ----------------------------------------------------
  const presRole = await api(`/api/users/${spareId}/role`, {
    method: 'PATCH', token: who.president.token, body: { role: 'clubLead' },
  });
  const rehmanRole = await api(`/api/users/${spareId}/role`, {
    method: 'PATCH', token: who.ceo.token, body: { role: 'clubLead' },
  });
  ok('V8.1', 'Neither the President nor another Director can change somebody\u2019s role',
    presRole.status === 403 && rehmanRole.status === 403, `${presRole.status} / ${rehmanRole.status}`);

  const titled = await api(`/api/users/${spareId}/role`, {
    method: 'PATCH', token: who.cmo.token, body: { role: 'clubMember', customTitle: 'Treasurer' },
  });
  ok('V8.1', 'The Club Director can give somebody a custom title',
    titled.status === 200 && titled.body.user && titled.body.user.customTitle === 'Treasurer',
    titled.txt.slice(0, 140));
  const spareLogin = await login(`spare.${stamp}@gwd.club`, superResets.body.temporaryPassword);
  const spareHome = spareLogin ? (await api('/api/home', { token: spareLogin.token })).body : {};
  ok('V8.1', 'and what they may do follows the role underneath it, not the title',
    // A member cannot broadcast to the club or manage departments; a title
    // that sounds senior changes neither.
    Boolean(spareLogin) && spareHome.capabilities && spareHome.capabilities.canBroadcast === false
    && spareHome.capabilities.canManageDepartments === false,
    JSON.stringify((spareHome.capabilities || {})).slice(0, 80));

  const moinTitled = await api(`/api/users/${who.director3.user.id}/role`, {
    method: 'PATCH', token: who.cmo.token, body: { customTitle: 'Director of Events' },
  });
  ok('V8.1', 'The Club Director can change a Director too', moinTitled.status === 200,
    `got ${moinTitled.status}`);
  await api(`/api/users/${who.director3.user.id}/role`, {
    method: 'PATCH', token: who.cmo.token, body: { customTitle: '' },
  });

  // --- removal --------------------------------------------------------------------------
  const rehmanCanRemovePres = ((await api(`/api/users/${who.president.user.id}/stats`,
    { token: who.ceo.token })).body.can || {}).remove;
  const superCanRemoveMoin = ((await api(`/api/users/${who.director3.user.id}/stats`,
    { token: who.cmo.token })).body.can || {}).remove;
  ok('V8.1', 'The Club Director may remove anybody, a Director included',
    superCanRemoveMoin === true, `${superCanRemoveMoin}`);
  const rehmanRemovesPres = await api(`/api/users/${who.president.user.id}`, {
    method: 'DELETE', token: who.ceo.token,
  });
  ok('V8.1', 'Another Director cannot remove the President',
    rehmanRemovesPres.status === 403 && rehmanCanRemovePres === false,
    `${rehmanRemovesPres.status} / flag ${rehmanCanRemovePres}`);
  const presRemoves = await api(`/api/users/${spareId}`, { method: 'DELETE', token: who.president.token });
  ok('V8.1', 'and the President cannot remove anybody', presRemoves.status === 403,
    `got ${presRemoves.status}`);
  const rehmanRemovesMember = await api(`/api/users/${spareId}`, { method: 'DELETE', token: who.ceo.token });
  ok('V8.1', 'but another Director can remove a member',
    rehmanRemovesMember.status === 200, `got ${rehmanRemovesMember.status}`);

  // --- the dashboard ---------------------------------------------------------------------
  const presDash = await api('/api/analytics', { token: who.president.token });
  const rehmanDash = await api('/api/analytics', { token: who.ceo.token });
  const superDash = await api('/api/analytics', { token: who.cmo.token });
  ok('V8.1', 'The Dashboard is the Club Director\u2019s alone',
    presDash.status === 403 && rehmanDash.status === 403 && superDash.status === 200,
    `president ${presDash.status}, rehman ${rehmanDash.status}, club director ${superDash.status}`);
  const presCaps = (await api('/api/home', { token: who.president.token })).body.capabilities || {};
  ok('V8.1', 'while the President still sees the approvals queue',
    presCaps.hasOversight === true && presCaps.canViewDashboard === false,
    JSON.stringify({ o: presCaps.hasOversight, d: presCaps.canViewDashboard }));

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

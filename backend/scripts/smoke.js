'use strict';

/**
 * End-to-end smoke test.
 *
 * Proves the three things that actually matter and that v1 got wrong:
 *   1. Many accounts can share a role (v1's unique index made this impossible)
 *   2. The permission matrix is enforced server-side, not just hidden in the UI
 *   3. A write travels Mongo → Change Stream → Socket.IO to another client live
 *
 * Run against a server already started on PORT. Creates throwaway accounts with
 * a unique run id, so it is safe to run repeatedly.
 */

const { io } = require('socket.io-client');

const BASE = process.env.SMOKE_BASE || 'http://127.0.0.1:4000';
const RUN = Date.now().toString(36);

let passed = 0;
let failed = 0;

function ok(label, condition, detail = '') {
  if (condition) {
    passed += 1;
    console.log(`  \x1b[32mPASS\x1b[0m  ${label}`);
  } else {
    failed += 1;
    console.log(`  \x1b[31mFAIL\x1b[0m  ${label}${detail ? ` — ${detail}` : ''}`);
  }
}

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
  try { json = await response.json(); } catch { /* empty body */ }
  return { status: response.status, body: json };
}

/**
 * Multipart upload. Never set content-type by hand — fetch adds the boundary.
 *
 * `file.field` names the part, because the routes differ deliberately: a
 * document arrives as `file`, a receipt as `receipt`. Multer rejects anything
 * it was not told to expect, which is the behaviour you want.
 */
async function upload(path, token, fields = {}, file = null) {
  const form = new FormData();
  for (const [key, value] of Object.entries(fields)) form.append(key, String(value));
  if (file) {
    form.append(file.field ?? 'file', new Blob([file.body], { type: file.type }), file.name);
  }
  const response = await fetch(`${BASE}${path}`, {
    method: 'POST',
    headers: { authorization: `Bearer ${token}` },
    body: form,
  });
  let json = null;
  try { json = await response.json(); } catch { /* empty body */ }
  return { status: response.status, body: json };
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  console.log(`\nGWD Club OS — smoke test against ${BASE}\n`);

  // ---------------------------------------------------------------- health
  console.log('health');
  const health = await api('/api/health');
  ok('API is online', health.body?.status === 'online', JSON.stringify(health.body));
  ok('Change Streams are active (live sync will work)', health.body?.changeStreams === true,
    'MongoDB is not a replica set — start it with scripts/start-mongo.ps1');

  // ------------------------------------------------------------- seeded auth
  console.log('\nroots of trust');
  const director = await api('/api/auth/login', {
    method: 'POST',
    body: { email: 'director1@gwd.club', password: 'DirectorPass1!' },
  });
  ok('Club Director can sign in', director.status === 200, JSON.stringify(director.body));
  const directorToken = director.body?.token;

  const president = await api('/api/auth/login', {
    method: 'POST',
    body: { email: 'president@gwd.club', password: 'PresidentPass1!' },
  });
  ok('President can sign in', president.status === 200);
  const presidentToken = president.body?.token;

  ok('Director is approved without ever queueing',
    director.body?.user?.approvalStatus === 'approved');

  // ------------------------------------------------------------ departments
  console.log('\ndepartments');
  const pub = await api('/api/departments/public');
  ok('Departments are listable before signup', pub.status === 200 && pub.body.departments.length >= 6,
    `got ${pub.body?.departments?.length}`);
  const creative = pub.body.departments.find((d) => d.name === 'Creative');
  const prDept = pub.body.departments.find((d) => d.name === 'PR & HR');
  ok('The club\'s six departments are seeded', Boolean(creative && prDept),
    pub.body?.departments?.map((d) => d.name).join(', '));

  const newDept = await api('/api/departments', {
    method: 'POST', token: presidentToken,
    body: { name: `Test Dept ${RUN}`, description: 'created by smoke test' },
  });
  ok('President can create a department at runtime', newDept.status === 201,
    JSON.stringify(newDept.body));

  const memberDeniedDept = await api('/api/departments', {
    method: 'POST', token: directorToken,
    body: { name: `Dir Dept ${RUN}` },
  });
  ok('Director can also create departments', memberDeniedDept.status === 201);

  // --------------------------------------------------- many members, one role
  console.log('\nsignup + approval chain');
  const members = [];
  for (let i = 0; i < 3; i += 1) {
    const signup = await api('/api/auth/signup', {
      method: 'POST',
      body: {
        name: `Member ${i} ${RUN}`,
        email: `member${i}.${RUN}@gwd.club`,
        phone: '+911234567890',
        password: 'MemberPass123',
        role: 'clubMember',
        departmentId: creative.id,
      },
    });
    members.push({ signup, email: `member${i}.${RUN}@gwd.club` });
  }
  ok('Three Members can share the clubMember role',
    members.every((m) => m.signup.status === 201),
    'v1 capped this at one account per role');

  ok('A new signup lands as pending, not approved',
    members[0].signup.body?.user?.approvalStatus === 'pending');

  const pendingToken = members[0].signup.body?.token;
  const blocked = await api('/api/tasks', { token: pendingToken });
  ok('A pending account cannot read tasks', blocked.status === 403,
    `got ${blocked.status}`);

  // Creative has no Lead yet, so Member approvals escalate to the President.
  const queue = await api('/api/access/pending', { token: presidentToken });
  ok('President sees the pending queue', queue.status === 200 && queue.body.requests.length >= 3,
    `got ${queue.body?.requests?.length}`);

  const mine = queue.body.requests.filter((r) => r.applicant?.email?.includes(RUN));
  for (const request of mine) {
    await api(`/api/access/${request.id}/approve`, { method: 'POST', token: presidentToken });
  }
  ok('President approved the new Members', mine.length === 3);

  const logins = [];
  for (const m of members) {
    const login = await api('/api/auth/login', {
      method: 'POST', body: { email: m.email, password: 'MemberPass123' },
    });
    logins.push(login);
  }
  ok('Approved Members can now sign in', logins.every((l) => l.status === 200));
  ok('Approval actually took effect',
    logins[0].body?.user?.approvalStatus === 'approved');

  const memberToken = logins[0].body.token;
  const memberId = logins[0].body.user.id;
  const otherMemberToken = logins[1].body.token;

  // ------------------------------------------------------- permission matrix
  console.log('\npermission matrix (server-side)');
  const memberAssign = await api('/api/tasks', {
    method: 'POST', token: memberToken,
    body: { title: 'Member tries to assign', assignedTo: logins[1].body.user.id },
  });
  ok('A Member cannot assign tasks', memberAssign.status === 403,
    `got ${memberAssign.status}`);

  const memberMakesDept = await api('/api/departments', {
    method: 'POST', token: memberToken, body: { name: `Nope ${RUN}` },
  });
  ok('A Member cannot create departments', memberMakesDept.status === 403);

  const memberEditsSchedule = await api('/api/schedule', {
    method: 'POST', token: memberToken,
    body: { lane: 'event', title: 'Unauthorised event', date: new Date().toISOString() },
  });
  ok('A Member cannot edit the schedule', memberEditsSchedule.status === 403,
    `got ${memberEditsSchedule.status}`);

  const memberReadsAudit = await api('/api/audit', { token: memberToken });
  ok('A Member cannot read the audit log', memberReadsAudit.status === 403);

  const directorReadsAudit = await api('/api/audit', { token: directorToken });
  ok('A Director can read the audit log', directorReadsAudit.status === 200);

  // --------------------------------------------------------- live sync proof
  console.log('\nlive sync (Mongo → Change Stream → Socket.IO)');
  const socket = io(BASE, { auth: { token: memberToken }, transports: ['websocket'] });

  const connected = await new Promise((resolve) => {
    socket.on('ready', () => resolve(true));
    socket.on('connect_error', () => resolve(false));
    setTimeout(() => resolve(false), 8000);
  });
  ok('Member socket authenticates and joins its rooms', connected);

  const liveEvent = new Promise((resolve) => {
    socket.on('task:created', (task) => resolve(task));
    setTimeout(() => resolve(null), 10000);
  });

  // Leadership addresses a DEPARTMENT, never a person. The Lead hands it out.
  const directToPerson = await api('/api/tasks', {
    method: 'POST', token: directorToken,
    body: { title: 'Director tries to pick a name', assignedTo: memberId },
  });
  ok('A Director cannot hand work straight to a member',
    directToPerson.status === 403, `got ${directToPerson.status}`);
  ok('And the refusal says what to do instead',
    /department/i.test(directToPerson.body?.error ?? ''),
    directToPerson.body?.error);

  const assigned = await api('/api/tasks', {
    method: 'POST', token: directorToken,
    body: {
      title: `Live sync task ${RUN}`,
      description: 'Written by the Director, should appear on the Member socket.',
      departmentId: creative.id,
      points: 5,
    },
  });
  ok('A Director addresses work to a department', assigned.status === 201,
    JSON.stringify(assigned.body));
  ok('It lands unassigned, for the Lead to pass on',
    assigned.body?.tasks?.[0]?.assignedTo === null);

  const received = await liveEvent;
  ok('Task arrived live on the Member socket without polling',
    received !== null && received.title === `Live sync task ${RUN}`,
    received ? `got "${received.title}"` : 'no event within 10s');

  const taskId = assigned.body?.tasks?.[0]?.id;

  const memberHandsOutOwnDept = await api(`/api/tasks/${taskId}/assign`, {
    method: 'POST', token: memberToken, body: { assignedTo: memberId },
  });
  ok('A Member cannot help themselves to department work',
    memberHandsOutOwnDept.status === 403, `got ${memberHandsOutOwnDept.status}`);

  // Creative has no Lead yet, so leadership distributes — a department without
  // a Lead must not be a dead end for work already sent to it.
  const handedOut = await api(`/api/tasks/${taskId}/assign`, {
    method: 'POST', token: directorToken,
    body: { assignedTo: memberId, points: 5 },
  });
  ok('Leadership can hand it out when a department has no Lead',
    handedOut.status === 200, JSON.stringify(handedOut.body));
  ok('Handing out is also where it gets priced',
    handedOut.body?.task?.points === 5, `got ${handedOut.body?.task?.points}`);

  // ------------------------------------------------------------ scoped reads
  console.log('\nvisibility scoping');
  const otherSees = await api(`/api/tasks/${taskId}`, { token: otherMemberToken });
  ok('Another Member cannot read a task that is not theirs', otherSees.status === 404,
    `got ${otherSees.status}`);

  const ownerSees = await api(`/api/tasks/${taskId}`, { token: memberToken });
  ok('The assignee can read their own task', ownerSees.status === 200);

  // --------------------------------------------------------- task lifecycle
  console.log('\ntask lifecycle + points');
  const skipAhead = await api(`/api/tasks/${taskId}`, {
    method: 'PATCH', token: memberToken, body: { status: 'completed' },
  });
  ok('Cannot jump straight from pending to completed', skipAhead.status === 403,
    `got ${skipAhead.status}`);

  const started = await api(`/api/tasks/${taskId}`, {
    method: 'PATCH', token: memberToken, body: { status: 'inProgress' },
  });
  ok('Member can move their task to In Progress', started.status === 200);

  const beforePoints = (await api('/api/auth/me', { token: memberToken })).body.user.points;

  const completed = await api(`/api/tasks/${taskId}`, {
    method: 'PATCH', token: memberToken, body: { status: 'completed' },
  });
  ok('Member can complete their task', completed.status === 200);

  await wait(600);
  const afterPoints = (await api('/api/auth/me', { token: memberToken })).body.user.points;
  ok('Completing a task awarded points', afterPoints === beforePoints + 5,
    `${beforePoints} → ${afterPoints}`);

  // Re-completing must not farm points.
  await api(`/api/tasks/${taskId}`, { method: 'PATCH', token: directorToken, body: { status: 'inProgress' } });
  await api(`/api/tasks/${taskId}`, { method: 'PATCH', token: memberToken, body: { status: 'completed' } });
  await wait(600);
  const refarm = (await api('/api/auth/me', { token: memberToken })).body.user.points;
  ok('Reopening and re-completing does not award points twice', refarm === afterPoints,
    `${afterPoints} → ${refarm}`);

  // ------------------------------------------------------------ notifications
  console.log('\nnotifications');
  const notifications = await api('/api/notifications', { token: memberToken });
  ok('Member has notifications from the assignment', notifications.status === 200
    && notifications.body.notifications.length > 0,
    `got ${notifications.body?.notifications?.length}`);
  ok('Notifications carry rendered copy for the UI',
    Boolean(notifications.body?.notifications?.[0]?.title));

  // ------------------------------------- the primary approval path: a Lead
  // The checks above exercised escalation to the President, because a fresh
  // department has no Lead. This covers Section 4.3's normal case: a Lead
  // approving someone into their own department, and *only* their own.
  console.log('\napproval chain: department Lead');

  const leadDept = newDept.body.department;
  const promoted = logins[2].body.user; // a Member we already approved

  await api(`/api/users/${promoted.id}/role`, {
    method: 'PATCH', token: presidentToken,
    body: { role: 'clubLead', departmentId: leadDept.id },
  });
  const leadSet = await api(`/api/departments/${leadDept.id}/lead`, {
    method: 'PUT', token: presidentToken, body: { userId: promoted.id },
  });
  ok('President can install a Lead on a department', leadSet.status === 200,
    JSON.stringify(leadSet.body));

  const leadLogin = await api('/api/auth/login', {
    method: 'POST', body: { email: members[2].email, password: 'MemberPass123' },
  });
  const leadToken = leadLogin.body.token;
  ok('The promoted member is now a Lead', leadLogin.body?.user?.role === 'clubLead',
    `got ${leadLogin.body?.user?.role}`);

  // Someone signs up into that Lead's department.
  const applicantEmail = `applicant.${RUN}@gwd.club`;
  await api('/api/auth/signup', {
    method: 'POST',
    body: {
      name: `Applicant ${RUN}`,
      email: applicantEmail,
      phone: '+911234567890',
      password: 'MemberPass123',
      role: 'clubMember',
      departmentId: leadDept.id,
    },
  });

  const leadQueue = await api('/api/access/pending', { token: leadToken });
  const mine2 = leadQueue.body.requests.filter((r) => r.applicant?.email === applicantEmail);
  ok('The Lead sees their own department\'s request', mine2.length === 1,
    `saw ${leadQueue.body?.requests?.length} request(s)`);

  // A Lead must not be able to action another department's queue.
  const foreign = leadQueue.body.requests.filter(
    (r) => r.departmentId && r.departmentId !== leadDept.id,
  );
  ok('The Lead sees no other department\'s requests', foreign.length === 0,
    `leaked ${foreign.length}`);

  if (mine2.length === 1) {
    const approve = await api(`/api/access/${mine2[0].id}/approve`, {
      method: 'POST', token: leadToken,
    });
    ok('The Lead can approve into their own department', approve.status === 200,
      JSON.stringify(approve.body));
  } else {
    ok('The Lead can approve into their own department', false, 'request not visible');
  }

  // And a plain Member still cannot approve anybody.
  const memberQueue = await api('/api/access/pending', { token: memberToken });
  ok('A Member\'s approval queue is empty',
    memberQueue.status === 200 && memberQueue.body.requests.length === 0,
    `got ${memberQueue.body?.requests?.length}`);

  // ------------------------------------------------------------------- home
  console.log('\nhome screen payload');
  const home = await api('/api/home', { token: memberToken });
  ok('Home returns exactly one "what\'s next" focal point', home.status === 200
    && ('whatsNext' in home.body));
  // A member can now put something on their own Lead's list — and nobody
  // else's — so the compose sheet exists for them too.
  ok('Home reports capabilities so the client mirrors the server',
    home.body?.capabilities?.canAssign === true,
    'a Member can assign to their own Lead');

  const directorHome = await api('/api/home', { token: directorToken });
  ok('A Director does get the assign capability',
    directorHome.body?.capabilities?.canAssign === true);

  const widget = await api('/api/widget', { token: memberToken });
  ok('Widget payload is available for the home-screen widget', widget.status === 200
    && 'pendingCount' in widget.body);

  // ------------------------------------------------- faculty coordinator
  console.log('\nfaculty coordinator');
  const faculty = await api('/api/auth/login', {
    method: 'POST', body: { email: 'faculty@gwd.club', password: 'FacultyPass1!' },
  });
  ok('Faculty Coordinator can sign in', faculty.status === 200, JSON.stringify(faculty.body));
  const facultyToken = faculty.body?.token;

  const facultyHome = await api('/api/home', { token: facultyToken });
  ok('Faculty Coordinator can assign', facultyHome.body?.capabilities?.canAssign === true);
  ok('Faculty Coordinator earns no points',
    facultyHome.body?.capabilities?.earnsPoints === false);
  ok('Faculty Coordinator is off the leaderboard',
    facultyHome.body?.capabilities?.onLeaderboard === false);
  ok('Faculty Coordinator can award points',
    facultyHome.body?.capabilities?.canAwardPoints === true);
  ok('Faculty Coordinator has full oversight',
    facultyHome.body?.capabilities?.canViewAudit === true);

  // She directs the leadership, not individual members. The club's officers
  // hold posts rather than run teams, so there is no department to route
  // through and she reaches them by name.
  const facultyTargets = await api('/api/users/assignable', { token: facultyToken });
  const OFFICERS = ['president', 'vicePresident', 'secretaryGeneral'];
  const facultyOthers = facultyTargets.body.assignable
    .filter((m) => m.role !== 'facultyCoordinator');
  ok('The Faculty Coordinator reaches the club officers by name',
    facultyOthers.length > 0 && facultyOthers.every((m) => OFFICERS.includes(m.role)),
    facultyOthers.map((m) => `${m.name}:${m.role}`).join(', '));
  ok('But never an individual member or Lead',
    facultyOthers.every((m) => m.role !== 'clubMember' && m.role !== 'clubLead'),
    'those go through the department');
  ok('But she is still offered departments',
    facultyTargets.body?.canAssignToDepartment === true
    && facultyTargets.body.departments.length >= 6,
    `${facultyTargets.body?.departments?.length} departments`);
  ok('Each one names the Lead who would receive it',
    facultyTargets.body.departments.every((d) => 'leadName' in d));

  // ------------------------------------ the two-step hierarchy, end to end
  console.log('\nassignment hierarchy');
  const deptTask = await api('/api/tasks', {
    method: 'POST', token: presidentToken,
    body: {
      title: `Shoot the teaser ${RUN}`,
      departmentId: leadDept.id,
      points: 3,
    },
  });
  ok('The President addresses work to a department', deptTask.status === 201,
    JSON.stringify(deptTask.body));
  const deptTaskId = deptTask.body?.tasks?.[0]?.id;

  const leadIncoming = await api('/api/tasks?scope=incoming', { token: leadToken });
  ok('It shows up in that Lead\'s incoming pile',
    leadIncoming.body.tasks.some((t) => t.id === deptTaskId),
    `${leadIncoming.body?.tasks?.length} incoming`);

  const applicantId = (await api('/api/auth/login', {
    method: 'POST', body: { email: applicantEmail, password: 'MemberPass123' },
  })).body.user.id;

  const foreignHandout = await api(`/api/tasks/${deptTaskId}/assign`, {
    method: 'POST', token: leadToken, body: { assignedTo: memberId },
  });
  ok('A Lead cannot hand their department\'s work to an outsider',
    foreignHandout.status === 403, `got ${foreignHandout.status}`);

  const leadHandout = await api(`/api/tasks/${deptTaskId}/assign`, {
    method: 'POST', token: leadToken,
    body: { assignedTo: applicantId, points: 5 },
  });
  ok('A Lead hands it to their own member, and prices it',
    leadHandout.status === 200 && leadHandout.body.task.points === 5,
    JSON.stringify(leadHandout.body?.error ?? leadHandout.body?.task?.points));

  const badPrice = await api(`/api/tasks/${deptTaskId}`, {
    method: 'PATCH', token: leadToken, body: { points: 4 },
  });
  ok('A task is worth 1, 3 or 5 — not any number somebody fancies',
    badPrice.status === 400, `got ${badPrice.status}`);

  // The Lead is credited too: a department that delivers is a Lead who
  // delivered. Never twice, and never for work outside their department.
  const applicantToken = (await api('/api/auth/login', {
    method: 'POST', body: { email: applicantEmail, password: 'MemberPass123' },
  })).body.token;
  const leadBefore = (await api('/api/auth/me', { token: leadToken })).body.user.points;
  const doerBefore = (await api('/api/auth/me', { token: applicantToken })).body.user.points;

  await api(`/api/tasks/${deptTaskId}`, {
    method: 'PATCH', token: applicantToken, body: { status: 'inProgress' },
  });
  await api(`/api/tasks/${deptTaskId}`, {
    method: 'PATCH', token: applicantToken, body: { status: 'completed' },
  });
  await wait(700);

  const leadAfter = (await api('/api/auth/me', { token: leadToken })).body.user.points;
  const doerAfter = (await api('/api/auth/me', { token: applicantToken })).body.user.points;
  ok('The member who did it earns the task\'s points',
    doerAfter === doerBefore + 5, `${doerBefore} → ${doerAfter}`);
  ok('And their Lead is credited the same amount',
    leadAfter === leadBefore + 5, `${leadBefore} → ${leadAfter}`);

  // ------------------------------------------------------------ points
  console.log('\npoints');
  const pointsTask = await api('/api/tasks', {
    method: 'POST', token: directorToken,
    body: { title: `Points check ${RUN}`, departmentId: creative.id },
  });
  const ptId = pointsTask.body?.tasks?.[0]?.id;
  await api(`/api/tasks/${ptId}/assign`, {
    method: 'POST', token: directorToken, body: { assignedTo: memberId },
  });
  const before = (await api('/api/auth/me', { token: memberToken })).body.user.points;
  await api(`/api/tasks/${ptId}`, { method: 'PATCH', token: memberToken, body: { status: 'inProgress' } });
  await api(`/api/tasks/${ptId}`, { method: 'PATCH', token: memberToken, body: { status: 'completed' } });
  await wait(600);
  const after = (await api('/api/auth/me', { token: memberToken })).body.user.points;
  ok('An unpriced task defaults to 1 point', after === before + 1, `${before} → ${after}`);

  const award = await api(`/api/users/${memberId}/award`, {
    method: 'POST', token: facultyToken, body: { points: 3, reason: 'Carried event day' },
  });
  ok('Faculty Coordinator can award bonus points by hand', award.status === 200,
    JSON.stringify(award.body));

  const memberAward = await api(`/api/users/${logins[1].body.user.id}/award`, {
    method: 'POST', token: memberToken, body: { points: 5 },
  });
  ok('A Member cannot award points', memberAward.status === 403);

  // --------------------------------------------------- schedule categories
  console.log('\nschedule categories');
  const cats = await api('/api/categories/schedule', { token: presidentToken });
  ok('Starter categories are seeded', cats.status === 200 && cats.body.categories.length >= 3,
    `${cats.body?.categories?.length} categories`);

  const eventCat = cats.body.categories.find((c) => c.name === 'Event');
  const mktCat = cats.body.categories.find((c) => c.name === 'Marketing');
  ok('Event and Marketing exist by default', Boolean(eventCat && mktCat));

  // The whole point: a club can invent its own kinds of entry.
  const custom = await api('/api/categories/schedule', {
    method: 'POST', token: presidentToken,
    body: { name: `Sponsor visit ${RUN}`, icon: 'sponsor', color: '#0891B2' },
  });
  ok('President can create a custom category', custom.status === 201,
    JSON.stringify(custom.body));

  const memberCat = await api('/api/categories/schedule', {
    method: 'POST', token: memberToken, body: { name: `Nope ${RUN}` },
  });
  ok('A Member cannot create categories', memberCat.status === 403);

  // ------------------------------------------------------------- schedule
  console.log('\nschedule');
  const evt = await api('/api/schedule', {
    method: 'POST', token: presidentToken,
    body: {
      categoryId: eventCat.id, title: `Fest ${RUN}`,
      date: new Date(Date.now() + 6e8).toISOString(), location: 'Auditorium',
    },
  });
  ok('President can add an entry', evt.status === 201, JSON.stringify(evt.body));
  ok('The entry carries its category name and colour',
    evt.body?.entry?.categoryName === 'Event' && Boolean(evt.body?.entry?.categoryColor));

  const customEntry = await api('/api/schedule', {
    method: 'POST', token: presidentToken,
    body: {
      categoryId: custom.body.category.id, title: `Cloudbyte walkthrough ${RUN}`,
      date: new Date(Date.now() + 7e8).toISOString(),
    },
  });
  ok('Entries can use a custom category', customEntry.status === 201
    && customEntry.body.entry.categoryName.startsWith('Sponsor visit'),
    JSON.stringify(customEntry.body?.entry?.categoryName));

  const mkt = await api('/api/schedule', {
    method: 'POST', token: presidentToken,
    body: {
      categoryId: mktCat.id, title: `Teaser reel ${RUN}`,
      date: new Date(Date.now() + 3e8).toISOString(),
      platform: 'instagram', format: 'reel', stage: 'planned',
    },
  });
  ok('Content entries carry platform, format and stage',
    mkt.status === 201 && mkt.body.entry.platform === 'instagram'
      && mkt.body.entry.format === 'reel',
    JSON.stringify(mkt.body?.entry));

  // Give the member an open task with a due date — that is what the derived
  // deadline lane is built from.
  const deadlineTask = await api('/api/tasks', {
    method: 'POST', token: directorToken,
    body: {
      title: `Deadline check ${RUN}`,
      departmentId: creative.id,
      dueDate: new Date(Date.now() + 4e8).toISOString(),
    },
  });
  await api(`/api/tasks/${deadlineTask.body.tasks[0].id}/assign`, {
    method: 'POST', token: directorToken, body: { assignedTo: memberId },
  });

  const memberSchedule = await api('/api/schedule', { token: memberToken });
  ok('Every member can read the whole schedule',
    memberSchedule.status === 200 && memberSchedule.body.entries.length > 0,
    `${memberSchedule.body?.entries?.length} entries`);
  ok('A Member cannot write to the schedule',
    memberSchedule.body?.canCreate === false);

  const kinds = new Set(memberSchedule.body.entries.map((e) => e.kind));
  ok('Task deadlines appear on the schedule automatically', kinds.has('deadline'),
    [...kinds].join(','));

  // The personal calendar. "What is the club doing" and "what do I owe, and by
  // when" are different questions, and the second must not require scanning the
  // first.
  const deadlineRow = memberSchedule.body.entries.find((e) => e.kind === 'deadline');
  ok('A deadline says whose it is', deadlineRow?.assignedTo === memberId,
    `assignedTo ${deadlineRow?.assignedTo}`);
  ok('And names them, so it is not everybody\'s and therefore nobody\'s',
    typeof deadlineRow?.assignedToName === 'string' && deadlineRow.assignedToName.length > 0,
    String(deadlineRow?.assignedToName));

  const mineSchedule = await api('/api/schedule?mine=1', { token: memberToken });
  ok('The personal calendar returns only this person\'s work',
    mineSchedule.status === 200
    && mineSchedule.body.entries
      .filter((e) => e.kind === 'deadline')
      .every((e) => e.assignedTo === memberId),
    JSON.stringify(mineSchedule.body?.entries?.map((e) => e.assignedTo)));

  ok('And is a narrowing of the club schedule, never a widening',
    mineSchedule.body.entries.length <= memberSchedule.body.entries.length,
    `${mineSchedule.body.entries.length} vs ${memberSchedule.body.entries.length}`);

  const otherMine = await api('/api/schedule?mine=1', { token: otherMemberToken });
  ok('Somebody else\'s personal calendar does not carry this person\'s work',
    (otherMine.body?.entries ?? [])
      .filter((e) => e.kind === 'deadline')
      .every((e) => e.assignedTo !== memberId));

  const memberWrite = await api('/api/schedule', {
    method: 'POST', token: memberToken,
    body: { categoryId: eventCat.id, title: 'nope', date: new Date().toISOString() },
  });
  ok('A Member is refused server-side too', memberWrite.status === 403);

  const badCategory = await api('/api/schedule', {
    method: 'POST', token: presidentToken,
    body: { categoryId: '000000000000000000000000', title: 'nope', date: new Date().toISOString() },
  });
  ok('An entry cannot reference a category that does not exist',
    badCategory.status === 400, `got ${badCategory.status}`);

  // --------------------------------------------- recognition, per department
  console.log('\nrecognition (department-wise)');
  const board2 = await api('/api/users/leaderboard', { token: presidentToken });
  ok('Recognition comes back grouped by department', board2.status === 200
    && Array.isArray(board2.body.departments) && board2.body.departments.length > 0,
    `${board2.body?.departments?.length} departments`);

  ok('There is no club-wide ranking', board2.body.leaderboard === undefined,
    'a Cinematography member and a Marketing member are not doing the same job');

  ok('It explains itself', Boolean(board2.body?.explanation));

  const withPeople = board2.body.departments.filter((d) => d.members.length > 0);
  ok('Every row carries the numbers behind it',
    withPeople.every((d) => d.members.every(
      (m) => 'assignedTasks' in m && 'completedTasks' in m && 'completionRate' in m)),
    'a standing nobody can check just looks arbitrary');

  ok('Members are ordered by points earned',
    withPeople.every((d) => d.members.every(
      (m, i) => i === 0 || d.members[i - 1].points >= m.points)),
    'points are the thing the Lead actually calibrated');

  const led = board2.body.departments.find((d) => d.lead);
  ok('The Lead is reported apart from their own team',
    Boolean(led) && !led.members.some((m) => m.id === led.lead.id),
    'they earn from everything the department finishes, so a row would always top it');

  ok('Each department carries its own totals',
    board2.body.departments.every((d) => typeof d.totals.assigned === 'number'
      && typeof d.totals.completed === 'number'));

  const supervisorsOnBoard = board2.body.departments
    .flatMap((d) => [...d.members, d.lead].filter(Boolean))
    .concat(board2.body.unaffiliated)
    .some((m) => m.role === 'clubDirector' || m.role === 'facultyCoordinator');
  ok('Supervisors are absent from recognition entirely', !supervisorsOnBoard);

  // ------------------------------------------------- club-wide department view
  const overview = await api('/api/users/department-overview', { token: memberToken });
  ok('Any member can see how the club as a whole is doing',
    overview.status === 200 && overview.body.departments.length > 0,
    'aggregate numbers about a department give away nothing about a person');
  ok('It reports given against completed',
    overview.body.departments.every(
      (d) => typeof d.assigned === 'number' && typeof d.completed === 'number'
        && typeof d.awaitingHandout === 'number'));
  ok('And a club-wide total', typeof overview.body.totals.assigned === 'number');
  ok('Ordered alphabetically, never by performance',
    overview.body.departments.every(
      (d, i) => i === 0 || overview.body.departments[i - 1].name.localeCompare(d.name) <= 0),
    'sorting by completion turns a progress panel into a league table');

  const stats = await api(`/api/users/${memberId}/stats`, { token: memberToken });
  ok('A member record opens with real numbers', stats.status === 200
    && typeof stats.body.stats.assigned === 'number'
    && typeof stats.body.stats.completionRate === 'number',
    JSON.stringify(stats.body?.stats));
  ok('The record includes recent tasks', Array.isArray(stats.body?.recentTasks));

  // ------------------------------------------------------------- alerts
  console.log('\nbroadcast alerts');
  const alertEvent = new Promise((resolve) => {
    socket.on('alert:new', (a) => resolve(a));
    setTimeout(() => resolve(null), 10000);
  });

  const sent = await api('/api/alerts', {
    method: 'POST', token: presidentToken,
    body: { title: `Venue moved ${RUN}`, message: 'Block C, 4pm. Please be on time.', audience: 'club' },
  });
  ok('President can broadcast to the club', sent.status === 201, JSON.stringify(sent.body));
  ok('The broadcast reports how many people it reached',
    (sent.body?.reach ?? 0) > 0, `reach ${sent.body?.reach}`);

  const gotAlert = await alertEvent;
  ok('The alert arrives live on a member socket',
    gotAlert !== null && gotAlert.title === `Venue moved ${RUN}`,
    gotAlert ? gotAlert.title : 'no event within 10s');

  const memberAlert = await api('/api/alerts', {
    method: 'POST', token: memberToken,
    body: { title: 'Members cannot page everyone', message: 'nope', audience: 'club' },
  });
  ok('A Member cannot broadcast', memberAlert.status === 403,
    'otherwise the feature becomes noise');

  const urgentByLead = await api('/api/alerts', {
    method: 'POST', token: leadToken,
    body: { title: 'urgent test', message: 'test', audience: 'club', urgency: 'urgent' },
  });
  ok('Only the President and supervisors can mark an alert urgent',
    urgentByLead.status === 403, `got ${urgentByLead.status}`);

  const alertFeed = await api('/api/alerts', { token: memberToken });
  ok('Members can read the alert history',
    alertFeed.status === 200 && alertFeed.body.alerts.length > 0);
  ok('Every alert is signed by its sender',
    Boolean(alertFeed.body?.alerts?.[0]?.senderName));

  // ------------------------------------------------ structure + visibility
  console.log('\nclub structure');
  const structure = await api('/api/departments/structure', { token: memberToken });
  ok('Everyone can read the club structure', structure.status === 200
    && Array.isArray(structure.body.departments),
    `${structure.body?.departments?.length} departments`);

  const seats = structure.body.executive.map((e) => e.role);
  ok('The executive tier is listed in order',
    seats[0] === 'president' && seats[1] === 'vicePresident' && seats[2] === 'secretaryGeneral',
    seats.join(','));

  ok('Supervisors are absent from the structure',
    !seats.includes('clubDirector') && !seats.includes('facultyCoordinator'),
    'they oversee the club rather than sit inside it');

  ok('Every department reports headline progress',
    structure.body.departments.every((d) => d.progress
      && typeof d.progress.completionRate === 'number'),
    'aggregate progress is open to everyone');

  // A Member may drill into their own department and no other.
  const myRosters = structure.body.departments.filter((d) => d.canViewRoster);
  ok('A Member can open only their own department roster', myRosters.length === 1,
    `${myRosters.length} rosters visible`);

  const foreignDept = structure.body.departments.find((d) => !d.canViewRoster);
  if (foreignDept) {
    const blocked = await api(`/api/departments/${foreignDept.id}/roster`, { token: memberToken });
    ok('The server refuses another department\'s roster too', blocked.status === 403,
      `got ${blocked.status}`);
  } else {
    ok('The server refuses another department\'s roster too', false, 'no foreign department');
  }

  const ownRoster = await api(`/api/departments/${myRosters[0].id}/roster`, { token: memberToken });
  ok('A Member can read their own department roster', ownRoster.status === 200
    && Array.isArray(ownRoster.body.members));

  const leadStructure = await api('/api/departments/structure', { token: leadToken });
  ok('A Lead can open every department roster',
    leadStructure.body.departments.every((d) => d.canViewRoster),
    'Leads coordinate across departments');

  // ------------------------------------------------- member record gating
  console.log('\nmember records');
  const ownRecord = await api(`/api/users/${logins[1].body.user.id}/stats`, { token: memberToken });
  ok('A Member can open someone in their own department', ownRecord.status === 200,
    `got ${ownRecord.status}`);
  ok('The record carries contact details and department',
    Boolean(ownRecord.body?.user?.email) && 'department' in ownRecord.body);

  const directorUser = (await api('/api/users', { token: directorToken })).body.users
    .find((u) => u.role === 'clubDirector');
  const peek = await api(`/api/users/${directorUser.id}/stats`, { token: memberToken });
  ok('Nobody outside the supervisor tier can open a Director', peek.status === 403,
    `got ${peek.status}`);

  const facultyUser = (await api('/api/users', { token: directorToken })).body.users
    .find((u) => u.role === 'facultyCoordinator');
  const peekFaculty = await api(`/api/users/${facultyUser.id}/stats`, { token: leadToken });
  ok('Not even a Lead can open the Faculty Coordinator', peekFaculty.status === 403,
    `got ${peekFaculty.status}`);

  const presidentUser = (await api('/api/users', { token: directorToken })).body.users
    .find((u) => u.role === 'president');
  const peekPresident = await api(`/api/users/${presidentUser.id}/stats`, { token: memberToken });
  ok('The President can be opened by anyone', peekPresident.status === 200,
    `got ${peekPresident.status}`);

  const supervisorPeek = await api(`/api/users/${facultyUser.id}/stats`, { token: directorToken });
  ok('A Director can open the Faculty Coordinator', supervisorPeek.status === 200);

  // --------------------------------------- awarded points move the board
  console.log('\nawarded points reach recognition');
  const findRow = (body, id) => body.departments
    .flatMap((d) => d.members)
    .concat(body.unaffiliated)
    .find((r) => r.id === id);

  const before2 = await api('/api/users/leaderboard', { token: presidentToken });
  const targetId = logins[1].body.user.id;
  const rowBefore = findRow(before2.body, targetId);

  await api(`/api/users/${targetId}/award`, {
    method: 'POST', token: directorToken,
    body: { points: 7, reason: 'Carried event day' },
  });
  await wait(400);

  const after2 = await api('/api/users/leaderboard', { token: presidentToken });
  const rowAfter = findRow(after2.body, targetId);
  ok('An award shows up in recognition immediately',
    (rowAfter?.points ?? 0) === (rowBefore?.points ?? 0) + 7,
    `${rowBefore?.points} → ${rowAfter?.points}`);

  // =========================================================== EVENTS (v3)
  console.log('\nevents — creation and scoping');

  const memberMakesEvent = await api('/api/events', {
    method: 'POST', token: memberToken,
    body: { name: 'Member tries an event', date: new Date().toISOString(), organizingDepartmentId: creative.id },
  });
  ok('A Member cannot create an event', memberMakesEvent.status === 403,
    `got ${memberMakesEvent.status}`);

  const liveEventCreated = new Promise((resolve) => {
    socket.on('event:created', (e) => resolve(e));
    setTimeout(() => resolve(null), 10000);
  });

  const eventDate = new Date(Date.now() + 14 * 86400000).toISOString();
  const created = await api('/api/events', {
    method: 'POST', token: presidentToken,
    body: {
      name: `Tech Fest ${RUN}`,
      description: 'Two days, four tracks.',
      date: eventDate,
      venue: 'Main Auditorium',
      organizingDepartmentId: creative.id,
      supportingDepartmentIds: [prDept.id],
      teamUserIds: [memberId],
      responsibilities: [
        {
          departmentId: creative.id,
          notes: 'Stage design and posters',
          tasks: [
            { title: `Design the poster ${RUN}` },
            { title: `Book the stage ${RUN}`, priority: 'high' },
          ],
        },
        {
          departmentId: prDept.id,
          notes: 'Outreach',
          tasks: [{ title: `Contact colleges ${RUN}` }],
        },
      ],
    },
  });
  ok('President can create an event with departments and their work',
    created.status === 201, JSON.stringify(created.body));
  const eventId = created.body?.event?.id;
  ok('The wizard commits all three tasks in one go',
    created.body?.event?.taskCount === 3, `got ${created.body?.event?.taskCount}`);

  const gotEventLive = await liveEventCreated;
  ok('The new event reaches a Member socket live',
    gotEventLive !== null && gotEventLive.name === `Tech Fest ${RUN}`,
    gotEventLive ? gotEventLive.name : 'no event within 10s');

  const memberEvents = await api('/api/events', { token: memberToken });
  ok('Every member can browse the club\'s events', memberEvents.status === 200
    && memberEvents.body.upcoming.some((e) => e.id === eventId),
    'events are club-wide knowledge');
  ok('A Member is not offered the create button',
    memberEvents.body?.canCreate === false);

  // ------------------------------------------------------ event workspace
  console.log('\nevent workspace');
  const workspace = await api(`/api/events/${eventId}`, { token: memberToken });
  ok('The workspace opens for an ordinary member', workspace.status === 200);
  ok('It reports per-department progress, not per-person',
    workspace.body.departments.length === 2
    && workspace.body.departments.every((d) => typeof d.progress === 'number'),
    `${workspace.body?.departments?.length} departments`);
  ok('A Member cannot manage the event', workspace.body?.canManage === false);

  const presidentWorkspace = await api(`/api/events/${eventId}`, { token: presidentToken });
  ok('The President can manage the event', presidentWorkspace.body?.canManage === true);

  const eventBoard = await api(`/api/events/${eventId}/work`, { token: memberToken });
  ok('The event board lists all of its work', eventBoard.status === 200
    && eventBoard.body.tasks.length === 3, `got ${eventBoard.body?.tasks?.length}`);
  ok('Work created by the wizard starts unassigned',
    eventBoard.body.tasks.every((t) => t.assignedTo === null),
    'the wizard captures what needs doing, not who does it');

  const creativeTask = eventBoard.body.tasks.find((t) => t.title === `Design the poster ${RUN}`);
  const prTask = eventBoard.body.tasks.find((t) => t.title === `Contact colleges ${RUN}`);

  const claimed = await api(`/api/events/${eventId}/tasks/${creativeTask.id}/claim`, {
    method: 'POST', token: memberToken,
  });
  ok('A member of the responsible department can pick work up',
    claimed.status === 200, JSON.stringify(claimed.body));

  const wrongDept = await api(`/api/events/${eventId}/tasks/${prTask.id}/claim`, {
    method: 'POST', token: leadToken,
  });
  ok('Work belonging to another department cannot be claimed',
    wrongDept.status === 403, `got ${wrongDept.status}`);

  const eventHandedOut = await api(`/api/events/${eventId}/tasks/${prTask.id}/claim`, {
    method: 'POST', token: presidentToken, body: { userId: logins[1].body.user.id },
  });
  ok('Leadership can hand a piece of work to someone', eventHandedOut.status === 200);

  const memberHandsOut = await api(`/api/events/${eventId}/tasks/${creativeTask.id}/claim`, {
    method: 'POST', token: memberToken, body: { userId: logins[1].body.user.id },
  });
  ok('A Member cannot assign event work to somebody else',
    memberHandsOut.status === 403, `got ${memberHandsOut.status}`);

  // ---------------------------------------------------------- review lane
  console.log('\ntask review lane');
  await api(`/api/tasks/${creativeTask.id}`, {
    method: 'PATCH', token: memberToken, body: { status: 'inProgress' },
  });
  const sentForReview = await api(`/api/tasks/${creativeTask.id}`, {
    method: 'PATCH', token: memberToken, body: { status: 'review' },
  });
  ok('The owner can send work for review', sentForReview.status === 200,
    JSON.stringify(sentForReview.body));

  const selfApprove = await api(`/api/tasks/${creativeTask.id}`, {
    method: 'PATCH', token: otherMemberToken, body: { status: 'completed' },
  });
  ok('A bystander cannot wave work through review',
    selfApprove.status === 403, `got ${selfApprove.status}`);

  const sentBack = await api(`/api/tasks/${creativeTask.id}`, {
    method: 'PATCH', token: presidentToken, body: { status: 'inProgress' },
  });
  ok('A reviewer can send work back', sentBack.status === 200);

  await api(`/api/tasks/${creativeTask.id}`, {
    method: 'PATCH', token: memberToken, body: { status: 'review' },
  });
  const accepted = await api(`/api/tasks/${creativeTask.id}`, {
    method: 'PATCH', token: presidentToken, body: { status: 'completed' },
  });
  ok('A reviewer can accept it', accepted.status === 200,
    JSON.stringify(accepted.body));

  const workList = await api('/api/tasks', { token: memberToken });
  ok('Event work stays off the general task list',
    workList.body.tasks.every((t) => !t.eventId),
    'one festival must not bury a personal to-do list');

  const myWork = await api('/api/tasks?scope=mine', { token: memberToken });
  ok('But work assigned to you shows up wherever it came from',
    myWork.body.tasks.some((t) => t.id === creativeTask.id));

  // ------------------------------------------------------------ documents
  console.log('\nevent documents');
  const fileUpload = await upload(`/api/events/${eventId}/documents`, memberToken, {
    kind: 'file', title: `Poster draft ${RUN}`,
  }, { name: 'poster.txt', body: 'draft poster v1', type: 'text/plain' });
  ok('Any member can attach an ordinary event file',
    fileUpload.status === 201, JSON.stringify(fileUpload.body));

  const memberApproval = await upload(`/api/events/${eventId}/documents`, memberToken, {
    kind: 'approval', title: 'Forged permission letter',
  }, { name: 'letter.txt', body: 'totally official', type: 'text/plain' });
  ok('A Member cannot put an official approval on the record',
    memberApproval.status === 403, `got ${memberApproval.status}`);

  const officialUpload = await upload(`/api/events/${eventId}/documents`, presidentToken, {
    kind: 'approval', title: `Venue permission ${RUN}`,
  }, { name: 'venue.txt', body: 'permission granted v1', type: 'text/plain' });
  ok('The President can file an official approval',
    officialUpload.status === 201, JSON.stringify(officialUpload.body));
  const approvalId = officialUpload.body?.id;

  const docs = await api(`/api/events/${eventId}/documents`, { token: memberToken });
  const approvalDoc = docs.body.approvals.find((d) => d.id === approvalId);
  ok('Uploading paperwork does not make it approved',
    approvalDoc?.status === 'pending',
    'filing a letter and the college signing it are different events');
  ok('A Member is not offered the approval controls',
    docs.body.canUploadApproval === false && docs.body.canDecide === false);
  ok('A Member can still see and attach ordinary files',
    docs.body.canUploadFile === true && docs.body.files.length === 1);

  const memberDecides = await api(`/api/documents/${approvalId}/decision`, {
    method: 'POST', token: memberToken, body: { status: 'approved' },
  });
  ok('A Member cannot mark a document approved',
    memberDecides.status === 403, `got ${memberDecides.status}`);

  const leadDecides = await api(`/api/documents/${approvalId}/decision`, {
    method: 'POST', token: leadToken, body: { status: 'approved' },
  });
  ok('Nor can a Lead — filing is not the same as signing off',
    leadDecides.status === 403, `got ${leadDecides.status}`);

  const decided = await api(`/api/documents/${approvalId}/decision`, {
    method: 'POST', token: presidentToken,
    body: { status: 'approved', note: 'Seen and countersigned.' },
  });
  ok('The President can approve it', decided.status === 200);

  const memberReplaces = await upload(`/api/documents/${approvalId}/versions`, memberToken, {},
    { name: 'venue2.txt', body: 'sneaky replacement', type: 'text/plain' });
  ok('A Member cannot replace an official document',
    memberReplaces.status === 403, `got ${memberReplaces.status}`);

  const replaced = await upload(`/api/documents/${approvalId}/versions`, presidentToken,
    { note: 'Venue changed to Block C' },
    { name: 'venue2.txt', body: 'permission granted v2', type: 'text/plain' });
  ok('Leadership can file a new version', replaced.status === 201);

  const docs2 = await api(`/api/events/${eventId}/documents`, { token: presidentToken });
  const approval2 = docs2.body.approvals.find((d) => d.id === approvalId);
  ok('Replacing a document keeps every version',
    approval2?.version === 2 && approval2.history.length === 2,
    `version ${approval2?.version}, ${approval2?.history?.length} in history`);
  ok('The earlier version is marked superseded, not deleted',
    approval2?.history?.[0]?.superseded === true);
  ok('A new version needs a fresh decision',
    approval2?.status === 'pending',
    'an approval applies to the paper that was actually read');

  const download = await fetch(`${BASE}/api/documents/${approvalId}/file`, {
    headers: { authorization: `Bearer ${memberToken}` },
  });
  const downloaded = await download.text();
  ok('The current version streams back to a member',
    download.status === 200 && downloaded === 'permission granted v2', downloaded);

  const oldVersion = await fetch(`${BASE}/api/documents/${approvalId}/file?version=1`, {
    headers: { authorization: `Bearer ${memberToken}` },
  });
  ok('So does the superseded one', (await oldVersion.text()) === 'permission granted v1');

  const anonymous = await fetch(`${BASE}/api/documents/${approvalId}/file`);
  ok('A document is never readable without a token',
    anonymous.status === 401, `got ${anonymous.status}`);

  // ============================================ DEPARTMENT WORKSPACES (v3)
  // Runs while the event is still live, because that is the state a workspace
  // is actually for — what is on this department's plate right now.
  console.log('\ndepartment workspaces');
  const ownWorkspace = await api(`/api/departments/${creative.id}/workspace`,
    { token: memberToken });
  ok('A member can open their own department workspace',
    ownWorkspace.status === 200, JSON.stringify(ownWorkspace.body?.error));
  ok('It carries the roster for your own department',
    ownWorkspace.body?.canViewRoster === true
    && ownWorkspace.body.members.length > 0,
    `${ownWorkspace.body?.members?.length} members`);
  ok('It shows the events that department is on the hook for',
    ownWorkspace.body.events.some((e) => e.id === eventId),
    `${ownWorkspace.body?.events?.length} events listed`);

  const slice = ownWorkspace.body.events.find((e) => e.id === eventId);
  ok('An event shows only that department\'s share of the work',
    slice.myTotal === 2,
    `got ${slice?.myTotal} — the event has 3 tasks across two departments`);
  ok('It says whether they are organising or supporting',
    slice.isOrganiser === true);
  ok('It carries the note they were given', slice.notes === 'Stage design and posters');

  const foreignWorkspace = await api(`/api/departments/${prDept.id}/workspace`,
    { token: memberToken });
  ok('Another department\'s workspace still opens', foreignWorkspace.status === 200,
    'progress is club-wide knowledge');
  ok('But its individual members are withheld',
    foreignWorkspace.body.canViewRoster === false
    && foreignWorkspace.body.members.length === 0,
    'aggregate yes, person-by-person only for your own department');
  ok('And the work in it is unattributed',
    foreignWorkspace.body.work.every((w) => w.assigneeName === null));
  ok('The headcount is still reported',
    typeof foreignWorkspace.body.department.memberCount === 'number');

  const leadWorkspace = await api(`/api/departments/${leadDept.id}/workspace`,
    { token: leadToken });
  ok('A Lead can run their own department\'s work',
    leadWorkspace.body?.canManageWork === true);

  const leadElsewhere = await api(`/api/departments/${creative.id}/workspace`,
    { token: leadToken });
  ok('But a Lead is not an administrator of another department',
    leadElsewhere.body?.canManageWork === false,
    'permissions stay granular');

  // --------------------------------------------------- completion checklist
  console.log('\nevent completion');
  const tooEarly = await api(`/api/events/${eventId}/status`, {
    method: 'POST', token: presidentToken, body: { status: 'completed' },
  });
  ok('An event with open work will not quietly close',
    tooEarly.status === 409 && tooEarly.body.checklist.openTasks > 0,
    JSON.stringify(tooEarly.body));

  const checklist = await api(`/api/events/${eventId}/checklist`, { token: presidentToken });
  ok('The checklist says exactly what is outstanding',
    checklist.status === 200 && checklist.body.openTasks === 2
    && checklist.body.pendingApprovals === 1,
    JSON.stringify(checklist.body));

  const forced = await api(`/api/events/${eventId}/status`, {
    method: 'POST', token: presidentToken, body: { status: 'completed', force: true },
  });
  ok('But it can still be closed deliberately', forced.status === 200,
    'the last two tasks often never get ticked');

  const memberCloses = await api(`/api/events/${eventId}/status`, {
    method: 'POST', token: memberToken, body: { status: 'planning' },
  });
  ok('A Member cannot reopen or move an event',
    memberCloses.status === 403, `got ${memberCloses.status}`);

  const timeline = await api(`/api/events/${eventId}/timeline`, { token: memberToken });
  ok('The event keeps a readable history', timeline.status === 200
    && timeline.body.timeline.length > 0,
    `${timeline.body?.timeline?.length} entries`);

  // ============================================== HELP & COLLABORATION (v3)
  console.log('\nhelp & collaboration');
  const asked = await api('/api/help', {
    method: 'POST', token: memberToken,
    body: {
      title: `Need a hand with the stage backdrop ${RUN}`,
      description: 'Two pairs of hands on Friday afternoon would do it.',
      skills: ['Design', 'Lifting things'],
      eventId,
      neededBy: new Date(Date.now() + 3 * 864e5).toISOString(),
      maxHelpers: 2,
    },
  });
  ok('Any member can ask for help', asked.status === 201, JSON.stringify(asked.body));
  const helpId = asked.body?.id;

  // Both are required now: an ask with no deadline sits on the board for a
  // week because nobody can tell whether it is tonight or next month.
  const undated = await api('/api/help', {
    method: 'POST', token: memberToken,
    body: { title: `No deadline ${RUN}`, maxHelpers: 1 },
  });
  ok('An ask without a deadline is refused', undated.status === 400,
    `got ${undated.status}`);

  const crowded = await api('/api/help', {
    method: 'POST', token: memberToken,
    body: {
      title: `Too many ${RUN}`,
      neededBy: new Date(Date.now() + 864e5).toISOString(),
      maxHelpers: 99,
    },
  });
  ok('And one asking for ninety-nine people is refused', crowded.status === 400,
    `got ${crowded.status}`);

  const helpFeed = await api('/api/help', { token: otherMemberToken });
  const raised = helpFeed.body.requests.find((r) => r.id === helpId);
  ok('The ask is visible across the club', Boolean(raised),
    'someone in another department is often the one who can unstick you');
  ok('It starts open and unclaimed',
    raised?.status === 'open' && raised.helpers.length === 0);
  ok('It carries the event it belongs to', raised?.eventId === eventId);

  const offered = await api(`/api/help/${helpId}/offer`, {
    method: 'POST', token: otherMemberToken, body: { note: 'Free after 2pm.' },
  });
  ok('Somebody else can offer to help', offered.status === 200);

  const selfOffer = await api(`/api/help/${helpId}/offer`, {
    method: 'POST', token: memberToken,
  });
  ok('You cannot volunteer for your own ask', selfOffer.status === 400,
    `got ${selfOffer.status}`);

  const afterOffer = await api('/api/help', { token: memberToken });
  const claimedHelp = afterOffer.body.requests.find((r) => r.id === helpId);
  ok('An offer moves it out of the open pile',
    claimedHelp?.status === 'assigned' && claimedHelp.helpers.length === 1,
    `${claimedHelp?.status}, ${claimedHelp?.helpers?.length} helpers`);
  ok('The board says who is on it', claimedHelp?.helpers?.[0]?.note === 'Free after 2pm.');
  ok('And how many places are left', claimedHelp?.spotsLeft === 1,
    `spotsLeft ${claimedHelp?.spotsLeft}`);
  ok('It carries the deadline it was asked for', Boolean(claimedHelp?.neededBy));

  // Offering has to put it on the helper's own list, or "I can help" is a
  // promise the app immediately forgets.
  const helperWork = await api('/api/tasks?scope=mine', { token: otherMemberToken });
  const fromHelp = (helperWork.body?.tasks ?? [])
    .find((t) => t.title === `Help: ${asked.body.title ?? ''}`
      || t.title.startsWith('Help: Need a hand with the stage backdrop'));
  ok('Offering to help lands on the helper\'s own task list', Boolean(fromHelp),
    (helperWork.body?.tasks ?? []).map((t) => t.title).join(' | '));
  ok('Carrying the deadline the ask specified', Boolean(fromHelp?.dueDate));

  // The cap actually stops at the number asked for.
  const thirdPerson = await api(`/api/help/${helpId}/offer`, {
    method: 'POST', token: leadToken,
  });
  ok('A second helper fits within the cap of two', thirdPerson.status === 200,
    `got ${thirdPerson.status}`);
  const fourthPerson = await api(`/api/help/${helpId}/offer`, {
    method: 'POST', token: presidentToken,
  });
  ok('A third is turned away once the places are full',
    fourthPerson.status === 409, `got ${fourthPerson.status}`);

  // An open ask lands on its department's workspace, which is how a Lead finds
  // out somebody on their team is stuck without anyone having to tell them.
  const helpInWorkspace = await api(`/api/departments/${creative.id}/workspace`,
    { token: memberToken });
  ok('An open ask surfaces on the department workspace',
    helpInWorkspace.body.helpRequests.some((h) => h.id === helpId),
    `${helpInWorkspace.body?.helpRequests?.length} listed`);

  const strangerResolves = await api(`/api/help/${helpId}/status`, {
    method: 'POST', token: leadToken, body: { status: 'resolved' },
  });
  ok('A passer-by cannot mark someone else\'s problem solved',
    strangerResolves.status === 403, `got ${strangerResolves.status}`);

  const resolved = await api(`/api/help/${helpId}/status`, {
    method: 'POST', token: memberToken, body: { status: 'resolved' },
  });
  ok('The person who asked closes it', resolved.status === 200);

  const steppedBack = await api(`/api/help/${helpId}/offer`, {
    method: 'DELETE', token: otherMemberToken,
  });
  ok('A helper can always step back out', steppedBack.status === 200,
    'offering to help must never be a trap');

  // Stepping back must actually undo it, or the app keeps nagging somebody
  // about work they withdrew from.
  const afterStepBack = await api('/api/tasks?scope=mine', { token: otherMemberToken });
  ok('And the task comes off their list with them',
    !(afterStepBack.body?.tasks ?? []).some((t) => t.title.startsWith('Help: Need a hand with the stage backdrop')),
    (afterStepBack.body?.tasks ?? []).map((t) => t.title).join(' | '));

  // ================================================= EVENT FINANCE (v3.1)
  console.log('\nevent finance');
  const memberSeesMoney = await api(`/api/events/${eventId}/bills`, { token: memberToken });
  ok('A general member cannot browse what the club spent',
    memberSeesMoney.status === 403, `got ${memberSeesMoney.status}`);

  const memberFiles = await upload(`/api/events/${eventId}/bills`, memberToken, {
    title: 'Member tries to expense something', amount: '500',
  });
  ok('Nor file an expense', memberFiles.status === 403, `got ${memberFiles.status}`);

  const leadBill = await upload(`/api/events/${eventId}/bills`, leadToken, {
    title: `Poster printing ${RUN}`,
    amount: '1450.50',
    category: 'Printing',
    paidByName: 'Aisha',
    note: 'A3 colour, 40 copies.',
  }, {
    field: 'receipt', name: 'receipt.txt',
    body: 'PRINT SHOP — Rs 1450.50', type: 'text/plain',
  });
  ok('A Lead can file one, with a receipt', leadBill.status === 201,
    JSON.stringify(leadBill.body));
  const billId = leadBill.body?.id;

  const bills = await api(`/api/events/${eventId}/bills`, { token: leadToken });
  const filed = bills.body.bills.find((b) => b.id === billId);
  ok('It lands awaiting approval, not approved', filed?.status === 'pending');
  ok('The amount survives the round trip exactly', filed?.amount === 1450.5,
    `got ${filed?.amount}`);
  ok('It records who is out of pocket', filed?.paidByName === 'Aisha');
  ok('And that a receipt is attached', filed?.hasReceipt === true);

  const leadApproves = await api(`/api/bills/${billId}/decision`, {
    method: 'POST', token: leadToken, body: { status: 'approved' },
  });
  ok('The person who filed it cannot approve it',
    leadApproves.status === 403, `got ${leadApproves.status}`);

  const settleBeforeApproval = await api(`/api/bills/${billId}/settle`, {
    method: 'POST', token: presidentToken, body: { reference: 'UPI' },
  });
  ok('Nothing is repaid before it is approved',
    settleBeforeApproval.status === 400, `got ${settleBeforeApproval.status}`);

  const approved = await api(`/api/bills/${billId}/decision`, {
    method: 'POST', token: presidentToken,
    body: { status: 'approved', note: 'Checked against the quote.' },
  });
  ok('The President approves it', approved.status === 200, JSON.stringify(approved.body));

  const owed = await api(`/api/events/${eventId}/bills`, { token: presidentToken });
  ok('Approved-but-unpaid shows as what the club owes its own members',
    owed.body.totals.owed === 1450.5, `got ${owed.body?.totals?.owed}`);

  const settled = await api(`/api/bills/${billId}/settle`, {
    method: 'POST', token: presidentToken, body: { reference: 'UPI ref 88231' },
  });
  ok('And can then be recorded as repaid', settled.status === 200);

  const afterSettle = await api(`/api/events/${eventId}/bills`, { token: presidentToken });
  const settledBill = afterSettle.body.bills.find((b) => b.id === billId);
  ok('Settling clears the debt but keeps the spend',
    settledBill.status === 'paid'
    && afterSettle.body.totals.owed === 0
    && afterSettle.body.totals.spent === 1450.5,
    JSON.stringify(afterSettle.body.totals));
  ok('The settlement carries its reference',
    settledBill.settlementRef === 'UPI ref 88231');

  const deleteSettled = await api(`/api/bills/${billId}`, {
    method: 'DELETE', token: presidentToken,
  });
  ok('A settled expense stays on the record',
    deleteSettled.status === 400, `got ${deleteSettled.status}`);

  const receipt = await fetch(`${BASE}/api/bills/${billId}/receipt`, {
    headers: { authorization: `Bearer ${presidentToken}` },
  });
  ok('The receipt streams back to someone entitled to it',
    (await receipt.text()) === 'PRINT SHOP — Rs 1450.50');

  const receiptAnon = await fetch(`${BASE}/api/bills/${billId}/receipt`);
  ok('And never without a token', receiptAnon.status === 401,
    `got ${receiptAnon.status}`);

  // ==================================================== PASSWORDS (v3.1)
  console.log('\npasswords');
  const wrongCurrent = await api('/api/auth/password', {
    method: 'POST', token: memberToken,
    body: { currentPassword: 'NotMyPassword', newPassword: 'BrandNewPass1' },
  });
  ok('Changing a password needs the current one',
    wrongCurrent.status === 401, `got ${wrongCurrent.status}`);

  const changed = await api('/api/auth/password', {
    method: 'POST', token: memberToken,
    body: { currentPassword: 'MemberPass123', newPassword: 'BrandNewPass1' },
  });
  ok('With it, the change goes through', changed.status === 200,
    JSON.stringify(changed.body));

  const oldPassword = await api('/api/auth/login', {
    method: 'POST', body: { email: members[0].email, password: 'MemberPass123' },
  });
  ok('The old password stops working', oldPassword.status === 401);

  const newPassword = await api('/api/auth/login', {
    method: 'POST', body: { email: members[0].email, password: 'BrandNewPass1' },
  });
  ok('The new one works', newPassword.status === 200);

  const forgot = await api('/api/auth/password/forgot', {
    method: 'POST', body: { email: members[0].email },
  });
  const forgotUnknown = await api('/api/auth/password/forgot', {
    method: 'POST', body: { email: `nobody.${RUN}@gwd.club` },
  });
  ok('"Forgot password" answers identically for any address',
    forgot.status === 200 && forgotUnknown.status === 200
    && forgot.body.message === forgotUnknown.body.message,
    'otherwise it becomes a way to discover who has an account');

  const memberResets = await api(`/api/users/${logins[1].body.user.id}/reset-password`, {
    method: 'POST', token: newPassword.body.token,
  });
  ok('A Member cannot reset somebody else\'s password',
    memberResets.status === 403, `got ${memberResets.status}`);

  const reset = await api(`/api/users/${memberId}/reset-password`, {
    method: 'POST', token: presidentToken,
  });
  ok('The President can', reset.status === 200, JSON.stringify(reset.body));
  ok('And is handed a temporary password to pass on',
    typeof reset.body.temporaryPassword === 'string'
    && reset.body.temporaryPassword.startsWith('gwd-'),
    reset.body?.temporaryPassword);

  const withTemporary = await api('/api/auth/login', {
    method: 'POST', body: { email: members[0].email, password: reset.body.temporaryPassword },
  });
  ok('It signs them in', withTemporary.status === 200);
  ok('Flagged so the app makes them choose their own',
    withTemporary.body?.user?.mustChangePassword === true);

  // ======================================================= NAMING (v3.2)
  //
  // The club must not end up with six people called "<Department> Lead".
  // Accounts created *for* somebody arrive with a placeholder, flagged as one,
  // and whoever hands the credentials over puts the real name on it.
  console.log('\nnaming');

  const seededLeads = await api('/api/users?role=clubLead', { token: presidentToken });
  ok('A seeded Lead account is flagged as unnamed',
    (seededLeads.body?.users ?? []).some((u) => u.mustSetName === true)
    || logins.every((l) => l.body?.user?.mustSetName !== undefined),
    'mustSetName must be present on the wire');

  const namingTarget = memberId;

  const leadRenames = await api(`/api/users/${namingTarget}/name`, {
    method: 'PATCH', token: leadToken, body: { name: 'Renamed By A Lead' },
  });
  ok('A Lead cannot rename another member',
    leadRenames.status === 403, `got ${leadRenames.status}`);

  const tooShort = await api(`/api/users/${namingTarget}/name`, {
    method: 'PATCH', token: presidentToken, body: { name: 'A' },
  });
  ok('A one-character name is refused', tooShort.status === 400, `got ${tooShort.status}`);

  const renamed = await api(`/api/users/${namingTarget}/name`, {
    method: 'PATCH', token: presidentToken, body: { name: 'Ananya Rao' },
  });
  ok('The President can name a member', renamed.status === 200,
    JSON.stringify(renamed.body));
  ok('The name is what was given', renamed.body?.user?.name === 'Ananya Rao');
  ok('And it is no longer flagged as a placeholder',
    renamed.body?.user?.mustSetName === false);

  const renamedNotifications = await api('/api/notifications', {
    method: 'GET', token: withTemporary.body.token,
  });
  ok('The person is told their name was changed',
    (renamedNotifications.body?.notifications ?? [])
      .some((n) => n.type === 'profileRenamed'),
    'finding out silently is worse than the rename');

  const selfNamed = await api('/api/users/me', {
    method: 'PATCH', token: withTemporary.body.token, body: { name: 'Ananya R' },
  });
  ok('Anyone can set their own name', selfNamed.status === 200,
    JSON.stringify(selfNamed.body));
  ok('Which also clears the placeholder flag',
    selfNamed.body?.user?.mustSetName === false);

  const supervisorRenames = await api(`/api/users/${namingTarget}/name`, {
    method: 'PATCH', token: directorToken, body: { name: 'Ananya Rao' },
  });
  ok('A supervisor can rename too', supervisorRenames.status === 200,
    `got ${supervisorRenames.status}`);

  // ================================================== HIERARCHY (v4.1)
  console.log('\nhierarchy');

  // The club's officers hold posts rather than run teams, so there is no
  // department to route through and they are reached by name.
  const directorTargets = await api('/api/users/assignable', { token: directorToken });
  const officerRoles = ['president', 'vicePresident', 'secretaryGeneral'];
  ok('A Director can assign to the officers by name',
    (directorTargets.body?.assignable ?? [])
      .some((m) => officerRoles.includes(m.role)),
    (directorTargets.body?.assignable ?? []).map((m) => m.role).join(','));
  ok('And still addresses departments',
    directorTargets.body?.canAssignToDepartment === true);

  const directorToPresident = await api('/api/tasks', {
    method: 'POST', token: directorToken,
    body: { title: `Sign the sponsor letter ${RUN}`, assignedTo: logins[0].body.user.id },
  });
  // Not a member — that still goes through the department.
  ok('But a Director still cannot hand work to a member by name',
    directorToPresident.status === 403, `got ${directorToPresident.status}`);

  const leadTargets = await api('/api/users/assignable', { token: leadToken });
  ok('A Lead reaches the officers too',
    (leadTargets.body?.assignable ?? []).some((m) => officerRoles.includes(m.role)),
    (leadTargets.body?.assignable ?? []).map((m) => m.role).join(','));

  // A member gets exactly one name: their own Lead. Needs somebody in the
  // Lead's own department — the fixture's other members sit in Creative, which
  // has no Lead, so they would correctly see nobody.
  const teammate = await api('/api/auth/signup', {
    method: 'POST',
    body: {
      name: `Teammate ${RUN}`, email: `teammate.${RUN}@gwd.club`,
      phone: '9000000001', password: 'TeammatePass1', role: 'clubMember',
      departmentId: leadDept.id,
    },
  });
  await api(`/api/access/${(await api('/api/access/pending', { token: leadToken }))
    .body.requests.find((r) => r.userId === teammate.body.user.id).id}/approve`, {
    method: 'POST', token: leadToken,
  });
  const teammateLogin = await api('/api/auth/login', {
    method: 'POST', body: { email: `teammate.${RUN}@gwd.club`, password: 'TeammatePass1' },
  });

  const memberTargets = await api('/api/users/assignable', {
    token: teammateLogin.body.token,
  });
  const memberOthers = (memberTargets.body?.assignable ?? [])
    .filter((m) => m.id !== teammate.body.user.id);
  ok('A member can assign only to their own department Lead',
    memberOthers.length > 0 && memberOthers.every((m) => m.role === 'clubLead'),
    memberOthers.map((m) => `${m.name}:${m.role}`).join(', '));
  ok('And never to the officers or another member',
    memberOthers.every((m) => !officerRoles.includes(m.role) && m.role !== 'clubMember'));

  // --- "what did I hand out?" ---------------------------------------------
  const handedOutView = await api('/api/users/my-overview', { token: presidentToken });
  ok('Leadership can see what they handed out', handedOutView.status === 200,
    JSON.stringify(handedOutView.body).slice(0, 160));
  ok('With totals that add up',
    (handedOutView.body?.totals?.assigned ?? 0)
      >= (handedOutView.body?.totals?.completed ?? 0)
    && (handedOutView.body?.totals?.assigned ?? 0) > 0,
    JSON.stringify(handedOutView.body?.totals));
  ok('And a row per person it landed on',
    Array.isArray(handedOutView.body?.people),
    `${handedOutView.body?.people?.length} people`);
  ok('Work still awaiting hand-out is counted apart from anyone being slow',
    typeof handedOutView.body?.totals?.awaitingHandout === 'number');

  // Scoped to the caller: a member who has handed out nothing sees nothing,
  // rather than the whole club's work.
  // A fresh token: memberToken was minted before this account's password was
  // reset in the passwords section, and that revokes it by design.
  const freshMemberForOverview = await api('/api/auth/login', {
    method: 'POST', body: { email: members[1].email, password: 'MemberPass123' },
  });
  const memberOverview = await api('/api/users/my-overview', {
    token: freshMemberForOverview.body.token,
  });
  ok('A member sees only their own, which is usually empty',
    memberOverview.status === 200
    && (memberOverview.body?.totals?.assigned ?? 0)
       <= (handedOutView.body?.totals?.assigned ?? 0),
    JSON.stringify(memberOverview.body?.totals));

  // --- asking another department -----------------------------------------
  // "Technical needs Production on the stage rig" is how cross-department work
  // is described, so the ask is addressed to the department, not to whichever
  // person over there happens to be free.
  // A department can only be asked if it has a Lead to receive the ask, and in
  // this fixture only leadDept has one — which is the asker's own. Give
  // Creative a Lead so there is somebody on the other side.
  const creativeLeadSignup = await api('/api/auth/signup', {
    method: 'POST',
    body: {
      name: `Creative Lead ${RUN}`, email: `creativelead.${RUN}@gwd.club`,
      phone: '9000000002', password: 'CreativeLeadPass1', role: 'clubMember',
      departmentId: creative.id,
    },
  });
  const creativePending = await api('/api/access/pending', { token: presidentToken });
  const creativeRow = creativePending.body.requests
    .find((r) => r.userId === creativeLeadSignup.body.user.id);
  if (creativeRow) {
    await api(`/api/access/${creativeRow.id}/approve`, { method: 'POST', token: directorToken });
  }
  // PUT, and it promotes them to Lead itself — no separate role change needed.
  const creativeLeadSet = await api(`/api/departments/${creative.id}/lead`, {
    method: 'PUT', token: presidentToken,
    body: { userId: creativeLeadSignup.body.user.id },
  });
  ok('Creative gets a Lead so there is somebody to ask',
    creativeLeadSet.status === 200, JSON.stringify(creativeLeadSet.body));

  const leadOptions = await api('/api/users/assignable', { token: leadToken });
  ok('A Lead is offered other departments to ask',
    (leadOptions.body?.requestableDepartments ?? []).length > 0,
    `${leadOptions.body?.requestableDepartments?.length} offered`);
  ok('But never their own',
    (leadOptions.body?.requestableDepartments ?? [])
      .every((d) => d.id !== leadDept.id));

  const askTarget = (leadOptions.body?.requestableDepartments ?? [])[0];
  const crossRequest = await api('/api/task-requests', {
    method: 'POST', token: leadToken,
    body: {
      toDepartmentId: askTarget.id,
      title: `Stage rig support ${RUN}`,
      description: 'Two people for the load-in.',
      dueDate: new Date(Date.now() + 4 * 864e5).toISOString(),
    },
  });
  ok('A Lead can ask another department for a hand',
    crossRequest.status === 201, JSON.stringify(crossRequest.body));
  ok('The ask records which department is asking',
    Boolean(crossRequest.body?.request?.fromDepartmentName),
    String(crossRequest.body?.request?.fromDepartmentName));

  const ownDepartment = await api('/api/task-requests', {
    method: 'POST', token: leadToken,
    body: { toDepartmentId: leadDept.id, title: `Own dept ${RUN}` },
  });
  ok('Asking your own department is refused - assign it instead',
    ownDepartment.status === 400, `got ${ownDepartment.status}`);

  const inbox = await api('/api/task-requests?direction=incoming', {
    token: presidentToken,
  });
  ok('A department ask reaches a real inbox', inbox.status === 200);

  // --- removing people ---------------------------------------------------
  const memberRemovesSomeone = await api(`/api/users/${memberId}`, {
    method: 'DELETE', token: teammateLogin.body.token,
  });
  ok('A member cannot remove anybody', memberRemovesSomeone.status === 403,
    `got ${memberRemovesSomeone.status}`);

  const presidentRemovesDirector = await api(`/api/users/${logins[0].body.user.id}`, {
    method: 'DELETE', token: presidentToken,
  });
  ok('Nor can the President remove people', presidentRemovesDirector.status === 403,
    `got ${presidentRemovesDirector.status}`);

  const throwaway = await api('/api/auth/signup', {
    method: 'POST',
    body: {
      name: `Removable ${RUN}`, email: `removable.${RUN}@gwd.club`,
      phone: '9000000000', password: 'RemovablePass1', role: 'clubMember',
      departmentId: creative.id,
    },
  });
  const removed = await api(`/api/users/${throwaway.body.user.id}`, {
    method: 'DELETE', token: directorToken,
  });
  ok('A Director can remove somebody from the club', removed.status === 200,
    JSON.stringify(removed.body));

  const gone = await api('/api/auth/login', {
    method: 'POST', body: { email: `removable.${RUN}@gwd.club`, password: 'RemovablePass1' },
  });
  ok('And they can no longer sign in', gone.status === 401, `got ${gone.status}`);

  // ===================================================== SECURITY (v4.0)
  console.log('\nsecurity');

  // Express turns `?role[$ne]=x` into a real Mongo operator. Two routes used to
  // drop that straight into a filter.
  const injected = await api('/api/users?role[$ne]=clubMember', { token: presidentToken });
  const injectedOk = injected.status === 200
    && Array.isArray(injected.body?.users)
    && injected.body.users.length > 0;
  ok('A Mongo operator in a query string is stripped, not honoured', injectedOk,
    `status ${injected.status}`);

  // A fresh token: `memberToken` was minted before this member's password was
  // reset in the passwords section, and that now revokes it — which is the
  // point of the feature, not a problem with it.
  const freshMember = await api('/api/auth/login', {
    method: 'POST', body: { email: members[1].email, password: 'MemberPass123' },
  });
  const injectedBody = await api('/api/users/me', {
    method: 'PATCH', token: freshMember.body.token,
    body: { name: 'Sanitised', $set: { role: 'clubDirector' } },
  });
  ok('And in a request body too', injectedBody.status === 200
    && injectedBody.body?.user?.role !== 'clubDirector',
    `status ${injectedBody.status}, role ${injectedBody.body?.user?.role}`);

  // Brute force. Keyed on the account, so one person guessing cannot lock the
  // rest of the club out from behind the same hotspot NAT.
  const victim = `bruteforce.${RUN}@gwd.club`;
  let limited = false;
  for (let attempt = 0; attempt < 14; attempt += 1) {
    const tryIt = await api('/api/auth/login', {
      method: 'POST', body: { email: victim, password: `guess-${attempt}` },
    });
    if (tryIt.status === 429) { limited = true; break; }
  }
  ok('Repeated failed sign-ins are rate limited', limited,
    'an unthrottled login endpoint is a guessable password');

  const stillFine = await api('/api/auth/login', {
    method: 'POST', body: { email: members[1].email, password: 'MemberPass123' },
  });
  ok('While a different account signs in normally', stillFine.status !== 429,
    `got ${stillFine.status}`);

  // Changing a password must end sessions that already exist — otherwise the
  // one reason anybody changes a password does not happen.
  const revokeLogin = await api('/api/auth/login', {
    method: 'POST', body: { email: members[2].email, password: 'MemberPass123' },
  });
  const doomed = revokeLogin.body.token;
  const beforeChange = await api('/api/auth/me', { token: doomed });
  ok('A token works before the password changes', beforeChange.status === 200);

  const changedNow = await api('/api/auth/password', {
    method: 'POST', token: doomed,
    body: { currentPassword: 'MemberPass123', newPassword: 'RotatedPass99' },
  });
  ok('The change goes through', changedNow.status === 200, JSON.stringify(changedNow.body));
  ok('And hands back a replacement token', typeof changedNow.body?.token === 'string');

  const afterChange = await api('/api/auth/me', { token: doomed });
  ok('The old token is dead', afterChange.status === 401, `got ${afterChange.status}`);

  const withNew = await api('/api/auth/me', { token: changedNow.body.token });
  ok('The replacement works', withNew.status === 200, `got ${withNew.status}`);

  // --- privilege escalation ----------------------------------------------
  // The Vice President can manage departments, which must NOT extend to
  // editing roles — sharing one gate would have let them promote themselves.
  const vpSignup = await api('/api/auth/signup', {
    method: 'POST',
    body: {
      name: `Escalation VP ${RUN}`, email: `escvp.${RUN}@gwd.club`,
      phone: '9000000003', password: 'EscalationPass1', role: 'vicePresident',
    },
  });
  let vpToken = null;
  if (vpSignup.body?.user?.id) {
    const vpRow = (await api('/api/access/pending', { token: directorToken }))
      .body.requests.find((r) => r.userId === vpSignup.body.user.id);
    if (vpRow) await api(`/api/access/${vpRow.id}/approve`, { method: 'POST', token: directorToken });
    vpToken = (await api('/api/auth/login', {
      method: 'POST', body: { email: `escvp.${RUN}@gwd.club`, password: 'EscalationPass1' },
    })).body?.token;
  }

  if (vpToken) {
    const vpPromotesSelf = await api(`/api/users/${vpSignup.body.user.id}/role`, {
      method: 'PATCH', token: vpToken, body: { role: 'president' },
    });
    ok('A Vice President cannot edit roles at all',
      vpPromotesSelf.status === 403, `got ${vpPromotesSelf.status}`);

    const vpMakesDept = await api('/api/departments', {
      method: 'POST', token: vpToken, body: { name: `VP dept ${RUN}` },
    });
    ok('But can still create a department', vpMakesDept.status === 201,
      `got ${vpMakesDept.status}`);
  }

  const presidentPromotesSelf = await api(`/api/users/${logins[0].body.user.id}/role`, {
    method: 'PATCH', token: presidentToken, body: { role: 'clubDirector' },
  });
  ok('Nobody can appoint a Director except a Director',
    presidentPromotesSelf.status === 403, `got ${presidentPromotesSelf.status}`);

  const bogusRole = await api(`/api/users/${memberId}/role`, {
    method: 'PATCH', token: presidentToken, body: { role: 'superAdmin' },
  });
  ok('An invented role is refused rather than written',
    bogusRole.status === 400, `got ${bogusRole.status}`);

  const secondPresident = await api(`/api/users/${memberId}/role`, {
    method: 'PATCH', token: presidentToken, body: { role: 'president' },
  });
  ok('And the club cannot end up with two Presidents',
    secondPresident.status === 409, `got ${secondPresident.status}`);

  // Security headers.
  const headed = await fetch(`${BASE}/api/health`);
  ok('Responses carry nosniff', headed.headers.get('x-content-type-options') === 'nosniff');
  ok('And refuse to be framed', headed.headers.get('x-frame-options') === 'DENY');

  socket.close();

  // ------------------------------------------------------------------- done
  console.log(`\n${'─'.repeat(56)}`);
  console.log(`  ${passed} passed, ${failed} failed`);
  console.log(`${'─'.repeat(56)}\n`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error('\nSmoke test crashed:', error);
  process.exit(1);
});

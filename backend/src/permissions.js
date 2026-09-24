'use strict';

/**
 * The role matrix, in one place.
 *
 * Routes ask this module questions; they never re-derive the rules themselves.
 * The client is never trusted — it only mirrors these answers to hide UI that
 * would fail anyway.
 */

const ROLES = {
  clubDirector: 'clubDirector',
  facultyCoordinator: 'facultyCoordinator',
  president: 'president',
  vicePresident: 'vicePresident',
  secretaryGeneral: 'secretaryGeneral',
  clubLead: 'clubLead',
  clubMember: 'clubMember',
};

const ALL_ROLES = Object.values(ROLES);

/**
 * Rank drives visibility ("sees everything below") and who approves whom.
 *
 * Faculty Coordinator sits between the Directors and the President: she is the
 * college's representative over the club, so she outranks the student
 * leadership, but the Directors remain the root of trust for the platform
 * itself. VP and Secretary General deliberately share a rank — equal authority,
 * one level below President.
 */
const RANK = {
  clubDirector: 100,
  facultyCoordinator: 95,
  president: 90,
  vicePresident: 80,
  secretaryGeneral: 80,
  clubLead: 50,
  clubMember: 10,
};

/** Singleton or near-singleton roles, and their hard caps. */
const ROLE_CAPS = {
  // Three. The club runs with a CMO, a CEO and one more seat at that level.
  clubDirector: 3,
  facultyCoordinator: 1,
  president: 1,
  vicePresident: 1,
  secretaryGeneral: 1,
  // clubLead is capped per-department (one Lead per department), not globally.
  // clubMember is uncapped.
};

/** Pre-seeded roots of trust — they never sit in an approval queue. */
const PRESEEDED_ROLES = new Set([ROLES.clubDirector, ROLES.facultyCoordinator]);

/**
 * Supervisors oversee the club rather than compete inside it.
 *
 * They earn **no** points and are excluded from the leaderboard: a Director
 * topping the board their own members are competing on would be meaningless,
 * and would quietly discourage the people the board is actually for. They can
 * still *award* points, which is the whole point of supervising.
 */
const SUPERVISOR_ROLES = new Set([ROLES.clubDirector, ROLES.facultyCoordinator]);

const isSupervisor = (role) => SUPERVISOR_ROLES.has(role);

/**
 * The Super Admin: one Director above the others.
 *
 * Every Director already clears nearly every gate in this file, so the tier is
 * not about seeing more. It is about **who governs the supervisors
 * themselves.** Before it existed, any Director could appoint another Director,
 * and nothing stopped one Director demoting another — or the President
 * demoting a Director, because the role route only checked appointments *into*
 * the tier, never out of it. A tier that anybody in it can reshape is not a
 * root of trust.
 *
 * So the Super Admin alone may appoint, demote or remove a Director or the
 * Faculty Coordinator, and may hand work to anybody by name.
 *
 * It is a **flag on the user, never a role**, for two reasons. Everything that
 * treats Directors as supervisors (no points, off the leaderboard, full
 * visibility) must keep applying to them without a second role name threaded
 * through every check. And the flag is set only by a server-side script
 * (`scripts/v8-hierarchy.js`) — no route writes it — so no API call, however
 * crafted, can mint a Super Admin. Requiring the Director role and an approved
 * account as well means a demoted or suspended account carrying a stale flag
 * holds no power at all.
 */
const isSuperAdmin = (user) =>
  Boolean(user)
  && user.superAdmin === true
  && user.role === ROLES.clubDirector
  && user.approvalStatus === 'approved';

/** Does completing a task credit this person? */
const earnsPoints = (role) => !isSupervisor(role);

/** Does this person appear on the leaderboard at all? */
const appearsOnLeaderboard = (role) => !isSupervisor(role);

/** May this person hand out points by hand, outside task completion? */
const canAwardPoints = (role) =>
  isSupervisor(role) || role === ROLES.president;

/**
 * May `actor` set `target`'s display name?
 *
 * A person's name is their own, so editing yourself is always allowed. Beyond
 * that this is deliberately narrow — renaming somebody is an identity change,
 * not an admin convenience, and it is audited.
 *
 * It exists because accounts get created *for* people: the six seeded Lead
 * accounts arrive with no real name on them, and whoever hands the credentials
 * over is the person who knows whose account it is. Without this, an account
 * would carry a placeholder until its holder signed in, and the approval queue
 * would be asking the President to admit somebody with no name.
 *
 * Leads are excluded on purpose. Running a department does not extend to
 * deciding what the people in it are called.
 */
function canRenameMember(actor, target) {
  if (!actor || !target) return false;
  // Your own name is yours: the first-run "what should we call you?" and a
  // later correction both come through here.
  if (String(actor._id) === String(target._id)) return true;
  // Anybody else's is the Super Admin's call alone — the club's decision, at
  // V8.1. It was supervisors and the President, and before V8 it let the
  // President rename a Director.
  if (isSuperAdmin(target)) return false;
  return isSuperAdmin(actor);
}

/**
 * Assignment hierarchy — two steps, never one long list.
 *
 * The club's leadership does **not** hand work to individuals. They address a
 * **department**; its Lead receives it and decides who actually does it, or
 * does it themselves. The Lead is the only person who assigns to a person.
 *
 * This is the whole point: an executive picking a name out of forty is a
 * decision they are not equipped to make and did not ask for. A Lead knows who
 * on their team is free this week.
 *
 *   Director · Faculty Coordinator · President · VP · Secretary General
 *        └── assign to a DEPARTMENT ────────────────┐
 *                                                    ▼
 *                                          that department's Lead
 *                                                    │
 *                        ┌───────────────────────────┴──────────────┐
 *                        ▼                                          ▼
 *              assign to their own member                   do it themselves
 *
 * Two things sit outside that shape, both deliberate:
 *
 * **The executive tier can be assigned to by name.** Directors, the Faculty
 * Coordinator and Leads can hand work straight to the President, VP or
 * Secretary General. There is no department to route through — those three are
 * the club's officers, not a team — so the two-step rule has nothing to bite
 * on. A Lead assigning upward looks odd next to the rest of this, but "the
 * sponsor letter needs the President's signature" is a task, not a favour, and
 * making it a request meant it could simply be declined into silence.
 *
 * **A member can assign to their own Lead.** Same reasoning in the other
 * direction: a member who finds something only the Lead can do should be able
 * to put it on the Lead's list rather than hope it gets noticed. Their own
 * Lead only — never another department's, and never anybody else.
 *
 * Everything else sideways is still a **request** — see REQUEST_TARGETS — and a
 * Lead still cannot reach into another department's members.
 */
const DEPARTMENT_ASSIGNERS = new Set([
  ROLES.clubDirector,
  ROLES.facultyCoordinator,
  ROLES.president,
  ROLES.vicePresident,
  ROLES.secretaryGeneral,
]);

/** May this role address work to a department as a whole? */
const canAssignToDepartment = (role) => DEPARTMENT_ASSIGNERS.has(role);

/**
 * The club's officers. They hold posts rather than run teams, so there is no
 * department to address work to them through.
 */
const EXECUTIVE_TIER = [
  ROLES.president,
  ROLES.vicePresident,
  ROLES.secretaryGeneral,
];

/**
 * Who may this role hand a task *to*, by name?
 *
 * `'ownDepartment'` → members of the actor's own department
 * a list of roles   → exactly those roles, club-wide (empty: nobody)
 *
 * The leadership tier still reaches *departments* through
 * `canAssignToDepartment`; this is only the by-name path.
 * Self-assignment is always allowed and is handled in `canAssignTo`.
 */
const ASSIGN_TARGETS = {
  // The Directors and the Faculty Coordinator reach the officers **and the
  // Club Leads** by name. The role table in CLAUDE.md always said so ("all
  // Leads"); the code stopped at the officers, which meant the Faculty
  // Coordinator could send work to a department but could not name the person
  // running it. Members are still reached through their Lead — the two-step
  // rule is about not making leadership choose among forty names, and a Lead
  // is one name, not forty.
  clubDirector: [...EXECUTIVE_TIER, ROLES.clubLead],
  facultyCoordinator: [...EXECUTIVE_TIER, ROLES.clubLead],
  // The officers address departments, and each other.
  president: [ROLES.vicePresident, ROLES.secretaryGeneral],
  vicePresident: [ROLES.secretaryGeneral],
  secretaryGeneral: [ROLES.vicePresident],
  clubLead: 'ownDepartment',
  // A member gives work to nobody - not even their own Lead. They *ask* their
  // Lead for work (REQUEST_TARGETS below), and the Lead decides. This used to
  // be 'ownLead', which let a member put a task on their Lead's list: the
  // hierarchy running backwards.
  clubMember: [],
};

/**
 * A *request* is a task you cannot impose — the recipient accepts or declines.
 * Leads use this laterally (to other Leads) and upward to the executive tier,
 * where they have no authority to assign.
 */
const REQUEST_TARGETS = {
  clubDirector: 'any',
  facultyCoordinator: 'any',
  president: 'any',
  vicePresident: [ROLES.clubLead, ROLES.secretaryGeneral, ROLES.president],
  secretaryGeneral: [ROLES.clubLead, ROLES.vicePresident, ROLES.president],
  clubLead: [
    ROLES.clubLead,
    ROLES.president,
    ROLES.vicePresident,
    ROLES.secretaryGeneral,
  ],
  // A member asks their own Lead, and nobody else, **for work**. Accepting it
  // hands the task to the member, priced by the Lead - see `asksForWork` - so
  // a member's request is never a way of giving their Lead something to do.
  clubMember: 'ownLead',
};

const isRole = (role) => ALL_ROLES.includes(role);
const rankOf = (role) => RANK[role] ?? 0;
const isDirector = (role) => role === ROLES.clubDirector;

/**
 * Can this role create work for anyone at all — by name or by department?
 * Drives whether the compose sheet and the "Assigned" tab exist.
 */
function canAssign(role) {
  if (canAssignToDepartment(role)) return true;
  const targets = ASSIGN_TARGETS[role];
  return targets === 'ownDepartment'
    || (Array.isArray(targets) && targets.length > 0);
}

/** Same department, and both actually in one. */
const sameDepartment = (a, b) =>
  Boolean(a?.departmentId) && String(a.departmentId) === String(b?.departmentId);

/** May `actor` assign a task to `target`, by name? Both are user documents. */
function canAssignTo(actor, target) {
  if (!actor || !target) return false;
  if (String(actor._id) === String(target._id)) return true; // always yourself

  // The Super Admin is never blocked by the shape of the hierarchy below them.
  // Only people who can actually receive work, though: an unapproved account
  // has nobody behind it to do anything.
  if (isSuperAdmin(actor)) return target.approvalStatus === 'approved';

  const rule = ASSIGN_TARGETS[actor.role];

  if (rule === 'ownDepartment') {
    // A Lead owns their department's members, and nobody else.
    //
    // Not the officers either. This used to return true for the executive
    // tier, on the reasoning that they have no department to route through —
    // which quietly let a Lead put a task on the President's list. Assigning
    // and requesting are different things: an assignment is an instruction,
    // and a Lead has no authority to instruct the people above them. Upward
    // and sideways both go through `canRequestTo`, where the recipient
    // accepts or declines. Erasing that distinction is the whole reason the
    // request system exists.
    return target.role === ROLES.clubMember && sameDepartment(target, actor);
  }

  return Array.isArray(rule) && rule.includes(target.role);
}

/**
 * Is this request a member asking their own Lead for work?
 *
 * Then accepting it gives the task to the **member**, not the Lead: the Lead
 * is deciding "yes, take this on", and pricing it as they would any hand-out.
 * Decided from the two people rather than stored on the request alone, so a
 * request raised before this rule existed is read the same way.
 */
function asksForWork(requester, recipient) {
  return Boolean(requester && recipient)
    && requester.role === ROLES.clubMember
    && recipient.role === ROLES.clubLead
    && sameDepartment(requester, recipient);
}

/**
 * May `actor` hand out a department task that has landed with them?
 *
 * That is the Lead of that department — and the leadership, so a department
 * without a Lead is not a dead end.
 */
function canDistributeDepartmentTask(actor, departmentId) {
  if (!actor || !departmentId) return false;
  if (canAssignToDepartment(actor.role)) return true;
  return (
    actor.role === ROLES.clubLead
    && actor.departmentId
    && String(actor.departmentId) === String(departmentId)
  );
}

/**
 * What a task can be worth.
 *
 * Set by the Lead when they hand it out, because they are the only person who
 * knows whether "design the poster" means twenty minutes or a weekend. Three
 * values, not a free number: a spectrum invites haggling, and the difference
 * between 6 and 7 points is not a conversation any club should be having.
 */
const TASK_POINT_VALUES = [1, 3, 5];
const isValidTaskPoints = (value) => TASK_POINT_VALUES.includes(Number(value));

/** May `actor` send a task *request* to `target`? */
function canRequestTo(actor, target) {
  if (!actor || !target) return false;
  if (String(actor._id) === String(target._id)) return false;
  const rule = REQUEST_TARGETS[actor.role];
  if (rule === 'any') return true;
  if (rule === 'ownLead') {
    return target.role === ROLES.clubLead && sameDepartment(target, actor);
  }
  return Array.isArray(rule) && rule.includes(target.role);
}

/**
 * The MongoDB filter scoping a task query to what this user may see.
 * The most security-sensitive function here: it stops a Member reading another
 * department's work.
 */
function taskVisibilityFilter(user) {
  switch (user.role) {
    case ROLES.clubDirector:
    case ROLES.facultyCoordinator:
    case ROLES.president:
    case ROLES.vicePresident:
    case ROLES.secretaryGeneral:
      return {}; // full oversight
    case ROLES.clubLead:
      return {
        $or: [
          { departmentId: user.departmentId },
          { assignedTo: user._id },
          { assignedBy: user._id },
          { eventId: { $ne: null } },
        ],
      };
    case ROLES.clubMember:
    default:
      return {
        $or: [
          { assignedTo: user._id },
          { assignedBy: user._id },
          // Work that belongs to an event is open to the whole club. That is
          // the point of an event board: anyone can see what still needs doing
          // and pick something up. Personal work stays private; event work is
          // the club's work.
          { eventId: { $ne: null } },
        ],
      };
  }
}

/** Who may see a given user record (member directory scoping). */
function userVisibilityFilter(user) {
  if (rankOf(user.role) >= RANK.vicePresident) return {};
  // Everyone can see their own department, plus the leadership they report
  // through — a club where you cannot find your own Lead is useless.
  return { $or: [{ departmentId: user.departmentId }, { role: { $ne: ROLES.clubMember } }] };
}

/**
 * May `actor` open `target`'s full record — contact details, task history, the
 * lot?
 *
 * The shape of this, in one breath: leadership and Leads can see every
 * individual. A plain Member sees individuals in their **own** department plus
 * the executive they report through; for other departments they get aggregate
 * progress only, never a person-by-person breakdown.
 *
 * Supervisors are the exception in the other direction — a Director's or the
 * Faculty Coordinator's own record is visible only to other supervisors. They
 * oversee the club; they are not part of the roster people browse.
 */
function canViewMemberDetail(actor, target) {
  if (!actor || !target) return false;
  if (String(actor._id) === String(target._id)) return true; // always yourself

  if (isSupervisor(target.role)) return isSupervisor(actor.role);

  // Directors, Faculty, President, VP, Secretary General — and Leads, who need
  // to see across departments to coordinate.
  if (rankOf(actor.role) >= RANK.clubLead) return true;

  // A Member: own department, or the executive tier above them.
  const sameDepartment =
    actor.departmentId &&
    target.departmentId &&
    String(actor.departmentId) === String(target.departmentId);
  const isExecutive = rankOf(target.role) >= RANK.vicePresident;
  return Boolean(sameDepartment || isExecutive);
}

/**
 * May `actor` see the individual members of `departmentId`, rather than just
 * that department's headline progress?
 */
function canViewDepartmentRoster(actor, departmentId) {
  if (!actor) return false;
  if (rankOf(actor.role) >= RANK.clubLead) return true;
  return Boolean(
    actor.departmentId && departmentId
      && String(actor.departmentId) === String(departmentId),
  );
}

/**
 * Department-level progress is deliberately open to everyone.
 *
 * Knowing that Marketing is 60% through its work is useful context for the
 * whole club and gives away nothing about any individual — which is exactly the
 * line: aggregate yes, person-by-person only for your own department.
 */
const canViewDepartmentProgress = () => true;

/**
 * The schedule is deliberately readable by *everyone* — the whole point is that
 * any member can see what the club is doing and when. Writing is scoped.
 *
 * Categories are managed data rather than a fixed list (see
 * routes/categories.js), so permission is per-role, not per-category: a club
 * that invents a "Shoot" category should not need a code change to decide who
 * may add one.
 */
function canCreateScheduleEntry(role) {
  return role !== ROLES.clubMember;
}

/** Can this role edit anything on the schedule at all? */
const canEditSchedule = (role) => canCreateScheduleEntry(role);

/**
 * Broadcast alerts.
 *
 * Anyone with people reporting to them can raise the whole club — that is what
 * makes it useful in an actual emergency ("venue moved, be there at 4"). A
 * plain Member cannot, or the feature becomes noise and nobody reads it.
 */
const canBroadcast = (role) => role !== ROLES.clubMember;

/**
 * Department admin — create, rename, assign a Lead, retire.
 *
 * The Vice President is included: they run operations day to day, and needing
 * the President for "add a Logistics department" is the kind of bottleneck that
 * gets worked around with a spreadsheet instead.
 */
function canManageDepartments(role) {
  return role === ROLES.clubDirector
    || role === ROLES.facultyCoordinator
    || role === ROLES.president
    || role === ROLES.vicePresident;
}

/**
 * Who may call an official meeting?
 *
 * The executive tier and department Leads. A general member cannot summon
 * people — a meeting is an instruction to be somewhere at a time, and an app
 * where anyone can put a compulsory entry in forty calendars stops being
 * trusted very quickly. A member who needs to gather people asks their Lead,
 * or raises it as a help request.
 */
const canScheduleMeeting = (role) =>
  role === ROLES.clubDirector
  || role === ROLES.facultyCoordinator
  || role === ROLES.president
  || role === ROLES.vicePresident
  || role === ROLES.secretaryGeneral
  || role === ROLES.clubLead;

/**
 * Who may record who actually turned up?
 *
 * Whoever called the meeting, plus the executive tier. Attendance feeds the
 * figures on people's profiles, so it is not something any attendee can edit
 * about themselves — marking your own attendance is not attendance.
 */
function canMarkAttendance(actor, meeting) {
  if (!actor || !meeting) return false;
  if (String(meeting.createdBy) === String(actor._id)) return true;
  return isSupervisor(actor.role) || rankOf(actor.role) >= RANK.secretaryGeneral;
}

/**
 * Change somebody's role or move them between departments.
 *
 * Deliberately **not** `canManageDepartments`, which now includes the Vice
 * President so they can create and retire departments. Sharing one gate meant
 * a VP could also edit roles — including their own, to President. Appointing
 * people is a narrower power than reorganising the club's structure.
 */
function canChangeRole(actor) {
  // Appointing people — and giving them a custom title — is the Super Admin's
  // alone at V8.1. It was the Directors, the Faculty Coordinator and the
  // President. Takes the actor now, not a role: the Super Admin is a flag on a
  // person, and a role cannot answer this.
  return isSuperAdmin(actor);
}

/**
 * May `actor` reset `target`'s password and be handed a temporary one?
 *
 * A reset is an **account takeover with extra steps** — whoever performs it
 * holds a working password for that account until its owner changes it. So it
 * may only ever reach *down*. It used to be gated on `canManageDepartments`,
 * which includes the Vice President, and checked the target only for being a
 * supervisor: the VP could reset the President's password and sign in as the
 * President, and any Director could do the same to another Director — the
 * Super Admin included.
 *
 * - nobody resets their own through here (that is a password change)
 * - nobody resets the Super Admin's through the API at all
 * - a supervisor's is reset only by the Super Admin
 * - otherwise a supervisor, or somebody strictly senior to the target — equal
 *   rank is not seniority, which is why the VP and the General Secretary
 *   cannot reset each other
 */
function canResetPasswordOf(actor, target) {
  if (!actor || !target) return false;
  if (String(actor._id) === String(target._id)) return false;
  if (isSuperAdmin(target)) return false;
  // The Super Admin, and nobody else, at V8.1. V8 already made a reset reach
  // only strictly down; the club then decided it should reach from one place.
  return isSuperAdmin(actor);
}

/** May `actor` appoint somebody *into* the supervisor tier? */
const canAppointSupervisors = (actor) => isSuperAdmin(actor);

/**
 * May `actor` change `target`'s role at all?
 *
 * `canChangeRole` answers "is this somebody who appoints people"; this answers
 * "may they do it to *this* person". The difference is the hole it closes: the
 * route used to check only appointments into the supervisor tier, so the
 * President could demote a Director or the Faculty Coordinator to a member,
 * and any Director could demote another. Governing the supervisors is the
 * Super Admin's alone, and the Super Admin's own role is changed by nobody
 * through the API — not even themselves, since an account that can demote
 * itself by a slip of the thumb leaves the club with no root at all.
 */
function canChangeRoleOf(actor, target) {
  if (!actor || !target) return false;
  if (!canChangeRole(actor)) return false;
  if (String(actor._id) === String(target._id)) return false;
  // Any other role, the other two Directors' included. Only the Super Admin's
  // own is out of reach from the API, so a slip of the thumb cannot leave the
  // club without its root.
  return !isSuperAdmin(target);
}

/**
 * Remove a person from the club entirely.
 *
 * Directors only, and deliberately so: this is the one action that can take the
 * President out, and it must not be something the President can do to a
 * Director in return. A Director cannot remove another Director either — that
 * is a conversation, not a button.
 */
function canRemoveMember(actor, target) {
  if (!actor || !target) return false;
  if (String(actor._id) === String(target._id)) return false; // never yourself
  if (isSuperAdmin(target)) return false; // nobody, through the API
  // The Super Admin may remove anybody, the other Directors included.
  if (isSuperAdmin(actor)) return true;
  // The other two Directors remove Leads and members, and nobody above them:
  // not the President, the Vice President, the General Secretary, the
  // Faculty Coordinator or another Director. Everybody else removes nobody.
  if (!isDirector(actor.role)) return false;
  return target.role === ROLES.clubLead || target.role === ROLES.clubMember;
}

/** Audit log and club-wide analytics. */
function hasOversight(role) {
  return role === ROLES.clubDirector
    || role === ROLES.facultyCoordinator
    || role === ROLES.president;
}

/**
 * The Dashboard — the club in numbers, and the full audit log.
 *
 * The Super Admin's alone at V8.1. It used to share one check with
 * "oversight", which is also what decides who sees the approvals queue — so
 * the two are separate now, and narrowing the Dashboard does not quietly stop
 * the President seeing who is waiting to join.
 */
const canViewDashboard = (actor) => isSuperAdmin(actor);

/**
 * Who approves a signup for `role`?
 *
 * `notify` is how Directors stay informed about approvals they are not
 * themselves actioning.
 */
function approvalRouteFor(role) {
  switch (role) {
    case ROLES.clubDirector:
    case ROLES.facultyCoordinator:
      return null; // pre-seeded, never queued
    case ROLES.president:
      return { approver: ROLES.clubDirector, notify: [] };
    case ROLES.vicePresident:
    case ROLES.secretaryGeneral:
    case ROLES.clubLead:
      return { approver: ROLES.president, notify: [ROLES.clubDirector] };
    case ROLES.clubMember:
    default:
      return { approver: 'departmentLead', notify: [] };
  }
}

/**
 * May `actor` approve `request` (an accessRequests document)?
 *
 * Also decides who *sees* it: the queue, the Home count and the live event all
 * ask this, so a request nobody may decide is a request nobody is shown.
 */
function canApproveAccess(actor, request, department) {
  if (actor.approvalStatus !== 'approved') return false;

  const route = approvalRouteFor(request.requestedRole);
  if (!route) return false;

  if (route.approver === 'departmentLead') {
    // A member joins a department, so that department's Lead decides - and
    // only them. Not the President, the VP, the General Secretary, and not the
    // Directors either (V8.1): the Lead is the one person who knows whether
    // this is somebody from their team, and a queue everybody can see is a
    // queue everybody assumes somebody else is dealing with.
    if (department?.leadUserId) {
      return actor.role === ROLES.clubLead
        && String(department.leadUserId) === String(actor._id);
    }
    // A department with no Lead yet would otherwise have a permanently stuck
    // queue - and its first member is usually the person who becomes that Lead.
    return actor.role === ROLES.president;
  }

  // Officers and Leads: a Director or the Faculty Coordinator can always
  // unblock a stuck queue.
  if (isSupervisor(actor.role)) return true;
  return actor.role === route.approver;
}

/**
 * Task status.
 *
 * The board reads TODO → IN PROGRESS → REVIEW → DONE. `review` is optional:
 * somebody finishing a poster can send it for a look, or just mark it done.
 * Forcing review through every trivial task turns a club into an approvals
 * queue, which is exactly what this app is supposed to remove.
 */
const TASK_STATUSES = ['pending', 'inProgress', 'review', 'completed', 'blocked', 'cancelled'];

const OWNER_TRANSITIONS = {
  pending: new Set(['inProgress', 'blocked']),
  // Straight to done, or out for review — the owner chooses.
  inProgress: new Set(['review', 'completed', 'blocked']),
  // Having sent it for review you can pull it back, but not wave it through
  // yourself; that is the assigner's call.
  review: new Set(['inProgress']),
  blocked: new Set(['inProgress']),
  completed: new Set([]),
  cancelled: new Set([]),
};

/**
 * Reviewing is the assigner's job (or a Lead's, or a supervisor's): accept the
 * work, or send it back with a reason.
 */
function canReviewTask(actor, task) {
  if (!actor || !task) return false;
  if (String(task.assignedBy) === String(actor._id)) return true;
  if (isSupervisor(actor.role)) return true;
  if (rankOf(actor.role) >= RANK.vicePresident) return true;
  return (
    actor.role === ROLES.clubLead
    && task.departmentId
    && String(task.departmentId) === String(actor.departmentId)
  );
}

function canChangeTaskStatus(actor, task, nextStatus) {
  if (!TASK_STATUSES.includes(nextStatus)) return { ok: false, reason: 'Unknown task status.' };
  const isOwner = String(task.assignedTo) === String(actor._id);
  const isAssigner = String(task.assignedBy) === String(actor._id);

  // A reviewer accepts the work or sends it back.
  if (task.status === 'review' && canReviewTask(actor, task)) {
    if (nextStatus === 'completed' || nextStatus === 'inProgress') return { ok: true };
  }

  if (isAssigner || isSupervisor(actor.role)) {
    if (nextStatus === 'cancelled') return { ok: true };
    if (task.status === 'completed' && nextStatus === 'inProgress') return { ok: true };
  }
  if (!isOwner) {
    return { ok: false, reason: 'Only the person the task is assigned to can move it forward.' };
  }
  if (!OWNER_TRANSITIONS[task.status]?.has(nextStatus)) {
    return { ok: false, reason: `A task cannot go from ${task.status} to ${nextStatus}.` };
  }
  return { ok: true };
}

/* ===========================================================================
 * EVENTS
 * ========================================================================= */

const EVENT_STATUSES = ['draft', 'planning', 'approved', 'ongoing', 'completed', 'cancelled'];

/** Who can start a new club event. */
function canCreateEvent(role) {
  return (
    isSupervisor(role)
    || rankOf(role) >= RANK.vicePresident
    || role === ROLES.clubLead // a Lead runs their own department's events
  );
}

/**
 * Who can change an event: its lead, the Lead of the organising department,
 * the executive tier, and supervisors.
 *
 * Deliberately not "anyone on the team" — being asked to make a poster should
 * not let you move the whole event's date.
 */
function canManageEvent(actor, event) {
  if (!actor || !event) return false;
  if (isSupervisor(actor.role)) return true;
  if (rankOf(actor.role) >= RANK.vicePresident) return true;
  if (String(event.leadUserId ?? '') === String(actor._id)) return true;
  return (
    actor.role === ROLES.clubLead
    && event.organizingDepartmentId
    && String(event.organizingDepartmentId) === String(actor.departmentId)
  );
}

/**
 * Who can add or edit the work for one department inside an event: that
 * department's Lead, plus anyone who can manage the event.
 */
function canManageEventDepartment(actor, event, departmentId) {
  if (canManageEvent(actor, event)) return true;
  return (
    actor.role === ROLES.clubLead
    && departmentId
    && String(actor.departmentId) === String(departmentId)
  );
}

/* --- Documents ----------------------------------------------------------- */

const DOCUMENT_KINDS = ['approval', 'file'];
const DOCUMENT_STATUSES = ['pending', 'approved', 'rejected', 'replaced'];

/**
 * Anyone on the club can attach an ordinary event file — a draft poster, a
 * schedule, a photo.
 */
const canUploadEventFile = (role) => role !== undefined && role !== null;

/**
 * Official approvals — the principal's permission letter, venue approval — are
 * a different matter. Only the offices that actually deal with the college can
 * put one on the record.
 */
function canUploadOfficialDocument(actor, event) {
  if (!actor) return false;
  if (isSupervisor(actor.role)) return true;
  if (rankOf(actor.role) >= RANK.vicePresident) return true;
  // The Lead running the event handles its paperwork.
  return (
    actor.role === ROLES.clubLead
    && event
    && event.organizingDepartmentId
    && String(event.organizingDepartmentId) === String(actor.departmentId)
  );
}

/**
 * Marking a document APPROVED is a stronger claim than uploading one: it says
 * the college has signed off. A Lead can put the letter on file; only the
 * executive and supervisors can declare it approved.
 */
function canDecideDocument(actor) {
  if (!actor) return false;
  return isSupervisor(actor.role) || rankOf(actor.role) >= RANK.vicePresident;
}

/* --- Event finance -------------------------------------------------------
 *
 * This is a **record of money already spent**, and an approval trail for
 * reimbursing it. It does not move money, and it deliberately stores no bank
 * or card details — a club app holding members' account numbers is a liability
 * nobody asked for. A bill carries an amount, what it was for, who paid, and a
 * photo of the receipt; paying it back happens by whatever means the club
 * already uses, and is then *recorded* here.
 */

const BILL_STATUSES = ['pending', 'approved', 'rejected', 'paid'];

const BILL_CATEGORIES = [
  'Printing', 'Venue', 'Refreshments', 'Travel', 'Props & materials',
  'Equipment', 'Guest hospitality', 'Other',
];

/**
 * Who may file an expense against an event.
 *
 * Department Leads and the executive tier — the people who actually commit club
 * money. A general member paying for something out of pocket asks their Lead to
 * file it, which is also the point at which somebody sanity-checks the spend.
 */
function canAddEventBill(actor) {
  if (!actor) return false;
  return isSupervisor(actor.role)
    || rankOf(actor.role) >= RANK.secretaryGeneral
    || actor.role === ROLES.clubLead;
}

/**
 * Who may approve one for reimbursement.
 *
 * Narrower than filing, on purpose: approving your own expense is the oldest
 * hole in any petty-cash system. The President and supervisors approve; the
 * President cannot approve their own, so a supervisor does.
 */
function canDecideEventBill(actor, bill) {
  if (!actor) return false;
  // Nobody approves their own expense — not the President, and not a
  // supervisor either. This used to return true for any supervisor *before*
  // looking at who filed the bill, so a Director could approve their own claim:
  // the exact hole this rule exists to close, left open for the most senior
  // people in the club. It holds for the Super Admin too. Separation of duties
  // is a control, not a restriction on administration; a Director's own bill
  // goes to another Director, the Faculty Coordinator or the President.
  if (bill && String(bill.createdBy) === String(actor._id)) return false;
  return isSupervisor(actor.role) || actor.role === ROLES.president;
}

/** Who may mark an approved bill as actually reimbursed. */
const canSettleEventBill = (actor) =>
  Boolean(actor) && (isSupervisor(actor.role) || actor.role === ROLES.president);

/**
 * Who may see the money at all.
 *
 * Everyone who could file one, plus supervisors. A club's spending is not a
 * secret from the people running it, but it is not browsing material for the
 * whole membership either — a member does not need to see what a guest speaker
 * cost.
 */
const canViewEventFinance = (actor) => canAddEventBill(actor);

module.exports = {
  ROLES,
  ALL_ROLES,
  RANK,
  ROLE_CAPS,
  PRESEEDED_ROLES,
  SUPERVISOR_ROLES,
  isSuperAdmin,
  canAppointSupervisors,
  canChangeRoleOf,
  canResetPasswordOf,
  TASK_STATUSES,
  TASK_POINT_VALUES,
  isValidTaskPoints,
  canAssignToDepartment,
  canDistributeDepartmentTask,
  EVENT_STATUSES,
  DOCUMENT_KINDS,
  DOCUMENT_STATUSES,
  canReviewTask,
  canCreateEvent,
  canManageEvent,
  canManageEventDepartment,
  canUploadEventFile,
  canUploadOfficialDocument,
  canDecideDocument,
  BILL_STATUSES,
  BILL_CATEGORIES,
  canAddEventBill,
  canDecideEventBill,
  canSettleEventBill,
  canViewEventFinance,
  isRole,
  rankOf,
  isDirector,
  isSupervisor,
  earnsPoints,
  appearsOnLeaderboard,
  canAwardPoints,
  canRenameMember,
  canAssign,
  canAssignTo,
  canRequestTo,
  asksForWork,
  taskVisibilityFilter,
  userVisibilityFilter,
  canViewMemberDetail,
  canViewDepartmentRoster,
  canViewDepartmentProgress,
  canCreateScheduleEntry,
  canEditSchedule,
  canBroadcast,
  canManageDepartments,
  canChangeRole,
  canRemoveMember,
  canScheduleMeeting,
  canMarkAttendance,
  hasOversight,
  canViewDashboard,
  approvalRouteFor,
  canApproveAccess,
  canChangeTaskStatus,
};

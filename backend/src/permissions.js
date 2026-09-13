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
  if (String(actor._id) === String(target._id)) return true;
  return isSupervisor(actor.role) || actor.role === ROLES.president;
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
 * `'ownDepartment'` → members of the actor's own department, plus the officers
 * `'ownLead'`       → the actor's own department Lead, and nobody else
 * a list of roles   → exactly those roles, club-wide
 *
 * The leadership tier still reaches *departments* through
 * `canAssignToDepartment`; this is only the by-name path.
 * Self-assignment is always allowed and is handled in `canAssignTo`.
 */
const ASSIGN_TARGETS = {
  clubDirector: EXECUTIVE_TIER,
  facultyCoordinator: EXECUTIVE_TIER,
  // The officers address departments, and each other.
  president: [ROLES.vicePresident, ROLES.secretaryGeneral],
  vicePresident: [ROLES.secretaryGeneral],
  secretaryGeneral: [ROLES.vicePresident],
  clubLead: 'ownDepartment',
  clubMember: 'ownLead',
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
  // A member can also *ask* their own Lead rather than assigning outright —
  // "could you look at this?" is a different thing from "this is yours", and
  // both are reasonable for somebody reaching their own Lead.
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
    || targets === 'ownLead'
    || (Array.isArray(targets) && targets.length > 0);
}

/** Same department, and both actually in one. */
const sameDepartment = (a, b) =>
  Boolean(a?.departmentId) && String(a.departmentId) === String(b?.departmentId);

/** May `actor` assign a task to `target`, by name? Both are user documents. */
function canAssignTo(actor, target) {
  if (!actor || !target) return false;
  if (String(actor._id) === String(target._id)) return true; // always yourself

  const rule = ASSIGN_TARGETS[actor.role];

  if (rule === 'ownDepartment') {
    // A Lead owns their department's members — and only members. Reaching into
    // another department is a request, never an assignment. They may also hand
    // work to the club's officers, who have no department to route through.
    if (EXECUTIVE_TIER.includes(target.role)) return true;
    return target.role === ROLES.clubMember && sameDepartment(target, actor);
  }

  if (rule === 'ownLead') {
    // A member reaches exactly one person by name: the Lead of their own
    // department. Not another department's Lead, not the officers.
    return target.role === ROLES.clubLead && sameDepartment(target, actor);
  }

  return Array.isArray(rule) && rule.includes(target.role);
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
  if (!isDirector(actor.role)) return false;
  return !isDirector(target.role) && target.role !== ROLES.facultyCoordinator;
}

/** Audit log and club-wide analytics. */
function canViewAudit(role) {
  return role === ROLES.clubDirector
    || role === ROLES.facultyCoordinator
    || role === ROLES.president;
}

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

/** May `actor` approve `request` (an accessRequests document)? */
function canApproveAccess(actor, request, department) {
  if (actor.approvalStatus !== 'approved') return false;
  // A Director or the Faculty Coordinator can always unblock a stuck queue.
  if (isSupervisor(actor.role)) return true;

  const route = approvalRouteFor(request.requestedRole);
  if (!route) return false;

  if (route.approver === 'departmentLead') {
    const isThatLead =
      actor.role === ROLES.clubLead &&
      department &&
      String(department.leadUserId || '') === String(actor._id);
    if (isThatLead) return true;
    // A department with no Lead yet would otherwise have a permanently stuck
    // queue — and its first member is usually the person who becomes that Lead.
    return actor.role === ROLES.president && !department?.leadUserId;
  }

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
  if (isSupervisor(actor.role)) return true;
  if (actor.role !== ROLES.president) return false;
  return !bill || String(bill.createdBy) !== String(actor._id);
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
  taskVisibilityFilter,
  userVisibilityFilter,
  canViewMemberDetail,
  canViewDepartmentRoster,
  canViewDepartmentProgress,
  canCreateScheduleEntry,
  canEditSchedule,
  canBroadcast,
  canManageDepartments,
  canRemoveMember,
  canViewAudit,
  approvalRouteFor,
  canApproveAccess,
  canChangeTaskStatus,
};

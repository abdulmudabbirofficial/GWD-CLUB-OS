'use strict';

const { col, C } = require('./db');
const { ROLES } = require('./permissions');

/**
 * The bootstrap accounts `src/seed.js` creates so a brand-new database can be
 * signed into at all — two Directors, a Faculty Coordinator, a President and a
 * Lead per department, all on `@gwd.club` — and when they may be retired.
 *
 * Once the club's real people exist these are duplicates, and worse than
 * duplicates: production ended up with five Directors against a cap of three,
 * two Presidents, and six placeholder Leads sitting in the President's approval
 * queue for departments that already had one.
 *
 * But "on the placeholder list" is not a reason to delete an account. The first
 * version of this retired everything on the list, and the list includes
 * `faculty@gwd.club` — which in production **is** the Faculty Coordinator,
 * because nobody else holds that seat. Running it against the live database
 * would have deleted the post.
 *
 * So an account is retired only when all three hold:
 *
 *   1. it is on the list,
 *   2. it has never been used — never signed in, and nothing in the club was
 *      done by it or to it, and
 *   3. somebody real already holds its seat, so retiring it leaves nothing
 *      empty.
 */
const PLACEHOLDER_EMAILS = [
  'director1@gwd.club', 'director2@gwd.club',
  'faculty@gwd.club', 'president@gwd.club',
  'lead.tech@gwd.club', 'lead.production@gwd.club',
  // Retired from earlier seeds, listed so an older database can still be
  // tidied by the same rule.
  'lead.marketing@gwd.club', 'lead.events@gwd.club', 'lead.technical@gwd.club',
  'lead.creative@gwd.club', 'lead.cinematography@gwd.club', 'lead.pr@gwd.club',
];

/** Has anything in the club been done by or to this account? */
async function activityOf(id) {
  const [audit, tasks, events, meetings] = await Promise.all([
    col(C.auditLog).countDocuments({ actorId: id }),
    col(C.tasks).countDocuments({ $or: [{ assignedTo: id }, { assignedBy: id }] }),
    col(C.events).countDocuments({ $or: [{ createdBy: id }, { leadUserId: id }, { teamUserIds: id }] }),
    col(C.meetings).countDocuments({ $or: [{ createdBy: id }, { 'participants.userId': id }] }),
  ]);
  return audit + tasks + events + meetings;
}

/**
 * Work out what may go, and why the rest stays.
 *
 * Returns `{ retire: [user], keep: [{ user, reason }] }` without writing
 * anything, so a caller can print a dry run.
 */
async function planPlaceholderRetirement() {
  const candidates = await col(C.users).find({ email: { $in: PLACEHOLDER_EMAILS } }).toArray();
  const placeholderIds = new Set(candidates.map((u) => String(u._id)));
  const isReal = (u) => u && !placeholderIds.has(String(u._id)) && u.approvalStatus === 'approved';

  const retire = [];
  const keep = [];
  for (const user of candidates) {
    if (user.lastLoginAt) {
      keep.push({ user, reason: 'has been signed into' });
      continue;
    }
    const activity = await activityOf(user._id);
    if (activity > 0) {
      keep.push({ user, reason: `has ${activity} thing(s) in the club attached to it` });
      continue;
    }

    let seatHeld = false;
    if (user.role === ROLES.clubLead) {
      const department = user.departmentId
        ? await col(C.departments).findOne({ _id: user.departmentId })
        : null;
      const namedLead = department?.leadUserId
        ? await col(C.users).findOne({ _id: department.leadUserId })
        : null;
      const anotherLead = user.departmentId
        ? (await col(C.users).find({ role: ROLES.clubLead, departmentId: user.departmentId }).toArray())
          .find(isReal)
        : null;
      seatHeld = isReal(namedLead) || Boolean(anotherLead);
    } else {
      const holders = await col(C.users).find({ role: user.role }).toArray();
      seatHeld = holders.some(isReal);
    }

    if (seatHeld) retire.push(user);
    else keep.push({ user, reason: 'nobody else holds this seat' });
  }
  return { retire, keep };
}

/**
 * Remove accounts, leaving nothing pointing at them.
 *
 * The same cleanup `DELETE /api/users/:id` does, applied to a set: department
 * seats pass to the real Lead, work in flight goes back to its department,
 * and anything addressed to them personally goes with them.
 */
async function retireAccounts(users) {
  if (users.length === 0) return { removed: 0, reassigned: 0 };
  const ids = users.map((u) => u._id);
  let reassigned = 0;

  for (const user of users) {
    const holding = await col(C.departments).find({ leadUserId: user._id }).toArray();
    for (const department of holding) {
      const realLead = await col(C.users).findOne({
        departmentId: department._id,
        role: ROLES.clubLead,
        approvalStatus: 'approved',
        _id: { $nin: ids },
      });
      await col(C.departments).updateOne(
        { _id: department._id },
        { $set: { leadUserId: realLead?._id ?? null } },
      );
      if (realLead) reassigned += 1;
    }
  }

  await col(C.tasks).updateMany({ assignedTo: { $in: ids } }, { $set: { assignedTo: null } });
  const president = await col(C.users).findOne({
    role: ROLES.president, approvalStatus: 'approved', _id: { $nin: ids },
  });
  if (president) {
    await col(C.tasks).updateMany({ assignedBy: { $in: ids } }, { $set: { assignedBy: president._id } });
  }
  await col(C.accessRequests).deleteMany({ userId: { $in: ids } });
  await col(C.notifications).deleteMany({ userId: { $in: ids } });
  await col(C.taskRequests).deleteMany({ $or: [{ toUserId: { $in: ids } }, { fromUserId: { $in: ids } }] });
  await col(C.devices).deleteMany({ userId: { $in: ids } });
  await col(C.users).deleteMany({ _id: { $in: ids } });

  return { removed: users.length, reassigned };
}

module.exports = { PLACEHOLDER_EMAILS, planPlaceholderRetirement, retireAccounts };

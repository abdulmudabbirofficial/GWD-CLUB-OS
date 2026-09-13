'use strict';

const express = require('express');
const { ObjectId } = require('mongodb');
const { col, C } = require('../db');
const { authenticate, requireApproved, publicUser, fail } = require('../auth');
const { ROLES, canApproveAccess, approvalRouteFor, isDirector, rankOf, RANK } = require('../permissions');
const { notify, notifyDirectors, audit } = require('../services/notify');

const router = express.Router();
router.use(authenticate, requireApproved);

const oid = (value, name) => {
  if (!ObjectId.isValid(value)) fail(`${name} is not valid.`);
  return new ObjectId(value);
};

/**
 * The pending-approvals queue (Section 4.3).
 *
 * What you see here is exactly what you are entitled to action:
 *   - a Lead sees their own department's Member requests
 *   - the President sees Lead / VP / Secretary General requests
 *   - a Director sees everything, and can unblock any stuck queue
 */
router.get('/pending', async (request, response, next) => {
  try {
    const actor = request.user;
    const requests = await col(C.accessRequests).find({ status: 'pending' }).sort({ createdAt: 1 }).toArray();
    if (requests.length === 0) return response.json({ requests: [] });

    const [users, departments] = await Promise.all([
      col(C.users).find({ _id: { $in: requests.map((r) => r.userId) } }).toArray(),
      col(C.departments).find({}).toArray(),
    ]);
    const userById = new Map(users.map((u) => [String(u._id), u]));
    const deptById = new Map(departments.map((d) => [String(d._id), d]));

    const actionable = requests.filter((r) =>
      canApproveAccess(actor, r, r.departmentId ? deptById.get(String(r.departmentId)) : null));

    response.json({
      requests: actionable.map((r) => {
        const applicant = userById.get(String(r.userId));
        const department = r.departmentId ? deptById.get(String(r.departmentId)) : null;
        return {
          id: String(r._id),
          userId: String(r.userId),
          requestedRole: r.requestedRole,
          departmentId: r.departmentId ? String(r.departmentId) : null,
          departmentName: department?.name ?? null,
          status: r.status,
          createdAt: r.createdAt,
          applicant: applicant
            ? {
                name: applicant.name,
                email: applicant.email,
                phone: applicant.phone,
                avatarColor: applicant.avatarColor,
                // A seeded Lead account arrives with a placeholder rather than
                // a person's name. Say so here, or the queue asks the President
                // to admit somebody it cannot name.
                mustSetName: applicant.mustSetName === true,
              }
            : null,
        };
      }),
    });
  } catch (error) {
    next(error);
  }
});

/**
 * Directors get read-only visibility of the whole queue, including requests
 * they are not the acting approver for (Section 4.4).
 */
router.get('/all', async (request, response, next) => {
  try {
    if (!isDirector(request.user.role) && rankOf(request.user.role) < RANK.president) {
      fail('You do not have permission to view the full queue.', 403);
    }
    const requests = await col(C.accessRequests).find({}).sort({ createdAt: -1 }).limit(200).toArray();
    const users = await col(C.users).find({ _id: { $in: requests.map((r) => r.userId) } }).toArray();
    const userById = new Map(users.map((u) => [String(u._id), u]));
    response.json({
      requests: requests.map((r) => ({
        id: String(r._id),
        userId: String(r.userId),
        requestedRole: r.requestedRole,
        status: r.status,
        createdAt: r.createdAt,
        decidedAt: r.decidedAt ?? null,
        applicantName: userById.get(String(r.userId))?.name ?? 'Unknown',
      })),
    });
  } catch (error) {
    next(error);
  }
});

async function decide(request, response, next, approve) {
  try {
    const actor = request.user;
    const id = oid(request.params.id, 'Request id');
    const accessRequest = await col(C.accessRequests).findOne({ _id: id });
    if (!accessRequest) fail('Request not found.', 404);
    if (accessRequest.status !== 'pending') fail('That request has already been decided.', 409);

    const department = accessRequest.departmentId
      ? await col(C.departments).findOne({ _id: accessRequest.departmentId })
      : null;

    if (!canApproveAccess(actor, accessRequest, department)) {
      fail('This request is not yours to decide.', 403);
    }

    const applicant = await col(C.users).findOne({ _id: accessRequest.userId });
    if (!applicant) fail('That applicant no longer exists.', 404);

    await col(C.accessRequests).updateOne(
      { _id: id },
      { $set: { status: approve ? 'approved' : 'rejected', approverId: actor._id, decidedAt: new Date() } },
    );

    await col(C.users).updateOne(
      { _id: applicant._id },
      { $set: { approvalStatus: approve ? 'approved' : 'rejected' } },
    );

    if (approve) {
      // A newly approved Lead takes the department's lead seat.
      if (accessRequest.requestedRole === ROLES.clubLead && department && !department.leadUserId) {
        await col(C.departments).updateOne(
          { _id: department._id },
          { $set: { leadUserId: applicant._id } },
        );
      }
      await notify(applicant._id, 'approvalGranted', {});
    } else {
      await notify(applicant._id, 'approvalRejected', {});
    }

    // Keep Directors informed of Lead-level decisions without making them act.
    const route = approvalRouteFor(accessRequest.requestedRole);
    if (route?.notify?.includes(ROLES.clubDirector) && !isDirector(actor.role)) {
      await notifyDirectors('departmentChanged', {
        message: `${applicant.name} was ${approve ? 'approved' : 'declined'} as ${accessRequest.requestedRole} by ${actor.name}.`,
      });
    }

    await audit(actor._id, approve ? 'access.approve' : 'access.reject', {
      applicantId: String(applicant._id),
      role: accessRequest.requestedRole,
    });

    response.json({ ok: true, user: publicUser({ ...applicant, approvalStatus: approve ? 'approved' : 'rejected' }) });
  } catch (error) {
    next(error);
  }
}

router.post('/:id/approve', (req, res, next) => decide(req, res, next, true));
router.post('/:id/reject', (req, res, next) => decide(req, res, next, false));

module.exports = router;

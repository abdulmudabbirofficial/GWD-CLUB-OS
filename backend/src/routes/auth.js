'use strict';

const express = require('express');
const { ObjectId } = require('mongodb');
const { col, C } = require('../db');
const config = require('../config');
const {
  hashPassword, verifyPassword, signToken, publicUser,
  authenticate, fail,
} = require('../auth');
const { ROLES, ROLE_CAPS, approvalRouteFor, isRole } = require('../permissions');
const { notify, notifyDirectors, usersWithRole, audit } = require('../services/notify');
const fcm = require('../services/fcm');

const { loginLimiter, signupLimiter, forgotLimiter } = require('../security');

const router = express.Router();

/**
 * A real bcrypt hash of a value nobody will ever send, compared against when no
 * account matches so that a failed sign-in takes the same time either way.
 * Generated once at startup rather than written in, so it is never a hash of
 * something guessable.
 */
const DUMMY_HASH = require('bcryptjs').hashSync(
  require('node:crypto').randomBytes(32).toString('hex'), 12,
);

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE = /^[+]?[\d\s()-]{7,20}$/;

function text(value, name, { min = 1, max = 200 } = {}) {
  if (typeof value !== 'string' || value.trim().length < min) fail(`${name} is required.`);
  const trimmed = value.trim();
  if (trimmed.length > max) fail(`${name} is too long.`);
  return trimmed;
}

/** Deterministic avatar tint so a member looks the same everywhere. */
function avatarColorFor(seed) {
  const palette = ['#DC2626', '#0B0B0F', '#9F1239', '#334155', '#B45309', '#15803D', '#1D4ED8', '#6D28D9'];
  let hash = 0;
  for (let i = 0; i < seed.length; i += 1) hash = (hash * 31 + seed.charCodeAt(i)) >>> 0;
  return palette[hash % palette.length];
}

/**
 * Sign up (Section 4).
 *
 * The account is created immediately but parked as `pending`; it can sign in
 * and see its own status, and nothing else. An accessRequest is raised and
 * routed to whoever is entitled to action it.
 */
router.post('/signup', signupLimiter, async (request, response, next) => {
  try {
    const name = text(request.body.name, 'Name', { min: 2, max: 80 });
    const email = text(request.body.email, 'Email').toLowerCase();
    const phone = text(request.body.phone, 'Phone number', { min: 7, max: 20 });
    const password = text(request.body.password, 'Password', { min: 8, max: 200 });
    const requestedRole = request.body.role ?? ROLES.clubMember;

    if (!EMAIL.test(email)) fail('Enter a valid email address.');
    if (!PHONE.test(phone)) fail('Enter a valid phone number.');
    if (password.length < 8) fail('Use a password with at least 8 characters.');
    if (!isRole(requestedRole)) fail('Choose a valid role.');
    if (requestedRole === ROLES.clubDirector) {
      fail('Club Director accounts are set up by the club, not through signup.', 403);
    }

    // Departments are required for everyone who sits inside one.
    const needsDepartment = requestedRole === ROLES.clubMember || requestedRole === ROLES.clubLead;
    let department = null;
    if (needsDepartment) {
      const departmentId = text(request.body.departmentId, 'Department');
      if (!ObjectId.isValid(departmentId)) fail('Choose a valid department.');
      department = await col(C.departments).findOne({ _id: new ObjectId(departmentId), active: { $ne: false } });
      if (!department) fail('That department is not available.');
    }

    if (await col(C.users).findOne({ email })) {
      fail('An account with this email already exists.', 409);
    }

    // Singleton roles cannot be double-claimed, even while pending.
    const cap = ROLE_CAPS[requestedRole];
    if (cap) {
      const held = await col(C.users).countDocuments({
        role: requestedRole,
        approvalStatus: { $in: ['approved', 'pending'] },
      });
      if (held >= cap) fail(`The ${requestedRole} position is already filled.`, 409);
    }
    if (requestedRole === ROLES.clubLead && department?.leadUserId) {
      fail('That department already has a Lead.', 409);
    }

    const now = new Date();
    const user = {
      name,
      email,
      phone,
      role: requestedRole,
      departmentId: department?._id ?? null,
      points: 0,
      approvalStatus: 'pending',
      passwordHash: await hashPassword(password),
      avatarColor: avatarColorFor(email),
      createdAt: now,
      lastLoginAt: now,
    };
    const inserted = await col(C.users).insertOne(user);
    user._id = inserted.insertedId;

    const route = approvalRouteFor(requestedRole);
    const accessRequest = {
      userId: user._id,
      departmentId: department?._id ?? null,
      requestedRole,
      approverId: null,
      status: 'pending',
      createdAt: now,
    };

    // Resolve the actual people who can action this.
    let approverIds = [];
    if (route?.approver === 'departmentLead') {
      if (department?.leadUserId) approverIds = [department.leadUserId];
      else approverIds = await usersWithRole(ROLES.president); // no Lead yet — escalate
    } else if (route?.approver) {
      approverIds = await usersWithRole(route.approver);
    }
    if (approverIds.length === 1) accessRequest.approverId = approverIds[0];

    await col(C.accessRequests).insertOne(accessRequest);

    await notify(approverIds, 'approvalNeeded', {
      applicantName: name,
      departmentName: department?.name ?? 'the club',
      requestedRole,
    });

    // Section 4.4 — Directors are told about Lead signups for visibility.
    if (route?.notify?.includes(ROLES.clubDirector)) {
      await notifyDirectors('approvalObserved', {
        applicantName: name,
        departmentName: department?.name ?? 'the club',
        requestedRole,
      });
    }

    await audit(user._id, 'signup', { role: requestedRole, departmentId: department?._id ?? null });

    response.status(201).json({
      token: signToken(user),
      user: publicUser(user),
      message: 'Your request is with the approver. You will be notified once it is reviewed.',
    });
  } catch (error) {
    next(error);
  }
});

router.post('/login', loginLimiter, async (request, response, next) => {
  try {
    const email = text(request.body.email, 'Email').toLowerCase();
    const password = text(request.body.password, 'Password');
    const user = await col(C.users).findOne({ email });

    // Always run a hash comparison, even when there is no such account.
    // Skipping it for an unknown email makes that request measurably faster,
    // which turns this endpoint into a way to discover who has an account —
    // the same leak `/password/forgot` is careful to avoid.
    const hash = user?.passwordHash ?? DUMMY_HASH;
    const correct = await verifyPassword(password, hash);

    if (!user || !correct) {
      fail('Email or password is incorrect.', 401);
    }
    await col(C.users).updateOne({ _id: user._id }, { $set: { lastLoginAt: new Date() } });
    response.json({ token: signToken(user), user: publicUser(user) });
  } catch (error) {
    next(error);
  }
});

router.get('/me', authenticate, async (request, response) => {
  const department = request.user.departmentId
    ? await col(C.departments).findOne({ _id: request.user.departmentId })
    : null;
  response.json({
    user: publicUser(request.user),
    department: department
      ? { id: String(department._id), name: department.name, leadUserId: department.leadUserId ? String(department.leadUserId) : null }
      : null,
    config: { pointsPerTask: config.pointsPerTask, clubName: config.clubName },
  });
});

/**
 * Change your own password.
 *
 * Requires the current one, so a borrowed unlocked phone cannot lock the owner
 * out of their own account. Every session stays valid — tokens are stateless
 * and a club has no "sign out everywhere" expectation.
 */
router.post('/password', authenticate, async (request, response, next) => {
  try {
    const current = text(request.body.currentPassword, 'Current password');
    const next_ = text(request.body.newPassword, 'New password', { min: 8, max: 200 });
    if (next_.length < 8) fail('Use a password with at least 8 characters.');
    if (current === next_) fail('That is the password you already have.');

    if (!(await verifyPassword(current, request.user.passwordHash))) {
      fail('That is not your current password.', 401);
    }

    // Stamping the moment kills every token issued before it — see
    // `authenticate`. Without it, changing a password leaves whoever already
    // had a session signed in for up to thirty more days, which is the one
    // thing the change was meant to stop.
    const changedAt = new Date();
    const updated = await col(C.users).findOneAndUpdate(
      { _id: request.user._id },
      {
        $set: { passwordHash: await hashPassword(next_), passwordChangedAt: changedAt },
        $unset: { mustChangePassword: '', passwordResetRequestedAt: '' },
      },
      { returnDocument: 'after' },
    );
    await audit(request.user._id, 'password.change', {});

    // Hand back a fresh token, or the caller has just invalidated its own
    // session by succeeding.
    response.json({ ok: true, token: signToken(updated), user: publicUser(updated) });
  } catch (error) {
    next(error);
  }
});

/**
 * "I forgot my password."
 *
 * Deliberately **not** an emailed reset link: that needs an SMTP account the
 * club does not have, and a club is not an anonymous internet service — every
 * member can find the President in a corridor.
 *
 * So this raises a flag that a Director or the President actions from the
 * member directory, handing over a temporary password in person or over
 * whatever channel they already trust. The response is identical whether or not
 * the address exists, so this cannot be used to discover who has an account.
 */
router.post('/password/forgot', forgotLimiter, async (request, response, next) => {
  try {
    const email = text(request.body.email, 'Email').toLowerCase();
    const user = await col(C.users).findOne({ email });

    if (user) {
      await col(C.users).updateOne(
        { _id: user._id },
        { $set: { passwordResetRequestedAt: new Date() } },
      );
      const approvers = [
        ...await usersWithRole(ROLES.clubDirector),
        ...await usersWithRole(ROLES.president),
      ];
      await notify(approvers, 'passwordResetRequested', {
        applicantName: user.name,
        applicantEmail: user.email,
      });
      await audit(user._id, 'password.forgot', {});
    }

    response.json({
      ok: true,
      message: 'A Director or the President has been asked to reset it for you. '
        + 'They will pass you a temporary password.',
    });
  } catch (error) {
    next(error);
  }
});

/** Register / drop an FCM device token. No-ops cleanly when push is off. */
router.post('/device', authenticate, async (request, response, next) => {
  try {
    const token = text(request.body.token, 'Device token', { max: 500 });
    await fcm.registerDevice(request.user._id, token, request.body.platform);
    response.json({ ok: true, pushEnabled: fcm.isEnabled() });
  } catch (error) {
    next(error);
  }
});

router.delete('/device', authenticate, async (request, response, next) => {
  try {
    await fcm.unregisterDevice(request.body?.token);
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

module.exports = router;

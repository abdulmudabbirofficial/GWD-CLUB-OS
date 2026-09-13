'use strict';

const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { ObjectId } = require('mongodb');
const config = require('./config');
const { col, C } = require('./db');
const { rankOf, RANK } = require('./permissions');

const hashPassword = (plain) => bcrypt.hash(plain, 12);
const verifyPassword = (plain, hash) => bcrypt.compare(plain, hash);

/**
 * `pwd` stamps which password this token was issued against.
 *
 * Not a comparison against the token's own `iat`: that is only second-accurate,
 * so a token minted in the same second as a password change would survive it —
 * and widening the comparison to catch that would kill the replacement token
 * issued in that same second too. Carrying the exact millisecond makes it an
 * equality check with no window at all.
 *
 * Zero means "no password change on record", which is both the pre-v4 state and
 * a freshly seeded account, so old tokens keep working until something actually
 * changes.
 */
const passwordStamp = (user) =>
  user?.passwordChangedAt ? new Date(user.passwordChangedAt).getTime() : 0;

function signToken(user) {
  return jwt.sign(
    {
      sub: String(user._id),
      role: user.role,
      dept: user.departmentId ? String(user.departmentId) : null,
      pwd: passwordStamp(user),
    },
    config.jwtSecret,
    { expiresIn: config.jwtExpiresIn },
  );
}

function readToken(token) {
  return jwt.verify(token, config.jwtSecret);
}

/**
 * The token carries a role claim, but we re-read the user on every request.
 * A role change or a revoked approval must take effect immediately, not
 * whenever the token happens to expire.
 */
async function loadUser(userId) {
  if (!ObjectId.isValid(userId)) return null;
  return col(C.users).findOne({ _id: new ObjectId(userId) });
}

function publicUser(user) {
  if (!user) return null;
  return {
    id: String(user._id),
    name: user.name,
    email: user.email,
    phone: user.phone ?? null,
    role: user.role,
    departmentId: user.departmentId ? String(user.departmentId) : null,
    points: user.points ?? 0,
    approvalStatus: user.approvalStatus,
    avatarColor: user.avatarColor ?? null,
    createdAt: user.createdAt,
    // Set when an account was created for somebody, or its password was reset
    // by an admin. The app nags until they pick their own — a temporary
    // password everybody keeps is not a password.
    mustChangePassword: user.mustChangePassword === true,
    // True while the account still carries the placeholder it was created with
    // rather than a person's actual name. A flag rather than string-matching
    // the name: "Creative Lead" is a perfectly good name for somebody to have
    // chosen, and guessing from the text would eventually rename a real person.
    mustSetName: user.mustSetName === true,
    // Only ever true for the person asking about themselves, or for an admin
    // looking at the directory — publicUser is not exposed anonymously.
    passwordResetRequested: Boolean(user.passwordResetRequestedAt),
  };
}

class HttpError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

const fail = (message, status = 400) => {
  throw new HttpError(message, status);
};

async function authenticate(request, response, next) {
  try {
    const header = request.headers.authorization || '';
    if (!header.startsWith('Bearer ')) fail('Sign in required.', 401);
    let claims;
    try {
      claims = readToken(header.slice(7));
    } catch {
      fail('Your session has expired. Please sign in again.', 401);
    }
    const user = await loadUser(claims.sub);
    if (!user) fail('This account no longer exists.', 401);

    // A token issued against a previous password is dead.
    //
    // Tokens are stateless and last 30 days, so without this, changing a
    // password does nothing about whoever already has a session — which is the
    // single reason anybody changes one. Exact equality on the millisecond
    // stamp, so there is no same-second window either way (see passwordStamp).
    if ((claims.pwd ?? 0) !== passwordStamp(user)) {
      fail('Your password changed. Please sign in again.', 401);
    }

    request.user = user;
    next();
  } catch (error) {
    next(error);
  }
}

/** Pending and rejected users may read their own status and nothing else. */
function requireApproved(request, response, next) {
  if (request.user?.approvalStatus !== 'approved') {
    return next(new HttpError('Your account is still awaiting approval.', 403));
  }
  return next();
}

function requireRole(...roles) {
  return (request, response, next) => {
    if (!roles.includes(request.user?.role)) {
      return next(new HttpError('You do not have permission to do that.', 403));
    }
    return next();
  };
}

function requireRank(minimumRole) {
  return (request, response, next) => {
    if (rankOf(request.user?.role) < RANK[minimumRole]) {
      return next(new HttpError('You do not have permission to do that.', 403));
    }
    return next();
  };
}

module.exports = {
  hashPassword,
  verifyPassword,
  signToken,
  readToken,
  loadUser,
  publicUser,
  authenticate,
  requireApproved,
  requireRole,
  requireRank,
  HttpError,
  fail,
};

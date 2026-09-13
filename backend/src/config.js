'use strict';

require('dotenv').config();

function required(key, hint) {
  const value = process.env[key];
  if (!value || !value.trim()) {
    throw new Error(
      `Missing ${key}. Copy backend/.env.example to backend/.env and set it.${hint ? ` ${hint}` : ''}`,
    );
  }
  return value.trim();
}

function optional(key, fallback) {
  const value = process.env[key];
  return value && value.trim() ? value.trim() : fallback;
}

const config = {
  port: Number(optional('PORT', '4000')),
  mongoUri: required('MONGODB_URI', 'Change Streams need a replica set — see backend/README.md.'),
  mongoDb: optional('MONGODB_DB', 'gwd_club_os'),
  jwtSecret: required('JWT_SECRET'),
  jwtExpiresIn: optional('JWT_EXPIRES_IN', '30d'),
  clientOrigin: optional('CLIENT_ORIGIN', '*'),
  // One point per task, for everyone. Kept deliberately flat: weighting tasks
  // turns every assignment into a negotiation about what it's worth.
  pointsPerTask: Number(optional('POINTS_PER_TASK', '1')),
  clubName: optional('CLUB_NAME', 'GWD Club'),

  /**
   * Pre-seeded roots of trust (Section 4.5). These accounts skip the approval
   * queue entirely. Format: "Name:email:password" separated by commas.
   */
  seedDirectors: optional('SEED_DIRECTORS', ''),
  seedFaculty: optional('SEED_FACULTY', ''),
  seedPresident: optional('SEED_PRESIDENT', ''),

  /** Optional. Absent means push is simply off; the app still works. */
  firebaseServiceAccount: optional('FIREBASE_SERVICE_ACCOUNT_JSON', ''),

  /**
   * Where uploaded event documents live.
   *
   * Deliberately the local disk rather than a cloud bucket: this runs on one
   * machine on the college network, and a permission letter must still open
   * when the internet does not. Files are served back through an authenticated
   * route, never as a static directory — see routes/documents.js.
   */
  uploadDir: optional('UPLOAD_DIR', ''),
  maxUploadBytes: Number(optional('MAX_UPLOAD_BYTES', String(15 * 1024 * 1024))),

  isProduction: process.env.NODE_ENV === 'production',
};

if (!Number.isFinite(config.pointsPerTask) || config.pointsPerTask < 0) {
  throw new Error('POINTS_PER_TASK must be a non-negative number.');
}

if (!config.uploadDir) {
  config.uploadDir = require('node:path').join(__dirname, '..', 'uploads');
}

module.exports = config;

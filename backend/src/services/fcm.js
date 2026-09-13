'use strict';

const config = require('../config');
const { col, C } = require('../db');

/**
 * Firebase Cloud Messaging — deliberately optional.
 *
 * The brief needs push for when the app is fully closed, but a Firebase
 * project is something only the club owner can create. So this module is
 * written to be completely inert when no service account is configured: the
 * app, the live toasts and the Notifications tab all work over Socket.IO
 * regardless. Dropping in the credentials later switches push on with no code
 * change anywhere else.
 */

let messaging = null;
let state = 'disabled';

function init() {
  if (!config.firebaseServiceAccount) {
    state = 'disabled';
    return { enabled: false, reason: 'No FIREBASE_SERVICE_ACCOUNT_JSON configured.' };
  }
  try {
    // Required lazily so the dependency stays optional at install time.
    // eslint-disable-next-line global-require
    const admin = require('firebase-admin');
    let credential;
    const raw = config.firebaseServiceAccount.trim();
    if (raw.startsWith('{')) {
      credential = admin.credential.cert(JSON.parse(raw));
    } else {
      // Treat it as a path to the service-account JSON file.
      // eslint-disable-next-line global-require, import/no-dynamic-require
      credential = admin.credential.cert(require(require('path').resolve(raw)));
    }
    if (admin.apps.length === 0) admin.initializeApp({ credential });
    messaging = admin.messaging();
    state = 'enabled';
    return { enabled: true };
  } catch (error) {
    state = 'error';
    console.warn('[fcm] disabled —', error.message);
    return { enabled: false, reason: error.message };
  }
}

const isEnabled = () => state === 'enabled' && messaging !== null;

/** Register a device token so this user can receive push. */
async function registerDevice(userId, token, platform) {
  if (!token) return;
  await col(C.devices).updateOne(
    { token },
    {
      $set: { userId, token, platform: platform ?? 'unknown', updatedAt: new Date() },
      $setOnInsert: { createdAt: new Date() },
    },
    { upsert: true },
  );
}

async function unregisterDevice(token) {
  if (!token) return;
  await col(C.devices).deleteOne({ token });
}

async function tokensFor(userIds) {
  const devices = await col(C.devices)
    .find({ userId: { $in: userIds } }, { projection: { token: 1 } })
    .toArray();
  return devices.map((d) => d.token).filter(Boolean);
}

/**
 * Send to every device belonging to these users.
 * A no-op when push is not configured — callers do not branch on it.
 */
async function sendToUsers(userIds, { title, body, data = {} }) {
  if (!isEnabled()) return { sent: 0, skipped: true };
  const tokens = await tokensFor(userIds);
  if (tokens.length === 0) return { sent: 0, skipped: false };

  const response = await messaging.sendEachForMulticast({
    tokens,
    notification: { title, body },
    data,
    android: { priority: 'high', notification: { channelId: 'gwd_club_default' } },
    apns: { payload: { aps: { sound: 'default' } } },
  });

  // Prune tokens Firebase tells us are dead, so the table does not rot.
  const dead = [];
  response.responses.forEach((r, i) => {
    const code = r.error?.code ?? '';
    if (code.includes('registration-token-not-registered') || code.includes('invalid-argument')) {
      dead.push(tokens[i]);
    }
  });
  if (dead.length > 0) await col(C.devices).deleteMany({ token: { $in: dead } });

  return { sent: response.successCount, failed: response.failureCount };
}

module.exports = { init, isEnabled, registerDevice, unregisterDevice, sendToUsers, get state() { return state; } };

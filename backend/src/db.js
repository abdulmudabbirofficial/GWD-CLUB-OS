'use strict';

const { MongoClient } = require('mongodb');
const config = require('./config');

/**
 * Connection pool, sized for the club rather than left to chance.
 *
 * The app is used in bursts — a committee meeting where eighty people open it
 * at once, not a steady trickle — so the pool has to be wide enough that a
 * roomful of simultaneous requests does not queue behind a handful of sockets.
 * `minPoolSize` keeps a few connections warm so the first person after a quiet
 * hour does not pay the handshake.
 *
 * `waitQueueTimeoutMS` is the important one: if the pool is genuinely saturated
 * a request fails in four seconds with an error the client can retry, instead
 * of hanging until the phone gives up and the user decides the app is broken.
 */
const client = new MongoClient(config.mongoUri, {
  maxPoolSize: 100,
  minPoolSize: 5,
  maxIdleTimeMS: 60_000,
  waitQueueTimeoutMS: 4_000,
  serverSelectionTimeoutMS: 5_000,
  // Reads and writes are small; a slow one means something is wrong rather
  // than something is big.
  socketTimeoutMS: 45_000,
  retryWrites: true,
  retryReads: true,
});
let db = null;

/** Collection names in one place so a typo can't silently create a new one. */
const C = {
  users: 'users',
  departments: 'departments',
  tasks: 'tasks',
  taskRequests: 'taskRequests',
  accessRequests: 'accessRequests',
  calendarEvents: 'calendarEvents',
  notifications: 'notifications',
  comments: 'comments',
  auditLog: 'auditLog',
  devices: 'devices',
  broadcasts: 'broadcasts',
  scheduleCategories: 'scheduleCategories',

  // --- Events domain -------------------------------------------------------
  // Distinct from `calendarEvents`, which stays what it is: lightweight
  // schedule entries (a date, a title, a category). An `event` is a project
  // with a team, department responsibilities, tasks and official paperwork.
  events: 'events',
  eventResponsibilities: 'eventResponsibilities',
  eventDocuments: 'eventDocuments',
  helpRequests: 'helpRequests',

  /**
   * Meetings, with their invitee list and attendance on the same document.
   *
   * Distinct from `calendarEvents`, where "Meeting" is only a category — a
   * schedule row is a date and a title, and cannot say who was asked, who
   * turned up, or what anybody's attendance record is.
   *
   * Participants are a **snapshot** taken when the meeting is created, not a
   * live department query. If somebody leaves Marketing next week, the record
   * of who was invited to last week's Marketing meeting must not change
   * underneath it — attendance history that rewrites itself is worthless.
   */
  meetings: 'meetings',

  // What an event cost, and whether the person who paid has been repaid.
  // A record and an approval trail — it never moves money, and deliberately
  // stores no bank details.
  eventBills: 'eventBills',
};

function database() {
  if (!db) throw new Error('Database accessed before connect().');
  return db;
}

const col = (name) => database().collection(name);

/**
 * Indexes.
 *
 * Note what is deliberately absent: v1 had a unique index on
 * `{workspaceId, role}` in `users`, which capped the whole app at one account
 * per role. A club has many Members. That index must never come back.
 */
async function ensureIndexes() {
  const d = database();
  await Promise.all([
    d.collection(C.users).createIndex({ email: 1 }, { unique: true }),
    d.collection(C.users).createIndex({ departmentId: 1, role: 1 }),
    d.collection(C.users).createIndex({ approvalStatus: 1 }),

    d.collection(C.departments).createIndex({ active: 1 }),
    d.collection(C.departments).createIndex({ name: 1 }, { unique: true }),

    // Section 9: scope these three for fast per-role queries.
    d.collection(C.tasks).createIndex({ assignedTo: 1, status: 1 }),
    d.collection(C.tasks).createIndex({ assignedBy: 1 }),
    d.collection(C.tasks).createIndex({ departmentId: 1 }),
    // Change Stream cursor resumption.
    d.collection(C.tasks).createIndex({ updatedAt: -1 }),
    d.collection(C.tasks).createIndex({ dueDate: 1 }),
    // The daily reminder sweep and the personal calendar both ask the same
    // question — "open, mine, due by then" — and it would otherwise scan every
    // task the club has ever created, growing slower every term.
    d.collection(C.tasks).createIndex({ status: 1, dueDate: 1, assignedTo: 1 }),

    d.collection(C.taskRequests).createIndex({ toUserId: 1, status: 1 }),
    d.collection(C.taskRequests).createIndex({ fromUserId: 1 }),

    d.collection(C.accessRequests).createIndex({ status: 1, departmentId: 1 }),
    d.collection(C.accessRequests).createIndex({ userId: 1 }),

    d.collection(C.calendarEvents).createIndex({ date: 1 }),
    // The schedule is queried category-by-category far more often than whole.
    d.collection(C.calendarEvents).createIndex({ categoryId: 1, date: 1 }),

    d.collection(C.scheduleCategories).createIndex({ name: 1 }, { unique: true }),
    d.collection(C.scheduleCategories).createIndex({ active: 1, order: 1 }),

    // Events are browsed by status and date far more than anything else.
    d.collection(C.events).createIndex({ status: 1, date: 1 }),
    d.collection(C.events).createIndex({ date: -1 }),
    d.collection(C.events).createIndex({ organizingDepartmentId: 1 }),

    d.collection(C.eventResponsibilities).createIndex({ eventId: 1, departmentId: 1 }, { unique: true }),
    d.collection(C.eventDocuments).createIndex({ eventId: 1, kind: 1 }),
    // Event work is the hot path on the Kanban board.
    d.collection(C.tasks).createIndex({ eventId: 1, status: 1 }),

    // Meetings are read two ways: "what is coming up" and "what was this
    // person invited to", the second being how every attendance figure in the
    // app is derived.
    d.collection(C.meetings).createIndex({ date: -1 }),
    d.collection(C.meetings).createIndex({ 'participants.userId': 1, date: -1 }),
    d.collection(C.meetings).createIndex({ status: 1, date: -1 }),

    d.collection(C.helpRequests).createIndex({ status: 1, createdAt: -1 }),
    d.collection(C.helpRequests).createIndex({ departmentId: 1 }),

    d.collection(C.eventBills).createIndex({ eventId: 1, status: 1 }),
    d.collection(C.eventBills).createIndex({ createdBy: 1 }),

    d.collection(C.broadcasts).createIndex({ createdAt: -1 }),
    d.collection(C.broadcasts).createIndex({ audience: 1, departmentId: 1 }),

    d.collection(C.notifications).createIndex({ userId: 1, read: 1, createdAt: -1 }),

    d.collection(C.comments).createIndex({ taskId: 1, createdAt: 1 }),

    d.collection(C.auditLog).createIndex({ createdAt: -1 }),
    d.collection(C.auditLog).createIndex({ actorId: 1 }),

    d.collection(C.devices).createIndex({ userId: 1 }),
    d.collection(C.devices).createIndex({ token: 1 }, { unique: true }),
  ]);
}

/**
 * Are Change Streams available?
 *
 * They require a replica set or sharded cluster. A standalone mongod silently
 * has no oplog to watch, so we detect it up front and degrade to emitting
 * events directly from the write path instead of pretending live sync works.
 */
async function supportsChangeStreams() {
  try {
    const info = await database().admin().command({ hello: 1 });
    return Boolean(info.setName || info.msg === 'isdbgrid');
  } catch {
    return false;
  }
}

async function connect() {
  await client.connect();
  db = client.db(config.mongoDb);
  await ensureIndexes();
  const live = await supportsChangeStreams();
  return { live };
}

async function close() {
  await client.close();
  db = null;
}

module.exports = { client, connect, close, database, col, C, ensureIndexes, supportsChangeStreams };

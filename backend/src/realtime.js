'use strict';

const { Server } = require('socket.io');
const config = require('./config');
const { readToken, loadUser } = require('./auth');
const { col, C, database } = require('./db');
const { ROLES, rankOf, RANK } = require('./permissions');

/**
 * Real-time layer.
 *
 * MongoDB is the system of record. A Change Stream on each collection fires the
 * instant a document changes — no matter which client or process wrote it — and
 * we fan that out over Socket.IO to exactly the clients entitled to see it.
 *
 * Routes therefore never emit socket events themselves. They just write to
 * Mongo. That is what keeps web and mobile genuinely in sync: a task completed
 * on web travels web → Mongo → change stream → socket → phone, with no special
 * casing per client.
 */

/** Room names. Membership is decided from the server-side user record only. */
const room = {
  user: (id) => `user:${id}`,
  dept: (id) => `dept:${id}`,
  leadership: 'leadership', // Directors, President, VP, Secretary General
  club: 'club', // everyone approved — calendar, announcements
};

let io = null;
const watchers = [];

function attach(httpServer) {
  io = new Server(httpServer, {
    cors: { origin: config.clientOrigin, methods: ['GET', 'POST', 'PATCH', 'DELETE'] },
    // Mobile networks drop; give clients room to resume before we cut them.
    pingTimeout: 30000,
  });

  io.use(async (socket, next) => {
    try {
      const token = socket.handshake.auth?.token;
      if (!token) return next(new Error('Authentication required.'));
      const claims = readToken(token);
      const user = await loadUser(claims.sub);
      if (!user) return next(new Error('Account not found.'));
      if (user.approvalStatus !== 'approved') {
        return next(new Error('Account awaiting approval.'));
      }
      socket.data.user = user;
      return next();
    } catch {
      return next(new Error('Authentication required.'));
    }
  });

  io.on('connection', (socket) => {
    const user = socket.data.user;
    socket.join(room.user(String(user._id)));
    socket.join(room.club);
    if (user.departmentId) socket.join(room.dept(String(user.departmentId)));
    if (rankOf(user.role) >= RANK.vicePresident) socket.join(room.leadership);

    socket.emit('ready', {
      userId: String(user._id),
      role: user.role,
      departmentId: user.departmentId ? String(user.departmentId) : null,
      serverTime: new Date().toISOString(),
    });

    // Presence is useful for "who is online" but must never leak across
    // departments, so it is announced only to the user's own rooms.
    socket.on('disconnect', () => {});
  });

  return io;
}

function emitTo(rooms, event, payload) {
  if (!io) return;
  const unique = [...new Set(rooms.filter(Boolean))];
  if (unique.length === 0) return;
  io.to(unique).emit(event, payload);
}

const idOf = (value) => (value ? String(value) : null);

/**
 * Who is entitled to hear about this task?
 *
 * Owner, assigner, the owning department, and leadership (who have app-wide
 * visibility). A Member in another department matches none of these and so is
 * never sent the event at all — the scoping is enforced at emit time, not by
 * asking the client to filter.
 */
function taskAudience(task) {
  return [
    task.assignedTo && room.user(idOf(task.assignedTo)),
    task.assignedBy && room.user(idOf(task.assignedBy)),
    task.departmentId && room.dept(idOf(task.departmentId)),
    room.leadership,
    // Work that belongs to an event is club-wide knowledge, the same way the
    // event itself is: anyone can open the event and watch its board move.
    task.eventId && room.club,
  ];
}

function serialiseTask(task) {
  if (!task) return null;
  return {
    id: idOf(task._id),
    title: task.title,
    description: task.description ?? '',
    assignedBy: idOf(task.assignedBy),
    assignedTo: idOf(task.assignedTo),
    departmentId: idOf(task.departmentId),
    eventId: idOf(task.eventId),
    status: task.status,
    dueDate: task.dueDate ?? null,
    points: task.points ?? 0,
    priority: task.priority ?? 'normal',
    createdAt: task.createdAt ?? null,
    updatedAt: task.updatedAt ?? null,
    completedAt: task.completedAt ?? null,
  };
}

function serialiseNotification(n) {
  return {
    id: idOf(n._id),
    userId: idOf(n.userId),
    type: n.type,
    payload: n.payload ?? {},
    read: Boolean(n.read),
    createdAt: n.createdAt,
  };
}

/**
 * Start one Change Stream per collection we care about.
 *
 * `fullDocument: 'updateLookup'` makes an update carry the whole post-update
 * document, so clients can render without a follow-up fetch.
 */
function startWatchers() {
  const specs = [
    {
      name: C.tasks,
      handler: (change) => {
        const doc = change.fullDocument;
        if (!doc) return;
        const payload = serialiseTask(doc);
        const event =
          change.operationType === 'insert' ? 'task:created' : 'task:updated';
        emitTo(taskAudience(doc), event, payload);
      },
    },
    {
      name: C.notifications,
      handler: (change) => {
        if (change.operationType !== 'insert') return;
        const doc = change.fullDocument;
        if (!doc) return;
        // Notifications are addressed to exactly one person.
        emitTo([room.user(idOf(doc.userId))], 'notification:new', serialiseNotification(doc));
      },
    },
    {
      name: C.taskRequests,
      handler: (change) => {
        const doc = change.fullDocument;
        if (!doc) return;
        emitTo(
          [room.user(idOf(doc.fromUserId)), room.user(idOf(doc.toUserId))],
          change.operationType === 'insert' ? 'taskRequest:created' : 'taskRequest:updated',
          {
            id: idOf(doc._id),
            fromUserId: idOf(doc.fromUserId),
            toUserId: idOf(doc.toUserId),
            title: doc.title ?? '',
            description: doc.description ?? '',
            status: doc.status,
            createdAt: doc.createdAt,
          },
        );
      },
    },
    {
      name: C.accessRequests,
      handler: async (change) => {
        const doc = change.fullDocument;
        if (!doc) return;
        // Approval queues are visible to the approver and to leadership.
        emitTo(
          [
            doc.departmentId && room.dept(idOf(doc.departmentId)),
            room.leadership,
            doc.userId && room.user(idOf(doc.userId)),
          ],
          change.operationType === 'insert' ? 'accessRequest:created' : 'accessRequest:updated',
          {
            id: idOf(doc._id),
            userId: idOf(doc.userId),
            departmentId: idOf(doc.departmentId),
            requestedRole: doc.requestedRole,
            status: doc.status,
            createdAt: doc.createdAt,
          },
        );
      },
    },
    {
      name: C.calendarEvents,
      handler: (change) => {
        const doc = change.fullDocument;
        const id = idOf(change.documentKey?._id);
        if (change.operationType === 'delete') {
          emitTo([room.club], 'schedule:deleted', { id });
          return;
        }
        if (!doc) return;
        // The schedule is club-wide knowledge by design — every member should
        // see what the club is doing, live.
        // The category's name and colour are not on the document, so the client
        // refetches rather than being handed a half-rendered entry.
        emitTo([room.club], change.operationType === 'insert' ? 'schedule:created' : 'schedule:updated', {
          id: idOf(doc._id),
          categoryId: idOf(doc.categoryId),
          title: doc.title,
          date: doc.date,
        });
      },
    },
    {
      name: C.broadcasts,
      handler: (change) => {
        if (change.operationType !== 'insert') return;
        const doc = change.fullDocument;
        if (!doc) return;
        // Scope the live delivery the same way the broadcast itself was scoped.
        const audience = doc.audience === 'department' && doc.departmentId
          ? [room.dept(idOf(doc.departmentId))]
          : doc.audience === 'leadership'
            ? [room.leadership]
            : [room.club];
        emitTo(audience, 'alert:new', {
          id: idOf(doc._id),
          title: doc.title,
          message: doc.message,
          urgency: doc.urgency,
          audience: doc.audience,
          senderName: doc.senderName,
          senderRole: doc.senderRole,
          senderId: idOf(doc.senderId),
          createdAt: doc.createdAt,
        });
      },
    },
    {
      name: C.departments,
      handler: (change) => {
        const doc = change.fullDocument;
        const id = idOf(change.documentKey?._id);
        if (change.operationType === 'delete') {
          emitTo([room.club], 'department:deleted', { id });
          return;
        }
        if (!doc) return;
        // Department structure is club-wide knowledge.
        emitTo([room.club], change.operationType === 'insert' ? 'department:created' : 'department:updated', {
          id: idOf(doc._id),
          name: doc.name,
          description: doc.description ?? '',
          leadUserId: idOf(doc.leadUserId),
          active: doc.active !== false,
          colorSeed: doc.colorSeed ?? null,
        });
      },
    },
    {
      // An event is club-wide knowledge: everybody should see the club's plans
      // appear and move without reopening the app.
      name: C.events,
      handler: (change) => {
        const id = idOf(change.documentKey?._id);
        if (change.operationType === 'delete') {
          emitTo([room.club], 'event:deleted', { id });
          return;
        }
        const doc = change.fullDocument;
        if (!doc) return;
        emitTo([room.club], change.operationType === 'insert' ? 'event:created' : 'event:updated', {
          id: idOf(doc._id),
          name: doc.name,
          date: doc.date,
          status: doc.status,
          venue: doc.venue ?? '',
          organizingDepartmentId: idOf(doc.organizingDepartmentId),
          leadUserId: idOf(doc.leadUserId),
        });
      },
    },
    {
      name: C.eventDocuments,
      handler: (change) => {
        const id = idOf(change.documentKey?._id);
        const doc = change.fullDocument;
        // Only the fact that something changed travels live. Whether the
        // recipient may see the document itself is decided by the route that
        // serves it, so nothing sensitive rides on the socket.
        emitTo([room.club], 'eventDocument:changed', {
          id,
          eventId: idOf(doc?.eventId),
          kind: doc?.kind ?? null,
          status: doc?.status ?? null,
          removed: change.operationType === 'delete',
        });
      },
    },
    {
      name: C.helpRequests,
      handler: (change) => {
        const id = idOf(change.documentKey?._id);
        if (change.operationType === 'delete') {
          emitTo([room.club], 'help:deleted', { id });
          return;
        }
        const doc = change.fullDocument;
        if (!doc) return;
        emitTo([room.club], change.operationType === 'insert' ? 'help:created' : 'help:updated', {
          id,
          status: doc.status,
          departmentId: idOf(doc.departmentId),
        });
      },
    },
    {
      name: C.users,
      handler: (change) => {
        const doc = change.fullDocument;
        if (!doc) return;
        // Points and role changes matter to the person and to leadership.
        emitTo(
          [room.user(idOf(doc._id)), doc.departmentId && room.dept(idOf(doc.departmentId)), room.leadership],
          'user:updated',
          {
            id: idOf(doc._id),
            name: doc.name,
            role: doc.role,
            departmentId: idOf(doc.departmentId),
            points: doc.points ?? 0,
            approvalStatus: doc.approvalStatus,
          },
        );
      },
    },
  ];

  for (const spec of specs) {
    startOne(spec);
  }
}

function startOne(spec, resumeAfter = undefined) {
  let stream;
  try {
    stream = col(spec.name).watch([], {
      fullDocument: 'updateLookup',
      ...(resumeAfter ? { resumeAfter } : {}),
    });
  } catch (error) {
    console.error(`[realtime] could not watch ${spec.name}:`, error.message);
    return;
  }

  stream.on('change', (change) => {
    try {
      spec.handler(change);
    } catch (error) {
      console.error(`[realtime] handler error on ${spec.name}:`, error.message);
    }
  });

  stream.on('error', (error) => {
    console.error(`[realtime] ${spec.name} stream error:`, error.message);
    // Resume from the last token we saw so no change is silently dropped.
    const token = stream.resumeToken;
    stream.close().catch(() => {});
    setTimeout(() => startOne(spec, token), 2000);
  });

  watchers.push(stream);
}

async function stopWatchers() {
  await Promise.all(watchers.map((w) => w.close().catch(() => {})));
  watchers.length = 0;
}

/**
 * Fallback for a standalone mongod with no oplog: routes call this after a
 * write so the app still feels live in local development. When Change Streams
 * are available this is never called — the stream is the only source.
 */
function emitFallback(kind, doc) {
  switch (kind) {
    case 'task':
      emitTo(taskAudience(doc), 'task:updated', serialiseTask(doc));
      break;
    case 'notification':
      emitTo([room.user(idOf(doc.userId))], 'notification:new', serialiseNotification(doc));
      break;
    default:
      break;
  }
}

module.exports = {
  attach,
  startWatchers,
  stopWatchers,
  emitTo,
  emitFallback,
  room,
  serialiseTask,
  serialiseNotification,
  get io() {
    return io;
  },
};

'use strict';

const http = require('http');
const os = require('os');
const path = require('path');
const compression = require('compression');
const cors = require('cors');
const express = require('express');

const config = require('./config');
const db = require('./db');
const realtime = require('./realtime');
const seed = require('./seed');
const fcm = require('./services/fcm');
const reminders = require('./services/reminders');
const security = require('./security');
const { HttpError } = require('./auth');

const app = express();
const server = http.createServer(app);

app.disable('x-powered-by');

// Behind a hosting proxy (Render sets RENDER), every request arrives from the
// proxy's address unless Express is told to read the forwarded one. Every
// IP-keyed limit then treated the whole club as one visitor: sixty sign-ups an
// hour, for everybody. Only trusted when there really is a proxy - on the
// laptop there is none, and trusting the header would let anybody pick their
// own address and step round the limits.
if (process.env.TRUST_PROXY || process.env.RENDER) {
  app.set('trust proxy', Number(process.env.TRUST_PROXY) || 1);
}

// gzip every response worth compressing.
//
// This backend serves a roomful of phones over one Wi-Fi hotspot, and its
// payloads are JSON — member lists, task lists, event workspaces — which
// compress to roughly a fifth of their size. That is the difference between a
// screen that fills instantly and one that visibly waits, and it costs a little
// CPU on a laptop that has plenty.
//
// Already-compressed bodies are skipped: file downloads stream through the
// documents and receipts routes, and re-compressing a JPEG or a PDF spends CPU
// to make the response slightly bigger.
app.use(compression({
  threshold: 1024,
  filter: (request, response) => {
    if (request.headers['x-no-compression']) return false;
    const type = String(response.getHeader('Content-Type') || '');
    if (/^(image|video|audio)\//.test(type) || type.includes('zip')) return false;
    return compression.filter(request, response);
  },
}));

app.use(security.headers);
app.use(cors({ origin: config.clientOrigin }));
app.use(express.json({ limit: '1mb' }));

// Strip Mongo operators out of body, query and params before any route sees
// them. Express turns `?role[$ne]=x` into a real operator object, and a route
// that drops a query value into a filter then offers a caller something it
// never meant to. Defence in depth: individual routes validate too.
app.use(security.sanitize);

// A ceiling on any one client. Mounted on /api only: the web build's own
// assets are static files and a member loading the app pulls dozens of them at
// once, which would burn a request budget meant for API calls.
app.use('/api', security.apiCeiling, security.apiLimiter);

// The Flutter web build, when one has been produced.
const webBuild = path.join(__dirname, '../../app/build/web');
app.use(express.static(webBuild));

app.get('/api/health', async (request, response) => {
  let mongo = 'down';
  let live = false;
  try {
    await db.database().command({ ping: 1 });
    mongo = 'up';
    live = await db.supportsChangeStreams();
  } catch {
    mongo = 'down';
  }
  response.json({
    service: 'GWD Club OS API',
    status: mongo === 'up' ? 'online' : 'degraded',
    mongo,
    changeStreams: live,
    push: fcm.state,
    // Whether the website actually shipped with this deploy. The web build is
    // optional and allowed to fail without taking the API down, so this is the
    // difference between "the site is missing" and "the whole deploy is stale"
    // — two things that look identical from outside and have opposite fixes.
    web: require('node:fs').existsSync(path.join(webBuild, 'index.html'))
      ? 'served' : 'missing',
    // The commit this process is running, when Render provides it. Without it,
    // a failed deploy and a successful one are indistinguishable from here.
    commit: (process.env.RENDER_GIT_COMMIT ?? '').slice(0, 7) || null,
    serverTime: new Date().toISOString(),
  });
});

app.use('/api/auth', require('./routes/auth'));
app.use('/api/departments', require('./routes/departments'));
app.use('/api/tasks', require('./routes/tasks'));
app.use('/api/task-requests', require('./routes/taskRequests'));
app.use('/api/access', require('./routes/access'));
app.use('/api/users', require('./routes/users'));
// The schedule replaces the old generic calendar: the same collection, but
// organised into lanes (events, meetings, marketing, task deadlines) because
// that is how a club actually plans. The old /api/calendar route is gone rather
// than left as a broken alias.
app.use('/api/categories', require('./routes/categories'));
app.use('/api/schedule', require('./routes/schedule'));
// Events are projects, not schedule rows — see routes/events.js. Documents
// mount at /api because they are addressed both under an event and on their
// own (a decision or a download names the document, not the event).
app.use('/api/events', require('./routes/events'));
// Its own path rather than /api/events/templates, which would be shadowed by
// the `/:id` route above and answer "templates is not a valid event id".
app.use('/api/event-templates', require('./routes/eventTemplates'));
app.use('/api', require('./routes/documents'));
// Bookkeeping for what an event cost, and an approval trail for repaying it.
// Mounted at /api for the same reason as documents: a bill is addressed both
// under its event and on its own.
app.use('/api', require('./routes/finance'));
// Meetings are a domain of their own, not a schedule category: they carry an
// invitee list and an attendance record, which a calendar row cannot.
app.use('/api/meetings', require('./routes/meetings'));
app.use('/api/help', require('./routes/help'));
app.use('/api/alerts', require('./routes/alerts'));
app.use('/api/notifications', require('./routes/notifications'));
app.use('/api', require('./routes/summary'));

// Single-page-app fallback for the Flutter web build.
app.get('*', (request, response, next) => {
  if (request.path.startsWith('/api') || request.path.startsWith('/socket.io')) return next();
  response.sendFile(path.join(webBuild, 'index.html'), (error) => {
    if (error) {
      response
        .status(404)
        .type('text/plain')
        .send('GWD Club OS API is running. Build the Flutter web app to serve the client from here.');
    }
  });
});

// eslint-disable-next-line no-unused-vars
app.use((error, request, response, next) => {
  const status = error instanceof HttpError ? error.status : error.status || 500;
  if (status >= 500) console.error(error);
  response.status(status).json({ error: status >= 500 ? 'Something went wrong on our side.' : error.message });
});

function lanAddress() {
  for (const list of Object.values(os.networkInterfaces())) {
    for (const iface of list ?? []) {
      if (iface.family === 'IPv4' && !iface.internal) return iface.address;
    }
  }
  return 'localhost';
}

async function start() {
  const { live } = await db.connect();
  console.log(`✅ MongoDB connected  (db: ${config.mongoDb})`);

  const report = await seed.run();
  const seeded = [
    ...report.directors.map((d) => `director ${d.email} ${d.action}`),
    ...report.faculty.map((f) => `faculty ${f.email} ${f.action}`),
    ...report.president.map((p) => `president ${p.email} ${p.action}`),
  ];
  if (seeded.length > 0) console.log('👤 ' + seeded.join('  |  '));
  console.log(`🏷️  departments ${report.departments.action} (${report.departments.count})`);

  // Printed exactly once, when the accounts are first created. The hashes are
  // one-way, so there is no second chance to read these — copy them now.
  if (report.leads.length > 0) {
    console.log('');
    console.log('🔑 Department Lead accounts created — awaiting approval');
    console.log('   Their passwords are not printed. Once the President approves');
    console.log('   one, the Club Director sets a temporary password from the');
    console.log('   member page (Reset their password) and hands it over; the');
    console.log('   holder chooses their own the first time they sign in.');
    console.log('');
    for (const lead of report.leads) {
      // Never the password itself: this output lands in server.log and in the
      // host's log viewer, where anybody who can read logs could sign in.
      console.log(`   ${lead.department.padEnd(26)} ${lead.email}`);
    }
    console.log('');
  }

  const push = fcm.init();
  console.log(push.enabled ? '🔔 FCM push enabled' : `🔕 FCM push off — ${push.reason}`);

  realtime.attach(server);
  if (live) {
    realtime.startWatchers();
    console.log('⚡ Change Streams active — live sync is on');
  } else {
    console.warn(
      '⚠️  Change Streams unavailable: MongoDB is not running as a replica set.\n' +
      '   Live sync will not work. See backend/README.md to start mongod with --replSet.',
    );
  }

  // The daily "you still have this open" nudge. One message per person per
  // day, only when something is actually due — see services/reminders.js.
  reminders.start();
  console.log(`⏰ Daily reminders on (from ${process.env.REMINDER_HOUR ?? 9}:00 local)`);

  server.listen(config.port, '0.0.0.0', () => {
    const lan = lanAddress();
    console.log('='.repeat(64));
    console.log(`🚀 ${config.clubName} OS — API + realtime gateway`);
    console.log(`   Local        http://localhost:${config.port}`);
    console.log(`   LAN / phone  http://${lan}:${config.port}`);
    console.log(`   WebSocket    ws://${lan}:${config.port}`);
    console.log('='.repeat(64));
  });
}

async function shutdown() {
  console.log('\nShutting down…');
  await realtime.stopWatchers();
  server.close();
  await db.close();
  process.exit(0);
}

// A stray rejected promise must not take the whole club offline. Logged, and
// the server keeps serving; every route already answers its own errors.
process.on('unhandledRejection', (error) => {
  console.error('[unhandled rejection]', error instanceof Error ? error.message : error);
});

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

start().catch((error) => {
  console.error('Unable to start the GWD Club OS API.\n', error.message);
  process.exit(1);
});

'use strict';

/**
 * The contract between the app and the server, checked by reading both.
 *
 *   node scripts/test-contract.js
 *
 * Needs no server and no database. It exists because of two gaps that no
 * running test could see, and that had both been open for weeks:
 *
 *   1. **Live events the app never subscribed to.** The server emitted
 *      twenty-eight kinds of live update and the store had a handler for every
 *      one, but the socket's subscription list stopped at fourteen — so events,
 *      meetings, the schedule, the help board, comments, documents, bills,
 *      categories and club alerts never arrived live on any client. Toasts
 *      still worked (`notification:new` was on the list), so it looked fine.
 *   2. **Endpoints the app calls that do not exist**, and store methods that
 *      exist and nothing calls. The first is a feature that fails on tap; the
 *      second, here, is a feature the server has and no screen offers.
 *
 * Both are the same mistake — two lists that must agree, maintained by hand in
 * two languages — so this reads both sides and says where they disagree.
 */

const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..', '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const walk = (dir, ext) => fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true })
  .flatMap((e) => (e.isDirectory()
    ? walk(path.join(dir, e.name), ext)
    : e.name.endsWith(ext) ? [path.join(dir, e.name)] : []));

let passed = 0;
let failed = 0;
const ok = (label, cond, detail = '') => {
  if (cond) { passed += 1; console.log(`  PASS  ${label}`); return; }
  failed += 1;
  console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`);
};

// --- live events -----------------------------------------------------------------
const serverSources = [
  'backend/src/realtime.js',
  ...walk('backend/src/routes', '.js'),
  ...walk('backend/src/services', '.js'),
].map(read).join('\n');

// Emitted names are 'noun:verb' literals passed to emitTo / io.to().emit, or
// either side of the insert-or-update ternary the change streams use.
const emitted = new Set();
for (const m of serverSources.matchAll(/(?:emitTo\([^;]*?|\?\s*|:\s*|emit\()\s*'([a-zA-Z]+:(?:created|updated|deleted|changed|new))'/g)) {
  emitted.add(m[1]);
}

const socketClient = read('app/lib/core/api/socket_client.dart');
const listBlock = socketClient.match(/static const eventNames = <String>\[([\s\S]*?)\];/);
const subscribed = new Set(listBlock ? [...listBlock[1].matchAll(/'([^']+)'/g)].map((m) => m[1]) : []);

const store = read('app/lib/core/state/club_store.dart');
const handled = new Set([...store.matchAll(/case '([a-zA-Z]+:[a-zA-Z]+)'/g)].map((m) => m[1]));

console.log('\nlive events: server → socket → store');
ok(`the server emits live events (${emitted.size} kinds found)`, emitted.size >= 20);
const unsubscribed = [...emitted].filter((e) => !subscribed.has(e)).sort();
ok('every event the server sends is one the app subscribes to',
  unsubscribed.length === 0, `never delivered: ${unsubscribed.join(', ')}`);
const unhandled = [...emitted].filter((e) => !handled.has(e)).sort();
ok('and one the store does something with',
  unhandled.length === 0, `dropped on arrival: ${unhandled.join(', ')}`);
const stale = [...subscribed].filter((e) => !emitted.has(e)).sort();
ok('the app subscribes to nothing the server has stopped sending',
  stale.length === 0, `listening for: ${stale.join(', ')}`);

// --- API calls ---------------------------------------------------------------------
const index = read('backend/src/index.js');
const routes = [];
for (const m of index.matchAll(/app\.use\('([^']+)',\s*require\('\.\/routes\/([a-zA-Z]+)'\)\)/g)) {
  const [, prefix, mod] = m;
  const src = read(`backend/src/routes/${mod}.js`);
  for (const r of src.matchAll(/router\.(get|post|patch|put|delete)\(\s*'([^']*)'/g)) {
    const full = (prefix.replace(/\/$/, '') + (r[2] === '/' ? '' : r[2])) || '/';
    routes.push({ method: r[1].toUpperCase(), path: full });
  }
}
for (const m of index.matchAll(/app\.(get|post|patch|put|delete)\(\s*'(\/api[^']*)'/g)) {
  routes.push({ method: m[1].toUpperCase(), path: m[2] });
}
const routeMatchers = routes.map((r) => ({
  ...r,
  re: new RegExp(`^${r.path.replace(/:[A-Za-z]+/g, '[^/]+')}$`),
}));

const dartFiles = walk('app/lib', '.dart');
const calls = [];
for (const file of dartFiles) {
  const text = read(file);
  // `_api.get('/api/...'` and the same call split across lines.
  // An interpolation is taken whole, quotes and all: a path that picks its
  // last segment with `${accept ? 'accept' : 'decline'}` is one call, not a
  // string that ends at the first quote inside it.
  for (const m of text.matchAll(/_api\s*\.\s*(get|post|patch|put|delete)\(\s*'(\/api(?:[^'$]|\$\{[^}]*\}|\$(?!\{))*)'/g)) {
    const pathOnly = m[2]
      .replace(/\$\{[^}]*\}/g, 'X')
      .replace(/\$[A-Za-z_][A-Za-z0-9_]*/g, 'X')
      .split('?')[0];
    const line = text.slice(0, m.index).split('\n').length;
    calls.push({ method: m[1].toUpperCase(), path: pathOnly, where: `${file.replace(/\\/g, '/')}:${line}` });
  }
}

console.log('\nAPI calls: app → server');
ok(`the app calls the API (${calls.length} calls found)`, calls.length >= 80);
// Either side may hold the wildcard: `/api/tasks/X` against the route
// `/api/tasks/:id`, or `/api/task-requests/X/X` — whose last segment is chosen
// at runtime — against the literal `/api/task-requests/:id/accept`.
const clientRe = (p) => new RegExp(`^${p.replace(/X/g, '[^/]+')}$`);
const unrouted = calls.filter((c) => !routeMatchers.some((r) => r.method === c.method
  && (r.re.test(c.path) || clientRe(c.path).test(r.path.replace(/:[A-Za-z]+/g, 'P')))));
ok('every endpoint the app calls exists on the server',
  unrouted.length === 0,
  unrouted.map((c) => `${c.method} ${c.path} (${c.where})`).join('; '));

console.log(`\n  ${passed} passed, ${failed} failed\n`);
process.exit(failed === 0 ? 0 : 1);

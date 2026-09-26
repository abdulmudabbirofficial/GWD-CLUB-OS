'use strict';

/**
 * Cross-cutting protections, in one place so they cannot be forgotten on a new
 * route. Each is small; together they close the holes an app like this actually
 * gets hit through — a shared campus network, a hundred members, phones people
 * lend each other.
 */

/**
 * Strip MongoDB operators out of anything the client sent.
 *
 * Express parses `?role[$ne]=clubMember` into `{ role: { $ne: 'clubMember' } }`,
 * and any route that drops a query value straight into a filter then hands the
 * caller an operator it never meant to offer. Two routes did exactly that.
 *
 * Rather than rely on every present and future route remembering to validate,
 * this removes keys beginning with `$` and keys containing a dot (which Mongo
 * treats as a path) before a handler ever sees them. Legitimate input never
 * needs either — no name, note or search term is called `$ne`.
 *
 * Applied to body, query and params. It rewrites in place because Express 4
 * exposes these as plain objects; the values are replaced, never the container,
 * so downstream references stay valid.
 */
function stripOperators(value, depth = 0) {
  if (depth > 8 || value === null || typeof value !== 'object') return value;

  if (Array.isArray(value)) {
    for (const item of value) stripOperators(item, depth + 1);
    return value;
  }

  for (const key of Object.keys(value)) {
    if (key.startsWith('$') || key.includes('.')) {
      delete value[key];
      continue;
    }
    stripOperators(value[key], depth + 1);
  }
  return value;
}

const sanitize = (request, response, next) => {
  stripOperators(request.body);
  stripOperators(request.query);
  stripOperators(request.params);
  next();
};

/**
 * Headers that cost nothing and remove whole classes of problem.
 *
 * `nosniff` matters most here: uploaded documents are streamed back to members,
 * and without it a browser may decide a file is HTML whatever the server said.
 * The app is served as a website too, so that is a real path, not a theoretical
 * one.
 */
const headers = (request, response, next) => {
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('X-Frame-Options', 'DENY');
  response.setHeader('Referrer-Policy', 'no-referrer');

  // Features this app has no use for. Denying them means a compromised page
  // cannot quietly ask for them either, and none of it costs anything.
  response.setHeader(
    'Permissions-Policy',
    'geolocation=(), microphone=(), payment=(), usb=(), magnetometer=(), gyroscope=()',
  );

  // HSTS, but only once the connection is already secure.
  //
  // The club's own server is a laptop on college Wi-Fi speaking plain HTTP, and
  // sending HSTS from there would pin every phone that ever loaded it to an
  // HTTPS endpoint that does not exist - a self-inflicted outage with a
  // six-month memory. Behind a TLS terminator, `x-forwarded-proto` is how the
  // proxy says it has already done the encrypting.
  const proto = String(request.headers['x-forwarded-proto'] || '').split(',')[0].trim();
  if (request.secure || proto === 'https') {
    response.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  }

  // Two different things are served from this origin and they need different
  // policies. Getting this wrong is silent and total: a `default-src 'none'`
  // on the web build blocks its own scripts and the site renders a blank page
  // with no server-side error to find.
  if (request.path.startsWith('/api')) {
    // JSON and file downloads. Nothing here should ever execute or embed.
    response.setHeader('Cross-Origin-Resource-Policy', 'same-site');
    response.setHeader(
      'Content-Security-Policy',
      "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
    );
  } else {
    // The Flutter web build. It loads its own scripts and workers from this
    // origin, inlines styles, decodes fonts and images as blobs, and talks to
    // this same origin over fetch and WebSocket.
    //
    // 'wasm-unsafe-eval' is required: Flutter's web renderer instantiates
    // WebAssembly, and without it the app does not start at all.
    //
    // `connect-src` stays wide on purpose. The sign-in screen carries a server
    // address override, which exists because this laptop's IP has already moved
    // twice mid-term; narrowing this to 'self' would silently break the one
    // control somebody has when that happens. It only guards exfiltration
    // *after* a script injection, and script-src is what stops that.
    response.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    response.setHeader(
      'Content-Security-Policy',
      [
        "default-src 'self'",
        "script-src 'self' 'wasm-unsafe-eval'",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' data: blob:",
        "font-src 'self' data:",
        "connect-src 'self' ws: wss: http: https:",
        "worker-src 'self' blob:",
        "frame-ancestors 'none'",
        "base-uri 'self'",
      ].join('; '),
    );
  }
  next();
};

/**
 * A fixed-window rate limiter, in memory.
 *
 * In memory because this is one Node process serving one club — a Redis
 * dependency to throttle a hundred people would be ceremony. It resets if the
 * server restarts, which is an acceptable trade for a brute-force guard: an
 * attacker cannot restart the server.
 *
 * Keyed on IP **and** the account being targeted where one is named, so one
 * person fat-fingering their password on the shared Wi-Fi cannot lock out
 * everybody else behind the same NAT — which is exactly what a club on one
 * hotspot would otherwise do to itself.
 */
function rateLimit({ windowMs, max, name, keyOn }) {
  const hits = new Map();

  // Sweeping on write would make one unlucky request pay for everybody. A
  // timer keeps the map from growing without bound on a long-running server.
  const sweep = setInterval(() => {
    const now = Date.now();
    for (const [key, entry] of hits) {
      if (entry.resetAt <= now) hits.delete(key);
    }
  }, windowMs);
  sweep.unref?.();

  return (request, response, next) => {
    const ip = request.ip || request.socket?.remoteAddress || 'unknown';
    const subject = typeof keyOn === 'function' ? keyOn(request) : null;
    const key = `${name}:${ip}:${subject ?? ''}`;
    const now = Date.now();

    let entry = hits.get(key);
    if (!entry || entry.resetAt <= now) {
      entry = { count: 0, resetAt: now + windowMs };
      hits.set(key, entry);
    }
    entry.count += 1;

    const remaining = Math.max(0, max - entry.count);
    response.setHeader('RateLimit-Limit', String(max));
    response.setHeader('RateLimit-Remaining', String(remaining));

    if (entry.count > max) {
      const retryAfter = Math.ceil((entry.resetAt - now) / 1000);
      response.setHeader('Retry-After', String(retryAfter));
      return response.status(429).json({
        error: `Too many attempts. Try again in ${retryAfter} second${retryAfter === 1 ? '' : 's'}.`,
      });
    }
    return next();
  };
}

/**
 * A ceiling on any one client, however it authenticates.
 *
 * Not a security boundary - everything behind it is already authorised - but a
 * runaway client is indistinguishable from an attack and does the same damage.
 * A load test of a hundred concurrent sign-ins starved every change stream in
 * the process, taking live sync down for the whole club; one phone stuck in a
 * retry loop can do the same thing more quietly.
 *
 * Keyed on the bearer token where there is one rather than on IP, because a
 * club on a single hotspot shares one address and a per-IP ceiling would count
 * eighty people as one very busy attacker. The limit is set where no real
 * person reaches it: a heavy screen costs a handful of requests, not hundreds.
 */
const apiLimiter = rateLimit({
  windowMs: 60_000,
  max: 600,
  name: 'api',
  keyOn: (request) => request.headers.authorization || '',
});

/**
 * A ceiling per address, whatever the Authorization header says.
 *
 * `apiLimiter` is keyed on the header so a hundred phones behind one hotspot
 * are a hundred budgets - but that also made a fresh budget out of every made-up
 * header, so it limited nobody who wanted to flood it. This caps the address as
 * a whole, high enough for a full room arriving at once (16 requests each).
 */
const apiCeiling = rateLimit({
  windowMs: 60_000,
  max: 6000,
  name: 'api-ip',
});

/** The email a request is about, lowercased — never an object. */
const emailKey = (request) =>
  typeof request.body?.email === 'string'
    ? request.body.email.trim().toLowerCase().slice(0, 120)
    : null;

/**
 * Signing in. Ten tries per account per ten minutes is generous for somebody
 * who genuinely forgot, and useless for guessing an eight-character password.
 */
const loginPerAccount = rateLimit({
  windowMs: 10 * 60 * 1000, max: 10, name: 'login', keyOn: emailKey,
});

/**
 * And a ceiling per address across every account, so one machine cannot try a
 * common password against the whole club's email list ten at a time. Generous
 * enough for a room signing in together behind one hotspot.
 */
const loginPerAddress = rateLimit({
  windowMs: 10 * 60 * 1000, max: 200, name: 'login-ip',
});

const loginLimiter = (request, response, next) =>
  loginPerAddress(request, response, (error) => {
    if (error) return next(error);
    return loginPerAccount(request, response, next);
  });

/**
 * Creating accounts.
 *
 * Deliberately generous. A club onboards in bursts — forty people joining in
 * one session, all on the same campus Wi-Fi and therefore all on one NAT
 * address — and a tight per-IP cap would lock out most of the room. The real
 * gate on signup is the approval queue: an account is useless until a human
 * lets it in, so this only has to stop somebody scripting thousands of rows.
 *
 * An earlier cap of 5/hour was tight enough to break the test suite, which was
 * a fair warning about what it would have done on onboarding day.
 */
const signupLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, max: 60, name: 'signup',
});

/**
 * "I forgot my password" raises a flag that pages a Director. Left open it is a
 * way to make somebody's phone buzz all evening.
 */
const forgotLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, max: 5, name: 'forgot', keyOn: emailKey,
});

/**
 * Which uploaded types may be shown **inline** in a browser.
 *
 * Everything else is sent as an attachment with a neutral content type. The
 * hole this closes: a member uploads an HTML or SVG file, the server echoes
 * back the content type the client claimed, another member opens it, and the
 * file runs as script on the app's own origin. Images and PDFs are the only
 * things anybody actually wants to view in place.
 */
const INLINE_SAFE = new Set([
  'image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/heic',
  'application/pdf', 'text/plain', 'text/csv',
]);

/**
 * Content-Type and Content-Disposition for a stored file, decided by the server
 * rather than echoed from whatever the uploader claimed.
 */
function dispositionFor(mimeType, filename) {
  const safeName = String(filename ?? 'file').replace(/["\r\n\\]/g, '').slice(0, 200);
  const claimed = String(mimeType ?? '').toLowerCase().split(';')[0].trim();
  const inline = INLINE_SAFE.has(claimed);
  return {
    contentType: inline ? claimed : 'application/octet-stream',
    disposition: `${inline ? 'inline' : 'attachment'}; filename="${safeName}"`,
  };
}

module.exports = {
  apiCeiling,
  apiLimiter,
  sanitize,
  headers,
  rateLimit,
  loginLimiter,
  signupLimiter,
  forgotLimiter,
  dispositionFor,
  INLINE_SAFE,
};

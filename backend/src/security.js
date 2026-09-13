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

/** The email a request is about, lowercased — never an object. */
const emailKey = (request) =>
  typeof request.body?.email === 'string'
    ? request.body.email.trim().toLowerCase().slice(0, 120)
    : null;

/**
 * Signing in. Ten tries per account per ten minutes is generous for somebody
 * who genuinely forgot, and useless for guessing an eight-character password.
 */
const loginLimiter = rateLimit({
  windowMs: 10 * 60 * 1000, max: 10, name: 'login', keyOn: emailKey,
});

/** Creating accounts. Slow enough that nobody fills the approval queue. */
const signupLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, max: 5, name: 'signup',
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
  sanitize,
  headers,
  rateLimit,
  loginLimiter,
  signupLimiter,
  forgotLimiter,
  dispositionFor,
  INLINE_SAFE,
};

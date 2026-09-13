'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const express = require('express');
const multer = require('multer');
const { ObjectId } = require('mongodb');

const config = require('../config');
const { dispositionFor } = require('../security');
const { col, C } = require('../db');
const { authenticate, requireApproved, fail } = require('../auth');
const {
  canUploadEventFile, canUploadOfficialDocument, canDecideDocument, canManageEvent,
} = require('../permissions');
const { notify, audit } = require('../services/notify');

const router = express.Router();

/**
 * Event documents.
 *
 * Two kinds live here and they are not the same thing:
 *
 *   `file`     — posters, scripts, budgets, photos. Anyone on the event can add
 *                one. Low stakes; the club wants these shared freely.
 *   `approval` — the official paperwork: permission letters, venue bookings,
 *                faculty sign-off. Only leadership and the organising Lead may
 *                upload one, and only leadership may mark one approved.
 *
 * Section 50: a normal member must not be able to mark a document approved,
 * replace an official permission letter, or impersonate an approver. That is
 * enforced here, on the server, per action — never by hiding a button.
 *
 * Versioning keeps history. Replacing a document never overwrites bytes on
 * disk: the old version stays readable and the audit log records who replaced
 * what, which is the whole point of paperwork.
 */

fs.mkdirSync(config.uploadDir, { recursive: true });

const upload = multer({
  storage: multer.diskStorage({
    destination: (request, file, done) => done(null, config.uploadDir),
    // Never trust the client's filename on disk. The original is kept in the
    // database for display; the bytes live under an opaque random name so a
    // crafted name cannot escape the directory or collide with anything.
    filename: (request, file, done) => {
      const extension = path.extname(file.originalname ?? '').slice(0, 12).replace(/[^.\w]/g, '');
      done(null, `${crypto.randomUUID()}${extension}`);
    },
  }),
  limits: { fileSize: config.maxUploadBytes, files: 1 },
});

router.use(authenticate, requireApproved);

const oid = (value, name) => {
  if (!ObjectId.isValid(value)) fail(`${name} is not valid.`);
  return new ObjectId(value);
};

const KINDS = new Set(['approval', 'file']);

/** Best-effort cleanup when validation rejects a request after multer wrote. */
async function discard(file) {
  if (!file) return;
  try { await fsp.unlink(file.path); } catch { /* already gone */ }
}

function serialise(document, { userName }) {
  const versions = document.versions ?? [];
  const current = versions[versions.length - 1] ?? null;
  return {
    id: String(document._id),
    eventId: String(document.eventId),
    kind: document.kind,
    title: document.title,
    note: document.note ?? '',
    status: document.status,
    decidedBy: document.decidedBy ? String(document.decidedBy) : null,
    decidedByName: userName.get(String(document.decidedBy)) ?? null,
    decidedAt: document.decidedAt ?? null,
    decisionNote: document.decisionNote ?? '',
    createdBy: String(document.createdBy),
    createdByName: userName.get(String(document.createdBy)) ?? 'Member',
    createdAt: document.createdAt,
    version: versions.length,
    current: current && {
      filename: current.filename,
      size: current.size,
      mimeType: current.mimeType,
      link: current.link ?? null,
      uploadedAt: current.uploadedAt,
      uploadedByName: userName.get(String(current.uploadedBy)) ?? 'Member',
    },
    history: versions.map((v, index) => ({
      version: index + 1,
      filename: v.filename,
      link: v.link ?? null,
      uploadedAt: v.uploadedAt,
      uploadedByName: userName.get(String(v.uploadedBy)) ?? 'Member',
      note: v.note ?? '',
      superseded: index < versions.length - 1,
    })),
  };
}

/* ---------------------------------------------------------------- listing */

router.get('/events/:eventId/documents', async (request, response, next) => {
  try {
    const eventId = oid(request.params.eventId, 'Event id');
    const event = await col(C.events).findOne({ _id: eventId });
    if (!event) fail('That event no longer exists.', 404);

    const documents = await col(C.eventDocuments)
      .find({ eventId }).sort({ createdAt: -1 }).toArray();

    const ids = documents.flatMap((d) => [
      d.createdBy, d.decidedBy, ...(d.versions ?? []).map((v) => v.uploadedBy),
    ]).filter(Boolean);
    const people = await col(C.users)
      .find({ _id: { $in: ids } }, { projection: { name: 1 } }).toArray();
    const userName = new Map(people.map((p) => [String(p._id), p.name]));

    const items = documents.map((d) => serialise(d, { userName }));
    response.json({
      approvals: items.filter((d) => d.kind === 'approval'),
      files: items.filter((d) => d.kind === 'file'),
      // The client uses these to decide what to *offer*. The server decides
      // what to allow, on every request below.
      canUploadFile: canUploadEventFile(request.user.role),
      canUploadApproval: canUploadOfficialDocument(request.user, event),
      canDecide: canDecideDocument(request.user),
    });
  } catch (error) {
    next(error);
  }
});

/* --------------------------------------------------------------- creation */

/**
 * Add a document.
 *
 * Accepts either a real upload (multipart, field `file`) or a link to one
 * elsewhere (JSON `link`) — clubs keep half their paperwork on Drive, and
 * refusing to record that just means it lives in a WhatsApp thread instead.
 */
router.post(
  '/events/:eventId/documents',
  upload.single('file'),
  async (request, response, next) => {
    try {
      const eventId = oid(request.params.eventId, 'Event id');
      const event = await col(C.events).findOne({ _id: eventId });
      if (!event) { await discard(request.file); fail('That event no longer exists.', 404); }

      const kind = KINDS.has(request.body.kind) ? request.body.kind : 'file';

      if (kind === 'approval' && !canUploadOfficialDocument(request.user, event)) {
        await discard(request.file);
        fail(
          'Official approvals can only be uploaded by the President, Vice President, '
          + 'Secretary General, a supervisor, or the organising department Lead.',
          403,
        );
      }
      if (kind === 'file' && !canUploadEventFile(request.user.role)) {
        await discard(request.file);
        fail('You cannot add files to this event.', 403);
      }

      const title = typeof request.body.title === 'string' ? request.body.title.trim() : '';
      if (title.length < 2) { await discard(request.file); fail('Give the document a name.'); }

      const link = typeof request.body.link === 'string' ? request.body.link.trim() : '';
      if (!request.file && !link) {
        fail('Attach a file or paste a link.');
      }
      if (link && !/^https?:\/\//i.test(link)) {
        await discard(request.file);
        fail('A link must start with http:// or https://');
      }

      const now = new Date();
      const document = {
        eventId,
        kind,
        title: title.slice(0, 200),
        note: typeof request.body.note === 'string' ? request.body.note.trim().slice(0, 1000) : '',
        // An approval starts life pending: uploading paperwork is not the same
        // as it having been approved, and conflating the two is exactly the
        // hole Section 50 is about.
        status: kind === 'approval' ? 'pending' : 'approved',
        createdBy: request.user._id,
        createdAt: now,
        decidedBy: null,
        decidedAt: null,
        decisionNote: '',
        versions: [{
          filename: request.file ? (request.file.originalname ?? 'file') : title.slice(0, 200),
          storedName: request.file ? request.file.filename : null,
          size: request.file ? request.file.size : 0,
          mimeType: request.file ? request.file.mimetype : 'text/uri-list',
          link: link || null,
          uploadedBy: request.user._id,
          uploadedAt: now,
          note: '',
        }],
      };

      const inserted = await col(C.eventDocuments).insertOne(document);

      if (kind === 'approval') {
        // Tell the people who can actually decide, rather than everyone.
        const deciders = await col(C.users).find(
          {
            approvalStatus: 'approved',
            role: { $in: ['clubDirector', 'facultyCoordinator', 'president', 'vicePresident', 'secretaryGeneral'] },
          },
          { projection: { _id: 1 } },
        ).toArray();
        await notify(
          deciders.map((u) => u._id).filter((id) => String(id) !== String(request.user._id)),
          'documentPending',
          { title: document.title, eventTitle: event.name, eventId: String(eventId) },
        );
      }

      await audit(request.user._id, 'document.upload', {
        eventId: String(eventId),
        documentId: String(inserted.insertedId),
        kind,
        title: document.title,
        viaLink: Boolean(link),
      });

      response.status(201).json({ id: String(inserted.insertedId) });
    } catch (error) {
      await discard(request.file);
      next(error);
    }
  },
);

/**
 * Replace a document with a new version.
 *
 * History is kept. For an official approval this resets the status to pending:
 * a decision applies to the paper that was actually read, not to whatever ends
 * up under the same title later.
 */
router.post('/documents/:id/versions', upload.single('file'), async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Document id');
    const document = await col(C.eventDocuments).findOne({ _id: id });
    if (!document) { await discard(request.file); fail('That document no longer exists.', 404); }

    const event = await col(C.events).findOne({ _id: document.eventId });
    if (!event) { await discard(request.file); fail('That event no longer exists.', 404); }

    if (document.kind === 'approval') {
      if (!canUploadOfficialDocument(request.user, event)) {
        await discard(request.file);
        fail('Only leadership can replace an official document.', 403);
      }
    } else if (String(document.createdBy) !== String(request.user._id)
      && !canManageEvent(request.user, event)) {
      await discard(request.file);
      fail('You can only replace a file you added.', 403);
    }

    const link = typeof request.body.link === 'string' ? request.body.link.trim() : '';
    if (!request.file && !link) fail('Attach a file or paste a link.');
    if (link && !/^https?:\/\//i.test(link)) {
      await discard(request.file);
      fail('A link must start with http:// or https://');
    }

    const now = new Date();
    const version = {
      filename: request.file ? (request.file.originalname ?? 'file') : document.title,
      storedName: request.file ? request.file.filename : null,
      size: request.file ? request.file.size : 0,
      mimeType: request.file ? request.file.mimetype : 'text/uri-list',
      link: link || null,
      uploadedBy: request.user._id,
      uploadedAt: now,
      note: typeof request.body.note === 'string' ? request.body.note.trim().slice(0, 500) : '',
    };

    await col(C.eventDocuments).updateOne({ _id: id }, {
      $push: { versions: version },
      $set: document.kind === 'approval'
        ? { status: 'pending', decidedBy: null, decidedAt: null, decisionNote: '' }
        : {},
    });

    await audit(request.user._id, 'document.replace', {
      eventId: String(document.eventId),
      documentId: String(id),
      title: document.title,
      version: (document.versions?.length ?? 0) + 1,
    });

    response.status(201).json({ version: (document.versions?.length ?? 0) + 1 });
  } catch (error) {
    await discard(request.file);
    next(error);
  }
});

/* --------------------------------------------------------------- decision */

/** Mark an official approval approved or rejected. Leadership only. */
router.post('/documents/:id/decision', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Document id');
    const document = await col(C.eventDocuments).findOne({ _id: id });
    if (!document) fail('That document no longer exists.', 404);

    if (document.kind !== 'approval') {
      fail('Only official approvals carry a decision.');
    }
    if (!canDecideDocument(request.user)) {
      fail('Only the President, Vice President, Secretary General or a supervisor can decide this.', 403);
    }

    const status = request.body.status;
    if (!['approved', 'rejected'].includes(status)) fail('Decide either approved or rejected.');

    await col(C.eventDocuments).updateOne({ _id: id }, {
      $set: {
        status,
        decidedBy: request.user._id,
        decidedAt: new Date(),
        decisionNote: typeof request.body.note === 'string'
          ? request.body.note.trim().slice(0, 500) : '',
      },
    });

    if (String(document.createdBy) !== String(request.user._id)) {
      await notify(document.createdBy, 'documentDecision', {
        title: document.title, status, byName: request.user.name,
        eventId: String(document.eventId),
      });
    }

    await audit(request.user._id, 'document.decision', {
      eventId: String(document.eventId),
      documentId: String(id),
      title: document.title,
      status,
    });

    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

/* --------------------------------------------------------------- download */

/**
 * Stream a stored document.
 *
 * Served through this route rather than a static directory precisely because
 * every hit must carry a token. An unguessable filename is not access control.
 */
router.get('/documents/:id/file', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Document id');
    const document = await col(C.eventDocuments).findOne({ _id: id });
    if (!document) fail('That document no longer exists.', 404);

    const versions = document.versions ?? [];
    const index = request.query.version
      ? Number(request.query.version) - 1
      : versions.length - 1;
    const version = versions[index];
    if (!version) fail('That version does not exist.', 404);
    if (!version.storedName) {
      // A link-only document: hand back the link rather than pretending.
      return response.json({ link: version.link });
    }

    const absolute = path.join(config.uploadDir, path.basename(version.storedName));
    if (!fs.existsSync(absolute)) fail('The stored file is missing.', 410);

    // The server decides how this is served, not the uploader.
    //
    // Echoing back the claimed content type with `inline` meant a member could
    // upload an HTML or SVG file and have it run as script on the app's own
    // origin when a colleague opened it — a stored XSS, and a live one now the
    // app is also a website. Only images, PDFs and plain text render in place;
    // everything else downloads as an opaque attachment.
    const { contentType, disposition } = dispositionFor(version.mimeType, version.filename);
    response.setHeader('Content-Type', contentType);
    response.setHeader('Content-Disposition', disposition);
    response.setHeader('X-Content-Type-Options', 'nosniff');
    return fs.createReadStream(absolute).pipe(response);
  } catch (error) {
    return next(error);
  }
});

router.delete('/documents/:id', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Document id');
    const document = await col(C.eventDocuments).findOne({ _id: id });
    if (!document) fail('That document no longer exists.', 404);
    const event = await col(C.events).findOne({ _id: document.eventId });

    const mine = String(document.createdBy) === String(request.user._id);
    const allowed = document.kind === 'approval'
      ? canDecideDocument(request.user)
      : (mine || (event && canManageEvent(request.user, event)));
    if (!allowed) fail('You cannot remove this document.', 403);

    await col(C.eventDocuments).deleteOne({ _id: id });
    for (const version of document.versions ?? []) {
      if (version.storedName) {
        try {
          await fsp.unlink(path.join(config.uploadDir, path.basename(version.storedName)));
        } catch { /* already gone */ }
      }
    }
    await audit(request.user._id, 'document.delete', {
      eventId: String(document.eventId), documentId: String(id), title: document.title,
    });
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

/** Multer's own errors are plain Errors; give them a status and real copy. */
// eslint-disable-next-line no-unused-vars
router.use((error, request, response, next) => {
  if (error instanceof multer.MulterError) {
    const message = error.code === 'LIMIT_FILE_SIZE'
      ? `That file is too large. The limit is ${Math.round(config.maxUploadBytes / (1024 * 1024))} MB.`
      : 'That file could not be accepted.';
    return response.status(400).json({ error: message });
  }
  return next(error);
});

module.exports = router;

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
  BILL_CATEGORIES, canAddEventBill, canDecideEventBill, canSettleEventBill,
  canViewEventFinance, ROLES,
} = require('../permissions');
const { notify, audit } = require('../services/notify');

const router = express.Router();

/**
 * Event finance.
 *
 * What an event cost, and whether the person who paid for it has been repaid.
 *
 * Scope, stated plainly because it matters: this is **bookkeeping, not
 * banking**. It records a spend, carries a photo of the receipt, routes it for
 * approval, and lets somebody mark it settled once the club has actually paid
 * the person back through whatever means it already uses. It moves no money and
 * stores **no bank or card details** — a club app holding members' account
 * numbers is a liability nobody asked for, and a reference like "UPI, 12 Mar"
 * is all the record anyone needs.
 *
 * The separation that makes it worth having: whoever files a bill is not the
 * person who approves it. Approving your own expense is the oldest hole in any
 * petty-cash system.
 */

fs.mkdirSync(config.uploadDir, { recursive: true });

const upload = multer({
  storage: multer.diskStorage({
    destination: (request, file, done) => done(null, config.uploadDir),
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

async function discard(file) {
  if (!file) return;
  try { await fsp.unlink(file.path); } catch { /* already gone */ }
}

/** Money in the smallest unit, so no total ever drifts by a rounding error. */
function parseAmount(value) {
  const rupees = Number(value);
  if (!Number.isFinite(rupees) || rupees <= 0) fail('Enter what it cost.');
  if (rupees > 10000000) fail('That figure looks wrong. Check it and try again.');
  return Math.round(rupees * 100);
}

function serialise(bill, { userName, departmentName }) {
  return {
    id: String(bill._id),
    eventId: String(bill.eventId),
    title: bill.title,
    note: bill.note ?? '',
    category: bill.category,
    amountPaise: bill.amountPaise,
    amount: bill.amountPaise / 100,
    status: bill.status,
    spentOn: bill.spentOn ?? null,
    departmentId: bill.departmentId ? String(bill.departmentId) : null,
    departmentName: departmentName.get(String(bill.departmentId)) ?? null,
    paidByName: bill.paidByName ?? userName.get(String(bill.createdBy)) ?? 'Member',
    createdBy: String(bill.createdBy),
    createdByName: userName.get(String(bill.createdBy)) ?? 'Member',
    createdAt: bill.createdAt,
    decidedByName: userName.get(String(bill.decidedBy)) ?? null,
    decidedAt: bill.decidedAt ?? null,
    decisionNote: bill.decisionNote ?? '',
    settledAt: bill.settledAt ?? null,
    settledByName: userName.get(String(bill.settledBy)) ?? null,
    settlementRef: bill.settlementRef ?? '',
    hasReceipt: Boolean(bill.receipt?.storedName),
    receiptName: bill.receipt?.filename ?? null,
  };
}

const rupees = (paise) => (paise / 100).toFixed(2);

/* ---------------------------------------------------------------- listing */

router.get('/events/:eventId/bills', async (request, response, next) => {
  try {
    const eventId = oid(request.params.eventId, 'Event id');
    if (!canViewEventFinance(request.user)) {
      fail('Event spending is visible to department Leads and club leadership.', 403);
    }

    const bills = await col(C.eventBills).find({ eventId }).sort({ createdAt: -1 }).toArray();

    const ids = bills.flatMap((b) => [b.createdBy, b.decidedBy, b.settledBy]).filter(Boolean);
    const [people, departments] = await Promise.all([
      col(C.users).find({ _id: { $in: ids } }, { projection: { name: 1 } }).toArray(),
      col(C.departments).find({}, { projection: { name: 1 } }).toArray(),
    ]);
    const userName = new Map(people.map((p) => [String(p._id), p.name]));
    const departmentName = new Map(departments.map((d) => [String(d._id), d.name]));

    const items = bills.map((b) => serialise(b, { userName, departmentName }));
    const sum = (predicate) => items
      .filter(predicate)
      .reduce((n, b) => n + b.amountPaise, 0) / 100;

    response.json({
      bills: items,
      totals: {
        // Everything filed, whatever happened to it — the honest "what did this
        // event cost" number.
        spent: sum(() => true),
        pending: sum((b) => b.status === 'pending'),
        approved: sum((b) => b.status === 'approved'),
        paid: sum((b) => b.status === 'paid'),
        rejected: sum((b) => b.status === 'rejected'),
        // Approved but not yet handed back — what the club currently owes its
        // own members, which is the number people actually chase.
        owed: sum((b) => b.status === 'approved'),
      },
      categories: BILL_CATEGORIES,
      canAdd: canAddEventBill(request.user),
      canDecide: canDecideEventBill(request.user, null),
      canSettle: canSettleEventBill(request.user),
    });
  } catch (error) {
    next(error);
  }
});

/* ----------------------------------------------------------------- filing */

router.post(
  '/events/:eventId/bills',
  upload.single('receipt'),
  async (request, response, next) => {
    try {
      const eventId = oid(request.params.eventId, 'Event id');
      const event = await col(C.events).findOne({ _id: eventId });
      if (!event) { await discard(request.file); fail('That event no longer exists.', 404); }

      if (!canAddEventBill(request.user)) {
        await discard(request.file);
        fail('Only department Leads and club leadership can file an expense. '
          + 'Ask your Lead to file it for you.', 403);
      }

      const title = typeof request.body.title === 'string' ? request.body.title.trim() : '';
      if (title.length < 2) { await discard(request.file); fail('Say what the money went on.'); }

      const amountPaise = parseAmount(request.body.amount);
      const category = BILL_CATEGORIES.includes(request.body.category)
        ? request.body.category : 'Other';

      const spentOn = request.body.spentOn ? new Date(request.body.spentOn) : new Date();
      if (Number.isNaN(spentOn.getTime())) {
        await discard(request.file);
        fail('Give a valid date for the spend.');
      }

      const now = new Date();
      const bill = {
        eventId,
        title: title.slice(0, 200),
        note: typeof request.body.note === 'string' ? request.body.note.trim().slice(0, 1000) : '',
        category,
        amountPaise,
        spentOn,
        // Who is out of pocket. Free text, because it is often somebody who
        // cannot file the bill themselves — and never an account number.
        paidByName: typeof request.body.paidByName === 'string' && request.body.paidByName.trim()
          ? request.body.paidByName.trim().slice(0, 120)
          : request.user.name,
        departmentId: request.user.departmentId ?? event.organizingDepartmentId ?? null,
        status: 'pending',
        createdBy: request.user._id,
        createdAt: now,
        decidedBy: null,
        decidedAt: null,
        decisionNote: '',
        settledBy: null,
        settledAt: null,
        settlementRef: '',
        receipt: request.file ? {
          filename: request.file.originalname ?? 'receipt',
          storedName: request.file.filename,
          size: request.file.size,
          mimeType: request.file.mimetype,
        } : null,
      };

      const inserted = await col(C.eventBills).insertOne(bill);

      // Tell the people who can actually decide it, rather than everyone.
      const deciders = await col(C.users).find(
        {
          approvalStatus: 'approved',
          role: { $in: [ROLES.clubDirector, ROLES.facultyCoordinator, ROLES.president] },
        },
        { projection: { _id: 1 } },
      ).toArray();
      await notify(
        deciders.map((u) => u._id).filter((id) => String(id) !== String(request.user._id)),
        'billFiled',
        {
          billTitle: bill.title,
          amount: rupees(amountPaise),
          eventTitle: event.name,
          byName: request.user.name,
          eventId: String(eventId),
        },
      );

      await audit(request.user._id, 'bill.create', {
        eventId: String(eventId),
        billId: String(inserted.insertedId),
        title: bill.title,
        amount: rupees(amountPaise),
        hasReceipt: Boolean(request.file),
      });

      response.status(201).json({ id: String(inserted.insertedId) });
    } catch (error) {
      await discard(request.file);
      next(error);
    }
  },
);

/* --------------------------------------------------------------- decision */

router.post('/bills/:id/decision', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Bill id');
    const bill = await col(C.eventBills).findOne({ _id: id });
    if (!bill) fail('That bill no longer exists.', 404);

    if (!canDecideEventBill(request.user, bill)) {
      fail(String(bill.createdBy) === String(request.user._id)
        ? 'You cannot approve an expense you filed yourself. A Director will.'
        : 'Only the President and Directors approve expenses.', 403);
    }
    if (bill.status === 'paid') fail('That one has already been settled.');

    const status = request.body.status;
    if (!['approved', 'rejected'].includes(status)) fail('Decide either approved or rejected.');

    await col(C.eventBills).updateOne({ _id: id }, {
      $set: {
        status,
        decidedBy: request.user._id,
        decidedAt: new Date(),
        decisionNote: typeof request.body.note === 'string'
          ? request.body.note.trim().slice(0, 500) : '',
      },
    });

    await notify(bill.createdBy, 'billDecision', {
      billTitle: bill.title,
      amount: rupees(bill.amountPaise),
      status,
      byName: request.user.name,
      eventId: String(bill.eventId),
    });
    await audit(request.user._id, 'bill.decision', {
      eventId: String(bill.eventId),
      billId: String(id),
      title: bill.title,
      amount: rupees(bill.amountPaise),
      status,
    });

    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

/**
 * Record that an approved expense has actually been paid back.
 *
 * This does not send money — nothing here can. It notes that the club settled
 * up, and against what reference, so the list stops showing a debt that no
 * longer exists.
 */
router.post('/bills/:id/settle', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Bill id');
    const bill = await col(C.eventBills).findOne({ _id: id });
    if (!bill) fail('That bill no longer exists.', 404);
    if (!canSettleEventBill(request.user)) {
      fail('Only the President and Directors can mark an expense repaid.', 403);
    }
    if (bill.status !== 'approved') {
      fail('Approve it before marking it repaid.');
    }

    const reference = typeof request.body.reference === 'string'
      ? request.body.reference.trim().slice(0, 200) : '';

    await col(C.eventBills).updateOne({ _id: id }, {
      $set: {
        status: 'paid',
        settledBy: request.user._id,
        settledAt: new Date(),
        settlementRef: reference,
      },
    });

    await notify(bill.createdBy, 'billSettled', {
      billTitle: bill.title,
      amount: rupees(bill.amountPaise),
      byName: request.user.name,
    });
    await audit(request.user._id, 'bill.settle', {
      eventId: String(bill.eventId),
      billId: String(id),
      title: bill.title,
      amount: rupees(bill.amountPaise),
      reference,
    });

    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

/* ---------------------------------------------------------------- receipt */

router.get('/bills/:id/receipt', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Bill id');
    if (!canViewEventFinance(request.user)) {
      fail('Event spending is visible to department Leads and club leadership.', 403);
    }
    const bill = await col(C.eventBills).findOne({ _id: id });
    if (!bill?.receipt?.storedName) fail('No receipt on this one.', 404);

    const absolute = path.join(config.uploadDir, path.basename(bill.receipt.storedName));
    if (!fs.existsSync(absolute)) fail('The stored receipt is missing.', 410);

    // Same rule as event documents: the server decides the content type, so a
    // receipt cannot be an HTML file that runs as script when somebody opens
    // it. See security.dispositionFor.
    const { contentType, disposition } =
      dispositionFor(bill.receipt.mimeType, bill.receipt.filename ?? 'receipt');
    response.setHeader('Content-Type', contentType);
    response.setHeader('Content-Disposition', disposition);
    response.setHeader('X-Content-Type-Options', 'nosniff');
    fs.createReadStream(absolute).pipe(response);
  } catch (error) {
    next(error);
  }
});

router.delete('/bills/:id', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Bill id');
    const bill = await col(C.eventBills).findOne({ _id: id });
    if (!bill) fail('That bill no longer exists.', 404);

    const mine = String(bill.createdBy) === String(request.user._id);
    // Withdraw your own while it is still pending; leadership can remove a
    // mistake at any point. A settled bill stays — it is the record of a
    // payment that actually happened.
    if (bill.status === 'paid') fail('A settled expense stays on the record.');
    if (!mine && !canSettleEventBill(request.user)) {
      fail('You can only withdraw an expense you filed.', 403);
    }

    await col(C.eventBills).deleteOne({ _id: id });
    if (bill.receipt?.storedName) {
      try {
        await fsp.unlink(path.join(config.uploadDir, path.basename(bill.receipt.storedName)));
      } catch { /* already gone */ }
    }
    await audit(request.user._id, 'bill.delete', {
      eventId: String(bill.eventId), billId: String(id), title: bill.title,
    });
    response.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

// eslint-disable-next-line no-unused-vars
router.use((error, request, response, next) => {
  if (error instanceof multer.MulterError) {
    const message = error.code === 'LIMIT_FILE_SIZE'
      ? `That receipt is too large. The limit is ${Math.round(config.maxUploadBytes / (1024 * 1024))} MB.`
      : 'That receipt could not be accepted.';
    return response.status(400).json({ error: message });
  }
  return next(error);
});

module.exports = router;

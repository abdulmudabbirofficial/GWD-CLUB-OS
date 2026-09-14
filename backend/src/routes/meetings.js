'use strict';

const express = require('express');
const { ObjectId } = require('mongodb');
const { col, C } = require('../db');
const { authenticate, requireApproved, fail } = require('../auth');
const {
  canScheduleMeeting, canMarkAttendance, ROLES, isSupervisor, rankOf, RANK,
} = require('../permissions');
const { notify, audit } = require('../services/notify');

const router = express.Router();
router.use(authenticate, requireApproved);

/**
 * Meetings, their invitees, and who turned up.
 *
 * Distinct from a schedule entry, where "Meeting" is only a category. A
 * schedule row is a date and a title; it cannot say who was asked, who came,
 * or what anybody's attendance record is.
 *
 * **Participants are a snapshot.** They are resolved once, when the meeting is
 * created, and stored on the document. Inviting "the whole Marketing team"
 * writes out the people who were in Marketing at that moment — it is not a
 * live query. If somebody transfers out next week, the record of who was
 * invited to last week's meeting must not change underneath it. Attendance
 * history that rewrites itself is worth nothing.
 *
 * Attendance lives on the same document rather than in its own collection.
 * It is only ever read and written alongside its meeting, and keeping it here
 * means a meeting and its attendance can never disagree or orphan each other.
 */

const MEETING_STATUSES = ['scheduled', 'held', 'cancelled'];
const ATTENDANCE = ['invited', 'attended', 'absent', 'excused'];

const oid = (value, name) => {
  if (!ObjectId.isValid(value)) fail(`${name} is not valid.`);
  return new ObjectId(value);
};
const maybeOid = (value) => (value && ObjectId.isValid(value) ? new ObjectId(value) : null);

const text = (value, max) =>
  (typeof value === 'string' ? value.trim().slice(0, max) : '');

function serialise(meeting, { userName, deptName, actorId }) {
  const participants = meeting.participants ?? [];
  const mine = participants.find((p) => String(p.userId) === String(actorId));
  const attended = participants.filter((p) => p.status === 'attended').length;
  const marked = participants.filter((p) => p.status !== 'invited').length;

  return {
    id: String(meeting._id),
    title: meeting.title,
    description: meeting.description ?? '',
    date: meeting.date,
    startTime: meeting.startTime ?? '',
    endTime: meeting.endTime ?? '',
    venue: meeting.venue ?? '',
    meetingUrl: meeting.meetingUrl ?? '',
    status: meeting.status,
    createdBy: String(meeting.createdBy),
    createdByName: userName.get(String(meeting.createdBy)) ?? 'Member',
    createdAt: meeting.createdAt,

    // Which departments were invited wholesale, for the summary line — "the
    // Marketing team" reads better than eleven names.
    departments: (meeting.departmentIds ?? []).map((id) => ({
      id: String(id),
      name: deptName.get(String(id)) ?? 'Department',
    })),

    participants: participants.map((p) => ({
      id: String(p.userId),
      name: userName.get(String(p.userId)) ?? 'Member',
      via: p.via,
      status: p.status,
      markedAt: p.markedAt ?? null,
    })),

    invitedCount: participants.length,
    attendedCount: attended,
    // Whether anybody has actually done the marking yet. Without this the UI
    // cannot tell "nobody came" from "nobody has recorded it".
    attendanceRecorded: marked > 0,

    // This viewer's own line.
    isInvited: Boolean(mine),
    myStatus: mine?.status ?? null,
  };
}

/** Names for everyone referenced, in one round trip. */
async function labels(meetings) {
  const userIds = meetings.flatMap((m) => [
    m.createdBy, ...(m.participants ?? []).map((p) => p.userId),
  ]).filter(Boolean);

  const [people, departments] = await Promise.all([
    col(C.users).find({ _id: { $in: userIds } }, { projection: { name: 1 } }).toArray(),
    col(C.departments).find({}, { projection: { name: 1 } }).toArray(),
  ]);
  return {
    userName: new Map(people.map((p) => [String(p._id), p.name])),
    deptName: new Map(departments.map((d) => [String(d._id), d.name])),
  };
}

/* ---------------------------------------------------------------- listing */

/**
 * Meetings this person can see.
 *
 * Everyone sees what they were invited to. Leadership sees all of them,
 * because scheduling clashes are exactly the thing they need to spot.
 */
router.get('/', async (request, response, next) => {
  try {
    const actor = request.user;
    const seesEverything = isSupervisor(actor.role)
      || rankOf(actor.role) >= RANK.secretaryGeneral;

    const filter = seesEverything ? {} : { 'participants.userId': actor._id };
    if (request.query.includeCancelled !== 'true') {
      filter.status = { $ne: 'cancelled' };
    }

    const meetings = await col(C.meetings)
      .find(filter).sort({ date: -1 }).limit(200).toArray();
    const { userName, deptName } = await labels(meetings);

    const rows = meetings.map((m) => serialise(m, { userName, deptName, actorId: actor._id }));

    // Split by calendar day, never by timestamp — a meeting at 10am today is
    // still today's meeting at 2pm, and comparing a stored time against `now`
    // is what made events vanish on the morning they ran.
    const startOfDay = (v) => { const d = new Date(v); d.setHours(0, 0, 0, 0); return d.getTime(); };
    const today = startOfDay(new Date());

    response.json({
      upcoming: rows.filter((m) => m.status === 'scheduled' && startOfDay(m.date) >= today)
        .sort((a, b) => new Date(a.date) - new Date(b.date)),
      past: rows.filter((m) => m.status !== 'scheduled' || startOfDay(m.date) < today),
      canSchedule: canScheduleMeeting(actor.role),
    });
  } catch (error) {
    next(error);
  }
});

router.get('/:id', async (request, response, next) => {
  try {
    const meeting = await col(C.meetings).findOne({ _id: oid(request.params.id, 'Meeting id') });
    if (!meeting) fail('That meeting no longer exists.', 404);
    const { userName, deptName } = await labels([meeting]);
    response.json({
      meeting: serialise(meeting, { userName, deptName, actorId: request.user._id }),
      canMarkAttendance: canMarkAttendance(request.user, meeting),
    });
  } catch (error) {
    next(error);
  }
});

/* --------------------------------------------------------------- creating */

/**
 * Call a meeting.
 *
 * Invitees arrive two ways and both end up in the same snapshot:
 *
 *   userIds[]        named people
 *   departmentIds[]  every approved member of those departments, Lead included
 *
 * The department form exists because the alternative is making somebody tick
 * eleven names to invite "Marketing" — which they will get wrong, and which
 * silently breaks the moment the team changes.
 */
router.post('/', async (request, response, next) => {
  try {
    const actor = request.user;
    if (!canScheduleMeeting(actor.role)) {
      fail('Your role cannot schedule meetings. Ask your Lead or the executive.', 403);
    }

    const title = text(request.body.title, 160);
    if (title.length < 3) fail('Give the meeting a title.');

    const date = new Date(request.body.date);
    if (Number.isNaN(date.getTime())) fail('Give the meeting a date.');

    const departmentIds = (Array.isArray(request.body.departmentIds)
      ? request.body.departmentIds : []).map(maybeOid).filter(Boolean);
    const namedIds = (Array.isArray(request.body.userIds)
      ? request.body.userIds : []).map(maybeOid).filter(Boolean);

    // Resolve the snapshot now.
    const fromDepartments = departmentIds.length === 0 ? [] : await col(C.users).find(
      { departmentId: { $in: departmentIds }, approvalStatus: 'approved' },
      { projection: { _id: 1, departmentId: 1 } },
    ).toArray();

    const named = namedIds.length === 0 ? [] : await col(C.users).find(
      { _id: { $in: namedIds }, approvalStatus: 'approved' },
      { projection: { _id: 1 } },
    ).toArray();

    // One entry per person even if they were caught by both a department and a
    // name — nobody should appear twice on an attendance sheet.
    const participants = new Map();
    for (const u of fromDepartments) {
      participants.set(String(u._id), { userId: u._id, via: 'department', status: 'invited' });
    }
    for (const u of named) {
      participants.set(String(u._id), { userId: u._id, via: 'person', status: 'invited' });
    }
    // The person calling it is in the room.
    participants.set(String(actor._id), {
      userId: actor._id, via: 'organiser', status: 'invited',
    });

    if (participants.size < 2) {
      fail('Invite somebody — a meeting with only you in it is a reminder.');
    }

    const now = new Date();
    const doc = {
      title,
      description: text(request.body.description, 2000),
      date,
      startTime: text(request.body.startTime, 10),
      endTime: text(request.body.endTime, 10),
      venue: text(request.body.venue, 200),
      meetingUrl: text(request.body.meetingUrl, 500),
      status: 'scheduled',
      departmentIds,
      participants: [...participants.values()],
      createdBy: actor._id,
      createdAt: now,
      updatedAt: now,
    };
    const inserted = await col(C.meetings).insertOne(doc);
    doc._id = inserted.insertedId;

    // Everyone except the organiser, who already knows.
    await notify(
      doc.participants.map((p) => p.userId).filter((id) => String(id) !== String(actor._id)),
      'meetingInvited',
      { meetingTitle: title, byName: actor.name, meetingId: String(doc._id) },
    );
    await audit(actor._id, 'meeting.create', {
      meetingId: String(doc._id), title, invited: doc.participants.length,
    });

    const { userName, deptName } = await labels([doc]);
    response.status(201).json({
      meeting: serialise(doc, { userName, deptName, actorId: actor._id }),
    });
  } catch (error) {
    next(error);
  }
});

/** Move it, rename it, or call it off. */
router.patch('/:id', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Meeting id');
    const meeting = await col(C.meetings).findOne({ _id: id });
    if (!meeting) fail('That meeting no longer exists.', 404);
    if (!canMarkAttendance(request.user, meeting)) {
      fail('Only the organiser and the executive can change this meeting.', 403);
    }

    const update = { updatedAt: new Date() };
    if (request.body.title !== undefined) update.title = text(request.body.title, 160);
    if (request.body.description !== undefined) update.description = text(request.body.description, 2000);
    if (request.body.venue !== undefined) update.venue = text(request.body.venue, 200);
    if (request.body.startTime !== undefined) update.startTime = text(request.body.startTime, 10);
    if (request.body.endTime !== undefined) update.endTime = text(request.body.endTime, 10);
    if (request.body.date !== undefined) {
      const date = new Date(request.body.date);
      if (Number.isNaN(date.getTime())) fail('That is not a valid date.');
      update.date = date;
    }
    if (request.body.status !== undefined) {
      if (!MEETING_STATUSES.includes(request.body.status)) fail('That is not a meeting status.');
      update.status = request.body.status;
    }

    const updated = await col(C.meetings)
      .findOneAndUpdate({ _id: id }, { $set: update }, { returnDocument: 'after' });

    // People rearrange their day around a meeting, so a move or a cancellation
    // has to reach them — silently changing it is worse than not having it.
    const movedOrCancelled = update.date !== undefined || update.status === 'cancelled';
    if (movedOrCancelled) {
      await notify(
        (meeting.participants ?? []).map((p) => p.userId)
          .filter((uid) => String(uid) !== String(request.user._id)),
        update.status === 'cancelled' ? 'meetingCancelled' : 'meetingMoved',
        { meetingTitle: updated.title, byName: request.user.name, meetingId: String(id) },
      );
    }

    await audit(request.user._id, 'meeting.update', { meetingId: String(id), ...update });
    const { userName, deptName } = await labels([updated]);
    response.json({
      meeting: serialise(updated, { userName, deptName, actorId: request.user._id }),
    });
  } catch (error) {
    next(error);
  }
});

/* ------------------------------------------------------------- attendance */

/**
 * Record who turned up.
 *
 * Takes the whole sheet in one call rather than one request per person: this is
 * done by somebody looking at a room, and a per-person endpoint would mean
 * thirty round trips and a half-marked meeting whenever one of them failed.
 */
router.post('/:id/attendance', async (request, response, next) => {
  try {
    const id = oid(request.params.id, 'Meeting id');
    const meeting = await col(C.meetings).findOne({ _id: id });
    if (!meeting) fail('That meeting no longer exists.', 404);
    if (!canMarkAttendance(request.user, meeting)) {
      fail('Only the organiser and the executive can record attendance.', 403);
    }
    if (meeting.status === 'cancelled') {
      fail('That meeting was cancelled, so there is nobody to mark.', 409);
    }

    const marks = Array.isArray(request.body.attendance) ? request.body.attendance : [];
    if (marks.length === 0) fail('Nothing to record.');

    const wanted = new Map();
    for (const mark of marks) {
      const userId = maybeOid(mark?.userId);
      if (!userId) continue;
      if (!ATTENDANCE.includes(mark.status)) continue;
      wanted.set(String(userId), mark.status);
    }
    if (wanted.size === 0) fail('None of those were valid.');

    const now = new Date();
    const participants = (meeting.participants ?? []).map((p) => {
      const next = wanted.get(String(p.userId));
      if (!next) return p;
      return { ...p, status: next, markedBy: request.user._id, markedAt: now };
    });

    const updated = await col(C.meetings).findOneAndUpdate(
      { _id: id },
      {
        $set: {
          participants,
          // Marking attendance is what turns a scheduled meeting into one that
          // happened, so the status follows rather than needing a second step.
          status: meeting.status === 'scheduled' ? 'held' : meeting.status,
          updatedAt: now,
        },
      },
      { returnDocument: 'after' },
    );

    await audit(request.user._id, 'meeting.attendance', {
      meetingId: String(id), marked: wanted.size,
    });

    const { userName, deptName } = await labels([updated]);
    response.json({
      meeting: serialise(updated, { userName, deptName, actorId: request.user._id }),
    });
  } catch (error) {
    next(error);
  }
});

/**
 * One person's attendance record.
 *
 * Derived from the meetings themselves, never from a counter kept on the user.
 * A stored tally is a second source of truth that drifts the first time a
 * meeting is edited, and then nobody can tell which number is right.
 */
async function attendanceFor(userId) {
  const meetings = await col(C.meetings).find(
    { 'participants.userId': userId, status: { $ne: 'cancelled' } },
    { projection: { participants: 1, date: 1, title: 1, status: 1 } },
  ).toArray();

  let invited = 0;
  let attended = 0;
  let absent = 0;
  for (const meeting of meetings) {
    const mine = (meeting.participants ?? [])
      .find((p) => String(p.userId) === String(userId));
    if (!mine) continue;
    // Only meetings that have actually been marked count towards a rate.
    // Counting an unmarked future meeting as a miss would show everybody
    // sliding towards 0% for no reason.
    if (mine.status === 'invited') continue;
    invited += 1;
    if (mine.status === 'attended') attended += 1;
    if (mine.status === 'absent') absent += 1;
  }

  return {
    invited,
    attended,
    absent,
    // No meetings recorded is not 0% — it is "nothing to show yet", and the
    // client needs to be able to tell those apart rather than printing a zero
    // that reads like a failing grade.
    rate: invited === 0 ? null : Math.round((attended / invited) * 100),
    upcoming: meetings.filter((m) => m.status === 'scheduled').length,
  };
}

router.get('/attendance/:userId', async (request, response, next) => {
  try {
    const userId = oid(request.params.userId, 'User id');
    response.json({ attendance: await attendanceFor(userId) });
  } catch (error) {
    next(error);
  }
});

module.exports = router;
module.exports.attendanceFor = attendanceFor;

# GWD Club OS v3 — Project Brief (condensed)

College club management app for **GWD Global**. Replaces the v1 prototype
(`mehnat_founder_os`). Flutter (Android + iOS + Web, one codebase) on a
Node/MongoDB real-time backend.

## The resolving principle

**Visual craft and navigational simplicity are separate axes, not a tradeoff.**
Load the app with features. Animate everything with intention. But never show a
user more than **one primary decision or focal point per screen**. Depth comes
from drilling down, not from stacking cards.

v1 failed on exactly this: nine competing dashboard cards on one screen
(`role_tailored_cockpit.dart` alone was 76 KB). That is the thing being escaped.

## Repo layout

```
/app        → Flutter project (Android APK, iOS, Web)
/backend    → Node/Express + Socket.IO + MongoDB
/CLAUDE.md  → this file
```

## Architecture, one line

App writes to MongoDB → Change Stream fires → Socket.IO pushes live to every
open client → FCM separately pings anyone not currently connected.

Change Streams **require a replica set**. Local dev runs MongoDB as a
single-node replica set (`rs0`). Swap `MONGODB_URI` for Atlas in production.

## Identity (permanent, do not change)

- applicationId / bundle ID: `com.gwd.clubos`
- Flutter package name: `gwd_club_os`
- Mongo DB name: `gwd_club_os`
- Display name: **GWD Club**

Anything still saying `mehnat`, `photonumbers`, `founder`, or `Photo Numbers` is
v1 residue and must be removed.

## Roles (enforce server-side, never trust the client)

| Role | Count | Assigns to | Sees | Approved by |
|---|---|---|---|---|
| Club Director | 2 | anyone | everything app-wide, full audit | none (pre-seeded) |
| **Faculty Coordinator** | 1 | President, VP, Sec Gen, all Leads | everything, full audit | none (pre-seeded) |
| President | 1 | VP, Sec Gen, all Leads | everything below | Directors (once) |
| Vice President | 1 | all Leads | same tier as Sec Gen | President |
| Secretary General | 1 | all Leads | same tier as VP | President |
| Club Lead | dynamic | own dept's members; may request across Leads and to Pres/VP/SecGen | own dept | President (Directors notified) |
| Club Member | many | — | own tasks only | own dept's Lead |

The five roles above Lead assign to a **department**, not a person — see
"Assigning work" below. `ASSIGN_TARGETS` is deliberately empty for all of them.

**Supervisors** = Club Director + Faculty Coordinator. They oversee rather than
compete: **no points, absent from the leaderboard**, but they *can* award points
by hand. A supervisor topping the board their own members are working up would
make the board meaningless. The Faculty Coordinator is the college's
representative — she directs the student leadership and stops at Leads, never
assigning to individual Members.

**Points: 1, 3 or 5 per task, set by the Lead when they hand it out.** Three
values, never a free number — a spectrum invites haggling, and the difference
between 6 and 7 points is not a conversation any club should be having. The Lead
prices it because they are the only person who knows whether "design the poster"
means twenty minutes or a weekend. Manual awards (1–20, with a reason) still
exist for what no per-task figure captures.

**The department Lead is credited whenever their department finishes
something.** Their job is getting the team's work done, so a department that
delivers is a Lead who delivered; crediting only the pair of hands makes running
a department look like doing nothing. Never twice — a Lead who did the task
themselves earns it once.

## Assigning work — two steps, never one long list

The club's leadership does **not** hand work to individuals. A Director
showing forty names and being asked to pick one is a decision they are not
equipped to make and did not ask for. A Lead knows who on their team is free
this week.

```
Director · Faculty Coordinator · President · VP · Secretary General
     └── assign to a DEPARTMENT ────────────────┐
                                                 ▼
                                       that department's Lead
                                                 │
                     ┌───────────────────────────┴──────────────┐
                     ▼                                          ▼
           assign to their own member                   do it themselves
```

- A department task lands **unassigned** (`assignedTo: null`) and notifies the
  Lead. If the department has no Lead, the President is told instead rather than
  the task sitting unseen.
- The Lead sees it in `scope=incoming` — the triage pile on the Work tab — and
  hands it out via `POST /api/tasks/:id/assign`, **pricing it at the same
  moment**.
- A Lead may assign only to their own department's Members. Anything sideways or
  upward is a **request**, not an assignment.
- `canAssignToDepartment` and `canDistributeDepartmentTask` in `permissions.js`
  are the authority; `/api/users/assignable` returns departments *or* people so
  the client never guesses.

**Departments are a dynamic collection, not an enum.** President and Directors
create/rename/deactivate them and assign Leads at runtime. v1 hardcoded these as
a Dart `enum` — that was the bug.

## Onboarding

Sign up (name, email, phone, department) → pending → that department's Lead
approves. If the signup *is* a Lead, it routes to the President, and **Directors
are notified too** for visibility. President + 2 Directors are pre-seeded.

## Navigation — five tabs, one question each

| Tab | The question it answers |
|---|---|
| **Home** | What should I do now? |
| **Events** | What is the club putting on? |
| **Work** | What am I responsible for? |
| **Departments** | How is each part of the club getting on? |
| **More** | Everything else — schedule, announcements, people, admin |

Events earns a tab because it is the unit a club organises around: tasks,
paperwork and who-does-what all hang off one. Schedule and Announcements moved
into **More** and Home surfaces what is happening today instead — a tab you open
once a week is a tab wasted. Admin screens (departments admin, analytics, audit)
also live in **More**, so they add zero weight for members who cannot use them.

**Home is the command centre.** Anything live today, then the one focal "what's
next" card, today's schedule, coming events, what needs *you*, who needs a hand,
quick actions, your week, and department progress — ordered by urgency, each
section labelled. Still exactly **one** primary decision. More information does
not have to mean more decisions.

## Events — the centre of gravity (v3)

An **event is a project, not a calendar entry**: a lead, an organising
department, supporting departments, a team, per-department responsibilities, the
work under those, and its official paperwork. Deliberately a separate collection
from `calendarEvents`, which stays a date and a title on the schedule. Merging
them would either bloat every schedule row with fields it never uses, or force a
real event through a model that cannot hold it.

- **Creation is one commit.** The three-step wizard collects everything —
  basics, team, and each department's opening tasks — and posts once. Splitting
  it would leave half-made events behind every time somebody backs out at step
  three. The wizard opens on the **root navigator** so it covers the tab bar; it
  returns the new id and the caller opens the workspace on its own navigator.
- **Unassigned work is a normal state.** The wizard captures *what* needs doing;
  who does it is a separate decision, often made days later by somebody else.
  Members of the responsible department pick work up from the board
  (`POST /events/:id/tasks/:taskId/claim`).
- **Event work stays off the general task list.** `/api/tasks` excludes
  `eventId` tasks unless `scope=mine` or `includeEvents=true` — one festival
  would otherwise bury everybody's own to-do list.
- **The board is four columns**: To do → In progress → Review → Done. `review`
  is optional; forcing it through every trivial task turns a club into an
  approvals queue. Blocked is *not* a column — a blocked card stays in its lane
  wearing a badge, because moving it somewhere else is how work gets forgotten.
- **Completion is checked, not blocked.** Closing an event with open work
  returns `409` plus a checklist; the UI shows what is outstanding and offers
  "close it anyway", because the last two tasks often never get ticked.

### Event documents — the one genuinely sensitive surface

Two kinds, and the distinction is the whole feature:

| Kind | Who may upload | Carries a status | Versioned |
|---|---|---|---|
| `file` (posters, scripts, budgets) | anyone approved | no | yes |
| `approval` (permission letters, venue bookings) | supervisors, exec, organising Lead | yes | yes |

**Filing a document is not approving it.** An uploaded approval lands as
`pending`; only supervisors and the executive tier can mark it `approved`, and
the decision is recorded against their name. Conflating the two is the hole this
model exists to close, so the upload sheet says so out loud.

Replacing a document **never overwrites bytes** — the old version stays readable
and an approval resets to pending, because a decision applies to the paper that
was actually read. Every upload, replacement, decision and deletion writes to the
audit log.

Files live on the backend's local disk (`UPLOAD_DIR`, default
`backend/uploads/`), served through an **authenticated route** — an unguessable
filename is not access control. That also means the URL cannot be handed to the
system browser: `ClubStore.downloadDocument` fetches the bytes with the token,
writes them to the cache directory, and hands the local file to `open_filex`.
Documents can also be a **link** to Drive; refusing that just means the
permission letter stays in a WhatsApp thread and the app is wrong about what
exists.

### Event finance — bookkeeping, not banking

A record of what an event cost and an approval trail for paying people back. It
**moves no money and stores no bank or card details** — a club app holding
members' account numbers is a liability nobody asked for, and "UPI, 12 Mar" is
all the record anyone needs.

- Department Leads and the executive tier **file**; a general member who paid out
  of pocket asks their Lead, which is also where somebody sanity-checks the
  spend.
- **Whoever files it cannot approve it.** Approving your own expense is the
  oldest hole in any petty-cash system, so approval is President + supervisors,
  and the President's own bills go to a Director.
- `pending → approved → paid`. *Approved* means somebody is **still out of
  pocket**; the Finance tab leads with two numbers, "spent" and "still owed",
  because those are the two anybody actually asks.
- Amounts are stored in **paise** so no total ever drifts by a rounding error,
  and rendered with lakh/crore grouping (₹1,45,000).
- A settled bill cannot be deleted — it is the record of a payment that happened.

## Security (v4)

`src/security.js` holds the cross-cutting protections so they cannot be
forgotten on a new route. What each one is actually for:

- **Operator stripping.** Express parses `?role[$ne]=clubMember` into a real
  Mongo operator, and any route dropping a query value into a filter then hands
  the caller something it never meant to offer — two routes did exactly that.
  Keys beginning with `$` or containing a dot are removed from body, query and
  params before a handler sees them. Routes still validate individually; this is
  the floor, not the wall.
- **Rate limiting**, in memory, on login / signup / forgot-password. Keyed on IP
  **and** the account named, so one person mistyping their password cannot lock
  out everybody else behind the same hotspot NAT — which is precisely what a
  club on one Wi-Fi would otherwise do to itself.
- **Constant-time login.** A dummy bcrypt comparison runs when no account
  matches, so an unknown address does not answer measurably faster. Without it
  the endpoint becomes a way to discover who has an account — the same leak
  `/password/forgot` is careful to avoid.
- **Password changes revoke existing tokens.** Tokens are stateless and last 30
  days, so without this, changing a password does nothing about whoever already
  has a session. The token carries a `pwd` claim holding the exact millisecond
  of the last change and `authenticate` compares for equality — **not** against
  the token's own `iat`, which is only second-accurate: a token minted in the
  same second as the change would survive it, and widening the comparison would
  kill the replacement token issued in that same second too. `/api/auth/password`
  therefore returns a fresh token, and the client adopts it (`Session.adoptToken`)
  or succeeding at changing your password signs you straight out. Admin resets
  stamp it too — that is the lost-phone case.
- **Uploads are served on the server's terms.** The stored file gets an opaque
  random name (so a crafted filename cannot escape the directory), and the
  response's content type is decided by `dispositionFor`, never echoed from what
  the uploader claimed. Only images, PDFs and plain text render inline;
  everything else downloads as an attachment. Echoing the claimed type with
  `inline` let a member upload an HTML or SVG file that ran as script on the
  app's own origin when a colleague opened it — a stored XSS, and a live one now
  that the app is also a website.
- **Two Content Security Policies, chosen by path.** `/api` gets
  `default-src 'none'`; the web build gets a policy allowing its own scripts and
  `wasm-unsafe-eval`, which Flutter's renderer requires. Getting this wrong is
  silent and total — a `'none'` policy over the web build blocks its own scripts
  and the site renders blank with nothing in the server log.

Data integrity: deleting a task now takes its comments with it. Comments are
addressed by task id and reachable no other way, so orphans accumulate forever.
Events **cancel** rather than delete, and retiring a department or a category
hides it, so nothing else is ever left pointing at a row that is gone.

## Platforms

One codebase, three targets, and each has a trap worth knowing.

- **Web.** `flutter build web`, served by the backend itself from
  `app/build/web`. The renderer is loaded from **this** server, not Google's
  CDN — see `web/flutter_bootstrap.js`. The default `canvasKitBaseUrl` points at
  gstatic.com, which is wrong twice: the server runs on a laptop on college
  Wi-Fi and must work when the internet does not, and fetching executable code
  from a third-party origin is what the CSP forbids, so the default renders a
  blank page. `window.flutterConfiguration` no longer exists and an inline
  `<script>` is blocked by the CSP; a custom `flutter_bootstrap.js` passing
  `config: { canvasKitBaseUrl }` to `_flutter.loader.load` is the supported way.
- **iOS.** The project exists and carries the right identity — `com.gwd.clubos`
  and "GWD Club". `flutter create` generates `com.gwd.gwdClubOs` and "Gwd Club
  Os" from the package name; both were corrected and must stay corrected, or
  Firebase and APNs bind to the wrong app. `Info.plist` carries
  `NSAllowsLocalNetworking` (not `NSAllowsArbitraryLoads`) so plain HTTP works
  on the LAN while ATS stays in force for the public internet, plus the local
  network, photo and camera usage strings iOS demands.
  `CADisableMinimumFrameDurationOnPhone` is already set, which is the iOS half
  of the high-refresh-rate work. **It still cannot be built on Windows** — that
  needs macOS and Xcode.
- **Android.** See the toolchain notes below.

Responsive behaviour is verified at all three window classes, on the web and on
a device: bottom bar under 640, icon rail at 640–1080, extended rail with labels
above that.

## Names — the person, then the position

**A name identifies somebody; a position only qualifies them.** Every surface
shows the name first and the role on the line underneath, never the other way
round and never one in place of the other.

The v3.1 seed got this exactly backwards: it wrote `name: "<Department> Lead"`,
so the club had six people called after their job and none called anything, and
there was no screen anywhere that could change a name — `PATCH /api/users/me`
existed and no client ever called it.

**The line under the name is the role _and_ the department**, via
`positionLineFor` / `Member.positionLine`: "Marketing Lead", "Marketing member",
and plain "President" for the executive tier, who have no department and whose
office names itself. The bare role is nearly useless in a club with six
departments — it says what somebody does without saying what they do it for, so
six different people read as the same person. Never print `member.name` raw or
show a role badge next to a department name and leave the reader to assemble the
sentence.

- Accounts created *for* people (the six seeded Leads, and the `.env` executive
  tier) carry `mustSetName: true`. **A flag, never string-matching the name** —
  "Creative Lead" is a perfectly good name for a person to have chosen, and
  guessing from the text would eventually badger a real one.
- `Member.displayName` renders `No name set` while that flag is up, greyed,
  with the role beneath. Use it everywhere a person is shown; never print
  `member.name` raw.
- Two ways to clear it, because accounts are handed over before they are used:
  whoever passes the credentials sets the name (`PATCH /api/users/:id/name`,
  President and supervisors only, audited, and **the person is told**), or the
  holder confirms it on first sign-in.
- First run asks for the name *before* the password. It is what everybody else
  in the club reads, and "who are you?" then "pick a password" reads like being
  welcomed rather than processed.
- Leads cannot rename anyone. Running a department does not extend to deciding
  what the people in it are called.
- `scripts/backfill-names.js` flags an existing database's placeholders. It only
  touches names this project is known to have shipped, and never re-flags
  somebody who has already answered.

## The personal calendar

The club schedule stays open to everyone. But *"what is the club doing"* and
*"what do I owe, and by when"* are different questions, and answering the second
by making somebody scan the first is how deadlines get missed.

`GET /api/schedule?mine=1` narrows the same data to the person asking: work
assigned to **them**, plus entries they have actually RSVP'd to. The narrowing
sits *inside* the visibility filter rather than replacing it — a scope parameter
must never be able to widen what somebody can see.

Alongside it, `services/reminders.js` sends one daily nudge. Three rules keep it
from being muted:

1. **One message per person per day, ever** — not one per task. Six
   notifications is how an app teaches people to swipe it away unread.
2. **Only when something is actually due.** No "you have nothing" pings.
3. **Only what is due.** Work with no due date is not late; next month is not
   today.

Idempotent across restarts via `users.lastRemindedOn` (a local `YYYY-MM-DD`), so
a laptop restarted four times in a morning still sends one. It ticks hourly
rather than firing at a precise time, because a machine asleep at 09:00 would
otherwise skip the day entirely — late beats never here. `scripts/test-reminders.js`
guards the once-a-day rule, which is the one that fails silently.

## Accounts and passwords

- **Six Lead accounts are seeded**, one per department, parked as **pending** so
  a Director or the President still lets each one in. Their passwords are
  printed **once** at first startup and are not recoverable; each account is
  flagged `mustChangePassword`, so the seeded password survives exactly one
  sign-in.
- **"Forgot password" is not an emailed link.** That needs an SMTP account the
  club does not have, and a club is not an anonymous internet service — every
  member can find the President in a corridor, which is a stronger identity
  check than an inbox. `POST /api/auth/password/forgot` raises a flag; a
  Director or the President resets it from the member record and is handed a
  temporary password to pass on. The endpoint answers **identically** for an
  unknown address, so it cannot be used to discover who has an account.
- `npm run reset` empties every collection and the uploads directory, so the
  next `npm start` reseeds clean. Destructive and deliberately awkward — it
  wants the database name typed back, or `--yes`.

## Help & collaboration (v3)

Two verbs: "I need help" and "I can help". The real failure mode in a club is not
that nobody will pitch in — it is that the person stuck on a poster at 11pm has
no way to say so without it sounding like a complaint.

So it is a **board, not a ticketing system**: no priorities, no SLAs, no
assignment authority. Anybody can offer, anybody can step back (offering to help
must never be a trap), and **only the person who asked closes it** — somebody
else declaring your problem solved is the fastest way to make people stop
asking. An ask notifies its own department, not the whole club; a club-wide ping
for every "can someone proofread this" is how people mute the app.

## Department workspaces (v3)

`GET /api/departments/:id/workspace` — people, current work, the events they are
on the hook for, and anyone asking them for help.

The rule that matters: **a department's view of an event shows only that
department's responsibilities.** A Marketing member opening a festival sees
Marketing's three tasks, not the festival's forty. Readable by everyone (a club
where you cannot see what another department is working on duplicates work);
the person-by-person breakdown stays behind `canViewDepartmentRoster`, and work
in another department's workspace comes back unattributed.

Being a Lead lets you run your own department's work. It does not make you an
administrator of anything else — `canManageWork` is per-department.

### The Schedule — categories, not fixed kinds

Schedule categories are **managed data**, exactly like departments — a club
holds rehearsals, shoots, sponsor visits, exam weeks, whatever that club does.
Seeded with Event / Meeting / Marketing / Shoot / Rehearsal; President and
supervisors add, rename, recolour and retire them at runtime
(`routes/categories.js`, `CategoryAdminPage`).

Hardcoding three kinds was the same mistake departments started with. Do not
reintroduce an enum here.

**One exception:** `deadline` is derived from any task with a due date. It is
never written directly, so the task list and the calendar cannot drift apart,
and tapping one opens the **task**, not a read-only copy.

**Agenda-first, not a month grid.** A grid looks like a calendar but answers
almost nothing a member actually asks. The date rail runs a **full year** and
marks month boundaries — an earlier version stopped dead after 14 days with no
way forward, which made the screen feel broken.

Retiring a category that still has entries **hides** it rather than deleting it,
or every past entry becomes an orphan with no name or colour. The API says which
happened; the UI repeats it.

**Every member can read every category.** The most common complaint about
running a club is people not knowing what is happening.

### Who can see whom

| Viewer | Individual records | Department rosters |
|---|---|---|
| Director, Faculty Coordinator | everyone | every department |
| President, VP, Secretary General | everyone | every department |
| Club Lead | everyone | every department |
| Club Member | own department + the executive | own department only |

**Supervisors are the exception in the other direction:** a Director's or the
Faculty Coordinator's own record opens only for other supervisors, and they are
omitted from the directory and the structure page. They oversee the club; they
are not part of the roster people browse.

**Department *progress* is open to everyone.** That is the line: a Member can
see Marketing is 60% through its work, but not who inside Marketing did what.
Aggregate yes, person-by-person only for your own department.

Enforced by `canViewMemberDetail` / `canViewDepartmentRoster` in
`permissions.js` — the client mirrors it with a `canOpen` flag per row so it
never offers a tap that would be refused.

### Recognition — per department, never club-wide

The leaderboard stays, but it is **split by department and stripped of the
competitive machinery**: no rank numbers, no podium, no gold/silver/bronze,
nothing telling anybody they are beating anybody.

Per department because a Cinematography member who shoots two films a term and a
Marketing member posting daily are **not doing the same job** — ranking them
against each other tells nobody anything. Inside a department the work is at
least alike, and the group is small enough to read as a team rather than a table.

- Ordered by **points earned**, which is the figure the Lead actually
  calibrated. Volume, then completion rate, then name break ties, so the list is
  stable rather than reshuffling every time somebody finishes something.
- The **Lead is shown above their team, not in it**. They earn from everything
  the department finishes, so a row would always sit on top and say nothing —
  and would quietly discourage everyone below.
- Anyone below `RANKING_THRESHOLD` (3) assigned tasks is still listed; the
  threshold only decides whether a completion rate is worth reading.
- People with no department (the executive tier) appear in their own
  "Running the club" group, never mixed into a department's list.
- `GET /api/users/department-overview` is the club-wide view: given against
  finished per department, plus work sent somewhere and not yet handed on.
  Open to everyone — aggregate numbers about a *department* give away nothing
  about any individual.

Same rule in every progress surface: department lists are sorted
**alphabetically, never by completion** — sorting by how well people are doing
turns a progress panel into a league table.

### Brand

The logo frames "GWD" between two open corner brackets. That bracket is the
strongest thing the mark owns, so `app/widgets/brand.dart` treats it as a
reusable device rather than a one-off splash image: `BracketFrame` (drawn, so it
themes and animates), `GwdMark`, `BracketLoader` (replaces the stock spinner),
`BrandedSectionHeader`. The selected nav tab gets a bracket rule, not a generic
pill.

Using a real brand element in place of stock Material chrome is most of what
separates an app that looks like *this club's* from one that looks generic.

### Responsive

`app/responsive.dart` defines three window classes by width, named for what they
mean for layout rather than for devices:

| Class | Width | Navigation | Columns |
|---|---|---|---|
| compact | < 640 | bottom bar | 1 |
| medium | 640–1080 | side rail | 1 |
| expanded | ≥ 1080 | extended rail | 2 |

A bottom bar on a tablet wastes the whole width and puts the controls miles from
the user's hands. `ContentWidth` caps line length on wide screens.

### Alerts

Two things, deliberately kept apart: *For you* (what needs **you**) and *Club*
(broadcasts). Mixing them buries the one message that needed you.

Broadcasts are signed with name and role, and the compose sheet states how many
people you are about to interrupt **before** you can send. Members cannot
broadcast — once everyone can page everyone, nobody reads any of it. Only the
President and supervisors can mark something *urgent*, so the word keeps meaning
something.

## Design system — KEEP AND EXTEND, do not rewrite

`app/lib/app/theme/gwd_theme.dart` + `apple_motion.dart` already satisfy most of
the design brief and are genuinely good. They provide:

- `GwdColors` — light + dark tokens with `*Of(context)` resolvers
- `GwdType` — real ramp (32/26/21/17/15/14.5/13.5...), **tabular figures** on `numeric`
- `GwdSpace` (4pt), `GwdRadius` (varied, not uniform 12), `GwdShadow` (contact + ambient)
- `AppleSprings` — real `SpringDescription` physics; `AppleCurves` — custom cubics
- `PressableScale` (+ `HapticStrength`), `AnimatedCounter`, `FluidPageTransitionsBuilder`,
  `FluidReveal`, `AppleStaggerItem`
- `SurfaceCard` with `SurfaceEmphasis.{quiet, raised, live}`

**Colour rule, inherited from v1 and worth keeping:** the canvas and cards stay
quiet; crimson is spent only on the one thing on screen that actually needs
attention.

Brand: crimson `#DC2626` + jet black `#09090B`, from the red club logo. Never
default Material purple.

Cleanup owed: `gwd_theme.dart` carries dead aliases from an abandoned neon/glass
iteration (`primaryIndigo`, `purple`, `electricViolet`, `neonPink`, `neonCyan`,
`glassSurface`, `GlassCard`). Delete as feature pages get rewritten.

**Dark mode must be ON.** v1 pinned `themeMode: ThemeMode.light` in `main.dart`
with a comment about auditing screens. The tokens already exist — unpin it and
audit.

## Rules

- Every state change animates with intent. Springs, not `easeInOut`. Task
  Pending→In Progress→Completed physically transitions.
- Live Socket.IO arrivals animate in; never a jarring full-list reload.
- Live toast is a custom branded component (`alert_island.dart`), not a Material
  SnackBar. Consistent edge, auto-dismiss, stacks gracefully.
- Haptics on task completion and approval (mobile only).
- Progressive disclosure: bulk-assign, audit log, task requests live behind a
  secondary action.
- Designed empty and loading states. No default spinners.
- Accessibility: dynamic text scaling, contrast in both themes, screen-reader
  labels on icon-only buttons.
- Points: **1, 3 or 5 per task**, set by the Lead at hand-out. Counts up, never
  jump-cuts. No confetti. Recognition is one tap deep inside More, never on Home.
- **Progress is never a ranking.** Department lists sort alphabetically, copy
  says "4 left to go" rather than "72% — 3rd of 5", and nothing compares one
  person or department to another.

## Data model

```
users          { _id, name, email, phone, role, departmentId, points, approvalStatus }
departments    { _id, name, leadUserId, active, createdBy, createdAt }
tasks          { _id, title, description, assignedBy, assignedTo, departmentId,
                 eventId, status, dueDate, points, updatedAt }
taskRequests   { _id, fromUserId, toUserId, description, status }
accessRequests { _id, userId, departmentId, approverId, status }
calendarEvents { _id, title, date, createdBy, categoryId }
notifications  { _id, userId, type, payload, read, createdAt }

-- v3 ------------------------------------------------------------------------
events                 { _id, name, description, type, date, startTime, endTime,
                         venue, status, banner, organizingDepartmentId,
                         leadUserId, supportingDepartmentIds[], teamUserIds[],
                         speakerName, guestDetails, externalOrganisation }
eventResponsibilities  { _id, eventId, departmentId, notes, createdBy }
eventDocuments         { _id, eventId, kind, title, note, status, createdBy,
                         decidedBy, decidedAt, decisionNote,
                         versions[{ filename, storedName, size, mimeType, link,
                                    uploadedBy, uploadedAt, note }] }
helpRequests           { _id, title, description, status, skills[],
                         departmentId, eventId, createdBy,
                         helpers[{ userId, note, at }], resolvedAt }

-- v3.1 ----------------------------------------------------------------------
eventBills             { _id, eventId, title, note, category, amountPaise,
                         spentOn, paidByName, departmentId, status, createdBy,
                         decidedBy, decidedAt, decisionNote,
                         settledBy, settledAt, settlementRef,
                         receipt{ filename, storedName, size, mimeType } }

users  gains  mustChangePassword, passwordResetRequestedAt
tasks  gains  assignedTo: null  (work addressed to a department, awaiting
              hand-out) and points ∈ {1, 3, 5}
```

Index `tasks` on `assignedTo`, `assignedBy`, `departmentId`; index `updatedAt`
for Change Stream cursor resumption.

**Never** re-create v1's unique index on `{workspaceId, role}` in `users` — it
capped the app at one account per role and made a real club impossible.

## Build / release

- `com.gwd.clubos`, chosen permanently, consistent across Android, iOS, Firebase.
- Release builds only. No `debuggable=true`.
- For distribution: App Bundle / per-ABI split.
- **For the user's own testing: one universal release APK they can forward.**
  This deliberately overrides the brief's "no fat APK" line, which is about
  store distribution.
- iOS requires macOS + Xcode — **cannot be built on this Windows machine.** Code
  stays iOS-clean; the build happens elsewhere.

## Local toolchain (portable, this machine)

Everything lives in `D:\dev\gwd-toolchain` — no admin rights, nothing installed
into C:. Flutter 3.47.4, Temurin JDK 17, Android SDK (platforms 34/35/36,
build-tools 35/36, NDK r28c, CMake), PortableGit, MongoDB 8.3.11 + mongosh.

Set these before any Flutter command:

```powershell
$root='D:\dev\gwd-toolchain'
$env:JAVA_HOME="$root\jdk"; $env:ANDROID_SDK_ROOT="$root\android-sdk"
$env:PATH="$root\flutter\bin;$root\jdk\bin;$root\git\cmd;$env:PATH"
```

### Gotchas that cost real time — read before repeating them

- **Never run two Flutter commands at once.** `flutter test` or `flutter analyze`
  during a `flutter build` deadlocks on the Flutter tool lockfile: the build's
  `dart` process sits at 0% CPU forever with no error. If a build goes silent
  for more than a few minutes, check `Get-Process dart` — 0 CPU means deadlock,
  not slowness. Kill the `dart`/`java` processes and delete
  `flutter\bin\cache\lockfile`.
- **MongoDB runs on 27018, not 27017.** This machine already has a MongoDB
  Windows service on 27017; it is deliberately left alone. Two consequences that
  have both bitten: `Get-Process mongod` **always** matches that service, so it
  can never be used to decide whether *our* instance is up — test the port; and
  a `mongod` in Task Manager is not evidence the app's database is running.
- **Neither backend process survives a reboot or a long sleep, and the app
  reports that as "can't sign in".** From a phone, a stopped server, a moved IP
  and a firewall block are indistinguishable — all three are a sign-in that
  never completes — but the fixes are unrelated. `scripts\start-server.ps1`
  brings both processes up and then says which of the three it is. Reach for it
  before debugging anything in the app. Data lives in `backend/.mongo-data` and
  survives all of this; a dead server is never a reason to re-seed.
- **`flutter build` rewrites `android/app/build.gradle.kts`.** It reverts a
  literal `minSdk` back to `flutter.minSdkVersion`. Don't fight it.
- **Do not turn R8 minification back on without testing on a real device.**
  `isMinifyEnabled = true` shipped a release APK that died instantly with no UI:

  ```
  Unable to get provider androidx.startup.InitializationProvider:
    Failed to create an instance of androidx.work.impl.WorkDatabase
  ```

  `home_widget` pulls in WorkManager, which uses Room. Room loads its generated
  `WorkDatabase_Impl` class reflectively by name; R8 renamed it, the lookup
  failed, and because WorkManager initialises through `androidx.startup` — which
  runs *before* any Activity — the process died before the first frame. It only
  reproduces in release, so `flutter run` and the web build both look fine.
  `proguard-rules.pro` now carries the keep rules that make R8 survivable, but
  minification stays off: it saves ~5 MB on a 57 MB APK that is mostly Flutter
  engine, which is not worth the fragility.
- **There is a working emulator for exactly this.** AVD `gwd_test`
  (Android 14, x86_64). Release-only crashes cannot be caught any other way:

  ```powershell
  D:\dev\gwd-toolchain\android-sdk\emulator\emulator.exe -avd gwd_test -no-window -no-audio -no-snapshot -gpu swiftshader_indirect
  adb install -r <apk>; adb shell am start -n com.gwd.clubos/.MainActivity
  adb logcat -d -v brief *:E
  ```
- **`sdkmanager --licenses` cannot be automated by piping `y`** — it needs a
  TTY. The license hash files are written directly instead. One license
  (`android-googlexr-license`, the XR emulator image) stays unaccepted; it is
  irrelevant to building an APK, so `flutter doctor` shows a warning that can be
  ignored.
- First Android build pulls the NDK (~3 GB) and takes ~20 minutes. Later builds
  are ~11 minutes.
- The `GWD_API_BASE` dart-define is **baked in at build time**, and a router
  reassigning the laptop's IP silently breaks every installed copy. This has
  already happened twice (`10.44.188.163` → `10.88.222.163` → back again, on a
  phone hotspot whose DHCP leases rotate). Three things address it:
  1. **Build with `scripts\build-apk.ps1`**, never `flutter build apk` by hand.
     It reads the live IPv4 off whichever adapter holds the default route —
     picking by adapter *name* breaks the moment Ethernet is plugged in — checks
     the backend actually answers there, bakes it in, and stages the APKs.
  2. The sign-in screen carries a **server address override**
     (`Session.setServer`, persisted) that highlights itself when a connection
     fails, so a moved server is a retype rather than a rebuild.
  3. `ApiClient` and `SocketClient` read the address through a provider on every
     call — never capture it once.

  Without the dart-define the app falls back to `10.0.2.2:4000` on Android,
  which is the emulator's alias for the host and reaches **nothing** from a real
  phone. An APK built plainly will look broken on hardware while working
  perfectly on the emulator.
- **The laptop's firewall has to let port 4000 in.** It currently does, via two
  inbound Allow rules for "Node.js JavaScript Runtime" on the **Public** profile
  — which is the profile a phone hotspot gets. If the app can reach nothing from
  a real phone while `curl` works on the laptop, check the rule's profile
  matches the current network's category (`Get-NetConnectionProfile`).
- **Android back needs two things, and both are easy to miss.**
  1. `android:enableOnBackInvokedCallback="true"` in the manifest. Without it on
     targetSdk 33+, back is never routed to the framework.
  2. The `PopScope` must sit **directly under the home route** (it lives in
     `main.dart`'s `_Root`). Inside `ClubShell` it sat behind that widget's own
     nested `Navigator` and was never consulted — back closed the app from
     anywhere, including out of an open task.

  The shell exposes `ClubShell.handleBack()` for the root to call. It unwinds:
  close a detail page → return to Home from any other tab → only then exit.
- **Never edit Dart sources with PowerShell `Get-Content`/`Set-Content`.** The
  round trip decodes UTF-8 as ANSI and re-encodes it, silently turning `·` into
  `Â·` and `—` into `â€”` *in the shipped UI*. Four files were corrupted this
  way. Use the Edit tool. To check:

  ```powershell
  Get-ChildItem app\lib -Recurse -Filter *.dart | ForEach-Object {
    $t=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($_.FullName))
    if ($t -match "Â[ -¿]" -or $t -match "â€") { $_.Name }
  }
  ```
- **Screens must read from the store, not fetch their own copy.** The
  leaderboard used to load once in `initState`, so awarding points updated the
  directory while the board silently disagreed. Anything that can change a
  standing (`awardPoints`, task completion, `user:updated`) refreshes
  `loadLeaderboard`. If a screen has its own `_load()` in `initState`, that is a
  sync bug waiting to be reported.
- **A failing socket used to freeze the UI.** Socket.IO retried a rejected token
  roughly once a second, and each attempt hit `notifyListeners`, rebuilding the
  whole tree and swallowing taps. `SocketClient` now stops on an auth rejection
  (`LiveStatus.unauthorized`) and signs out; `ClubStore` ignores status churn
  that does not change the value.
- **`compileSdk` is pinned to 36 in `android/app/build.gradle.kts`.** Plugin AARs
  now routinely declare they must be compiled against 36 or later, and the build
  dies at `:checkReleaseAarMetadata` otherwise. Overriding a *plugin's* own
  compileSdk from the root Gradle file does not work — the Android plugin reads
  it before `afterEvaluate` and throws "It is too late to set compileSdk". The
  fix is to upgrade the offending package (`file_picker` 8 → 12 dropped the
  transitive dependency entirely), not to fight Gradle. `targetSdk` and `minSdk`
  stay tracking the Flutter SDK, so nothing changes about which phones can
  install the APK.
- **A widget that owns a button cannot validate on a child's field.** The event
  wizard's Continue button lives in the flow widget; the name field lives in a
  step. Typing rebuilt only the step, so the button stayed greyed out however
  much you typed. The flow now listens to the controller and exposes
  `refresh()` for steps to call. Any split like this has the same trap.
- **A `PageView`'s children stay alive.** Seeding step three from what step two
  chose cannot go in step three's `initState` — it runs once and never notices
  the choice changing. Seed on the *transition* instead (`_go(2)`).
- **`FlexibleSpaceBar.title` draws over the background at every scroll
  position.** With a hero title in the background, the small pinned title sat
  directly on top of the large one. The event header is hand-rolled: a
  `LayoutBuilder` computes how open the header is and cross-fades the two, so
  exactly one is ever readable.
- **`adb shell input text` silently drops `!`.** It cost half an hour of "wrong
  password" on a seeded account. Tap the key on the soft keyboard, or test with
  an alphanumeric-only password.
- **Pull screenshots, never redirect them.** `adb exec-out screencap -p > f.png`
  through PowerShell corrupts the binary (BOM + CRLF). Use
  `adb shell screencap -p /sdcard/s.png; adb pull /sdcard/s.png`.
- **.NET file APIs in PowerShell ignore the shell's working directory.**
  `[IO.File]::ReadAllLines('scripts\x.js')` resolves against the *process* cwd,
  not `Set-Location`'s. Use absolute paths, or just use the Edit tool.
- **A button's enabled state cannot depend on `onSubmitted`.** `GwdField` has
  both; `onSubmitted` fires only when the keyboard's Done key is pressed, which
  people reasonably never do — so the button sits dead while they type. Use
  `onChanged` for anything a Continue/Save depends on. This shipped twice: the
  event wizard's Continue and the password sheet's Save.
- **A widget that owns a button cannot validate a child's field.** Same family:
  the event wizard's Continue lives in the flow, the name field in a step, so
  typing rebuilt only the step. The flow listens to the controller and exposes
  `refresh()` for steps to call.
- **A phone window sits at 60Hz until the app asks for more.** On most Android
  devices — OnePlus and Samsung especially — Flutter renders at 60 on a 120Hz
  panel, so the app looks obviously less fluid than the launcher it was opened
  from and reads as slow. `MainActivity.requestHighestRefreshRate()` asks for
  the fastest mode **at the current resolution**; taking the fastest mode
  outright would silently downgrade resolution on devices that offer that
  trade. It is a request — the system still overrides it for battery and
  thermals, which is correct.
- **An eager `ListView(children: [...])` builds every row at once**, and every
  row here owns an animation controller (`FluidReveal`). Fine for six people, a
  visible stutter for a club of a hundred. Member lists use `ListView.builder`
  so roughly a screenful is alive at a time. `maxDelayMs` already caps the
  stagger, so long lists do not also wait seconds to finish appearing.
- **Responses are gzipped** (`compression`, 1KB threshold, already-compressed
  types skipped). The backend serves a roomful of phones over one hotspot and
  its payloads are JSON, which compresses to about a fifth. Skipping images and
  PDFs matters: re-compressing them spends CPU to make the response bigger.
- **The Mongo pool is sized explicitly** (`maxPoolSize: 100`), because the app
  is used in bursts — eighty people opening it at the start of a meeting, not a
  steady trickle. `waitQueueTimeoutMS` is the important one: a saturated pool
  fails in four seconds with something the client can retry, instead of hanging
  until the user decides the app is broken.
- **Anything the app must fetch on load has to be in `ClubStore.loadAll`.**
  `loadIncoming` existed, was called from two write paths, and was missing from
  `loadAll` — so a Lead's triage pile was empty until they assigned something.
  Adding a `load*` method is two edits, not one.

## Firebase / FCM

Built but optional. The app must run correctly with **no** `google-services.json`
present — in-app live toasts and the Notifications tab work over Socket.IO alone.
Dropping in the real Firebase file later switches background push on with no
code change.

# GWD Club OS v2

Club management for **GWD Global** — a Flutter app (Android, iOS, Web from one
codebase) on a Node/MongoDB real-time backend.

This is a rebuild of the v1 prototype, which shipped under the leftover identity
`mehnat_founder_os` / `com.photonumbers.mehnat` and was structurally a
three-founder startup tracker with a club UI bolted on top.

```
/app        → Flutter project
/backend    → Express + Socket.IO + MongoDB
/CLAUDE.md  → the condensed project brief
```

---

## The one design rule

**Visual craft and navigational simplicity are separate axes, not a tradeoff.**

Load the app with features. Animate everything with intention. But never show
more than **one primary decision per screen**. Depth comes from drilling down,
not from stacking.

v1 failed exactly here: nine competing cards on one dashboard, one of which
(`role_tailored_cockpit.dart`) was 76 KB on its own. Home now shows your name, a
quiet points counter, and *one* thing to do next.

---

## Architecture

```
app writes → MongoDB → Change Stream fires → Socket.IO pushes to every open client
                                           → FCM pings anyone who isn't connected
```

Routes never emit socket events themselves. They write to Mongo; the Change
Stream is the only source of live events. That is what makes a task completed on
web appear on a phone in about a second without any per-client special casing.

**Change Streams require a replica set.** A standalone `mongod` has no oplog to
watch and live sync silently does nothing — so `/api/health` reports
`changeStreams: true|false` honestly rather than pretending.

---

## Running it locally

### The short version — after a reboot

```powershell
.\scripts\start-server.ps1
```

Starts MongoDB and the API, checks the API answers on the LAN address, and
compares that address against the one baked into the last APK build. Neither
process survives a reboot or a long sleep, and when they are down the app says
"can't sign in" — which reads as a broken app rather than a stopped server.

It distinguishes the two failures that look identical from a phone:

| What it says | What to do |
|---|---|
| `Health FAILED` | firewall — the Node.js inbound rule must be on the profile the current network has |
| `Address CHANGED since the last APK build` | the server moved; retype the address on the sign-in screen, don't rebuild |

Pass `-Restart` to replace a running API after changing backend code.

### 1. MongoDB (single-node replica set)

```bash
powershell -File backend/scripts/start-mongo.ps1
```

Starts `mongod` on **port 27018** with `--replSet rs0` and initiates the set.
Port 27018, not the default 27017, because this machine already runs a MongoDB
Windows service — that one is left untouched.

### 2. Backend

```bash
cd backend
npm install
npm start
```

Prints the LAN address your phone should use. First run seeds the two Club
Directors, the President, and five starting departments from `backend/.env`.

Verify it end to end:

```powershell
.\backend\scripts\smoke-isolated.ps1
```

232 checks covering the permission matrix, the approval chain, live Socket.IO
delivery, points, visibility scoping, event finance, passwords, naming, and the
daily reminder sweep.

It runs against a **throwaway database on its own port**, then drops it. Use
this rather than `npm run smoke` once the club is actually using the app: the
suite creates accounts, departments and tasks, and against the live database
those turn up in the real member directory and never leave.

### 3. The app

```bash
cd app
flutter run --dart-define=GWD_API_BASE=http://<your-lan-ip>:4000
```

Without `GWD_API_BASE` the app defaults to `10.0.2.2:4000` on Android (the
emulator's alias for the host) and `localhost:4000` elsewhere. Web builds use
the origin they were served from.

### Building the APK

```powershell
.\scripts\build-apk.ps1              # arm64 only, ~24 MB
.\scripts\build-apk.ps1 -Universal   # also the fat APK, ~60 MB
```

The script reads this machine's current LAN address off whichever adapter holds
the default route, checks the backend is actually answering there, bakes the
address in, and stages the APKs at the repo root. Pass `-Ip 192.168.1.42` to
override the detection.

By hand, if you prefer:

```bash
flutter build apk --release --split-per-abi \
  --dart-define=GWD_API_BASE=http://<your-lan-ip>:4000
```

The API base is **baked in at build time**, so an APK built against one LAN
address will not reach a server that has since moved. Two things soften that:

- the sign-in screen carries a **server-address override** that highlights
  itself when a connection fails, so a moved server is a retype rather than a
  rebuild;
- `scripts/build-apk.ps1` removes the step where the new IP gets forgotten.

Two APKs are produced at the repo root:

| File | Size | Use |
|---|---|---|
| `GWD-Club-v4.0.0.apk` | 60 MB | universal — runs on any phone, good for forwarding to anyone |
| `GWD-Club-v4.0.0-arm64.apk` | 24 MB | arm64 only — every modern phone, small enough to send over chat |

### As a website

```bash
cd app
flutter build web --release --dart-define=GWD_API_BASE=http://<lan-ip>:4000
```

The backend serves `app/build/web` from `/`, so once it is built the same
address that answers the API also serves the site — open
`http://<lan-ip>:4000` in any browser on the network. The renderer is served
from that server too rather than Google's CDN, so the site works when the
internet does not.

### On iOS

`app/ios/` exists and carries the right identity (`com.gwd.clubos`, "GWD
Club"), an ATS exception for local-network HTTP, and the usage strings iOS
requires. **The build itself needs macOS and Xcode** — it cannot be produced on
this Windows machine. On a Mac: `cd app && flutter build ios --release
--dart-define=GWD_API_BASE=...`.

### Starting from nothing

```bash
cd backend
npm run reset     # empties every collection and the uploads directory
npm start         # reseeds: 6 departments, 6 pending Lead accounts, the roots of trust
```

The Lead passwords are printed **once**, at the moment the accounts are created.
They are hashed, so there is no second chance to read them — copy them out of
that first startup log. Each account arrives in the approval queue and is asked
to choose its own password the first time it signs in.

**R8 minification is deliberately off.** Turning it on produced a release APK
that died instantly with no UI, because Room (via WorkManager, via
`home_widget`) loads a generated class reflectively and R8 renamed it. See
`CLAUDE.md` for the full stack trace and the keep rules. Do not re-enable it
without testing the release build on a device.

### Testing a release build

Release-only crashes do not reproduce with `flutter run` or on web. There is an
emulator set up for this:

```bash
D:\dev\gwd-toolchain\android-sdk\emulator\emulator.exe -avd gwd_test -no-window -no-audio -no-snapshot -gpu swiftshader_indirect
adb install -r GWD-Club-v2.0.0.apk
adb shell am start -n com.gwd.clubos/.MainActivity
adb logcat -d -v brief *:E
```

---

## Sign-in accounts

Seeded from `backend/.env`. The defaults in `.env.example` are placeholders —
change them before this is used by anyone real.

| Role | Email | Approval |
|---|---|---|
| Club Director ×2 | `director1@gwd.club`, `director2@gwd.club` | none — pre-seeded root of trust |
| President | `president@gwd.club` | none — pre-seeded |
| Everyone else | signs up in the app | routed to their approver |

Anyone else signs up with name, email, phone and department, lands in a pending
state, and is approved by their department Lead — or by the President if they
*are* a Lead, with the Directors notified for visibility.

---

## What is and isn't wired up

**Working:** all six roles enforced server-side, dynamic departments, the
approval chain, both Task tabs, task requests, calendar with RSVP, notifications,
points, leaderboard, member directory, audit log, one analytics screen, live sync
over Change Streams, dark mode, and the Android home-screen widget.

**Built but dormant:** FCM push. The whole server side exists (`devices`
collection, `/api/auth/device`, `services/fcm.js`) and the app runs perfectly
without it. Switching it on needs a Firebase project for `com.gwd.clubos` — see
the note in `app/pubspec.yaml`.

**Not built here:** the iOS build. It needs macOS and Xcode; this repo was
developed on Windows. The Dart code is platform-clean and the `home_widget`
bridge already targets a WidgetKit extension, but `ios/` has to be generated and
the widget extension written on a Mac.

**Platform honesty on widgets:** Android redraws the widget whenever task data
changes. iOS meters refreshes through WidgetKit's timeline budget — typically
15–30 minutes, or on a push. The iOS widget is *not* real-time and shouldn't be
described as such.

---

## Release identity

`com.gwd.clubos`, chosen permanently and consistent across Android, iOS, and any
Firebase/APNs binding.

Release builds are signed with a real keystore when `android/key.properties`
exists, and fall back to debug signing when it doesn't so `flutter run --release`
still works on a fresh clone. **A debug-signed APK is for testing only** — create
a real keystore before distributing.

`android/app/src/main/res/xml/network_security_config.xml` currently permits
cleartext HTTP, because the test APK talks to a plain-HTTP dev server on a
DHCP-assigned LAN address. Put the backend behind HTTPS and flip that to `false`
before real users touch it.

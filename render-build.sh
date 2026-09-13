#!/usr/bin/env bash
#
# Render build: install the API's dependencies, then build the Flutter web app
# that the same service will serve.
#
# `set -euo pipefail` on purpose. A half-built deploy is worse than a failed
# one: the API would come up healthy while the website served 404s, and the
# health check would report everything fine.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-stable}"
FLUTTER_DIR="$HOME/flutter"

echo "==> Installing API dependencies"
cd backend
# `npm ci` not `npm install`: it installs exactly what package-lock.json pins,
# so a deploy cannot quietly pick up a different version of anything.
npm ci --omit=dev
cd ..

echo "==> Fetching Flutter ($FLUTTER_VERSION)"
if [ ! -d "$FLUTTER_DIR" ]; then
  # --depth 1 keeps this to a fraction of the full SDK history. Cloning is used
  # rather than a pinned tarball URL because the tarball name encodes an exact
  # version, and that link rots on every Flutter release.
  git clone --depth 1 -b "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"

# Render's build container is not a git-safe directory by default, and Flutter
# shells out to git to work out its own version.
git config --global --add safe.directory "$FLUTTER_DIR" || true

flutter --version
flutter config --no-analytics >/dev/null 2>&1 || true

echo "==> Building the web app"
cd app
flutter pub get
# No --dart-define here on purpose. On web the app resolves its API base to the
# origin it was served from, and this service serves both — so the build works
# on whatever hostname Render gives it, including preview URLs.
flutter build web --release
cd ..

echo "==> Build complete"
echo "    web output: app/build/web"
ls -la app/build/web/index.html

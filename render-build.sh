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
# Set BUILD_WEB=false to skip the website entirely and deploy only the API.
BUILD_WEB="${BUILD_WEB:-true}"

# --- the part that must not fail ------------------------------------------
echo "==> Installing API dependencies"
cd backend
# `npm ci` not `npm install`: it installs exactly what package-lock.json pins,
# so a deploy cannot quietly pick up a different version of anything.
npm ci --omit=dev
cd ..

# --- the part that is allowed to fail --------------------------------------
#
# The website is built here as a convenience. It is NOT allowed to fail the
# deploy, and that is a correction of an earlier decision.
#
# The earlier reasoning was that a half-built deploy is worse than a failed one:
# the API would come up healthy while the site served 404s. That was wrong about
# which failure is worse. In practice the Flutter web build is the heaviest step
# by far — dart2js wants well over a gigabyte, which a free build container does
# not reliably have — and when it died, `set -e` took the whole deploy with it.
# Render then kept serving the previous release, so *every* backend fix silently
# failed to reach production while /api/health stayed green. Security fixes were
# sitting unshipped behind a website nobody had asked to block them.
#
# So: the API always deploys. If the web build fails the site is simply absent,
# the log says so plainly, and /api/health reports `web: "missing"` rather than
# leaving anyone to guess.
build_web() {
  echo "==> Fetching Flutter ($FLUTTER_VERSION)"
  if [ ! -d "$FLUTTER_DIR" ]; then
    # --depth 1 keeps this to a fraction of the full SDK history. Cloning is
    # used rather than a pinned tarball URL because the tarball name encodes an
    # exact version, and that link rots on every Flutter release.
    git clone --depth 1 -b "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  fi
  export PATH="$FLUTTER_DIR/bin:$PATH"

  # Render's build container is not a git-safe directory by default, and
  # Flutter shells out to git to work out its own version.
  git config --global --add safe.directory "$FLUTTER_DIR" || true

  flutter --version
  flutter config --no-analytics >/dev/null 2>&1 || true

  cd app
  flutter pub get
  # No --dart-define on purpose. On web the app resolves its API base to the
  # origin it was served from, and this service serves both — so the build works
  # on whatever hostname Render gives it, including preview URLs.
  flutter build web --release
  cd ..
}

if [ "$BUILD_WEB" = "true" ]; then
  echo "==> Building the web app (optional - will not fail the deploy)"
  # The subshell keeps a `cd` inside build_web from stranding us if it dies.
  if ( build_web ); then
    echo "==> Web build OK: app/build/web"
    ls -la app/build/web/index.html
  else
    echo ""
    echo "############################################################"
    echo "  WEB BUILD FAILED - deploying the API anyway."
    echo "  The API, and every fix in it, is live. The website is not."
    echo "  Most likely the build container ran out of memory."
    echo "  Set BUILD_WEB=false to stop attempting it."
    echo "############################################################"
    echo ""
    rm -rf app/build/web || true
  fi
else
  echo "==> Skipping the web build (BUILD_WEB=false). API only."
fi

echo "==> Build complete"

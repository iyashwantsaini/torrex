#!/usr/bin/env bash
# Installs Flutter into Vercel's build cache and pre-caches web artifacts.
# Runs on every Vercel build, but the clone + precache are cached between
# builds via $HOME (Vercel persists $HOME across builds for the same project).

set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.9}"
FLUTTER_HOME="$HOME/flutter"

if [ ! -d "$FLUTTER_HOME/bin" ]; then
  echo "==> Installing Flutter $FLUTTER_VERSION into $FLUTTER_HOME"
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_HOME"
else
  echo "==> Reusing cached Flutter at $FLUTTER_HOME"
  (cd "$FLUTTER_HOME" && git fetch --depth 1 origin "$FLUTTER_VERSION" && git checkout "$FLUTTER_VERSION") || true
fi

export PATH="$FLUTTER_HOME/bin:$PATH"

flutter --version
flutter config --no-analytics --no-cli-animations
flutter precache --web --no-android --no-ios --no-linux --no-macos --no-windows --no-fuchsia

echo "==> Resolving app dependencies"
(cd app && flutter pub get)

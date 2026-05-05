#!/usr/bin/env bash
# Builds the Flutter web bundle for Vercel.
#   --release           production tree-shaken build
#   --wasm              enable skwasm renderer alongside CanvasKit (best fidelity)
#   --base-href /       site is served from the domain root
#
# Output lands in app/build/web (matched by `outputDirectory` in vercel.json).

set -euo pipefail

export PATH="$HOME/flutter/bin:$PATH"

cd app

echo "==> Building Flutter web (release, wasm)"
flutter build web --release --wasm --base-href /

echo "==> Build artefacts:"
ls -lah build/web | head -n 30

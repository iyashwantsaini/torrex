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

# NOTE: --wasm is intentionally OFF.
# `flutter_secure_storage_web` 1.2.1 still imports `dart:html`, which the
# dart2wasm compiler doesn't support. The standard CanvasKit/JS build is
# fully featured and visually identical for our use case. Revisit once
# flutter_secure_storage_web is upgraded to its `package:web` based 2.x.
echo "==> Building Flutter web (release, CanvasKit)"
flutter build web --release --base-href /

echo "==> Build artefacts:"
ls -lah build/web | head -n 30

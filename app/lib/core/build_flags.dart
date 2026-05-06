import 'package:flutter/foundation.dart';

/// Compile-time switches.
///
/// `kAllowDemo` controls whether the offline preview backend (baseUrl
/// `demo`) is exposed to the user. We want this in development and in
/// CI screenshot runs, but **not** in the production Vercel build —
/// random users landing on torrex.vercel.app shouldn't be greeted by
/// canned fake torrents that look real.
///
/// Resolution order:
///   1. `--dart-define=ALLOW_DEMO=true|false` if explicitly set.
///   2. Otherwise defaults to `kDebugMode` (true in debug, false in
///      release / profile builds).
///
/// The Vercel build script (`scripts/vercel-build.sh`) does not pass
/// the flag, so production stays off. To re-enable for a one-off
/// preview deploy, prepend `--dart-define=ALLOW_DEMO=true` to the
/// `flutter build web` invocation.
const bool kAllowDemo = bool.fromEnvironment(
  'ALLOW_DEMO',
  defaultValue: kDebugMode,
);

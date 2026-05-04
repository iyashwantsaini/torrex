import 'package:flutter/material.dart';

import 'app.dart';
import 'core/backend_warmer.dart';
import 'core/demo_results.dart';
import 'core/settings_store.dart';
import 'features/detail/detail_page.dart';
import 'features/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsStore();
  await settings.load();
  await _maybeApplyUrlOverrides(settings);
  final warmer = BackendWarmer();
  // `?warmupDelay=<ms>` (web only) artificially keeps the banner visible
  // for N ms so we can preview the "Waking backend…" UI even when the
  // Space is already awake. Capped at 60s to avoid foot-guns.
  final delayParam = Uri.base.queryParameters['warmupDelay'];
  final delayMs = int.tryParse(delayParam ?? '');
  final artificialDelay = (delayMs != null && delayMs > 0)
      ? Duration(milliseconds: delayMs.clamp(0, 60000))
      : null;
  // Fire-and-forget — the UI shows a banner while this is in flight.
  // Hugging Face Spaces sleep after ~48h; this hides the cold start
  // behind whatever the user is doing on the home screen.
  // ignore: discarded_futures
  warmer.warm(settings, artificialDelay: artificialDelay);
  // Re-warm whenever the user saves a new backend URL in Settings.
  String lastBase = settings.baseUrl;
  settings.addListener(() {
    if (settings.baseUrl != lastBase) {
      lastBase = settings.baseUrl;
      // ignore: discarded_futures
      warmer.warm(settings, artificialDelay: artificialDelay);
    }
  });
  runApp(TorrexApp(
    settings: settings,
    warmer: warmer,
    initialRoute: _routeFromUrl(),
  ));
}

/// On web, allow `?demo=1` and `?page=...` URL parameters to drive the app
/// into a specific state. Used by the screenshot tooling and as a friendly
/// "preview" entry point — has no effect when the params are absent.
Future<void> _maybeApplyUrlOverrides(SettingsStore settings) async {
  final uri = Uri.base;
  if (uri.queryParameters['demo'] == '1') {
    await settings.update(baseUrl: 'demo', apiKey: 'demo', indexer: 'all');
  }
  final theme = uri.queryParameters['theme'];
  switch (theme) {
    case 'light':
      await settings.update(themeMode: ThemeMode.light);
    case 'dark':
      await settings.update(themeMode: ThemeMode.dark);
  }
}

InitialRoute _routeFromUrl() {
  final p = Uri.base.queryParameters['page'];
  return switch (p) {
    'settings' => InitialRoute.settings,
    'detail' => InitialRoute.detail,
    _ => InitialRoute.search,
  };
}

enum InitialRoute { search, settings, detail }

class InitialRouteApplier extends StatefulWidget {
  const InitialRouteApplier({
    super.key,
    required this.route,
    required this.settings,
    required this.warmer,
  });

  final InitialRoute route;
  final SettingsStore settings;
  final BackendWarmer warmer;

  @override
  State<InitialRouteApplier> createState() => _InitialRouteApplierState();
}

class _InitialRouteApplierState extends State<InitialRouteApplier> {
  @override
  void initState() {
    super.initState();
    if (widget.route == InitialRoute.detail) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                DetailPage(result: DemoResults.forQuery('').first),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => AppShell(
        settings: widget.settings,
        warmer: widget.warmer,
        initialIndex: widget.route == InitialRoute.settings ? 1 : 0,
      );
}

import 'package:flutter/material.dart';
import 'package:wolwoloom/wolwoloom.dart';

import 'core/backend_warmer.dart';
import 'core/settings_store.dart';
import 'main.dart' show InitialRoute, InitialRouteApplier;

class TorrexApp extends StatelessWidget {
  const TorrexApp({
    super.key,
    required this.settings,
    required this.warmer,
    this.initialRoute = InitialRoute.search,
  });

  final SettingsStore settings;
  final BackendWarmer warmer;
  final InitialRoute initialRoute;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Torrex',
          debugShowCheckedModeBanner: false,
          theme: WlmTheme.light(),
          darkTheme: WlmTheme.dark(),
          themeMode: settings.themeMode,
          home: InitialRouteApplier(
            route: initialRoute,
            settings: settings,
            warmer: warmer,
          ),
        );
      },
    );
  }
}

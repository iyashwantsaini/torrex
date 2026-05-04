import 'package:flutter/material.dart';
import 'package:wolwoloom/wolwoloom.dart';

import 'core/settings_store.dart';
import 'features/shell/app_shell.dart';

class TorrexApp extends StatelessWidget {
  const TorrexApp({super.key, required this.settings});

  final SettingsStore settings;

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
          home: AppShell(settings: settings),
        );
      },
    );
  }
}

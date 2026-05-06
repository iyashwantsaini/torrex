import 'package:flutter/material.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../core/settings_store.dart';

/// Top-right theme cycle button. Rendered identically on every screen
/// (`AppShell`, `OnboardingPage`, `DetailPage`) so the user always has a
/// single, predictable place to flip themes. Cycles
/// `system → light → dark → system`.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key, required this.settings});

  final SettingsStore settings;

  IconData _icon() {
    switch (settings.themeMode) {
      case ThemeMode.light:
        return Icons.wb_sunny_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
    }
  }

  String _tooltip() {
    switch (settings.themeMode) {
      case ThemeMode.light:
        return 'Theme: light \u00b7 tap for dark';
      case ThemeMode.dark:
        return 'Theme: dark \u00b7 tap for system';
      case ThemeMode.system:
        return 'Theme: system \u00b7 tap for light';
    }
  }

  void _cycle() {
    final next = switch (settings.themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    settings.update(themeMode: next);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever the user flips the theme so the icon swaps in place.
    return AnimatedBuilder(
      animation: settings,
      builder: (_, _) => WlmHeaderIconButton(
        icon: _icon(),
        tooltip: _tooltip(),
        onPressed: _cycle,
      ),
    );
  }
}

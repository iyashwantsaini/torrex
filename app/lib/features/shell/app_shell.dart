import 'package:flutter/material.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/settings_store.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.settings, this.initialIndex = 0});

  final SettingsStore settings;
  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialIndex;

  static const _titles = ['Torrex', 'Settings'];

  IconData _themeIcon() {
    switch (widget.settings.themeMode) {
      case ThemeMode.light:
        return Icons.wb_sunny_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
    }
  }

  String _themeTooltip() {
    switch (widget.settings.themeMode) {
      case ThemeMode.light:
        return 'Theme: light \u00b7 tap for dark';
      case ThemeMode.dark:
        return 'Theme: dark \u00b7 tap for system';
      case ThemeMode.system:
        return 'Theme: system \u00b7 tap for light';
    }
  }

  void _cycleTheme() {
    final next = switch (widget.settings.themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    widget.settings.update(themeMode: next);
  }

  @override
  Widget build(BuildContext context) {
    return WlmAppScaffold(
      appBar: WlmAppBar(
        title: _titles[_index],
        actions: [
          WlmHeaderIconButton(
            icon: _themeIcon(),
            tooltip: _themeTooltip(),
            onPressed: _cycleTheme,
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          SearchPage(settings: widget.settings),
          SettingsPage(settings: widget.settings),
        ],
      ),
      bottomNav: const [
        WlmNavItem(icon: Icons.search_outlined, label: 'Search'),
        WlmNavItem(icon: Icons.tune_outlined, label: 'Settings'),
      ],
      bottomNavIndex: _index,
      onBottomNavTap: (i) => setState(() => _index = i),
    );
  }
}

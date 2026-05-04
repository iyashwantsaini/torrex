import 'package:flutter/material.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/backend_warmer.dart';
import '../../core/settings_store.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.settings,
    required this.warmer,
    this.initialIndex = 0,
  });

  final SettingsStore settings;
  final BackendWarmer warmer;
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
      body: Column(
        children: [
          AnimatedBuilder(
            animation: widget.warmer,
            builder: (_, _) => _WarmupBanner(state: widget.warmer.state),
          ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                SearchPage(settings: widget.settings),
                SettingsPage(settings: widget.settings),
              ],
            ),
          ),
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

/// Thin status banner shown above the body while the on-launch backend
/// warm-up ping is in flight. Hidden once the Space responds (or fails —
/// a real search will surface the actual error).
class _WarmupBanner extends StatelessWidget {
  const _WarmupBanner({required this.state});

  final WarmupState state;

  @override
  Widget build(BuildContext context) {
    final visible = state == WarmupState.waking;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: !visible
          ? const SizedBox.shrink()
          : const WlmBanner(
              tone: WlmCalloutTone.info,
              title: 'Waking backend\u2026',
              message:
                  'Hugging Face Spaces sleep when idle. This usually takes '
                  '20\u201330 seconds on first launch.',
            ),
    );
  }
}

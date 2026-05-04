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

  @override
  Widget build(BuildContext context) {
    return WlmAppScaffold(
      appBar: WlmAppBar(title: _titles[_index]),
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

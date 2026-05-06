import 'package:flutter/material.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/backend_warmer.dart';
import '../../core/settings_store.dart';
import '../../models/torrent_result.dart';
import '../../widgets/theme_toggle_button.dart';
import '../detail/detail_page.dart';
import '../discover/discover_page.dart';
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

  /// Currently-selected result on wide screens. Null means "show empty
  /// placeholder in the right pane". On narrow screens we ignore this and
  /// push DetailPage as a route instead.
  TorrentResult? _selectedResult;

  /// Lets us reach into the SearchPage to pre-fill a query when the user
  /// taps "Find torrents" inside the Discover tab.
  final _searchKey = GlobalKey<SearchPageState>();

  static const _titles = ['Torrex', 'Movies & TV', 'Settings'];
  static const _wideBreakpoint = 900.0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= _wideBreakpoint;
    final scheme = Theme.of(context).colorScheme;

    // On wide screens, tapping a result updates the inline detail pane
    // instead of pushing a new route.
    final searchPage = SearchPage(
      key: _searchKey,
      settings: widget.settings,
      onSelect: isWide
          ? (r) => setState(() => _selectedResult = r)
          : null,
    );

    final searchPane = isWide && _index == 0
        ? Row(
            children: [
              Expanded(flex: 5, child: searchPage),
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              Expanded(
                flex: 6,
                child: _selectedResult == null
                    ? _DetailPlaceholder(scheme: scheme)
                    : DetailPage(
                        key: ValueKey(_selectedResult!.bestUri),
                        result: _selectedResult!,
                        settings: widget.settings,
                        embedded: true,
                      ),
              ),
            ],
          )
        : searchPage;

    return WlmAppScaffold(
      appBar: WlmAppBar(
        title: _titles[_index],
        actions: [
          ThemeToggleButton(settings: widget.settings),
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
                searchPane,
                DiscoverPage(
                  settings: widget.settings,
                  onOpenSettings: () => setState(() => _index = 2),
                  onFindTorrents: _findTorrents,
                ),
                SettingsPage(settings: widget.settings),
              ],
            ),
          ),
        ],
      ),
      bottomNav: const [
        WlmNavItem(icon: Icons.search_outlined, label: 'Search'),
        WlmNavItem(icon: Icons.movie_outlined, label: 'Movies & TV'),
        WlmNavItem(icon: Icons.tune_outlined, label: 'Settings'),
      ],
      bottomNavIndex: _index,
      onBottomNavTap: (i) => setState(() => _index = i),
    );
  }

  /// Bridge from the Discover tab back to the Search tab. Switches index
  /// then nudges the SearchPage state to run the query.
  void _findTorrents(String query) {
    setState(() => _index = 0);
    // Wait for IndexedStack to surface the search pane so its state is
    // attached before we poke it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchKey.currentState?.runQuery(query);
    });
  }
}

/// Inline status card shown above the body while the on-launch backend
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
          : const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: WlmCallout(
                tone: WlmCalloutTone.info,
                title: 'Waking backend\u2026',
                body:
                    'Hugging Face Spaces sleep when idle. This usually takes '
                    '20\u201330 seconds on first launch.',
              ),
            ),
    );
  }
}

/// Empty-state shown in the right pane on wide screens before the user has
/// picked a result. Kept intentionally bare — a single hint, no chrome.
class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined,
                size: 36, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              'Pick a result to see its details here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

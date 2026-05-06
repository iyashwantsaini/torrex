import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/build_flags.dart';
import '../../core/settings_store.dart';
import '../../core/torznab_client.dart';

/// Settings screen.
///
/// In addition to the basic backend / theme inputs, this screen now talks to
/// Jackett's `/api/v2.0/indexers` endpoint when both the base URL and API key
/// are non-empty, so the user can pick an indexer from a dropdown instead of
/// memorizing slugs. The list refreshes lazily and falls back to a free-text
/// field if Jackett is unreachable.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _indexerText;
  late final TextEditingController _tmdbKey;

  final _client = TorznabClient();

  /// Cached list from Jackett. `null` while loading, `[]` after a failed
  /// fetch (we then fall back to the free-text field).
  List<JackettIndexer>? _indexers;
  bool _loadingIndexers = false;

  static const _kRepoUrl = 'https://github.com/iyashwantsaini/torrex';

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: widget.settings.baseUrl);
    _apiKey = TextEditingController(text: widget.settings.apiKey);
    _indexerText = TextEditingController(
      text: widget.settings.indexer.isEmpty ? 'all' : widget.settings.indexer,
    );
    _tmdbKey = TextEditingController(text: widget.settings.tmdbKey);
    // Try fetching the indexer list with whatever creds are saved.
    _refreshIndexers();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _indexerText.dispose();
    _tmdbKey.dispose();
    super.dispose();
  }

  Future<void> _refreshIndexers() async {
    final base = _baseUrl.text.trim();
    final key = _apiKey.text.trim();
    // Demo backend: synthesize a believable indexer list so the dropdown
    // is exercised in screenshots / demos. Only honoured when the demo
    // gate is open (debug builds, or release builds with
    // --dart-define=ALLOW_DEMO=true).
    if (base == 'demo' && kAllowDemo) {
      setState(() => _indexers = const [
            JackettIndexer(id: 'thepiratebay', name: 'The Pirate Bay'),
            JackettIndexer(id: '1337x', name: '1337x'),
            JackettIndexer(id: 'rarbg', name: 'RARBG'),
            JackettIndexer(id: 'nyaasi', name: 'Nyaa.si'),
            JackettIndexer(id: 'limetorrents', name: 'LimeTorrents'),
            JackettIndexer(id: 'yts', name: 'YTS'),
          ]);
      return;
    }
    if (base.isEmpty || key.isEmpty) {
      setState(() => _indexers = const []);
      return;
    }
    setState(() => _loadingIndexers = true);
    final list = await _client.listIndexers(baseUrl: base, apiKey: key);
    if (!mounted) return;
    setState(() {
      _indexers = list;
      _loadingIndexers = false;
    });
  }

  Future<void> _save() async {
    await widget.settings.update(
      baseUrl: _baseUrl.text.trim(),
      apiKey: _apiKey.text.trim(),
      indexer: _indexerText.text.trim().isEmpty
          ? 'all'
          : _indexerText.text.trim(),
      tmdbKey: _tmdbKey.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved.')));
    await _refreshIndexers();
  }

  Future<void> _openRepo() async {
    await launchUrl(
      Uri.parse(_kRepoUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  /// Switch to / from the offline preview backend. Demo mode pre-fills
  /// `baseUrl='demo'` and a placeholder API key so the user can browse
  /// the canned [DemoResults]; "Exit demo" wipes both back to empty so
  /// the next save targets a real Jackett instance.
  Future<void> _enterDemo() async {
    _baseUrl.text = 'demo';
    _apiKey.text = 'demo';
    _indexerText.text = 'all';
    await widget.settings.update(
      baseUrl: 'demo',
      apiKey: 'demo',
      indexer: 'all',
    );
    if (!mounted) return;
    setState(() {});
    await _refreshIndexers();
  }

  Future<void> _exitDemo() async {
    _baseUrl.clear();
    _apiKey.clear();
    _indexerText.text = 'all';
    await widget.settings.update(
      baseUrl: '',
      apiKey: '',
      indexer: 'all',
    );
    if (!mounted) return;
    setState(() => _indexers = const []);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final indexers = _indexers;
    final isDemo = widget.settings.baseUrl == 'demo';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (isDemo) ...[
          WlmCallout(
            tone: WlmCalloutTone.info,
            title: 'Demo mode',
            body:
                'Showing canned results. Tap below to switch to a real '
                'Jackett backend.',
            action: WlmGhostButton(
              label: 'Exit demo',
              icon: Icons.logout_rounded,
              onPressed: _exitDemo,
            ),
          ),
          const SizedBox(height: 16),
        ] else if (kAllowDemo && widget.settings.baseUrl.isEmpty) ...[
          // First-time / cleared: offer the one-tap demo path.
          // Hidden in production builds (kAllowDemo=false) so public web
          // visitors don't see fake torrents.
          Align(
            alignment: Alignment.centerRight,
            child: WlmGhostButton(
              label: 'Try demo backend',
              icon: Icons.science_outlined,
              onPressed: _enterDemo,
            ),
          ),
          const SizedBox(height: 8),
        ],
        const WlmSectionLabel('Backend',
            padding: EdgeInsets.only(bottom: 8)),
        const SizedBox(height: 12),
        WlmTextField(
          controller: _baseUrl,
          label: 'Base URL',
          hintText: 'https://your-space.hf.space',
          keyboardType: TextInputType.url,
          prefixIcon: Icons.link_rounded,
          clearable: true,
        ),
        const SizedBox(height: 12),
        WlmTextField(
          controller: _apiKey,
          label: 'API key',
          hintText: 'jackett api key',
          obscureText: true,
          prefixIcon: Icons.key_rounded,
          clearable: true,
        ),
        const SizedBox(height: 16),
        _buildIndexerPicker(context, indexers),
        const SizedBox(height: 24),
        const WlmSectionLabel('TMDB (optional)',
            padding: EdgeInsets.only(bottom: 8)),
        const SizedBox(height: 12),
        WlmTextField(
          controller: _tmdbKey,
          label: 'TMDB API key (v3 auth)',
          hintText: 'paste your TMDB API key',
          obscureText: true,
          prefixIcon: Icons.movie_filter_outlined,
          clearable: true,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: WlmGhostButton(
            label: 'How to get a key',
            icon: Icons.open_in_new,
            onPressed: () => launchUrl(
              Uri.parse('https://www.themoviedb.org/settings/api'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const WlmSectionLabel('Result card',
            padding: EdgeInsets.only(bottom: 8)),
        const SizedBox(height: 12),
        _ChipPicker(
          selected: widget.settings.cardChips,
          onChanged: (next) {
            widget.settings.update(cardChips: next);
            setState(() {});
          },
        ),
        const SizedBox(height: 24),
        const WlmSectionLabel('Appearance',
            padding: EdgeInsets.only(bottom: 8)),
        const SizedBox(height: 12),
        WlmSegmentedControl<ThemeMode>(
          value: widget.settings.themeMode,
          onChanged: (m) => widget.settings.update(themeMode: m),
          segments: const [
            WlmSegment(value: ThemeMode.system, label: 'System'),
            WlmSegment(value: ThemeMode.light, label: 'Light'),
            WlmSegment(value: ThemeMode.dark, label: 'Dark'),
          ],
        ),
        const SizedBox(height: 24),
        WlmPrimaryButton(label: 'Save', expand: true, onPressed: _save),
        const SizedBox(height: 24),
        const WlmDivider(),
        const SizedBox(height: 16),
        // Single, low-noise pointer to the repo. The repo README (and the
        // backend/ folder inside it) holds the long-form setup docs, so we
        // don't duplicate them in the app UI.
        Semantics(
          button: true,
          label: 'Open the Torrex GitHub repository',
          child: WlmGhostButton(
            label: 'Setup help & source on GitHub',
            icon: Icons.code_rounded,
            expand: true,
            onPressed: _openRepo,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _kRepoUrl,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.outline),
        ),
      ],
    );
  }

  Widget _buildIndexerPicker(
    BuildContext context,
    List<JackettIndexer>? indexers,
  ) {
    if (_loadingIndexers && indexers == null) {
      return const WlmSkeleton(height: 56);
    }

    // Couldn't reach Jackett (or creds blank) → free-text fallback so the
    // user can still type a slug like `thepiratebay`.
    if (indexers == null || indexers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WlmTextField(
            controller: _indexerText,
            label: 'Indexer',
            hintText: 'all',
            prefixIcon: Icons.dns_outlined,
            helperText:
                'Use "all" to query every configured indexer. Save creds and '
                'tap refresh to pick from a list.',
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: WlmGhostButton(
              label: 'Refresh list',
              icon: Icons.refresh_rounded,
              onPressed: _refreshIndexers,
            ),
          ),
        ],
      );
    }

    // Happy path: dropdown with a leading "All indexers" entry.
    final items = <WlmDropdownItem<String>>[
      const WlmDropdownItem(value: 'all', label: 'All indexers'),
      for (final i in indexers)
        WlmDropdownItem(
          value: i.id,
          label: i.name.isEmpty ? i.id : i.name,
        ),
    ];
    final current = widget.settings.indexer.isEmpty
        ? 'all'
        : widget.settings.indexer;
    // If the saved value isn't in the live list (e.g. indexer was removed),
    // gracefully reset to 'all' to avoid a Dropdown assertion.
    final value = items.any((it) => it.value == current) ? current : 'all';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WlmDropdown<String>(
          label: 'Indexer',
          expand: true,
          value: value,
          items: items,
          onChanged: (v) {
            if (v == null) return;
            widget.settings.update(indexer: v);
            _indexerText.text = v;
            setState(() {});
          },
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: WlmGhostButton(
            label: 'Refresh list',
            icon: Icons.refresh_rounded,
            onPressed: _refreshIndexers,
          ),
        ),
      ],
    );
  }
}

/// Multi-select chip toggle row for picking which fields appear on each
/// search-result card. Order matches the canonical `defaultCardChips`
/// list so the picker reads top-to-bottom in the same order users see.
class _ChipPicker extends StatelessWidget {
  const _ChipPicker({required this.selected, required this.onChanged});

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  // Display labels for each known chip id. Keep in sync with
  // SettingsStore._allKnownChips and _ResultCard._chipFor in search_page.
  static const _allChips = <(String, String)>[
    ('seeders', 'Seeders'),
    ('leechers', 'Leechers'),
    ('size', 'Size'),
    ('age', 'Age'),
    ('indexer', 'Indexer'),
    ('category', 'Category'),
    ('magnet', 'Magnet'),
  ];

  void _toggle(String id) {
    final next = [...selected];
    if (next.contains(id)) {
      next.remove(id);
    } else {
      // Re-insert in canonical order so the chip row stays predictable.
      next.add(id);
      next.sort((a, b) {
        final ia = _allChips.indexWhere((p) => p.$1 == a);
        final ib = _allChips.indexWhere((p) => p.$1 == b);
        return ia.compareTo(ib);
      });
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (id, label) in _allChips)
          WlmChip(
            label: label,
            selected: selected.contains(id),
            onTap: () => _toggle(id),
          ),
      ],
    );
  }
}

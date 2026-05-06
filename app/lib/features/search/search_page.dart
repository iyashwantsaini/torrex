import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/build_flags.dart';
import '../../core/formatters.dart';
import '../../core/settings_store.dart';
import '../../core/torznab_client.dart';
import '../../models/torrent_result.dart';
import '../detail/detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.settings, this.onSelect});

  final SettingsStore settings;

  /// When non-null, tapping a result calls this instead of pushing a new
  /// route. Used by the wide-screen two-pane shell so the detail view stays
  /// inline.
  final ValueChanged<TorrentResult>? onSelect;

  @override
  State<SearchPage> createState() => SearchPageState();
}

enum _SortBy { seeders, size, date }

const int _pageSize = 10;

class SearchPageState extends State<SearchPage> {
  final _client = TorznabClient();
  final _controller = TextEditingController();

  bool _loading = false;
  String? _error;
  List<TorrentResult> _all = const [];
  _SortBy _sort = _SortBy.seeders;
  bool _onlyMagnet = false;
  int _page = 1;
  String _lastBaseUrl = '';

  @override
  void initState() {
    super.initState();
    _lastBaseUrl = widget.settings.baseUrl;
    widget.settings.addListener(_onSettingsChanged);
    if (widget.settings.baseUrl == 'demo') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch());
    }
  }

  /// Drop stale results when the user switches backends from Settings
  /// (e.g. exits demo). Otherwise the old demo cards linger in the
  /// list, which looks like a bug.
  void _onSettingsChanged() {
    final base = widget.settings.baseUrl;
    if (base == _lastBaseUrl) return;
    _lastBaseUrl = base;
    if (!mounted) return;
    setState(() {
      _all = const [];
      _error = null;
      _page = 1;
      _controller.clear();
    });
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Public hook used by AppShell when the user taps "Find torrents" on
  /// a TMDB media page. Sets the input field and immediately runs the
  /// search so the user lands on a populated results list.
  void runQuery(String query) {
    _controller.text = query;
    _runSearch();
  }

  Future<void> _runSearch() async {
    final query = _controller.text.trim();
    final isDemo = widget.settings.baseUrl == 'demo';
    if (query.isEmpty && !isDemo) return;

    if (!widget.settings.isConfigured) {
      setState(() {
        _error = 'Backend not configured. Open Settings to add your URL + key.';
        _all = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });

    try {
      final r = await _client.search(
        baseUrl: widget.settings.baseUrl,
        apiKey: widget.settings.apiKey,
        indexer: widget.settings.indexer,
        query: query,
        // Pull files / trackers / coverurl in the same round-trip so the
        // detail page can render them without a second backend call.
        extended: true,
      );
      setState(() {
        _all = r;
        _loading = false;
      });
    } on TorznabException catch (e) {
      setState(() {
        _error = e.message;
        _all = const [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Unexpected error: $e';
        _all = const [];
        _loading = false;
      });
    }
  }

  List<TorrentResult> get _filtered {
    final list = _onlyMagnet
        ? _all.where((r) => r.hasMagnet).toList()
        : [..._all];
    switch (_sort) {
      case _SortBy.seeders:
        list.sort((a, b) => b.seeders.compareTo(a.seeders));
      case _SortBy.size:
        list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      case _SortBy.date:
        final epoch = DateTime.fromMillisecondsSinceEpoch(0);
        list.sort(
          (a, b) => (b.publishDate ?? epoch).compareTo(a.publishDate ?? epoch),
        );
    }
    return list;
  }

  int get _pageCount {
    final n = _filtered.length;
    if (n == 0) return 1;
    return ((n - 1) ~/ _pageSize) + 1;
  }

  List<TorrentResult> get _pageSlice {
    final f = _filtered;
    final start = (_page - 1) * _pageSize;
    final end = (start + _pageSize).clamp(0, f.length);
    return f.sublist(start.clamp(0, f.length), end);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: WlmSearchField(
            controller: _controller,
            hintText: 'Search torrents\u2026',
            onSubmitted: (_) => _runSearch(),
          ),
        ),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, _) => const WlmSkeleton(height: 88),
      );
    }
    if (_error != null) {
      return WlmErrorState(
        title: 'Search failed',
        body: _error,
        onRetry: _runSearch,
      );
    }
    if (_all.isEmpty) {
      if (!widget.settings.isConfigured) {
        return WlmEmptyState(
          eyebrow: 'SETUP',
          icon: Icons.settings_outlined,
          title: 'Connect a backend',
          body: kAllowDemo
              ? 'Add your Jackett or Prowlarr URL and API key in Settings to '
                  'start searching. Or set Base URL to \u201cdemo\u201d to '
                  'preview the app.'
              : 'Add your Jackett or Prowlarr URL and API key in Settings to '
                  'start searching.',
        );
      }
      return const WlmEmptyState(
        eyebrow: 'SEARCH',
        icon: Icons.search_outlined,
        title: 'Search the swarm',
        body: 'Type a query above to search across all your indexers.',
      );
    }

    final filtered = _filtered;
    final slice = _pageSlice;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        _ResultsHeader(
          totalCount: _all.length,
          filteredCount: filtered.length,
          sort: _sort,
          onlyMagnet: _onlyMagnet,
          onSort: (v) => setState(() {
            _sort = v;
            _page = 1;
          }),
          onToggleMagnet: () => setState(() {
            _onlyMagnet = !_onlyMagnet;
            _page = 1;
          }),
        ),
        const SizedBox(height: 12),
        for (final r in slice) ...[
          _ResultCard(
            result: r,
            chipIds: widget.settings.cardChips,
            onTap: _openDetail,
            onOpen: _openMagnet,
            onCopy: _copy,
          ),
          const SizedBox(height: 8),
        ],
        if (filtered.isEmpty) ...[
          const SizedBox(height: 24),
          const WlmEmptyState(
            eyebrow: 'FILTER',
            icon: Icons.filter_alt_off_outlined,
            title: 'No results match',
            body: 'Try clearing the filter to see every result again.',
          ),
        ],
        if (_pageCount > 1) ...[
          const SizedBox(height: 16),
          WlmPagination(
            page: _page,
            pageCount: _pageCount,
            onPageChanged: (p) => setState(() => _page = p),
          ),
        ],
      ],
    );
  }

  void _openDetail(TorrentResult r) {
    final inline = widget.onSelect;
    if (inline != null) {
      inline(r);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailPage(result: r, settings: widget.settings),
      ),
    );
  }

  Future<void> _openMagnet(TorrentResult r) async {
    final uri = r.bestUri;
    if (uri.isEmpty) {
      _snack('No magnet or download link in this result.');
      return;
    }
    final ok = await launchUrl(
      Uri.parse(uri),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) _snack('No app installed to handle this link.');
  }

  Future<void> _copy(TorrentResult r) async {
    final uri = r.bestUri;
    if (uri.isEmpty) {
      _snack('No link to copy.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: uri));
    _snack('Link copied.');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.totalCount,
    required this.filteredCount,
    required this.sort,
    required this.onlyMagnet,
    required this.onSort,
    required this.onToggleMagnet,
  });

  final int totalCount;
  final int filteredCount;
  final _SortBy sort;
  final bool onlyMagnet;
  final ValueChanged<_SortBy> onSort;
  final VoidCallback onToggleMagnet;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = onlyMagnet
        ? '$filteredCount / $totalCount'
        : '$totalCount results';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Row(
            children: [
              Text(
                label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.4,
                      color: scheme.outline,
                    ),
              ),
              const Spacer(),
              WlmChip(
                label: 'magnet only',
                selected: onlyMagnet,
                onTap: onToggleMagnet,
              ),
            ],
          ),
        ),
        WlmSegmentedControl<_SortBy>(
          value: sort,
          onChanged: onSort,
          segments: const [
            WlmSegment(value: _SortBy.seeders, label: 'Seeders'),
            WlmSegment(value: _SortBy.size, label: 'Size'),
            WlmSegment(value: _SortBy.date, label: 'Date'),
          ],
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.chipIds,
    required this.onTap,
    required this.onOpen,
    required this.onCopy,
  });

  final TorrentResult result;
  final List<String> chipIds;
  final ValueChanged<TorrentResult> onTap;
  final ValueChanged<TorrentResult> onOpen;
  final ValueChanged<TorrentResult> onCopy;

  /// Build the chip for a given preference id, or `null` to hide it
  /// (e.g. magnet chip on a torrent without a magnet link).
  Widget? _chipFor(String id) {
    switch (id) {
      case 'seeders':
        return WlmChip(label: '\u2191 ${result.seeders}');
      case 'leechers':
        return WlmChip(label: '\u2193 ${result.leechers}');
      case 'size':
        return WlmChip(label: formatBytes(result.sizeBytes));
      case 'age':
        return WlmChip(label: formatRelative(result.publishDate));
      case 'indexer':
        if (result.indexer.isEmpty) return null;
        return WlmChip(label: result.indexer);
      case 'category':
        if (result.category.isEmpty) return null;
        return WlmChip(label: result.category);
      case 'magnet':
        if (!result.hasMagnet) return null;
        return const WlmChip(label: 'magnet');
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <Widget>[
      for (final id in chipIds) ?_chipFor(id),
    ];
    return WlmCard(
      onTap: () => onTap(result),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.title,
            style: theme.textTheme.titleSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              WlmGhostButton(
                label: 'Copy',
                icon: Icons.copy_outlined,
                onPressed: () => onCopy(result),
              ),
              const SizedBox(width: 8),
              WlmPrimaryButton(
                label: 'Open',
                icon: Icons.open_in_new,
                onPressed: () => onOpen(result),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

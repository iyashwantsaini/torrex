import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/build_flags.dart';
import '../../core/search_filters.dart';
import '../../core/search_history.dart';
import '../../core/settings_store.dart';
import '../../core/torznab_client.dart';
import '../../models/torrent_result.dart';
import '../detail/detail_page.dart';
import 'filter_sheet.dart';
import 'result_card.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.settings,
    this.history,
    this.onSelect,
  });

  final SettingsStore settings;

  /// Recent-query store. Optional so tests and embedded uses can construct
  /// the page without wiring persistence.
  final SearchHistory? history;

  /// When non-null, tapping a result calls this instead of pushing a new
  /// route. Used by the wide-screen two-pane shell so the detail view stays
  /// inline.
  final ValueChanged<TorrentResult>? onSelect;

  @override
  State<SearchPage> createState() => SearchPageState();
}

class SearchPageState extends State<SearchPage> {
  final _client = TorznabClient();
  final _controller = TextEditingController();

  bool _loading = false;
  String? _error;

  /// Non-null while the client is retrying a cold / flaky backend, so the
  /// user sees *why* it's taking a while instead of assuming it hung.
  String? _retryNotice;

  /// Every result the backend returned for the current query, unfiltered.
  List<TorrentResult> _all = const [];

  /// True once a search has actually completed — lets us tell "you haven't
  /// searched yet" apart from "that search found nothing", which the old
  /// UI conflated and which made working searches look broken.
  bool _hasSearched = false;

  /// The query [_all] belongs to. Used for relevance sorting and for the
  /// "no results for X" copy.
  String _resultQuery = '';

  SearchFilters _filters = const SearchFilters();
  int _page = 1;
  int _pageSize = 25;
  String _lastBaseUrl = '';

  /// Monotonic id for the in-flight search. A response whose id is stale is
  /// discarded, so a slow first attempt can never overwrite the results of
  /// a newer query — the classic "I searched again and the old empty result
  /// came back" bug.
  int _searchSeq = 0;
  CancelToken? _inFlight;

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
  /// (e.g. exits demo). Otherwise the old demo cards linger in the list,
  /// which looks like a bug.
  void _onSettingsChanged() {
    final base = widget.settings.baseUrl;
    if (base == _lastBaseUrl) return;
    _lastBaseUrl = base;
    if (!mounted) return;
    _inFlight?.cancel('backend changed');
    _searchSeq++;
    setState(() {
      _all = const [];
      _error = null;
      _retryNotice = null;
      _hasSearched = false;
      _loading = false;
      _page = 1;
      _controller.clear();
    });
  }

  @override
  void dispose() {
    _inFlight?.cancel('page disposed');
    widget.settings.removeListener(_onSettingsChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Public hook used by AppShell when the user taps "Find torrents" on a
  /// TMDB media page. Sets the input field and immediately runs the search
  /// so the user lands on a populated results list.
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
        _hasSearched = false;
      });
      return;
    }

    // Supersede anything still on the wire. Without this two searches race
    // and whichever finishes last wins — which is exactly why the same
    // query sometimes only "worked" on the third attempt.
    _inFlight?.cancel('superseded');
    final token = CancelToken();
    _inFlight = token;
    final seq = ++_searchSeq;

    setState(() {
      _loading = true;
      _error = null;
      _retryNotice = null;
      _page = 1;
    });

    try {
      final r = await _client.search(
        baseUrl: widget.settings.baseUrl,
        apiKey: widget.settings.apiKey,
        indexer: widget.settings.indexer,
        query: query,
        limit: widget.settings.resultLimit,
        // Narrow server-side too when the user picked exactly one bucket —
        // fewer wasted indexer round-trips and a much higher hit rate
        // within the result limit.
        categories: _filters.categories.length == 1
            ? [_filters.categories.first.torznabId]
            : const [],
        // Pull files / trackers / coverurl in the same round-trip so the
        // detail page can render them without a second backend call.
        extended: true,
        cancelToken: token,
        onRetry: (attempt) {
          if (!mounted || seq != _searchSeq) return;
          setState(() {
            _retryNotice =
                'The backend was slow to answer — retrying ($attempt of 2)…';
          });
        },
      );
      if (!mounted || seq != _searchSeq) return;
      // Drop indexer selections that no longer exist in this result set,
      // otherwise the list silently renders empty after a new search.
      final live = {for (final x in r) x.indexer};
      setState(() {
        _all = r;
        _resultQuery = query;
        _hasSearched = true;
        _loading = false;
        _retryNotice = null;
        if (_filters.indexers.isNotEmpty) {
          _filters = _filters.copyWith(
            indexers: _filters.indexers.intersection(live),
          );
        }
      });
      if (r.isNotEmpty) await widget.history?.add(query);
    } on TorznabException catch (e) {
      if (!mounted || seq != _searchSeq) return;
      if (e.message == 'Search cancelled.') return;
      setState(() {
        _error = e.message;
        _all = const [];
        _hasSearched = true;
        _loading = false;
        _retryNotice = null;
      });
    } catch (e) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _error = 'Unexpected error: $e';
        _all = const [];
        _hasSearched = true;
        _loading = false;
        _retryNotice = null;
      });
    }
  }

  List<TorrentResult> get _filtered =>
      applyFilters(_all, _filters, query: _resultQuery);

  int _pageCount(int total) => total == 0 ? 1 : ((total - 1) ~/ _pageSize) + 1;

  List<TorrentResult> _pageSlice(List<TorrentResult> f) {
    final start = ((_page - 1) * _pageSize).clamp(0, f.length);
    final end = (start + _pageSize).clamp(0, f.length);
    return f.sublist(start, end);
  }

  void _setFilters(SearchFilters next) {
    setState(() {
      _filters = next;
      _page = 1;
    });
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
    if (_loading) return _buildLoading();
    if (_error != null) {
      return WlmErrorState(
        title: 'Search failed',
        body: _error,
        onRetry: _runSearch,
      );
    }
    if (_all.isEmpty) return _buildEmpty(context);

    final filtered = _filtered;
    final slice = _pageSlice(filtered);
    final pageCount = _pageCount(filtered.length);

    return RefreshIndicator(
      onRefresh: _runSearch,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _FacetBar(all: _all, filters: _filters, onChanged: _setFilters),
          const SizedBox(height: 8),
          _ResultsToolbar(
            totalCount: _all.length,
            filteredCount: filtered.length,
            filters: _filters,
            onChanged: _setFilters,
            onOpenFilters: _openFilterSheet,
          ),
          const SizedBox(height: 12),
          for (final r in slice) ...[
            ResultCard(
              key: ValueKey(r.id),
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
            WlmEmptyState(
              eyebrow: 'FILTER',
              icon: Icons.filter_alt_off_outlined,
              title: 'No results match your filters',
              body:
                  '${_all.length} results are hidden. Loosen or clear the '
                  'filters to see them again.',
              action: WlmSecondaryButton(
                label: 'Clear filters',
                icon: Icons.refresh_rounded,
                onPressed: () => _setFilters(_filters.cleared()),
              ),
            ),
          ],
          if (pageCount > 1) ...[
            const SizedBox(height: 16),
            WlmPagination(
              page: _page,
              pageCount: pageCount,
              onPageChanged: (p) => setState(() => _page = p),
            ),
            const SizedBox(height: 12),
            _PageSizePicker(
              value: _pageSize,
              onChanged: (v) => setState(() {
                _pageSize = v;
                _page = 1;
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoading() {
    final notice = _retryNotice;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (notice != null) ...[
          WlmCallout(
            tone: WlmCalloutTone.warning,
            title: 'Still searching',
            body: notice,
          ),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < 6; i++) ...[
          const WlmSkeleton(height: 112),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
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

    // Post-search empty state. Previously this fell through to the generic
    // "type a query above" copy, which read as "nothing happened" — the
    // main reason searches felt like they needed several attempts.
    if (_hasSearched) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          WlmEmptyState(
            eyebrow: 'NO RESULTS',
            icon: Icons.search_off_outlined,
            title: 'Nothing found for \u201c$_resultQuery\u201d',
            body:
                'Try fewer or more general words, check the spelling, or '
                'switch the indexer in Settings. Some indexers rate-limit '
                'and go quiet for a minute.',
            action: WlmSecondaryButton(
              label: 'Search again',
              icon: Icons.refresh_rounded,
              onPressed: _runSearch,
            ),
          ),
          const SizedBox(height: 24),
          _HistoryStrip(history: widget.history, onPick: runQuery),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const WlmEmptyState(
          eyebrow: 'SEARCH',
          icon: Icons.search_outlined,
          title: 'Search the swarm',
          body: 'Type a query above to search across all your indexers.',
        ),
        const SizedBox(height: 24),
        _HistoryStrip(history: widget.history, onPick: runQuery),
      ],
    );
  }

  Future<void> _openFilterSheet() async {
    final languages = <String>{};
    for (final r in _all) {
      languages.addAll(r.release.languages);
    }
    final next = await showFilterSheet(
      context: context,
      current: _filters,
      availableIndexers: [for (final f in indexerFacets(_all)) f.indexer],
      availableLanguages: languages.toList()..sort(),
    );
    if (next != null) _setFilters(next);
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
    // launchUrl throws (rather than returning false) for unhandled schemes
    // on web and on some Android OEM builds — `magnet:` with no torrent
    // client installed is the common case, and it used to crash the tap.
    try {
      final ok = await launchUrl(
        Uri.parse(uri),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) _snack('No app installed to handle this link.');
    } catch (_) {
      _snack('No app installed to handle this link. Copy it instead.');
    }
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

/// Horizontally scrolling indexer + category facet chips pinned above the
/// results — the "filter by source" affordance aggregator sites lead with.
class _FacetBar extends StatelessWidget {
  const _FacetBar({
    required this.all,
    required this.filters,
    required this.onChanged,
  });

  final List<TorrentResult> all;
  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final indexers = indexerFacets(all);
    final categories = categoryFacets(all);
    // A single indexer is not a filter, it's a fact — don't waste a row.
    final showIndexers = indexers.length > 1;
    final showCategories = categories.length > 1;
    if (!showIndexers && !showCategories) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showIndexers)
          _FacetRow(
            label: 'Indexers',
            children: [
              WlmChip(
                label: 'All (${all.length})',
                selected: filters.indexers.isEmpty,
                onTap: () => onChanged(filters.copyWith(indexers: const {})),
              ),
              for (final f in indexers)
                WlmChip(
                  label: '${f.indexer} (${f.count})',
                  selected: filters.indexers.contains(f.indexer),
                  onTap: () {
                    final next = {...filters.indexers};
                    if (!next.remove(f.indexer)) next.add(f.indexer);
                    onChanged(filters.copyWith(indexers: next));
                  },
                ),
            ],
          ),
        if (showIndexers && showCategories) const SizedBox(height: 6),
        if (showCategories)
          _FacetRow(
            label: 'Categories',
            children: [
              WlmChip(
                label: 'All',
                selected: filters.categories.isEmpty,
                onTap: () => onChanged(filters.copyWith(categories: const {})),
              ),
              for (final f in categories)
                WlmChip(
                  label: '${f.category.label} (${f.count})',
                  selected: filters.categories.contains(f.category),
                  onTap: () {
                    final next = {...filters.categories};
                    if (!next.remove(f.category)) next.add(f.category);
                    onChanged(filters.copyWith(categories: next));
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _FacetRow extends StatelessWidget {
  const _FacetRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.4,
              color: scheme.outline,
            ),
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) => Align(child: children[i]),
          ),
        ),
      ],
    );
  }
}

/// Result count + sort control + filter entry point.
class _ResultsToolbar extends StatelessWidget {
  const _ResultsToolbar({
    required this.totalCount,
    required this.filteredCount,
    required this.filters,
    required this.onChanged,
    required this.onOpenFilters,
  });

  final int totalCount;
  final int filteredCount;
  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = filters.activeCount;
    final label = filteredCount == totalCount
        ? '$totalCount results'
        : '$filteredCount of $totalCount';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
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
                label: active == 0 ? 'Filters' : 'Filters ($active)',
                icon: Icons.tune_rounded,
                selected: active > 0,
                onTap: onOpenFilters,
              ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: SortBy.values.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final s = SortBy.values[i];
                    final selected = filters.sortBy == s;
                    return Align(
                      child: WlmChip(
                        label: s.label,
                        selected: selected,
                        // Tapping the active sort flips direction — the
                        // same gesture as clicking a table header twice.
                        onTap: () => onChanged(
                          selected
                              ? filters.copyWith(
                                  descending: !filters.descending,
                                )
                              : filters.copyWith(sortBy: s, descending: true),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 6),
            WlmIconButton(
              icon: filters.descending
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              tooltip: filters.descending
                  ? 'Sorted descending'
                  : 'Sorted ascending',
              size: 34,
              onPressed: () =>
                  onChanged(filters.copyWith(descending: !filters.descending)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Recent queries, tappable. Rendered under both empty states.
class _HistoryStrip extends StatelessWidget {
  const _HistoryStrip({required this.history, required this.onPick});

  final SearchHistory? history;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final h = history;
    if (h == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: h,
      builder: (context, _) {
        if (h.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const WlmSectionLabel('Recent searches'),
                const Spacer(),
                WlmGhostButton(
                  label: 'Clear',
                  icon: Icons.delete_outline_rounded,
                  onPressed: h.clear,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final q in h.entries)
                  WlmChip(
                    label: q,
                    icon: Icons.history_rounded,
                    onTap: () => onPick(q),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PageSizePicker extends StatelessWidget {
  const _PageSizePicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  static const _options = [10, 25, 50, 100];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        Text(
          'PER PAGE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.4,
            color: scheme.outline,
          ),
        ),
        for (final o in _options)
          WlmChip(label: '$o', selected: o == value, onTap: () => onChanged(o)),
      ],
    );
  }
}

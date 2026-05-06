import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/settings_store.dart';
import '../../core/tmdb_client.dart';
import 'media_detail_page.dart';

/// Browse-and-search catalog backed by TMDB. Two sub-tabs (Movies / TV);
/// each shows a trending feed by default and switches to live search
/// results when the user types. Tapping a card opens [MediaDetailPage].
///
/// Without a TMDB key this page is purely an empty state pointing to
/// Settings — we never call TMDB without the user opting in.
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({
    super.key,
    required this.settings,
    required this.onOpenSettings,
    required this.onFindTorrents,
  });

  final SettingsStore settings;
  final VoidCallback onOpenSettings;

  /// Called when the user taps "Find torrents" inside a TMDB media
  /// detail. The host (AppShell) is responsible for switching to the
  /// search tab and pre-filling the query.
  final ValueChanged<String> onFindTorrents;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _client = TmdbClient();
  final _queryCtrl = TextEditingController();

  // Per-tab caches so flicking between Movies/TV doesn't refetch.
  List<TmdbMedia>? _moviesTrending;
  List<TmdbMedia>? _tvTrending;
  List<TmdbMedia>? _moviesSearch;
  List<TmdbMedia>? _tvSearch;
  bool _loading = false;

  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
    widget.settings.addListener(_onSettingsChanged);
    _loadTrending();
  }

  void _onSettingsChanged() {
    // If the user just added a key, kick off the trending fetch.
    if (widget.settings.hasTmdbKey && _moviesTrending == null) {
      _loadTrending();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _tab.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    if (!widget.settings.hasTmdbKey) return;
    setState(() => _loading = true);
    final movies = await _client.trending(
      apiKey: widget.settings.tmdbKey,
      kind: TmdbMediaKind.movie,
    );
    final tv = await _client.trending(
      apiKey: widget.settings.tmdbKey,
      kind: TmdbMediaKind.tv,
    );
    if (!mounted) return;
    setState(() {
      _moviesTrending = movies;
      _tvTrending = tv;
      _loading = false;
    });
  }

  Future<void> _runSearch(String q) async {
    final trimmed = q.trim();
    setState(() => _query = trimmed);
    if (trimmed.isEmpty) {
      setState(() {
        _moviesSearch = null;
        _tvSearch = null;
      });
      return;
    }
    if (!widget.settings.hasTmdbKey) return;
    setState(() => _loading = true);
    final movies = await _client.search(
      apiKey: widget.settings.tmdbKey,
      query: trimmed,
      kind: TmdbMediaKind.movie,
    );
    final tv = await _client.search(
      apiKey: widget.settings.tmdbKey,
      query: trimmed,
      kind: TmdbMediaKind.tv,
    );
    if (!mounted) return;
    setState(() {
      _moviesSearch = movies;
      _tvSearch = tv;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.settings.hasTmdbKey) {
      return _NoKeyEmptyState(onOpenSettings: widget.onOpenSettings);
    }
    final scheme = Theme.of(context).colorScheme;
    final movies = _query.isEmpty ? _moviesTrending : _moviesSearch;
    final tv = _query.isEmpty ? _tvTrending : _tvSearch;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: WlmTextField(
            controller: _queryCtrl,
            label: 'Search movies & TV',
            hintText: 'Inception, Severance, \u2026',
            prefixIcon: Icons.search_rounded,
            clearable: true,
            onSubmitted: _runSearch,
            onChanged: (v) {
              // Debounce-light: only run when user pauses on a non-trivial
              // length; the Submit handler covers explicit Enter.
              if (v.isEmpty) _runSearch('');
            },
          ),
        ),
        TabBar(
          controller: _tab,
          labelColor: scheme.primary,
          unselectedLabelColor: scheme.outline,
          indicatorColor: scheme.primary,
          tabs: const [
            Tab(text: 'Movies'),
            Tab(text: 'TV'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _MediaGrid(
                items: movies,
                loading: _loading,
                settings: widget.settings,
                onFindTorrents: widget.onFindTorrents,
                emptyTitle: _query.isEmpty
                    ? 'Nothing trending right now'
                    : 'No movies match \u201c$_query\u201d',
              ),
              _MediaGrid(
                items: tv,
                loading: _loading,
                settings: widget.settings,
                onFindTorrents: widget.onFindTorrents,
                emptyTitle: _query.isEmpty
                    ? 'Nothing trending right now'
                    : 'No shows match \u201c$_query\u201d',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoKeyEmptyState extends StatelessWidget {
  const _NoKeyEmptyState({required this.onOpenSettings});
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const WlmEmptyState(
              eyebrow: 'TMDB',
              icon: Icons.movie_filter_outlined,
              title: 'Add a TMDB key to browse movies & TV',
              body:
                  'The Movies & TV catalog uses themoviedb.org for posters, '
                  'descriptions, and episode lists. The free key takes 60s '
                  'and stays on this device.',
            ),
            const SizedBox(height: 16),
            WlmPrimaryButton(
              label: 'Open Settings',
              icon: Icons.tune_outlined,
              onPressed: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({
    required this.items,
    required this.loading,
    required this.emptyTitle,
    required this.settings,
    required this.onFindTorrents,
  });

  final List<TmdbMedia>? items;
  final bool loading;
  final String emptyTitle;
  final SettingsStore settings;
  final ValueChanged<String> onFindTorrents;

  @override
  Widget build(BuildContext context) {
    if (items == null && loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items == null || items!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: WlmEmptyState(
            eyebrow: 'EMPTY',
            icon: Icons.theaters_outlined,
            title: emptyTitle,
            body: 'Try a different search.',
          ),
        ),
      );
    }
    return MasonryGridView.count(
      padding: const EdgeInsets.all(12),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      itemCount: items!.length,
      itemBuilder: (context, i) => _PosterCard(
        media: items![i],
        settings: settings,
        onFindTorrents: onFindTorrents,
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.media,
    required this.settings,
    required this.onFindTorrents,
  });
  final TmdbMedia media;
  final SettingsStore settings;
  final ValueChanged<String> onFindTorrents;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final poster = TmdbClient.posterUrl(media.posterPath);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                MediaDetailPage(media: media, settings: settings),
          ),
        );
        if (result is FindTorrentsRequest) {
          onFindTorrents(result.query);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: poster.isEmpty
                  ? Container(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(Icons.image_not_supported_outlined,
                          color: scheme.outline),
                    )
                  : CachedNetworkImage(
                      imageUrl: poster,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(color: scheme.surfaceContainerHighest),
                      errorWidget: (_, _, _) =>
                          Container(color: scheme.surfaceContainerHighest),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            media.title,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (media.year.isNotEmpty)
            Text(
              media.year,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.outline),
            ),
        ],
      ),
    );
  }
}

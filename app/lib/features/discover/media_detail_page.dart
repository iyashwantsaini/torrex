import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/settings_store.dart';
import '../../core/tmdb_client.dart';

/// Pop-result returned by [MediaDetailPage] when the user taps "Find
/// torrents". Lets the AppShell switch to the Search tab and pre-fill
/// the query without coupling the discover feature to the search page.
class FindTorrentsRequest {
  const FindTorrentsRequest(this.query);
  final String query;
}

/// TMDB-driven detail screen reached from the Discover catalog. Shows
/// poster + backdrop + overview, a season / episode list for TV, and a
/// "Find torrents" CTA.
class MediaDetailPage extends StatefulWidget {
  const MediaDetailPage({
    super.key,
    required this.media,
    required this.settings,
  });

  final TmdbMedia media;
  final SettingsStore settings;

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  final _client = TmdbClient();
  TmdbMedia? _full;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final apiKey = widget.settings.tmdbKey;
    if (apiKey.isEmpty) {
      setState(() {
        _full = widget.media;
        _loading = false;
      });
      return;
    }
    final m = await _client.details(
      apiKey: apiKey,
      id: widget.media.id,
      kind: widget.media.kind,
    );
    if (!mounted) return;
    setState(() {
      _full = m ?? widget.media;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = _full ?? widget.media;
    final scheme = Theme.of(context).colorScheme;
    final backdrop = TmdbClient.backdropUrl(m.backdropPath);
    final poster = TmdbClient.posterUrl(m.posterPath);

    return Scaffold(
      appBar: AppBar(title: Text(m.title)),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (backdrop.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: backdrop,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    Container(color: scheme.surfaceContainerHighest),
                errorWidget: (_, _, _) =>
                    Container(color: scheme.surfaceContainerHighest),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (poster.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: poster,
                      width: 100,
                      height: 150,
                      fit: BoxFit.cover,
                    ),
                  ),
                if (poster.isNotEmpty) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (m.year.isNotEmpty)
                        Text(
                          m.year,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: scheme.outline),
                        ),
                      const SizedBox(height: 8),
                      if (m.voteAverage > 0)
                        Row(
                          children: [
                            Icon(Icons.star_rounded,
                                size: 16, color: scheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              '${m.voteAverage.toStringAsFixed(1)} / 10',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                      if (m.genres.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final g in m.genres) WlmChip(label: g),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (m.overview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                m.overview,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: WlmPrimaryButton(
              label: 'Find torrents',
              icon: Icons.search_rounded,
              expand: true,
              // Send title + year so the Torznab search returns the
              // actual film/show instead of every release that happens
              // to share a word with the title ("It", "Up", "Cars").
              onPressed: () => Navigator.of(context).pop(
                FindTorrentsRequest(
                  m.year.isNotEmpty ? '${m.title} ${m.year}' : m.title,
                ),
              ),
            ),
          ),
          if (m.kind == TmdbMediaKind.tv && m.seasons.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: WlmSectionLabel('Seasons (${m.seasons.length})'),
            ),
            for (final s in m.seasons)
              _SeasonTile(
                tvId: m.id,
                season: s,
                apiKey: widget.settings.tmdbKey,
              ),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SeasonTile extends StatefulWidget {
  const _SeasonTile({
    required this.tvId,
    required this.season,
    required this.apiKey,
  });
  final int tvId;
  final TmdbSeason season;
  final String apiKey;

  @override
  State<_SeasonTile> createState() => _SeasonTileState();
}

class _SeasonTileState extends State<_SeasonTile> {
  final _client = TmdbClient();
  List<TmdbEpisode>? _episodes;
  bool _loading = false;
  bool _expanded = false;

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    if (_expanded && _episodes == null && !_loading) {
      if (widget.apiKey.isEmpty) return;
      setState(() => _loading = true);
      final eps = await _client.seasonEpisodes(
        apiKey: widget.apiKey,
        tvId: widget.tvId,
        seasonNumber: widget.season.seasonNumber,
      );
      if (!mounted) return;
      setState(() {
        _episodes = eps;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: scheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.season.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    '${widget.season.episodeCount} ep',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              )
            else if (_episodes != null)
              for (final ep in _episodes!)
                Padding(
                  padding: const EdgeInsets.only(left: 32, top: 4, bottom: 4),
                  child: Text(
                    'E${ep.episodeNumber} \u00b7 ${ep.name}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

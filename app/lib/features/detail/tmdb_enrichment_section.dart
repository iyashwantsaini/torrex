import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:wolwoloom/wolwoloom.dart';

import '../../core/settings_store.dart';
import '../../core/tmdb_client.dart';
import '../../models/torrent_result.dart';

/// Inline TMDB enrichment block shown on the detail page **only for
/// movie / TV results**. Renders nothing while loading and nothing on
/// failure (TMDB is best-effort). When the user has no TMDB key set, a
/// small callout invites them to add one in Settings.
class TmdbEnrichmentSection extends StatefulWidget {
  const TmdbEnrichmentSection({
    super.key,
    required this.result,
    required this.settings,
  });

  final TorrentResult result;
  final SettingsStore settings;

  @override
  State<TmdbEnrichmentSection> createState() => _TmdbEnrichmentSectionState();
}

class _TmdbEnrichmentSectionState extends State<TmdbEnrichmentSection> {
  final _client = TmdbClient();
  TmdbMedia? _media;
  bool _loading = false;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    _maybeFetch();
  }

  @override
  void didUpdateWidget(covariant TmdbEnrichmentSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result.title != widget.result.title ||
        oldWidget.settings.tmdbKey != widget.settings.tmdbKey) {
      _attempted = false;
      _media = null;
      _maybeFetch();
    }
  }

  Future<void> _maybeFetch() async {
    if (_attempted) return;
    if (!widget.result.isMedia) return;
    if (!widget.settings.hasTmdbKey) return;
    setState(() {
      _loading = true;
      _attempted = true;
    });
    final hint = widget.result.mediaKindHint;
    final m = await _client.searchBest(
      apiKey: widget.settings.tmdbKey,
      query: widget.result.title,
      kind: TmdbMediaKind.parse(hint),
    );
    if (!mounted) return;
    setState(() {
      _media = m;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Not media → render nothing. Keeps non-media (linux ISOs, software,
    // music) detail pages clutter-free.
    if (!widget.result.isMedia) return const SizedBox.shrink();

    // No key → one-time soft prompt. We deliberately don't auto-open
    // Settings; the user might be mid-task.
    if (!widget.settings.hasTmdbKey) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: WlmCallout(
          tone: WlmCalloutTone.neutral,
          title: 'Add a TMDB key for posters & synopses',
          body:
              'Settings → TMDB. The free key takes 60s to create at '
              'themoviedb.org and stays on this device.',
        ),
      );
    }

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: WlmSkeleton(height: 120),
      );
    }

    final m = _media;
    if (m == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final poster = TmdbClient.posterUrl(m.posterPath, size: 'w185');
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (poster.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: poster,
                width: 80,
                height: 120,
                fit: BoxFit.cover,
                placeholder: (_, _) => const SizedBox(
                  width: 80,
                  height: 120,
                  child: WlmSkeleton(height: 120),
                ),
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          if (poster.isNotEmpty) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.year.isEmpty ? m.title : '${m.title} (${m.year})',
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (m.voteAverage > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(
                          children: [
                            Icon(Icons.star_rounded,
                                size: 14, color: scheme.primary),
                            const SizedBox(width: 2),
                            Text(
                              m.voteAverage.toStringAsFixed(1),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  m.kind == TmdbMediaKind.tv ? 'TV series' : 'Movie',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.outline),
                ),
                const SizedBox(height: 8),
                if (m.overview.isNotEmpty)
                  Text(
                    m.overview,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

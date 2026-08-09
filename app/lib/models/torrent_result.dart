import 'dart:math' as math;

import '../core/release_parser.dart';

/// A single result returned from a Torznab `t=search` query.
class TorrentResult {
  const TorrentResult({
    required this.title,
    required this.indexer,
    required this.sizeBytes,
    required this.seeders,
    required this.leechers,
    required this.publishDate,
    required this.magnetUri,
    required this.downloadUrl,
    required this.detailsUrl,
    required this.category,
    this.infoHash = '',
    this.imdbId = '',
    this.tmdbId = '',
    this.tvdbId = '',
    this.coverUrl = '',
    this.files = const [],
    this.trackers = const [],
    this.sourceIndexers = const {},
  });

  final String title;
  final String indexer;
  final int sizeBytes;
  final int seeders;
  final int leechers;
  final DateTime? publishDate;

  /// Either a `magnet:` URI parsed from the feed, or empty if the indexer
  /// only supplies a `.torrent` download link.
  final String magnetUri;

  /// HTTP(S) link to a `.torrent` blob hosted by the indexer (may be empty).
  final String downloadUrl;

  /// Human-facing details page on the indexer (may be empty).
  final String detailsUrl;

  final String category;

  /// Optional extended fields populated when the indexer responds to
  /// `extended=1` and includes the corresponding `<torznab:attr>`. All
  /// default to empty / empty list so callers can render unconditionally.
  final String infoHash;
  final String imdbId;
  final String tmdbId;
  final String tvdbId;
  final String coverUrl;
  final List<TorrentFile> files;
  final List<String> trackers;

  /// Every indexer that reported this exact torrent. Populated by the
  /// dedupe pass; a single-source result carries just its own indexer
  /// (or nothing at all, when the feed omitted one).
  final Set<String> sourceIndexers;

  bool get hasMagnet => magnetUri.startsWith('magnet:');

  /// Best link to hand to a torrent client — magnet preferred.
  String get bestUri => hasMagnet ? magnetUri : downloadUrl;

  /// A stable identity for this result. Prefers the BitTorrent info-hash
  /// (which is the same across every indexer), falling back to the link
  /// and finally the title so list keys never collapse to `''`.
  String get id {
    if (infoHash.isNotEmpty) return infoHash.toLowerCase();
    if (bestUri.isNotEmpty) return bestUri;
    return '$indexer|$title|$sizeBytes';
  }

  /// Technical metadata parsed out of the release name (resolution,
  /// source, codec, HDR, season/episode, group, …). Memoised inside
  /// [ReleaseParser], so reading this in a build method is cheap.
  ReleaseInfo get release => ReleaseParser.parse(title);

  /// Seed/leech ratio, capped so a 5000:0 torrent doesn't blow out the
  /// health bar. Returns `0` when nobody is seeding.
  double get ratio {
    if (seeders <= 0) return 0;
    if (leechers <= 0) return 3;
    return (seeders / leechers).clamp(0, 3).toDouble();
  }

  /// Swarm health in `0..1`, the same idea as the coloured health bars on
  /// mainstream torrent sites. Weighted mostly by absolute seeder count
  /// (what actually determines download speed) with a ratio nudge.
  double get health {
    if (seeders <= 0) return 0;
    // log-ish curve: 1 seeder ≈ 0.10, 10 ≈ 0.45, 100 ≈ 0.80, 1000+ ≈ 1.0.
    final s = seeders.clamp(1, 1000).toDouble();
    final base = 0.1 + 0.85 * (math.log(s) / math.ln10) / 3;
    final ratioBonus = (ratio / 3) * 0.1;
    return (base * 0.9 + ratioBonus).clamp(0.0, 1.0);
  }

  /// Human label for [health], used for the badge and for screen readers.
  String get healthLabel {
    if (seeders <= 0) return 'Dead';
    if (seeders < 5) return 'Weak';
    if (seeders < 25) return 'Fair';
    if (seeders < 100) return 'Good';
    return 'Excellent';
  }

  /// Copy carrying a different set of contributing indexers.
  TorrentResult withSources(Set<String> sources) =>
      _copy(sourceIndexers: {...sourceIndexers, ...sources});

  /// Copy with merged swarm numbers — used when the same torrent is
  /// reported by several indexers with different seeder counts.
  TorrentResult copyWithSwarm({int? seeders, int? leechers}) =>
      _copy(seeders: seeders, leechers: leechers);

  TorrentResult _copy({
    int? seeders,
    int? leechers,
    Set<String>? sourceIndexers,
  }) {
    return TorrentResult(
      title: title,
      indexer: indexer,
      sizeBytes: sizeBytes,
      seeders: seeders ?? this.seeders,
      leechers: leechers ?? this.leechers,
      publishDate: publishDate,
      magnetUri: magnetUri,
      downloadUrl: downloadUrl,
      detailsUrl: detailsUrl,
      category: category,
      infoHash: infoHash,
      imdbId: imdbId,
      tmdbId: tmdbId,
      tvdbId: tvdbId,
      coverUrl: coverUrl,
      files: files,
      trackers: trackers,
      sourceIndexers: sourceIndexers ?? this.sourceIndexers,
    );
  }

  /// Whether the title looks like media (movie / TV episode). Used to
  /// gate TMDB lookups so we don't waste API calls on `ubuntu-22.iso`.
  ///
  /// Heuristic order:
  ///   1. Torznab category id range (2000=Movies, 5000=TV).
  ///   2. Human category string contains "movie"/"tv"/"show".
  ///   3. Title pattern matches a TV episode tag (S01E02) or a movie
  ///      release year (1900–2099 in parens or surrounded by separators).
  /// Step 3 catches indexers that don't emit a category at all (some nyaa
  /// feeds) so they still get poster / synopsis enrichment.
  bool get isMedia {
    final c = category.toLowerCase();
    if (c.startsWith('2000') || c.startsWith('5000')) return true;
    if (c.contains('2000') || c.contains('5000')) return true;
    if (c.contains('movie') ||
        c.contains('tv') ||
        c.contains('show') ||
        c.contains('video') ||
        c.contains('film') ||
        c.contains('anime') ||
        c.contains('series')) {
      return true;
    }
    final t = title;
    if (RegExp(r'[Ss]\d{1,2}[Ee]\d{1,3}').hasMatch(t)) return true;
    if (RegExp(r'(?:^|[\s.\-_(\[])(19|20)\d{2}(?:[\s.\-_)\]]|$)').hasMatch(t)) {
      return true;
    }
    return false;
  }

  /// `'movie'` if the category is in the Torznab 2000 range,
  /// `'tv'` for 5000, otherwise `null`. Used to bias TMDB to a specific
  /// search endpoint.
  String? get mediaKindHint {
    final c = category.toLowerCase();
    if (c.contains('5000') ||
        c.contains('tv') ||
        c.contains('show') ||
        c.contains('series') ||
        c.contains('anime')) {
      return 'tv';
    }
    if (c.contains('2000') || c.contains('movie') || c.contains('film')) {
      return 'movie';
    }
    if (RegExp(r'[Ss]\d{1,2}[Ee]\d{1,3}').hasMatch(title)) return 'tv';
    return null;
  }
}

/// One file inside a torrent's file list (when the indexer publishes it
/// via `<torznab:attr name="files" value="...">` or repeated `filename`
/// attrs). `bytes` is `null` when only the name is known.
class TorrentFile {
  const TorrentFile({required this.name, this.bytes});
  final String name;
  final int? bytes;
}

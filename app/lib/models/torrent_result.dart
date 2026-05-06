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

  bool get hasMagnet => magnetUri.startsWith('magnet:');

  /// Best link to hand to a torrent client — magnet preferred.
  String get bestUri => hasMagnet ? magnetUri : downloadUrl;

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
    if (c.contains('movie') || c.contains('tv') || c.contains('show') ||
        c.contains('video') || c.contains('film') || c.contains('anime') ||
        c.contains('series')) {
      return true;
    }
    final t = title;
    if (RegExp(r'[Ss]\d{1,2}[Ee]\d{1,3}').hasMatch(t)) return true;
    if (RegExp(r'(?:^|[\s.\-_(\[])(19|20)\d{2}(?:[\s.\-_)\]]|$)')
        .hasMatch(t)) {
      return true;
    }
    return false;
  }

  /// `'movie'` if the category is in the Torznab 2000 range,
  /// `'tv'` for 5000, otherwise `null`. Used to bias TMDB to a specific
  /// search endpoint.
  String? get mediaKindHint {
    final c = category.toLowerCase();
    if (c.contains('5000') || c.contains('tv') || c.contains('show') ||
        c.contains('series') || c.contains('anime')) {
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

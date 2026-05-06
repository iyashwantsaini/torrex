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
  /// Heuristic: the Torznab category id starts with `2000` (Movies) or
  /// `5000` (TV). Falls back to the human-readable category string.
  bool get isMedia {
    if (category.isEmpty) return false;
    final c = category.toLowerCase();
    if (c.startsWith('2000') || c.startsWith('5000')) return true;
    return c.contains('movie') || c.contains('tv') || c.contains('show');
  }

  /// `'movie'` if the category is in the Torznab 2000 range,
  /// `'tv'` for 5000, otherwise `null`. Used to bias TMDB to a specific
  /// search endpoint.
  String? get mediaKindHint {
    final c = category.toLowerCase();
    if (c.startsWith('2000') || c.contains('movie')) return 'movie';
    if (c.startsWith('5000') || c.contains('tv') || c.contains('show')) {
      return 'tv';
    }
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

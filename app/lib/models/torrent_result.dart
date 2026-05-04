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

  bool get hasMagnet => magnetUri.startsWith('magnet:');

  /// Best link to hand to a torrent client — magnet preferred.
  String get bestUri => hasMagnet ? magnetUri : downloadUrl;
}

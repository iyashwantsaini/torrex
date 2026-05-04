import '../models/torrent_result.dart';

/// Hardcoded sample results used only when the configured base URL equals
/// `demo`. Lets the app showcase the search/detail UI without standing up a
/// real Jackett/Prowlarr backend (used for documentation screenshots and as
/// a first-run preview).
class DemoResults {
  static const String triggerUrl = 'demo';

  static List<TorrentResult> forQuery(String query) {
    final q = query.toLowerCase();
    return _all
        .where(
          (r) => q.isEmpty || r.title.toLowerCase().contains(q.split(' ').first),
        )
        .toList(growable: false);
  }

  static final List<TorrentResult> _all = [
    TorrentResult(
      title: 'Ubuntu 26.04 LTS Desktop amd64 ISO',
      indexer: 'LinuxTracker',
      sizeBytes: 4_672_000_000,
      seeders: 4821,
      leechers: 132,
      publishDate: DateTime.now().subtract(const Duration(hours: 6)),
      magnetUri:
          'magnet:?xt=urn:btih:8C4ADD24F12345BC0F9876ABCDEF1234567890AB&dn=ubuntu-26.04-desktop-amd64.iso&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337',
      downloadUrl: '',
      detailsUrl: 'https://example.invalid/torrent/ubuntu-26-04',
      category: 'OS / Linux',
    ),
    TorrentResult(
      title: 'Debian 13 netinst amd64',
      indexer: 'LinuxTracker',
      sizeBytes: 612_000_000,
      seeders: 1893,
      leechers: 47,
      publishDate: DateTime.now().subtract(const Duration(days: 3)),
      magnetUri:
          'magnet:?xt=urn:btih:1A2B3C4D5E6F7A8B9C0D1E2F3A4B5C6D7E8F9A0B&dn=debian-13-netinst.iso',
      downloadUrl: '',
      detailsUrl: 'https://example.invalid/torrent/debian-13',
      category: 'OS / Linux',
    ),
    TorrentResult(
      title: 'Blender 4.3.0 Linux x86_64 portable',
      indexer: 'BlenderArchive',
      sizeBytes: 327_000_000,
      seeders: 612,
      leechers: 21,
      publishDate: DateTime.now().subtract(const Duration(days: 12)),
      magnetUri:
          'magnet:?xt=urn:btih:F0E1D2C3B4A5968778695A4B3C2D1E0F90817263&dn=blender-4.3.0-linux',
      downloadUrl: '',
      detailsUrl: 'https://example.invalid/torrent/blender-430',
      category: 'Software',
    ),
    TorrentResult(
      title: 'Big Buck Bunny 1080p (Creative Commons)',
      indexer: 'CCArchive',
      sizeBytes: 1_140_000_000,
      seeders: 384,
      leechers: 9,
      publishDate: DateTime.now().subtract(const Duration(days: 30)),
      magnetUri:
          'magnet:?xt=urn:btih:DD8255ECDC7CA55FB0BBF81323D87062DB1F6D1C&dn=big-buck-bunny-1080p',
      downloadUrl: '',
      detailsUrl: 'https://example.invalid/torrent/bbb-1080p',
      category: 'Video / CC',
    ),
    TorrentResult(
      title: 'Sintel — open movie 4K HDR',
      indexer: 'CCArchive',
      sizeBytes: 8_900_000_000,
      seeders: 271,
      leechers: 14,
      publishDate: DateTime.now().subtract(const Duration(days: 90)),
      magnetUri:
          'magnet:?xt=urn:btih:08ADA5A7A6183AAE1E09D831DF6748D566095A10&dn=sintel-4k-hdr',
      downloadUrl: '',
      detailsUrl: 'https://example.invalid/torrent/sintel-4k',
      category: 'Video / CC',
    ),
    TorrentResult(
      title: 'Wikipedia EN dump — 2026-04 articles only',
      indexer: 'WikiArchive',
      sizeBytes: 21_300_000_000,
      seeders: 142,
      leechers: 3,
      publishDate: DateTime.now().subtract(const Duration(days: 5)),
      magnetUri: '',
      downloadUrl: 'https://example.invalid/dl/wiki-en-2026-04.torrent',
      detailsUrl: 'https://example.invalid/torrent/wiki-en-2026-04',
      category: 'Data / Archive',
    ),
  ];
}

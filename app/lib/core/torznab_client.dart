import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../models/torrent_result.dart';
import 'demo_results.dart';

/// Thin client for the Torznab API exposed by Jackett / Prowlarr.
///
/// Endpoints follow the standard Torznab shape:
/// `<baseUrl>/api/v2.0/indexers/<indexer>/results/torznab/api?apikey=...&t=search&q=...`
///
/// Where `<indexer>` is `all` for an aggregate search across every configured
/// indexer, or a specific indexer slug.
class TorznabClient {
  TorznabClient({Dio? dio}) : _dio = dio ?? _defaultDio();

  static Dio _defaultDio() {
    final d = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        // Jackett proxies every configured indexer serially-ish; a cold
        // aggregate search across 20+ trackers routinely needs 40s+.
        // The old 30s cut it off mid-flight, which is why the same query
        // "worked on the 3rd try" — by then the indexers were warm.
        receiveTimeout: const Duration(seconds: 75),
        responseType: ResponseType.plain,
        headers: {'Accept': 'application/xml,text/xml,*/*'},
        // Let us read Jackett's own error body instead of Dio throwing a
        // generic "bad response" for 4xx.
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    return d;
  }

  final Dio _dio;

  /// How many times to re-issue a search that came back empty or timed
  /// out. Hugging Face Spaces cold-start and Jackett's per-indexer
  /// scrapers frequently fail the *first* request after an idle period
  /// and succeed moments later — retrying here is the difference between
  /// "it works" and "I had to search four times".
  static const int _maxAttempts = 3;

  static const List<Duration> _backoff = [
    Duration(milliseconds: 900),
    Duration(milliseconds: 2200),
  ];

  /// Run a `t=search` query and parse the RSS/Torznab response.
  ///
  /// Retries transient failures (timeouts, 5xx-ish, empty-but-OK bodies)
  /// with backoff. Pass a [cancelToken] so a superseded search can be
  /// aborted instead of racing the new one.
  ///
  /// Throws [TorznabException] on any HTTP / parse / API error that
  /// survived every attempt.
  Future<List<TorrentResult>> search({
    required String baseUrl,
    required String apiKey,
    required String query,
    String indexer = 'all',
    int limit = 300,
    int offset = 0,
    List<int> categories = const [],
    bool extended = false,
    CancelToken? cancelToken,
    void Function(int attempt)? onRetry,
  }) async {
    if (baseUrl == DemoResults.triggerUrl) {
      // Local preview / screenshot mode — no network call.
      return DemoResults.forQuery(query);
    }
    if (baseUrl.isEmpty) throw const TorznabException('Backend URL not set.');
    if (apiKey.isEmpty) throw const TorznabException('API key not set.');

    TorznabException? lastError;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      if (attempt > 0) {
        onRetry?.call(attempt);
        await Future<void>.delayed(_backoff[attempt - 1]);
        if (cancelToken?.isCancelled ?? false) {
          throw const TorznabException('Search cancelled.');
        }
      }
      try {
        final results = await _searchOnce(
          baseUrl: baseUrl,
          apiKey: apiKey,
          query: query,
          indexer: indexer,
          limit: limit,
          offset: offset,
          categories: categories,
          extended: extended,
          cancelToken: cancelToken,
        );
        // A genuinely empty result set and a "all my indexers timed out"
        // result set look identical over Torznab, so give it one more
        // shot before believing it. Only for non-empty queries — an
        // empty query legitimately returns nothing on most indexers.
        if (results.isEmpty &&
            query.trim().isNotEmpty &&
            attempt < _maxAttempts - 1) {
          continue;
        }
        return results;
      } on _TransientTorznabException catch (e) {
        lastError = TorznabException(e.message);
        continue;
        // Auth / bad-request style failures will never succeed on retry,
        // so plain TorznabExceptions propagate straight out of the loop.
      }
    }
    throw lastError ??
        const TorznabException('Backend did not respond. Try again.');
  }

  Future<List<TorrentResult>> _searchOnce({
    required String baseUrl,
    required String apiKey,
    required String query,
    required String indexer,
    required int limit,
    required int offset,
    required List<int> categories,
    required bool extended,
    CancelToken? cancelToken,
  }) async {
    final url = _buildUrl(baseUrl, indexer);
    final Response<String> resp;
    try {
      resp = await _dio.get<String>(
        url,
        cancelToken: cancelToken,
        queryParameters: {
          'apikey': apiKey,
          't': 'search',
          'q': query,
          'limit': limit,
          if (offset > 0) 'offset': offset,
          if (categories.isNotEmpty) 'cat': categories.join(','),
          if (extended) 'extended': 1,
        },
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw const TorznabException('Search cancelled.');
      }
      if (_isTransient(e)) {
        throw _TransientTorznabException(_describeDioError(e));
      }
      throw TorznabException(_describeDioError(e));
    }

    final status = resp.statusCode ?? 0;
    if (status == 401 || status == 403) {
      throw const TorznabException(
        'Auth failed. Check your API key in Settings.',
      );
    }
    if (status == 404) {
      throw const TorznabException(
        'Indexer not found on the backend. Pick a different one in Settings.',
      );
    }
    if (status == 429) {
      throw const _TransientTorznabException(
        'Backend is rate-limiting. Retrying\u2026',
      );
    }

    final body = resp.data?.trim() ?? '';
    if (body.isEmpty) {
      throw const _TransientTorznabException('Backend returned an empty body.');
    }
    // Jackett behind a sleeping HF Space (or any reverse proxy hiccup)
    // answers with an HTML page instead of XML. Treat that as transient
    // rather than surfacing an unreadable parse error.
    if (!body.startsWith('<?xml') && !body.startsWith('<rss')) {
      final looksLikeHtml =
          body.startsWith('<!') || body.toLowerCase().startsWith('<html');
      if (looksLikeHtml) {
        throw const _TransientTorznabException(
          'Backend is still waking up. Retrying\u2026',
        );
      }
    }

    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(body);
    } on XmlException catch (e) {
      throw TorznabException('Invalid XML response: ${e.message}');
    }

    // Surface Torznab error elements (e.g. wrong API key).
    final err = doc.findAllElements('error').firstOrNull;
    if (err != null) {
      final code = err.getAttribute('code') ?? '?';
      final desc = err.getAttribute('description') ?? 'Unknown error';
      // 100/101 = auth, 200/201/202 = bad request — permanent.
      // 5xx codes are Jackett's "indexer unavailable", worth a retry.
      final numeric = int.tryParse(code) ?? 0;
      if (numeric >= 500) {
        throw _TransientTorznabException('Indexer error $code: $desc');
      }
      throw TorznabException('Indexer error $code: $desc');
    }

    return doc.findAllElements('item').map(_parseItem).toList(growable: false);
  }

  static bool _isTransient(DioException e) {
    final status = e.response?.statusCode;
    if (status != null) return status >= 500 || status == 429;
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError => true,
      _ => false,
    };
  }

  /// List the configured indexers (ones the user has set up in Jackett's
  /// admin UI). Used by the Settings → Indexer dropdown so users don't
  /// have to type slugs by hand. Returns an empty list on error so
  /// callers can fall back to free-text input.
  Future<List<JackettIndexer>> listIndexers({
    required String baseUrl,
    required String apiKey,
  }) async {
    if (baseUrl.isEmpty || apiKey.isEmpty) return const [];
    if (baseUrl == DemoResults.triggerUrl) return const [];
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = '$trimmed/api/v2.0/indexers';
    try {
      final resp = await _dio.get<dynamic>(
        url,
        queryParameters: {'apikey': apiKey, 'configured': true},
        options: Options(
          responseType: ResponseType.json,
          headers: {'Accept': 'application/json'},
        ),
      );
      final data = resp.data;
      if (data is! List) return const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(JackettIndexer.fromJson)
          .toList(growable: false);
    } on DioException {
      return const [];
    }
  }

  static String _buildUrl(String baseUrl, String indexer) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final id = indexer.trim().isEmpty ? 'all' : indexer.trim();
    return '$trimmed/api/v2.0/indexers/$id/results/torznab/api';
  }

  static TorrentResult _parseItem(XmlElement item) {
    String text(String name) =>
        item.findElements(name).firstOrNull?.innerText.trim() ?? '';

    String? attr(String element, String attribute) =>
        item.findElements(element).firstOrNull?.getAttribute(attribute);

    // torznab:attr name="..." value="..."
    String? torznabAttr(String name) {
      for (final el in item.findAllElements('torznab:attr')) {
        if (el.getAttribute('name') == name) return el.getAttribute('value');
      }
      // Some feeds drop the namespace prefix.
      for (final el in item.findAllElements('attr')) {
        if (el.getAttribute('name') == name) return el.getAttribute('value');
      }
      return null;
    }

    final title = text('title');
    final indexer = text('jackettindexer').isNotEmpty
        ? text('jackettindexer')
        : (attr('jackettindexer', 'id') ?? '');
    // Indexers emit one or many <category> elements (numeric Torznab ids
    // and/or human strings). RARBG puts the numeric id first; PTB/nyaasi
    // put a string like "Video/HD" first. We need *all* of them so the
    // isMedia heuristic on TorrentResult fires consistently — otherwise
    // TMDB enrichment only kicks in for RARBG.
    final category = item
        .findElements('category')
        .map((e) => e.innerText.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');

    final sizeStr = text('size').isNotEmpty
        ? text('size')
        : (torznabAttr('size') ?? '0');
    final size = int.tryParse(sizeStr) ?? 0;

    final seeders = int.tryParse(torznabAttr('seeders') ?? '0') ?? 0;
    final peers = int.tryParse(torznabAttr('peers') ?? '0') ?? 0;
    final leechers =
        int.tryParse(torznabAttr('leechers') ?? '') ??
        (peers > seeders ? peers - seeders : 0);

    final pubDateStr = text('pubDate');
    DateTime? pubDate;
    if (pubDateStr.isNotEmpty) {
      pubDate = _tryParseRfc822(pubDateStr) ?? DateTime.tryParse(pubDateStr);
    }

    final magnet = torznabAttr('magneturl') ?? '';
    final detailsUrl = text('comments').isNotEmpty
        ? text('comments')
        : text('guid');
    // <link> is the .torrent download or magnet, depending on indexer.
    final link = text('link');

    // Extended attributes (only present when the caller passed `extended=1`
    // AND the indexer supports them). All fall back to empty / empty list.
    final infoHash = torznabAttr('infohash') ?? '';
    final imdbId = torznabAttr('imdb') ?? torznabAttr('imdbid') ?? '';
    final tmdbId = torznabAttr('tmdb') ?? torznabAttr('tmdbid') ?? '';
    final tvdbId = torznabAttr('tvdb') ?? torznabAttr('tvdbid') ?? '';
    final coverUrl =
        torznabAttr('coverurl') ??
        torznabAttr('cover') ??
        torznabAttr('poster') ??
        '';

    final files = _collectFiles(item);
    final trackers = _collectMulti(item, 'tracker');

    // Magnet resolution. We *strongly* prefer a usable magnet URI so the
    // app can hand it straight to the user's torrent client (Flud,
    // qBittorrent, Transmission, etc.) without going through Jackett's
    // /dl redirect — which is flaky on web and on some Android browsers.
    //
    //   1. If the feed already gave us a `magnet:` (either via the
    //      `magneturl` torznab:attr or as the <link>), use it as-is.
    //   2. Otherwise, if Jackett surfaced an `infohash`, synthesise a
    //      magnet client-side: xt=urn:btih:<hash> + dn=<title> +
    //      every tracker we know about. This is what every torrent
    //      client expects and works offline.
    //   3. Fall back to the .torrent download URL as a last resort.
    String magnetUri;
    String downloadUrl;
    if (magnet.startsWith('magnet:')) {
      magnetUri = magnet;
      downloadUrl = link.startsWith('magnet:') ? '' : link;
    } else if (link.startsWith('magnet:')) {
      magnetUri = link;
      downloadUrl = '';
    } else if (infoHash.isNotEmpty) {
      magnetUri = _buildMagnet(
        infoHash: infoHash,
        displayName: title,
        trackers: trackers,
      );
      // Keep the .torrent URL around as a fallback for the "Download
      // .torrent" button when the user explicitly wants the file.
      downloadUrl = link;
    } else {
      magnetUri = '';
      downloadUrl = link;
    }

    return TorrentResult(
      title: title,
      indexer: indexer,
      sizeBytes: size,
      seeders: seeders,
      leechers: leechers,
      publishDate: pubDate,
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
      sourceIndexers: indexer.isEmpty ? const {} : {indexer},
    );
  }

  /// Build a `magnet:` URI from the pieces Jackett gives us in extended
  /// mode. The result includes the standard well-known public DHT trackers
  /// in addition to whatever the indexer reported, so even feeds that
  /// don't list trackers (TheRARBG, YTS) still produce a magnet that
  /// connects to the swarm immediately.
  static String _buildMagnet({
    required String infoHash,
    required String displayName,
    required List<String> trackers,
  }) {
    // BTIH must be 40-char hex (v1) or 32-char base32. Don't try to
    // be clever — pass through whatever Jackett gave us; clients are
    // tolerant of casing.
    final params = <String>[
      'xt=urn:btih:$infoHash',
      if (displayName.isNotEmpty) 'dn=${Uri.encodeQueryComponent(displayName)}',
    ];
    final seen = <String>{};
    for (final t in [...trackers, ..._kPublicTrackers]) {
      final url = t.trim();
      if (url.isEmpty) continue;
      if (!seen.add(url)) continue;
      params.add('tr=${Uri.encodeQueryComponent(url)}');
    }
    return 'magnet:?${params.join('&')}';
  }

  /// A small set of widely-used public DHT/UDP trackers. We append these
  /// as a fallback when the indexer's feed doesn't include any tracker
  /// list of its own. Keeps magnets working even on minimal RSS feeds.
  static const List<String> _kPublicTrackers = [
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://open.stealth.si:80/announce',
    'udp://tracker.torrent.eu.org:451/announce',
    'udp://exodus.desync.com:6969/announce',
    'udp://tracker.openbittorrent.com:6969/announce',
  ];

  /// Collect every value of a repeated `<torznab:attr name="X">` (or the
  /// unprefixed `<attr>` variant). Order preserved.
  static List<String> _collectMulti(XmlElement item, String name) {
    final out = <String>[];
    void scan(Iterable<XmlElement> els) {
      for (final el in els) {
        if (el.getAttribute('name') == name) {
          final v = el.getAttribute('value');
          if (v != null && v.isNotEmpty) out.add(v);
        }
      }
    }

    scan(item.findAllElements('torznab:attr'));
    scan(item.findAllElements('attr'));
    return out;
  }

  /// Heuristic file-list extractor. Different indexers expose this very
  /// differently, so we try a few shapes:
  ///
  /// 1. Repeated `<torznab:attr name="filename" value="...">` paired with
  ///    `<torznab:attr name="filesize" value="...">` (RARBG-style).
  /// 2. Single `<torznab:attr name="files">` whose value is an integer
  ///    file-count (no per-file detail).
  /// 3. Custom `<files>` child with nested `<file name=".." size="..">`.
  ///
  /// Returns an empty list when none match — UI hides the section then.
  static List<TorrentFile> _collectFiles(XmlElement item) {
    final names = _collectMulti(item, 'filename');
    if (names.isNotEmpty) {
      final sizes = _collectMulti(item, 'filesize');
      return [
        for (var i = 0; i < names.length; i++)
          TorrentFile(
            name: names[i],
            bytes: i < sizes.length ? int.tryParse(sizes[i]) : null,
          ),
      ];
    }
    final filesEl = item.findElements('files').firstOrNull;
    if (filesEl != null) {
      final out = <TorrentFile>[];
      for (final f in filesEl.findElements('file')) {
        final n = f.getAttribute('name') ?? f.innerText.trim();
        if (n.isEmpty) continue;
        out.add(
          TorrentFile(
            name: n,
            bytes: int.tryParse(f.getAttribute('size') ?? ''),
          ),
        );
      }
      if (out.isNotEmpty) return out;
    }
    return const [];
  }

  static DateTime? _tryParseRfc822(String input) {
    // Minimal RFC 822 parser for "Tue, 05 May 2026 14:23:00 +0000".
    try {
      const months = {
        'Jan': 1,
        'Feb': 2,
        'Mar': 3,
        'Apr': 4,
        'May': 5,
        'Jun': 6,
        'Jul': 7,
        'Aug': 8,
        'Sep': 9,
        'Oct': 10,
        'Nov': 11,
        'Dec': 12,
      };
      final parts = input.split(RegExp(r'\s+'));
      if (parts.length < 6) return null;
      // parts: [Day,, dd, Mon, yyyy, hh:mm:ss, +zzzz]
      final day = int.parse(parts[1]);
      final month = months[parts[2]];
      if (month == null) return null;
      final year = int.parse(parts[3]);
      final time = parts[4].split(':');
      final hour = int.parse(time[0]);
      final minute = int.parse(time[1]);
      final second = time.length > 2 ? int.parse(time[2]) : 0;
      return DateTime.utc(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }

  static String _describeDioError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return 'Auth failed (HTTP $status). Check your API key.';
    }
    if (status != null) {
      return 'Backend returned HTTP $status.';
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out.';
      case DioExceptionType.connectionError:
        return 'Cannot reach backend. Is the URL correct?';
      default:
        return e.message ?? 'Network error.';
    }
  }
}

class TorznabException implements Exception {
  const TorznabException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Internal marker for failures worth retrying. Never escapes [search] —
/// callers only ever see a plain [TorznabException].
class _TransientTorznabException extends TorznabException {
  const _TransientTorznabException(super.message);
}

/// One configured indexer as reported by Jackett's `/api/v2.0/indexers`.
class JackettIndexer {
  const JackettIndexer({
    required this.id,
    required this.name,
    this.type = '',
    this.description = '',
  });

  final String id;
  final String name;
  final String type;
  final String description;

  factory JackettIndexer.fromJson(Map<String, dynamic> json) => JackettIndexer(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? json['id'] ?? '').toString(),
    type: (json['type'] ?? '').toString(),
    description: (json['description'] ?? '').toString(),
  );
}

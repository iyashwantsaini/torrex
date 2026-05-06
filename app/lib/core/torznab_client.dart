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
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.plain,
        headers: {'Accept': 'application/xml,text/xml,*/*'},
      ),
    );
    return d;
  }

  final Dio _dio;

  /// Run a `t=search` query and parse the RSS/Torznab response.
  ///
  /// Throws [TorznabException] on any HTTP / parse / API error.
  Future<List<TorrentResult>> search({
    required String baseUrl,
    required String apiKey,
    required String query,
    String indexer = 'all',
    int limit = 100,
    bool extended = false,
  }) async {
    if (baseUrl == DemoResults.triggerUrl) {
      // Local preview / screenshot mode — no network call.
      return DemoResults.forQuery(query);
    }
    if (baseUrl.isEmpty) throw const TorznabException('Backend URL not set.');
    if (apiKey.isEmpty) throw const TorznabException('API key not set.');

    final url = _buildUrl(baseUrl, indexer);
    final Response<String> resp;
    try {
      resp = await _dio.get<String>(
        url,
        queryParameters: {
          'apikey': apiKey,
          't': 'search',
          'q': query,
          'limit': limit,
          if (extended) 'extended': 1,
        },
      );
    } on DioException catch (e) {
      throw TorznabException(_describeDioError(e));
    }

    final body = resp.data ?? '';
    if (body.isEmpty) return const [];

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
      throw TorznabException('Indexer error $code: $desc');
    }

    return doc.findAllElements('item').map(_parseItem).toList(growable: false);
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
    final category = text('category');

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
    final magnetUri = magnet.startsWith('magnet:')
        ? magnet
        : (link.startsWith('magnet:') ? link : '');
    final downloadUrl = link.startsWith('magnet:') ? '' : link;

    // Extended attributes (only present when the caller passed `extended=1`
    // AND the indexer supports them). All fall back to empty / empty list.
    final infoHash = torznabAttr('infohash') ?? '';
    final imdbId = torznabAttr('imdb') ?? torznabAttr('imdbid') ?? '';
    final tmdbId = torznabAttr('tmdb') ?? torznabAttr('tmdbid') ?? '';
    final tvdbId = torznabAttr('tvdb') ?? torznabAttr('tvdbid') ?? '';
    final coverUrl = torznabAttr('coverurl') ??
        torznabAttr('cover') ??
        torznabAttr('poster') ??
        '';

    final files = _collectFiles(item);
    final trackers = _collectMulti(item, 'tracker');

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
    );
  }

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
        out.add(TorrentFile(
          name: n,
          bytes: int.tryParse(f.getAttribute('size') ?? ''),
        ));
      }
      if (out.isNotEmpty) return out;
    }
    return const [];
  }

  static DateTime? _tryParseRfc822(String input) {
    // Minimal RFC 822 parser for "Tue, 05 May 2026 14:23:00 +0000".
    try {
      const months = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
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

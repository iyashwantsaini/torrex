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
    );
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

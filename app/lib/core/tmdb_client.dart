import 'package:dio/dio.dart';

/// Thin client for [The Movie Database](https://www.themoviedb.org/) v3 REST
/// API. Used only when the user has supplied a personal API key in
/// Settings — without one, every method short-circuits to `null` so the UI
/// can silently degrade.
///
/// The free TMDB key is generous (≈ 50 req/s) but it's still the user's
/// quota: every call must originate from the user's device, never our
/// backend.
class TmdbClient {
  TmdbClient({Dio? dio}) : _dio = dio ?? _defaultDio();

  static Dio _defaultDio() => Dio(
        BaseOptions(
          baseUrl: 'https://api.themoviedb.org/3',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          responseType: ResponseType.json,
        ),
      );

  static const String _imageBase = 'https://image.tmdb.org/t/p';

  /// Build a poster URL at the given width preset (`w92`, `w154`, `w185`,
  /// `w342`, `w500`, `w780`, `original`). Returns empty string when the
  /// path is missing so callers can guard with `.isEmpty`.
  static String posterUrl(String? path, {String size = 'w342'}) {
    if (path == null || path.isEmpty) return '';
    return '$_imageBase/$size$path';
  }

  /// Build a backdrop URL — same shape as [posterUrl] but tuned defaults.
  static String backdropUrl(String? path, {String size = 'w780'}) {
    if (path == null || path.isEmpty) return '';
    return '$_imageBase/$size$path';
  }

  final Dio _dio;

  /// Search by free-text query. Returns the best-matched movie OR TV show.
  /// Falls back to `null` on auth / network / no-result.
  Future<TmdbMedia?> searchBest({
    required String apiKey,
    required String query,
    TmdbMediaKind? kind,
  }) async {
    if (apiKey.isEmpty || query.trim().isEmpty) return null;
    final cleaned = _cleanReleaseTitle(query);
    if (cleaned.isEmpty) return null;
    try {
      final endpoint = switch (kind) {
        TmdbMediaKind.movie => '/search/movie',
        TmdbMediaKind.tv => '/search/tv',
        _ => '/search/multi',
      };
      final resp = await _dio.get<Map<String, dynamic>>(
        endpoint,
        queryParameters: {
          'api_key': apiKey,
          'query': cleaned,
          'include_adult': false,
        },
      );
      final results = (resp.data?['results'] as List?) ?? const [];
      if (results.isEmpty) return null;
      // Prefer items with both a poster AND vote_count >= 5 — protects
      // against TMDB's many low-quality entries that match anything.
      Map<String, dynamic>? pick;
      for (final r in results.whereType<Map<String, dynamic>>()) {
        if ((r['poster_path'] ?? '').toString().isEmpty) continue;
        if ((r['vote_count'] ?? 0) is num &&
            (r['vote_count'] as num) >= 5) {
          pick = r;
          break;
        }
      }
      pick ??= results.first as Map<String, dynamic>;
      return TmdbMedia.fromJson(pick);
    } on DioException {
      return null;
    }
  }

  /// Fetch full details (overview, runtime, episodes-count, etc.) for an
  /// already-identified media item.
  Future<TmdbMedia?> details({
    required String apiKey,
    required int id,
    required TmdbMediaKind kind,
  }) async {
    if (apiKey.isEmpty) return null;
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/${kind.endpoint}/$id',
        queryParameters: {'api_key': apiKey},
      );
      if (resp.data == null) return null;
      // Stamp the kind in so downstream rendering knows which fields to
      // pull (TV uses name + first_air_date, movies use title + release_date).
      final data = Map<String, dynamic>.from(resp.data!);
      data['__kind'] = kind.endpoint;
      return TmdbMedia.fromJson(data);
    } on DioException {
      return null;
    }
  }

  /// Episodes for a single TV season. Returns empty on failure.
  Future<List<TmdbEpisode>> seasonEpisodes({
    required String apiKey,
    required int tvId,
    required int seasonNumber,
  }) async {
    if (apiKey.isEmpty) return const [];
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/tv/$tvId/season/$seasonNumber',
        queryParameters: {'api_key': apiKey},
      );
      final list = (resp.data?['episodes'] as List?) ?? const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(TmdbEpisode.fromJson)
          .toList(growable: false);
    } on DioException {
      return const [];
    }
  }

  /// "What's hot right now" feed used by the Discover tab. `kind` selects
  /// movie/TV; window defaults to weekly.
  Future<List<TmdbMedia>> trending({
    required String apiKey,
    required TmdbMediaKind kind,
    String window = 'week',
  }) async {
    if (apiKey.isEmpty) return const [];
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/trending/${kind.endpoint}/$window',
        queryParameters: {'api_key': apiKey},
      );
      final results = (resp.data?['results'] as List?) ?? const [];
      return results
          .whereType<Map<String, dynamic>>()
          .map((j) {
            final tagged = Map<String, dynamic>.from(j)
              ..['__kind'] = kind.endpoint;
            return TmdbMedia.fromJson(tagged);
          })
          .toList(growable: false);
    } on DioException {
      return const [];
    }
  }

  /// User-driven catalog search. Unlike [searchBest] this returns the full
  /// page of results (capped at TMDB's default 20). Empty list on any
  /// error so the UI can render an empty state.
  Future<List<TmdbMedia>> search({
    required String apiKey,
    required String query,
    required TmdbMediaKind kind,
  }) async {
    if (apiKey.isEmpty || query.trim().isEmpty) return const [];
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/search/${kind.endpoint}',
        queryParameters: {
          'api_key': apiKey,
          'query': query.trim(),
          'include_adult': 'false',
        },
      );
      final results = (resp.data?['results'] as List?) ?? const [];
      return results
          .whereType<Map<String, dynamic>>()
          .map((j) {
            final tagged = Map<String, dynamic>.from(j)
              ..['__kind'] = kind.endpoint;
            return TmdbMedia.fromJson(tagged);
          })
          .toList(growable: false);
    } on DioException {
      return const [];
    }
  }

  /// Strip common torrent release-name junk so TMDB sees a clean title.
  /// This is the same heuristic Jackett uses internally — kept simple
  /// rather than hauling in a parser dependency.
  static String _cleanReleaseTitle(String raw) {
    var s = raw;
    // Strip year and everything after — TMDB queries match better without.
    s = s.replaceAll(
        RegExp(r'\b(19|20)\d{2}\b.*'), '');
    // Strip resolution + codec + source tags.
    s = s.replaceAll(
        RegExp(
            r'\b(720p|1080p|2160p|4k|x264|x265|h264|h265|hevc|aac|dts|bluray|blu-ray|webrip|web-dl|hdrip|brrip|dvdrip|amzn|nf|hulu|ddp?5\.1)\b',
            caseSensitive: false),
        '');
    // Strip parens / brackets contents.
    s = s.replaceAll(RegExp(r'[\[(].*?[\])]'), '');
    // Strip release group suffix (-GROUP at the end).
    s = s.replaceAll(RegExp(r'-[A-Za-z0-9]+$'), '');
    // Collapse separators.
    s = s.replaceAll(RegExp(r'[._]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.trim();
  }
}

enum TmdbMediaKind {
  movie('movie'),
  tv('tv');

  const TmdbMediaKind(this.endpoint);
  final String endpoint;

  static TmdbMediaKind? parse(String? value) => switch (value) {
        'movie' => TmdbMediaKind.movie,
        'tv' => TmdbMediaKind.tv,
        _ => null,
      };
}

/// Lightweight projection of a TMDB movie / tv item — only the fields the
/// UI actually renders. Source JSON has many more.
class TmdbMedia {
  const TmdbMedia({
    required this.id,
    required this.kind,
    required this.title,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.year,
    this.voteAverage = 0,
    this.voteCount = 0,
    this.runtimeMinutes,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.seasons = const [],
    this.genres = const [],
  });

  final int id;
  final TmdbMediaKind kind;
  final String title;
  final String overview;
  final String posterPath;
  final String backdropPath;
  final String year;
  final double voteAverage;
  final int voteCount;
  final int? runtimeMinutes;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;
  final List<TmdbSeason> seasons;
  final List<String> genres;

  factory TmdbMedia.fromJson(Map<String, dynamic> json) {
    // Detect the kind: explicit first (passed via `__kind` or
    // `media_type` from /search/multi), otherwise infer from fields.
    final tag = (json['__kind'] ?? json['media_type'] ?? '').toString();
    final inferred = tag == 'tv' ||
            json.containsKey('first_air_date') ||
            json.containsKey('number_of_seasons')
        ? TmdbMediaKind.tv
        : TmdbMediaKind.movie;

    final title = (json['title'] ?? json['name'] ?? '').toString();
    final dateStr =
        (json['release_date'] ?? json['first_air_date'] ?? '').toString();
    final year = dateStr.length >= 4 ? dateStr.substring(0, 4) : '';

    final genreList = <String>[];
    final genres = json['genres'];
    if (genres is List) {
      for (final g in genres.whereType<Map<String, dynamic>>()) {
        final n = (g['name'] ?? '').toString();
        if (n.isNotEmpty) genreList.add(n);
      }
    }

    final seasonList = <TmdbSeason>[];
    final seasons = json['seasons'];
    if (seasons is List) {
      for (final s in seasons.whereType<Map<String, dynamic>>()) {
        seasonList.add(TmdbSeason.fromJson(s));
      }
    }

    return TmdbMedia(
      id: (json['id'] is num) ? (json['id'] as num).toInt() : 0,
      kind: inferred,
      title: title,
      overview: (json['overview'] ?? '').toString(),
      posterPath: (json['poster_path'] ?? '').toString(),
      backdropPath: (json['backdrop_path'] ?? '').toString(),
      year: year,
      voteAverage: (json['vote_average'] is num)
          ? (json['vote_average'] as num).toDouble()
          : 0,
      voteCount:
          (json['vote_count'] is num) ? (json['vote_count'] as num).toInt() : 0,
      runtimeMinutes: (json['runtime'] is num)
          ? (json['runtime'] as num).toInt()
          : null,
      numberOfSeasons: (json['number_of_seasons'] is num)
          ? (json['number_of_seasons'] as num).toInt()
          : null,
      numberOfEpisodes: (json['number_of_episodes'] is num)
          ? (json['number_of_episodes'] as num).toInt()
          : null,
      seasons: seasonList,
      genres: genreList,
    );
  }
}

class TmdbSeason {
  const TmdbSeason({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.posterPath = '',
  });

  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String posterPath;

  factory TmdbSeason.fromJson(Map<String, dynamic> json) => TmdbSeason(
        seasonNumber: (json['season_number'] is num)
            ? (json['season_number'] as num).toInt()
            : 0,
        name: (json['name'] ?? '').toString(),
        episodeCount: (json['episode_count'] is num)
            ? (json['episode_count'] as num).toInt()
            : 0,
        posterPath: (json['poster_path'] ?? '').toString(),
      );
}

class TmdbEpisode {
  const TmdbEpisode({
    required this.episodeNumber,
    required this.name,
    required this.overview,
    required this.airDate,
    this.stillPath = '',
  });

  final int episodeNumber;
  final String name;
  final String overview;
  final String airDate;
  final String stillPath;

  factory TmdbEpisode.fromJson(Map<String, dynamic> json) => TmdbEpisode(
        episodeNumber: (json['episode_number'] is num)
            ? (json['episode_number'] as num).toInt()
            : 0,
        name: (json['name'] ?? '').toString(),
        overview: (json['overview'] ?? '').toString(),
        airDate: (json['air_date'] ?? '').toString(),
        stillPath: (json['still_path'] ?? '').toString(),
      );
}

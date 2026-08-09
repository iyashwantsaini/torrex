import '../models/torrent_result.dart';
import 'release_parser.dart';

/// Top-level Torznab category buckets, matching what mainstream torrent
/// sites put in their nav bar.
///
/// Torznab reserves 1000-blocks per type; we map the block to a bucket and
/// fall back to keyword-matching the human-readable category string that
/// most Jackett indexers also emit.
enum TorrentCategory {
  movies('Movies', 2000),
  tv('TV', 5000),
  anime('Anime', 5070),
  music('Music', 3000),
  games('Games', 1000),
  apps('Apps', 4000),
  books('Books', 7000),
  xxx('XXX', 6000),
  other('Other', 8000);

  const TorrentCategory(this.label, this.torznabId);

  final String label;

  /// The id Torrex sends as `&cat=` when the user narrows the *server-side*
  /// search to this bucket.
  final int torznabId;

  /// Buckets offered in the filter bar, in display order. `xxx` is last on
  /// purpose and `other` is intentionally excluded from server-side search.
  static const List<TorrentCategory> pickable = [
    movies,
    tv,
    anime,
    music,
    games,
    apps,
    books,
    xxx,
  ];
}

/// Classify a result from its Torznab category blob + release name.
TorrentCategory? categorize(TorrentResult r) {
  final c = r.category.toLowerCase();

  // 1. Numeric Torznab ids are the most reliable signal. Check the
  //    narrowest ranges first (anime and XXX live inside the TV/other
  //    blocks on some indexers).
  for (final id in _numericIds(c)) {
    if (id >= 5070 && id <= 5079) return TorrentCategory.anime;
    if (id >= 6000 && id < 7000) return TorrentCategory.xxx;
    if (id >= 2000 && id < 3000) return TorrentCategory.movies;
    if (id >= 5000 && id < 6000) return TorrentCategory.tv;
    if (id >= 3000 && id < 4000) return TorrentCategory.music;
    if (id >= 1000 && id < 2000) return TorrentCategory.games;
    if (id >= 4000 && id < 5000) {
      // 4050 = PC/Games, 4060 = PC/Mac-games on most indexers.
      if (id == 4050 || id == 4060) return TorrentCategory.games;
      return TorrentCategory.apps;
    }
    if (id >= 7000 && id < 8000) return TorrentCategory.books;
  }

  // 2. Human strings ("Video/HD", "Anime/Raw", "Applications/Windows").
  final info = r.release;
  if (c.contains('anime')) return TorrentCategory.anime;
  if (c.contains('xxx') || c.contains('adult') || c.contains('porn')) {
    return TorrentCategory.xxx;
  }
  if (c.contains('tv') || c.contains('show') || c.contains('series')) {
    return TorrentCategory.tv;
  }
  // "Video" is the generic bucket several indexers use for both films and
  // episodes — let the release name break the tie.
  if (c.contains('movie') || c.contains('film') || c.contains('video')) {
    return info.season != null ? TorrentCategory.tv : TorrentCategory.movies;
  }
  if (c.contains('music') || c.contains('audio') || c.contains('flac')) {
    return TorrentCategory.music;
  }
  if (c.contains('game') || c.contains('console')) return TorrentCategory.games;
  if (c.contains('app') || c.contains('software') || c.contains('pc/')) {
    return TorrentCategory.apps;
  }
  if (c.contains('book') ||
      c.contains('ebook') ||
      c.contains('comic') ||
      c.contains('audiobook')) {
    return TorrentCategory.books;
  }

  // 3. Last resort — infer from the release name, but *only* when the
  //    indexer gave us no category at all. A category we simply don't
  //    recognise ("OS / Linux", "Data / Archive") is far better answered
  //    with `other` than guessed at from the title, which used to file
  //    Linux ISOs under Movies.
  if (c.isEmpty) {
    if (info.season != null) return TorrentCategory.tv;
    if (info.resolution != null || info.source != null) {
      return TorrentCategory.movies;
    }
    return null;
  }
  return TorrentCategory.other;
}

Iterable<int> _numericIds(String category) sync* {
  for (final m in RegExp(r'\b(\d{4,5})\b').allMatches(category)) {
    final v = int.tryParse(m.group(1)!);
    if (v != null) yield v;
  }
}

/// How the result list is ordered.
enum SortBy {
  relevance('Relevance'),
  seeders('Seeders'),
  leechers('Leechers'),
  size('Size'),
  date('Date'),
  quality('Quality');

  const SortBy(this.label);
  final String label;
}

/// Client-side filter state. Immutable — the search page swaps whole
/// instances so `setState` diffs stay trivial and the "reset" path is a
/// single assignment.
class SearchFilters {
  const SearchFilters({
    this.indexers = const {},
    this.categories = const {},
    this.resolutions = const {},
    this.sources = const {},
    this.codecs = const {},
    this.languages = const {},
    this.minSeeders = 0,
    this.minSizeBytes,
    this.maxSizeBytes,
    this.magnetOnly = false,
    this.hdrOnly = false,
    this.excludeXxx = true,
    this.excludeTerms = '',
    this.sortBy = SortBy.seeders,
    this.descending = true,
    this.dedupe = true,
  });

  /// Empty set = "all". Non-empty = show only these.
  final Set<String> indexers;
  final Set<TorrentCategory> categories;
  final Set<Resolution> resolutions;
  final Set<Source> sources;
  final Set<Codec> codecs;
  final Set<String> languages;

  final int minSeeders;
  final int? minSizeBytes;
  final int? maxSizeBytes;
  final bool magnetOnly;
  final bool hdrOnly;

  /// Hide adult results unless the user opts in. Mirrors the "safe mode"
  /// toggle mainstream sites default to on.
  final bool excludeXxx;

  /// Space/comma separated words; a result is dropped if its title
  /// contains any of them (case-insensitive).
  final String excludeTerms;

  final SortBy sortBy;
  final bool descending;

  /// Collapse the same torrent (matched by info-hash, else by a normalised
  /// title+size key) reported by several indexers into one row.
  final bool dedupe;

  SearchFilters copyWith({
    Set<String>? indexers,
    Set<TorrentCategory>? categories,
    Set<Resolution>? resolutions,
    Set<Source>? sources,
    Set<Codec>? codecs,
    Set<String>? languages,
    int? minSeeders,
    int? Function()? minSizeBytes,
    int? Function()? maxSizeBytes,
    bool? magnetOnly,
    bool? hdrOnly,
    bool? excludeXxx,
    String? excludeTerms,
    SortBy? sortBy,
    bool? descending,
    bool? dedupe,
  }) {
    return SearchFilters(
      indexers: indexers ?? this.indexers,
      categories: categories ?? this.categories,
      resolutions: resolutions ?? this.resolutions,
      sources: sources ?? this.sources,
      codecs: codecs ?? this.codecs,
      languages: languages ?? this.languages,
      minSeeders: minSeeders ?? this.minSeeders,
      minSizeBytes: minSizeBytes == null ? this.minSizeBytes : minSizeBytes(),
      maxSizeBytes: maxSizeBytes == null ? this.maxSizeBytes : maxSizeBytes(),
      magnetOnly: magnetOnly ?? this.magnetOnly,
      hdrOnly: hdrOnly ?? this.hdrOnly,
      excludeXxx: excludeXxx ?? this.excludeXxx,
      excludeTerms: excludeTerms ?? this.excludeTerms,
      sortBy: sortBy ?? this.sortBy,
      descending: descending ?? this.descending,
      dedupe: dedupe ?? this.dedupe,
    );
  }

  /// Number of *narrowing* filters currently applied. Drives the badge on
  /// the "Filters" button — sort order and dedupe don't count because they
  /// don't hide anything.
  int get activeCount =>
      (indexers.isEmpty ? 0 : 1) +
      (categories.isEmpty ? 0 : 1) +
      (resolutions.isEmpty ? 0 : 1) +
      (sources.isEmpty ? 0 : 1) +
      (codecs.isEmpty ? 0 : 1) +
      (languages.isEmpty ? 0 : 1) +
      (minSeeders > 0 ? 1 : 0) +
      (minSizeBytes != null ? 1 : 0) +
      (maxSizeBytes != null ? 1 : 0) +
      (magnetOnly ? 1 : 0) +
      (hdrOnly ? 1 : 0) +
      (excludeTerms.trim().isEmpty ? 0 : 1);

  bool get isPristine => activeCount == 0;

  /// Reset every narrowing filter but keep the user's sort / dedupe /
  /// safe-mode preferences — those are "settings", not "a query".
  SearchFilters cleared() => SearchFilters(
    excludeXxx: excludeXxx,
    sortBy: sortBy,
    descending: descending,
    dedupe: dedupe,
  );
}

/// Applies [filters] to [source] and returns a new, sorted list.
///
/// Pure function so it can be unit-tested without a widget tree.
List<TorrentResult> applyFilters(
  List<TorrentResult> source,
  SearchFilters f, {
  String query = '',
}) {
  final excluded = f.excludeTerms
      .toLowerCase()
      .split(RegExp(r'[,\s]+'))
      .where((t) => t.isNotEmpty)
      .toList(growable: false);

  var out = <TorrentResult>[];
  for (final r in source) {
    if (f.indexers.isNotEmpty && !f.indexers.contains(r.indexer)) continue;

    final cat = categorize(r);
    if (f.categories.isNotEmpty && !f.categories.contains(cat)) continue;
    // Safe mode only bites when the user hasn't explicitly asked for XXX.
    if (f.excludeXxx &&
        cat == TorrentCategory.xxx &&
        !f.categories.contains(TorrentCategory.xxx)) {
      continue;
    }

    if (r.seeders < f.minSeeders) continue;
    if (f.magnetOnly && !r.hasMagnet) continue;

    final min = f.minSizeBytes;
    final max = f.maxSizeBytes;
    // Treat a zero/unknown size as "unfiltered" rather than dropping it —
    // several indexers omit <size> entirely.
    if (r.sizeBytes > 0) {
      if (min != null && r.sizeBytes < min) continue;
      if (max != null && r.sizeBytes > max) continue;
    }

    final info = r.release;
    if (f.resolutions.isNotEmpty &&
        (info.resolution == null || !f.resolutions.contains(info.resolution))) {
      continue;
    }
    if (f.sources.isNotEmpty &&
        (info.source == null || !f.sources.contains(info.source))) {
      continue;
    }
    if (f.codecs.isNotEmpty &&
        (info.codec == null || !f.codecs.contains(info.codec))) {
      continue;
    }
    if (f.languages.isNotEmpty &&
        info.languages.intersection(f.languages).isEmpty) {
      continue;
    }
    if (f.hdrOnly && !info.hasHdr) continue;

    if (excluded.isNotEmpty) {
      final lower = r.title.toLowerCase();
      if (excluded.any(lower.contains)) continue;
    }

    out.add(r);
  }

  if (f.dedupe) out = dedupeResults(out);
  _sort(out, f, query);
  return out;
}

/// Collapse duplicates that several indexers reported for the same
/// torrent. The surviving row keeps the highest seeder count and records
/// how many indexers carried it (rendered as a "×3" badge, exactly like
/// the "N sources" column on aggregator sites).
List<TorrentResult> dedupeResults(List<TorrentResult> input) {
  final byKey = <String, TorrentResult>{};
  final order = <String>[];
  for (final r in input) {
    final key = _dedupeKey(r);
    final existing = byKey[key];
    if (existing == null) {
      byKey[key] = r.withSources({if (r.indexer.isNotEmpty) r.indexer});
      order.add(key);
      continue;
    }
    // Keep whichever copy is richer: prefer a magnet, then more seeders.
    final keepNew =
        (r.hasMagnet && !existing.hasMagnet) ||
        (r.hasMagnet == existing.hasMagnet && r.seeders > existing.seeders);
    final merged = (keepNew ? r : existing).withSources({
      ...existing.sourceIndexers,
      if (r.indexer.isNotEmpty) r.indexer,
    });
    byKey[key] = merged.copyWithSwarm(
      seeders: existing.seeders > r.seeders ? existing.seeders : r.seeders,
      leechers: existing.leechers > r.leechers ? existing.leechers : r.leechers,
    );
  }
  return [for (final k in order) byKey[k]!];
}

String _dedupeKey(TorrentResult r) {
  if (r.infoHash.length >= 32) return 'h:${r.infoHash.toLowerCase()}';
  final magnetHash = _hashFromMagnet(r.magnetUri);
  if (magnetHash != null) return 'h:$magnetHash';
  // No hash anywhere — fall back to normalised title + size rounded to the
  // nearest MiB (indexers disagree on the last few bytes).
  final t = r.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return 't:$t:${r.sizeBytes ~/ (1024 * 1024)}';
}

String? _hashFromMagnet(String magnet) {
  if (!magnet.startsWith('magnet:')) return null;
  final m = RegExp(r'xt=urn:btih:([A-Za-z0-9]{32,40})').firstMatch(magnet);
  return m?.group(1)?.toLowerCase();
}

void _sort(List<TorrentResult> list, SearchFilters f, String query) {
  final dir = f.descending ? 1 : -1;
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  int cmp(TorrentResult a, TorrentResult b) {
    switch (f.sortBy) {
      case SortBy.seeders:
        return b.seeders.compareTo(a.seeders);
      case SortBy.leechers:
        return b.leechers.compareTo(a.leechers);
      case SortBy.size:
        return b.sizeBytes.compareTo(a.sizeBytes);
      case SortBy.date:
        return (b.publishDate ?? epoch).compareTo(a.publishDate ?? epoch);
      case SortBy.quality:
        return _qualityScore(b).compareTo(_qualityScore(a));
      case SortBy.relevance:
        final rb = _relevance(b, query);
        final ra = _relevance(a, query);
        final byScore = rb.compareTo(ra);
        return byScore != 0 ? byScore : b.seeders.compareTo(a.seeders);
    }
  }

  list.sort((a, b) {
    final primary = cmp(a, b) * dir;
    if (primary != 0) return primary;
    // Stable, meaningful tiebreak so equal rows don't shuffle between
    // rebuilds (a real bug users perceive as "the list keeps jumping").
    final bySeeders = b.seeders.compareTo(a.seeders);
    return bySeeders != 0 ? bySeeders : a.title.compareTo(b.title);
  });
}

/// Composite "how good is this release" score used by [SortBy.quality].
int _qualityScore(TorrentResult r) {
  final i = r.release;
  var score = 0;
  score += (i.resolution?.index ?? 0) * 100;
  score += (i.source?.index ?? 0) * 10;
  if (i.codec == Codec.h265 || i.codec == Codec.av1) score += 5;
  if (i.hasHdr) score += 8;
  if (i.audio.contains(AudioFormat.atmos)) score += 3;
  if (i.isProper || i.isRepack) score += 2;
  // A pristine release nobody seeds is useless — keep swarm in the mix.
  score += r.seeders.clamp(0, 200) ~/ 20;
  return score;
}

/// Token-overlap relevance against the user's query, biased by swarm size.
/// Deliberately simple: Torznab already did the real matching server-side,
/// this just floats exact-ish titles above loosely-related noise.
int _relevance(TorrentResult r, String query) {
  final q = query.toLowerCase().trim();
  if (q.isEmpty) return r.seeders;
  final title = r.title.toLowerCase();
  var score = 0;
  if (title.contains(q)) score += 60;
  final tokens = q.split(RegExp(r'\s+')).where((t) => t.length > 1);
  var matched = 0;
  var total = 0;
  for (final t in tokens) {
    total++;
    if (title.contains(t)) matched++;
  }
  if (total > 0) score += (matched * 40) ~/ total;
  if (r.release.cleanTitle.toLowerCase() == q) score += 25;
  return score * 1000 + r.seeders.clamp(0, 999);
}

/// Per-indexer result counts for the filter bar, ordered by count desc.
List<({String indexer, int count})> indexerFacets(List<TorrentResult> all) {
  final counts = <String, int>{};
  for (final r in all) {
    if (r.indexer.isEmpty) continue;
    counts[r.indexer] = (counts[r.indexer] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  return [for (final e in entries) (indexer: e.key, count: e.value)];
}

/// Per-category result counts for the category filter row.
List<({TorrentCategory category, int count})> categoryFacets(
  List<TorrentResult> all,
) {
  final counts = <TorrentCategory, int>{};
  for (final r in all) {
    final c = categorize(r);
    if (c == null) continue;
    counts[c] = (counts[c] ?? 0) + 1;
  }
  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.index.compareTo(b.key.index);
    });
  return [for (final e in entries) (category: e.key, count: e.value)];
}

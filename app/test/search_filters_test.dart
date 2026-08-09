import 'package:flutter_test/flutter_test.dart';
import 'package:torrex/core/release_parser.dart';
import 'package:torrex/core/search_filters.dart';
import 'package:torrex/models/torrent_result.dart';

TorrentResult _r({
  String title = 'Some Movie 2024 1080p WEB-DL x264-GRP',
  String indexer = 'idx',
  int size = 1024 * 1024 * 1024,
  int seeders = 10,
  int leechers = 2,
  String? magnet,
  String infoHash = '',
  String category = '2000',
  DateTime? published,
}) {
  // Derive a unique-per-title hash by default so the dedupe pass doesn't
  // silently collapse unrelated fixtures. Pass `magnet: ''` for a result
  // with no magnet at all.
  final stem = title.hashCode
      .toUnsigned(32)
      .toRadixString(16)
      .padLeft(8, '0')
      .toUpperCase();
  return TorrentResult(
    title: title,
    indexer: indexer,
    sizeBytes: size,
    seeders: seeders,
    leechers: leechers,
    publishDate: published,
    magnetUri: magnet ?? 'magnet:?xt=urn:btih:${stem * 5}',
    downloadUrl: '',
    detailsUrl: '',
    category: category,
    infoHash: infoHash,
    sourceIndexers: indexer.isEmpty ? const {} : {indexer},
  );
}

void main() {
  group('categorize', () {
    test('maps numeric torznab ids to buckets', () {
      expect(categorize(_r(category: '2040')), TorrentCategory.movies);
      expect(categorize(_r(category: '5030')), TorrentCategory.tv);
      expect(categorize(_r(category: '5070')), TorrentCategory.anime);
      expect(categorize(_r(category: '3010')), TorrentCategory.music);
      expect(categorize(_r(category: '6010')), TorrentCategory.xxx);
      expect(categorize(_r(category: '4050')), TorrentCategory.games);
      expect(categorize(_r(category: '4020')), TorrentCategory.apps);
      expect(categorize(_r(category: '7020')), TorrentCategory.books);
    });

    test('falls back to the human category string', () {
      expect(categorize(_r(category: 'Video/Movies')), TorrentCategory.movies);
      expect(categorize(_r(category: 'Anime/Raw')), TorrentCategory.anime);
      expect(
        categorize(_r(category: 'Applications/Windows')),
        TorrentCategory.apps,
      );
    });

    test('generic "Video" splits on the release name', () {
      expect(
        categorize(_r(category: 'Video / CC', title: 'Sintel 2160p HDR')),
        TorrentCategory.movies,
      );
      expect(
        categorize(_r(category: 'Video / CC', title: 'Some Show S02E01')),
        TorrentCategory.tv,
      );
    });

    test('unrecognised categories are Other, not guessed from the title', () {
      // Regression: 'OS / Linux' used to fall through to release-name
      // inference and file Linux distro torrents under Movies.
      expect(
        categorize(_r(category: 'OS / Linux', title: 'Ubuntu 26.04 LTS ISO')),
        TorrentCategory.other,
      );
      expect(
        categorize(_r(category: 'Data / Archive', title: 'Wikipedia dump')),
        TorrentCategory.other,
      );
    });

    test('an absent category still infers from the release name', () {
      expect(
        categorize(_r(category: '', title: 'Movie 2024 1080p WEB-DL')),
        TorrentCategory.movies,
      );
      expect(
        categorize(_r(category: '', title: 'Show S01E03 720p')),
        TorrentCategory.tv,
      );
      expect(categorize(_r(category: '', title: 'random blob')), isNull);
    });
  });

  group('applyFilters', () {
    final all = [
      _r(title: 'Movie 2024 2160p BluRay x265-A', seeders: 100, indexer: 'a'),
      _r(title: 'Movie 2024 1080p WEB-DL x264-B', seeders: 50, indexer: 'b'),
      _r(title: 'Movie 2024 720p HDTV XviD-C', seeders: 5, indexer: 'a'),
      _r(title: 'Movie 2024 CAM x264-D', seeders: 1, indexer: 'c', magnet: ''),
    ];

    test('filters by indexer', () {
      final out = applyFilters(all, const SearchFilters(indexers: {'a'}));
      expect(out, hasLength(2));
      expect(out.every((r) => r.indexer == 'a'), isTrue);
    });

    test('duplicate info-hashes across indexers collapse into one row', () {
      final dupes = [
        _r(title: 'Same Movie 2024 1080p', indexer: 'a', infoHash: 'DEAD01'),
        _r(title: 'Same Movie 2024 1080p', indexer: 'b', infoHash: 'dead01'),
      ];
      expect(applyFilters(dupes, const SearchFilters()), hasLength(1));
      expect(
        applyFilters(dupes, const SearchFilters(dedupe: false)),
        hasLength(2),
      );
    });

    test('filters by resolution', () {
      final out = applyFilters(
        all,
        const SearchFilters(resolutions: {Resolution.p2160}),
      );
      expect(out, hasLength(1));
      expect(out.single.title, contains('2160p'));
    });

    test('filters by minimum seeders', () {
      expect(
        applyFilters(all, const SearchFilters(minSeeders: 25)),
        hasLength(2),
      );
    });

    test('magnet-only drops link-less results', () {
      final out = applyFilters(all, const SearchFilters(magnetOnly: true));
      expect(out, hasLength(3));
    });

    test('exclude terms are case-insensitive and space/comma separated', () {
      final out = applyFilters(
        all,
        const SearchFilters(excludeTerms: 'cam, xvid'),
      );
      expect(out, hasLength(2));
    });

    test('sorts by seeders descending by default', () {
      final out = applyFilters(all, const SearchFilters());
      expect(out.first.seeders, 100);
      expect(out.last.seeders, 1);
    });

    test('honours ascending direction', () {
      final out = applyFilters(all, const SearchFilters(descending: false));
      expect(out.first.seeders, 1);
    });

    test('quality sort puts the best release first', () {
      final out = applyFilters(
        all,
        const SearchFilters(sortBy: SortBy.quality),
      );
      expect(out.first.title, contains('2160p'));
    });

    test('safe mode hides XXX unless explicitly requested', () {
      final adult = [..._all(), _r(title: 'Adult Thing', category: '6010')];
      expect(applyFilters(adult, const SearchFilters()), hasLength(1));
      expect(
        applyFilters(
          adult,
          const SearchFilters(categories: {TorrentCategory.xxx}),
        ),
        hasLength(1),
      );
    });

    test('activeCount ignores sort and dedupe preferences', () {
      const f = SearchFilters(sortBy: SortBy.size, dedupe: false);
      expect(f.activeCount, 0);
      expect(f.isPristine, isTrue);
      expect(const SearchFilters(minSeeders: 5).activeCount, 1);
    });

    test('cleared() keeps sort/safe-mode but drops narrowing filters', () {
      const f = SearchFilters(
        minSeeders: 20,
        indexers: {'a'},
        sortBy: SortBy.date,
        excludeXxx: false,
      );
      final c = f.cleared();
      expect(c.minSeeders, 0);
      expect(c.indexers, isEmpty);
      expect(c.sortBy, SortBy.date);
      expect(c.excludeXxx, isFalse);
    });
  });

  group('dedupeResults', () {
    test('merges the same info-hash across indexers', () {
      final merged = dedupeResults([
        _r(indexer: 'a', infoHash: 'ABC123', seeders: 10),
        _r(indexer: 'b', infoHash: 'abc123', seeders: 40),
      ]);
      expect(merged, hasLength(1));
      expect(merged.single.seeders, 40);
      expect(merged.single.sourceIndexers, containsAll(['a', 'b']));
    });

    test('merges by normalised title + size when no hash exists', () {
      final merged = dedupeResults([
        _r(indexer: 'a', magnet: '', title: 'The.Thing.1982.1080p'),
        _r(indexer: 'b', magnet: '', title: 'The Thing 1982 1080p'),
      ]);
      expect(merged, hasLength(1));
    });

    test('keeps genuinely different torrents apart', () {
      final merged = dedupeResults([
        _r(indexer: 'a', magnet: '', title: 'A', size: 1),
        _r(indexer: 'b', magnet: '', title: 'B', size: 2),
      ]);
      expect(merged, hasLength(2));
    });
  });

  group('facets', () {
    test('indexerFacets counts and orders by frequency', () {
      final facets = indexerFacets([
        _r(indexer: 'a'),
        _r(indexer: 'b'),
        _r(indexer: 'a'),
      ]);
      expect(facets.first.indexer, 'a');
      expect(facets.first.count, 2);
      expect(facets.last.count, 1);
    });

    test('categoryFacets skips uncategorised results', () {
      final facets = categoryFacets([
        _r(category: '2000'),
        _r(category: '2000'),
        _r(category: '5000'),
      ]);
      expect(facets.first.category, TorrentCategory.movies);
      expect(facets.first.count, 2);
    });
  });

  group('TorrentResult health', () {
    test('dead torrents score zero', () {
      expect(_r(seeders: 0).health, 0);
      expect(_r(seeders: 0).healthLabel, 'Dead');
    });

    test('health grows with seeders and stays within 0..1', () {
      final weak = _r(seeders: 2).health;
      final strong = _r(seeders: 800).health;
      expect(weak, lessThan(strong));
      expect(strong, lessThanOrEqualTo(1.0));
      expect(weak, greaterThan(0));
    });
  });
}

List<TorrentResult> _all() => [_r(title: 'Normal Movie 2024 1080p')];

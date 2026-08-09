import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrex/core/release_parser.dart';
import 'package:torrex/core/search_filters.dart';
import 'package:torrex/features/search/filter_sheet.dart';
import 'package:torrex/features/search/result_card.dart';
import 'package:torrex/models/torrent_result.dart';
import 'package:wolwoloom/wolwoloom.dart';

/// WlmChip renders its label uppercased, so finders must match that.
Finder chip(String label) => find.text(label.toUpperCase());

void main() {
  group('showFilterSheet', () {
    testWidgets('Apply returns the edited filters', (tester) async {
      SearchFilters? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: WlmTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await showFilterSheet(
                      context: context,
                      current: const SearchFilters(),
                      availableIndexers: const ['alpha', 'beta'],
                      availableLanguages: const ['HINDI'],
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(chip('1080p'));
      await tester.pump();
      await tester.tap(chip('x265'));
      await tester.pump();
      await tester.tap(find.text('APPLY'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.resolutions, {Resolution.p1080});
      expect(result!.codecs, {Codec.h265});
      expect(result!.activeCount, 2);
    });

    testWidgets('Cancel discards the edits', (tester) async {
      SearchFilters? result;
      var called = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: WlmTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await showFilterSheet(
                      context: context,
                      current: const SearchFilters(),
                      availableIndexers: const [],
                      availableLanguages: const [],
                    );
                    called = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(chip('1080p'));
      await tester.pump();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
      expect(result, isNull);
    });

    testWidgets('pre-selects the filters it was opened with', (tester) async {
      // Tall surface so the whole sheet is laid out — the section list is a
      // lazy ListView, so off-screen sections are never built.
      tester.view.physicalSize = const Size(400 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: WlmTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showFilterSheet(
                    context: context,
                    current: const SearchFilters(resolutions: {
                      Resolution.p2160,
                    }),
                    availableIndexers: const ['alpha'],
                    availableLanguages: const ['HINDI'],
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Reset is only offered once something is actually narrowing, so its
      // presence proves the incoming filters were adopted.
      expect(find.text('RESET'), findsOneWidget);
      // Language and indexer sections only render when options were passed.
      expect(chip('Hindi'), findsOneWidget);
      expect(chip('alpha'), findsOneWidget);
    });
  });

  group('ResultCard', () {
    TorrentResult sample({
      String title = 'Dune Part Two 2024 2160p WEB-DL x265 HDR-GRP',
      int seeders = 120,
      Set<String> sources = const {'alpha'},
    }) {
      return TorrentResult(
        title: title,
        indexer: 'alpha',
        sizeBytes: 8 * 1024 * 1024 * 1024,
        seeders: seeders,
        leechers: 12,
        publishDate: DateTime.now().subtract(const Duration(days: 2)),
        magnetUri: 'magnet:?xt=urn:btih:'
            'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        downloadUrl: '',
        detailsUrl: '',
        category: '2000',
        sourceIndexers: sources,
      );
    }

    Future<void> pumpCard(WidgetTester tester, TorrentResult r) {
      return tester.pumpWidget(
        MaterialApp(
          theme: WlmTheme.dark(),
          home: Scaffold(
            body: ListView(
              children: [
                ResultCard(
                  result: r,
                  chipIds: const ['seeders', 'size', 'age'],
                  onTap: (_) {},
                  onOpen: (_) {},
                  onCopy: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('renders parsed quality badges', (tester) async {
      await pumpCard(tester, sample());
      expect(find.text('4K'), findsOneWidget);
      expect(find.text('WEB-DL'), findsOneWidget);
      expect(find.text('x265'), findsOneWidget);
      expect(find.text('HDR'), findsOneWidget);
    });

    testWidgets('shows a multi-source badge when deduped', (tester) async {
      await pumpCard(tester, sample(sources: {'alpha', 'beta', 'gamma'}));
      expect(find.text('+2 sources'), findsOneWidget);
    });

    testWidgets('does not show a source badge for a single indexer',
        (tester) async {
      await pumpCard(tester, sample());
      expect(find.textContaining('source'), findsNothing);
    });

    testWidgets('lays out without overflow on a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpCard(tester, sample(title: 'A ' * 60));
      expect(tester.takeException(), isNull);
    });
  });
}

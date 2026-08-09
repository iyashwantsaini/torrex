import 'package:flutter_test/flutter_test.dart';
import 'package:torrex/features/discover/discover_page.dart';

void main() {
  group('discoverGridColumns', () {
    test('phones get a two-up grid', () {
      expect(discoverGridColumns(320), 2);
      expect(discoverGridColumns(390), 2);
      expect(discoverGridColumns(430), 2);
    });

    test('tablets scale up', () {
      expect(discoverGridColumns(768), 3);
      expect(discoverGridColumns(1024), 5);
    });

    test('desktop windows use the width instead of two huge posters', () {
      // The reported case: a maximised ~1650dp window rendered 2 columns.
      expect(discoverGridColumns(1650), greaterThanOrEqualTo(7));
      expect(discoverGridColumns(1920), 8);
    });

    test('is clamped at both ends', () {
      expect(discoverGridColumns(0), 2);
      expect(discoverGridColumns(-100), 2);
      expect(discoverGridColumns(100), 2);
      expect(discoverGridColumns(5000), 8);
    });

    test('never returns a column count that would overflow the row', () {
      for (var w = 200.0; w <= 3000; w += 7) {
        final n = discoverGridColumns(w);
        final needed =
            n * kDiscoverTargetTileWidth +
            (n - 1) * kDiscoverGridSpacing +
            kDiscoverGridSpacing * 2;
        // Two columns is a hard floor, so only check where the clamp isn't
        // forcing our hand.
        if (n > 2) expect(needed, lessThanOrEqualTo(w));
      }
    });

    test('grows monotonically with width', () {
      var previous = 0;
      for (var w = 200.0; w <= 3000; w += 13) {
        final n = discoverGridColumns(w);
        expect(n, greaterThanOrEqualTo(previous));
        previous = n;
      }
    });
  });
}

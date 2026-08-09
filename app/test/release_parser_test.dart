import 'package:flutter_test/flutter_test.dart';
import 'package:torrex/core/release_parser.dart';

void main() {
  group('ReleaseParser', () {
    test('parses a typical movie release name', () {
      final i = ReleaseParser.parse(
        'Dune Part Two 2024 2160p UHD BluRay REMUX DV HDR10 TrueHD 7.1 Atmos-FraMeSToR',
      );
      expect(i.cleanTitle, 'Dune Part Two 2024');
      expect(i.year, 2024);
      expect(i.resolution, Resolution.p2160);
      expect(i.isRemux, isTrue);
      expect(i.source, Source.remux);
      expect(i.hdr, containsAll([HdrFormat.dolbyVision, HdrFormat.hdr10]));
      expect(i.audio, contains(AudioFormat.atmos));
      expect(i.channels, '7.1');
      expect(i.group, 'FraMeSToR');
    });

    test('parses a TV episode release name', () {
      final i = ReleaseParser.parse(
        'Severance.S02E05.1080p.WEB-DL.DDP5.1.H.264-NTb',
      );
      expect(i.cleanTitle, 'Severance');
      expect(i.season, 2);
      expect(i.episode, 5);
      expect(i.isSeasonPack, isFalse);
      expect(i.resolution, Resolution.p1080);
      expect(i.source, Source.webDl);
      expect(i.codec, Codec.h264);
      expect(i.episodeTag, 'S02E05');
    });

    test('detects a season pack', () {
      final i = ReleaseParser.parse('The Bear S03 1080p WEB-DL x265-GRP');
      expect(i.season, 3);
      expect(i.episode, isNull);
      expect(i.isSeasonPack, isTrue);
      expect(i.episodeTag, 'S03');
    });

    test('handles the 1x02 episode form', () {
      final i = ReleaseParser.parse('Some Show 1x02 720p HDTV XviD');
      expect(i.season, 1);
      expect(i.episode, 2);
      expect(i.source, Source.hdtv);
      expect(i.codec, Codec.xvid);
    });

    test('picks up anime group brackets and languages', () {
      final i = ReleaseParser.parse(
        '[SubsPlease] Frieren - 12 (1080p) [JAPANESE] [ESub]',
      );
      expect(i.group, 'SubsPlease');
      expect(i.resolution, Resolution.p1080);
      expect(i.languages, contains('JAPANESE'));
      expect(i.isSubbed, isTrue);
    });

    test('flags low-quality sources', () {
      expect(ReleaseParser.parse('Movie 2025 HDCAM x264').source, Source.cam);
      expect(
        ReleaseParser.parse('Movie 2025 HDTS 720p').source,
        Source.telesync,
      );
    });

    test('does not mistake a resolution suffix for a release group', () {
      expect(ReleaseParser.parse('Some Movie 2019 1080p').group, isNull);
      expect(ReleaseParser.parse('Some Movie 2019').group, isNull);
    });

    test('does not treat a bare ISO as a full-disc video source', () {
      // Regression: `ubuntu-…-amd64.iso` used to pick up a COMPLETE badge
      // and get filed under Movies.
      final i = ReleaseParser.parse('Ubuntu 26.04 LTS Desktop amd64 ISO');
      expect(i.source, isNull);
      expect(i.resolution, isNull);
      expect(i.badges, isEmpty);
    });

    test('still detects a genuine full BluRay disc', () {
      expect(
        ReleaseParser.parse('Some Film 2024 COMPLETE BLURAY-GRP').source,
        Source.fullDisc,
      );
    });

    test('never throws on junk input', () {
      for (final s in ['', '   ', '???', '1080p', '-', '[]']) {
        expect(() => ReleaseParser.parse(s), returnsNormally);
      }
    });

    test('is memoised — repeated parses return an identical instance', () {
      const title = 'Arrival 2016 1080p BluRay x264-SPARKS';
      expect(
        identical(ReleaseParser.parse(title), ReleaseParser.parse(title)),
        isTrue,
      );
    });
  });
}

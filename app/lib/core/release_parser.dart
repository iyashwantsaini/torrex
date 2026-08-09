/// Scene / P2P release-name parser.
///
/// Torznab feeds hand us a single blob of text per result — the release
/// name. Every "famous" torrent site derives its quality badges, filters
/// and dedupe keys from that same string, so we do too.
///
/// The parser is deliberately conservative: every field is nullable and
/// an unrecognised token is simply dropped. It must never throw, and it
/// must be cheap — it runs once per result, for every result, on every
/// keystroke of the client-side filter.
library;

/// Video resolution bucket, ordered worst → best so `index` doubles as a
/// sort key.
enum Resolution {
  sd('SD'),
  p480('480p'),
  p576('576p'),
  p720('720p'),
  p1080('1080p'),
  p1440('1440p'),
  p2160('4K'),
  p4320('8K');

  const Resolution(this.label);
  final String label;
}

/// Where the video came from. Roughly ordered worst → best.
enum Source {
  cam('CAM'),
  telesync('TS'),
  telecine('TC'),
  screener('SCR'),
  dvdRip('DVDRip'),
  hdtv('HDTV'),
  webRip('WEBRip'),
  webDl('WEB-DL'),
  hdRip('HDRip'),
  blurayRip('BluRay'),
  remux('REMUX'),
  fullDisc('COMPLETE');

  const Source(this.label);
  final String label;
}

/// Video codec.
enum Codec {
  xvid('XviD'),
  h264('x264'),
  h265('x265'),
  av1('AV1'),
  vp9('VP9'),
  mpeg2('MPEG-2');

  const Codec(this.label);
  final String label;
}

/// High-dynamic-range flavour.
enum HdrFormat {
  hdr10('HDR'),
  hdr10Plus('HDR10+'),
  dolbyVision('DV'),
  hlg('HLG');

  const HdrFormat(this.label);
  final String label;
}

/// Audio format, best-effort.
enum AudioFormat {
  aac('AAC'),
  ac3('AC3'),
  eac3('EAC3'),
  dts('DTS'),
  dtsHd('DTS-HD'),
  dtsX('DTS:X'),
  trueHd('TrueHD'),
  atmos('Atmos'),
  flac('FLAC'),
  opus('Opus');

  const AudioFormat(this.label);
  final String label;
}

/// Everything we could infer from a single release name.
class ReleaseInfo {
  const ReleaseInfo({
    required this.cleanTitle,
    this.year,
    this.season,
    this.episode,
    this.isSeasonPack = false,
    this.resolution,
    this.source,
    this.codec,
    this.hdr = const {},
    this.audio = const {},
    this.channels,
    this.group,
    this.languages = const {},
    this.isMultiAudio = false,
    this.isSubbed = false,
    this.isDubbed = false,
    this.isProper = false,
    this.isRepack = false,
    this.isExtended = false,
    this.is3d = false,
    this.isRemux = false,
    this.isHevcTenBit = false,
  });

  /// Title with all technical tags stripped — used for TMDB lookups and
  /// for grouping near-identical releases together.
  final String cleanTitle;
  final int? year;
  final int? season;
  final int? episode;

  /// `S02` with no episode number, or an explicit "Season 2 Complete".
  final bool isSeasonPack;

  final Resolution? resolution;
  final Source? source;
  final Codec? codec;
  final Set<HdrFormat> hdr;
  final Set<AudioFormat> audio;

  /// e.g. `5.1`, `7.1`, `2.0`.
  final String? channels;

  /// Release group (the `-GROUP` suffix).
  final String? group;

  /// ISO-ish language names found in the title (`HINDI`, `DUAL`, …).
  final Set<String> languages;

  final bool isMultiAudio;
  final bool isSubbed;
  final bool isDubbed;
  final bool isProper;
  final bool isRepack;
  final bool isExtended;
  final bool is3d;
  final bool isRemux;
  final bool isHevcTenBit;

  bool get hasHdr => hdr.isNotEmpty;

  /// `S01E02` / `S01` / `null`.
  String? get episodeTag {
    final s = season;
    if (s == null) return null;
    final two = s.toString().padLeft(2, '0');
    final e = episode;
    if (e == null) return 'S$two';
    return 'S${two}E${e.toString().padLeft(2, '0')}';
  }

  /// Short badges rendered on the result card, most-significant first.
  /// Capped by the caller.
  List<String> get badges => [
    ?resolution?.label,
    if (isRemux) 'REMUX' else if (source != null) source!.label,
    ?codec?.label,
    for (final h in hdr) h.label,
    if (audio.contains(AudioFormat.atmos)) 'Atmos',
    ?channels,
    if (isRepack) 'REPACK',
    if (isExtended) 'EXTENDED',
    if (is3d) '3D',
  ];

  static const empty = ReleaseInfo(cleanTitle: '');
}

/// Stateless parser. All methods are pure.
abstract final class ReleaseParser {
  /// Bounded memo cache — the same titles get re-parsed on every filter
  /// pass and every rebuild, and regex work adds up on a 1000-row list.
  static final Map<String, ReleaseInfo> _cache = <String, ReleaseInfo>{};
  static const int _maxCache = 4000;

  static ReleaseInfo parse(String rawTitle) {
    if (rawTitle.isEmpty) return ReleaseInfo.empty;
    final hit = _cache[rawTitle];
    if (hit != null) return hit;
    final parsed = _parse(rawTitle);
    if (_cache.length >= _maxCache) _cache.clear();
    _cache[rawTitle] = parsed;
    return parsed;
  }

  static ReleaseInfo _parse(String rawTitle) {
    // Normalise separators: release names use `.`, `_` and spaces
    // interchangeably. Keep brackets — anime groups live in them.
    final normalized = rawTitle.replaceAll(RegExp(r'[._]+'), ' ');
    final upper = normalized.toUpperCase();

    final resolution = _resolution(upper);
    final isRemux = RegExp(r'\bREMUX\b').hasMatch(upper);
    final source = _source(upper, isRemux: isRemux);
    final codec = _codec(upper);
    final hdr = _hdr(upper);
    final audio = _audio(upper);
    final channels = _channels(upper);
    final languages = _languages(upper);

    final seasonEpisode = _seasonEpisode(normalized);
    final year = _year(normalized);

    return ReleaseInfo(
      cleanTitle: _cleanTitle(normalized),
      year: year,
      season: seasonEpisode.$1,
      episode: seasonEpisode.$2,
      isSeasonPack:
          seasonEpisode.$1 != null &&
          seasonEpisode.$2 == null &&
          !RegExp(r'\bE\d{1,3}\b').hasMatch(upper),
      resolution: resolution,
      source: source,
      codec: codec,
      hdr: hdr,
      audio: audio,
      channels: channels,
      group: _group(rawTitle),
      languages: languages,
      isMultiAudio: RegExp(
        r'\b(MULTI|DUAL[ -]?AUDIO|MULTI[ -]?AUDIO)\b',
      ).hasMatch(upper),
      isSubbed: RegExp(r'\b(SUBBED|ESUB[S]?|MSUB[S]?|SUBS)\b').hasMatch(upper),
      isDubbed: RegExp(r'\bDUBBED\b').hasMatch(upper),
      isProper: RegExp(r'\bPROPER\b').hasMatch(upper),
      isRepack: RegExp(r'\bREPACK\b').hasMatch(upper),
      isExtended: RegExp(
        r"\b(EXTENDED|DIRECTOR'?S CUT|UNRATED|UNCUT)\b",
      ).hasMatch(upper),
      is3d: RegExp(r'\b(3D|HSBS|H-SBS|HOU)\b').hasMatch(upper),
      isRemux: isRemux,
      isHevcTenBit: RegExp(r'\b10 ?BIT\b').hasMatch(upper),
    );
  }

  static Resolution? _resolution(String upper) {
    if (RegExp(r'\b(4320P|8K)\b').hasMatch(upper)) return Resolution.p4320;
    if (RegExp(r'\b(2160P|4K|UHD)\b').hasMatch(upper)) return Resolution.p2160;
    if (RegExp(r'\b1440P\b').hasMatch(upper)) return Resolution.p1440;
    if (RegExp(r'\b1080[PI]\b').hasMatch(upper)) return Resolution.p1080;
    if (RegExp(r'\b720[PI]\b').hasMatch(upper)) return Resolution.p720;
    if (RegExp(r'\b576[PI]\b').hasMatch(upper)) return Resolution.p576;
    if (RegExp(r'\b480[PI]\b').hasMatch(upper)) return Resolution.p480;
    // Common SD markers with no explicit height.
    if (RegExp(r'\b(DVDRIP|VHSRIP|SDTV|XVID)\b').hasMatch(upper)) {
      return Resolution.sd;
    }
    return null;
  }

  static Source? _source(String upper, {required bool isRemux}) {
    // Order matters — check the most specific first. Note we deliberately
    // do *not* treat a bare "ISO" as a full-disc video rip: distro and
    // software torrents (`ubuntu-26.04-desktop-amd64.iso`) are full of it
    // and would otherwise pick up a bogus COMPLETE badge.
    if (RegExp(
      r'\b(COMPLETE (BLURAY|UHD)|BD(25|50|66|100))\b',
    ).hasMatch(upper)) {
      return Source.fullDisc;
    }
    if (isRemux) return Source.remux;
    if (RegExp(r'\b(BLU-?RAY|BDRIP|BRRIP|BDREMUX|UHDBD)\b').hasMatch(upper)) {
      return Source.blurayRip;
    }
    if (RegExp(r'\bWEB-?DL\b').hasMatch(upper)) return Source.webDl;
    if (RegExp(r'\bWEB-?RIP\b').hasMatch(upper)) return Source.webRip;
    // Bare "WEB" is ambiguous but far more often WEB-DL in practice.
    if (RegExp(r'\bWEB\b').hasMatch(upper)) return Source.webDl;
    if (RegExp(r'\bHD-?RIP\b').hasMatch(upper)) return Source.hdRip;
    if (RegExp(r'\b(HDTV|PDTV|DSR|SDTV)\b').hasMatch(upper)) return Source.hdtv;
    if (RegExp(r'\b(DVD-?RIP|DVD-?R|DVD5|DVD9|VHSRIP)\b').hasMatch(upper)) {
      return Source.dvdRip;
    }
    if (RegExp(r'\b(SCREENER|DVDSCR|BDSCR|SCR)\b').hasMatch(upper)) {
      return Source.screener;
    }
    if (RegExp(r'\b(TELECINE|TC)\b').hasMatch(upper)) return Source.telecine;
    if (RegExp(r'\b(TELESYNC|HDTS|TS|PREDVD|PRE-?DVD)\b').hasMatch(upper)) {
      return Source.telesync;
    }
    if (RegExp(r'\b(CAM-?RIP|CAMRIP|HDCAM|CAM)\b').hasMatch(upper)) {
      return Source.cam;
    }
    return null;
  }

  static Codec? _codec(String upper) {
    if (RegExp(r'\b(AV1)\b').hasMatch(upper)) return Codec.av1;
    if (RegExp(r'\b(X265|H ?265|HEVC)\b').hasMatch(upper)) return Codec.h265;
    if (RegExp(r'\b(X264|H ?264|AVC)\b').hasMatch(upper)) return Codec.h264;
    if (RegExp(r'\b(VP9)\b').hasMatch(upper)) return Codec.vp9;
    if (RegExp(r'\b(XVID|DIVX)\b').hasMatch(upper)) return Codec.xvid;
    if (RegExp(r'\b(MPEG-?2)\b').hasMatch(upper)) return Codec.mpeg2;
    return null;
  }

  static Set<HdrFormat> _hdr(String upper) {
    final out = <HdrFormat>{};
    if (RegExp(r'\b(DV|DOVI|DOLBY ?VISION)\b').hasMatch(upper)) {
      out.add(HdrFormat.dolbyVision);
    }
    if (RegExp(r'\bHDR10\+|\bHDR10PLUS\b').hasMatch(upper)) {
      out.add(HdrFormat.hdr10Plus);
    } else if (RegExp(r'\bHDR(10)?\b').hasMatch(upper)) {
      out.add(HdrFormat.hdr10);
    }
    if (RegExp(r'\bHLG\b').hasMatch(upper)) out.add(HdrFormat.hlg);
    return out;
  }

  static Set<AudioFormat> _audio(String upper) {
    final out = <AudioFormat>{};
    if (RegExp(r'\bATMOS\b').hasMatch(upper)) out.add(AudioFormat.atmos);
    if (RegExp(r'\bTRUE-?HD\b').hasMatch(upper)) out.add(AudioFormat.trueHd);
    if (RegExp(r'\bDTS[ -]?X\b').hasMatch(upper)) {
      out.add(AudioFormat.dtsX);
    } else if (RegExp(r'\bDTS[ -]?HD([ -]?MA)?\b').hasMatch(upper)) {
      out.add(AudioFormat.dtsHd);
    } else if (RegExp(r'\bDTS\b').hasMatch(upper)) {
      out.add(AudioFormat.dts);
    }
    if (RegExp(r'\b(EAC3|E-AC-?3|DDP|DD\+)\b').hasMatch(upper)) {
      out.add(AudioFormat.eac3);
    } else if (RegExp(r'\b(AC-?3|DD)\b').hasMatch(upper)) {
      out.add(AudioFormat.ac3);
    }
    if (RegExp(r'\bAAC\b').hasMatch(upper)) out.add(AudioFormat.aac);
    if (RegExp(r'\bFLAC\b').hasMatch(upper)) out.add(AudioFormat.flac);
    if (RegExp(r'\bOPUS\b').hasMatch(upper)) out.add(AudioFormat.opus);
    return out;
  }

  static String? _channels(String upper) {
    final m = RegExp(r'\b([2578])[ .]([01])\b').firstMatch(upper);
    if (m == null) return null;
    return '${m.group(1)}.${m.group(2)}';
  }

  /// Language tokens commonly stuffed into release names. We keep the raw
  /// uppercase token so the filter UI can show exactly what it matched.
  static const _languageTokens = <String>{
    'HINDI',
    'TAMIL',
    'TELUGU',
    'MALAYALAM',
    'KANNADA',
    'BENGALI',
    'PUNJABI',
    'MARATHI',
    'GUJARATI',
    'URDU',
    'ENGLISH',
    'SPANISH',
    'CASTELLANO',
    'LATINO',
    'FRENCH',
    'TRUEFRENCH',
    'VOSTFR',
    'GERMAN',
    'ITALIAN',
    'PORTUGUESE',
    'DUBLADO',
    'RUSSIAN',
    'UKRAINIAN',
    'POLISH',
    'DUTCH',
    'NORDIC',
    'SWEDISH',
    'DANISH',
    'NORWEGIAN',
    'FINNISH',
    'TURKISH',
    'ARABIC',
    'PERSIAN',
    'FARSI',
    'HEBREW',
    'THAI',
    'VIETNAMESE',
    'INDONESIAN',
    'JAPANESE',
    'KOREAN',
    'CHINESE',
    'MANDARIN',
    'CANTONESE',
    'CZECH',
    'HUNGARIAN',
    'ROMANIAN',
    'GREEK',
    'BULGARIAN',
    'CROATIAN',
    'SERBIAN',
    'SLOVAK',
    'MULTI',
    'DUAL',
  };

  static Set<String> _languages(String upper) {
    final out = <String>{};
    for (final token in _languageTokens) {
      if (RegExp('\\b$token\\b').hasMatch(upper)) out.add(token);
    }
    return out;
  }

  /// `-GROUP` at the very end, or `[Group]` at the very start (anime).
  static String? _group(String raw) {
    final anime = RegExp(r'^\s*\[([^\]]{2,24})\]').firstMatch(raw);
    if (anime != null) return anime.group(1);
    final tail = RegExp(r'-([A-Za-z0-9]{2,20})\s*$').firstMatch(raw.trim());
    final g = tail?.group(1);
    if (g == null) return null;
    // Guard against `-1080p`, `-2024` and other false positives.
    if (RegExp(r'^\d+$').hasMatch(g)) return null;
    if (RegExp(r'^\d{3,4}[pi]$', caseSensitive: false).hasMatch(g)) return null;
    return g;
  }

  /// Returns `(season, episode)`. Handles `S01E02`, `S01 E02`, `1x02`,
  /// `Season 3 Episode 4`, and season-only `S01`.
  static (int?, int?) _seasonEpisode(String normalized) {
    final se = RegExp(
      r'\bS(\d{1,2})\s?E(\d{1,3})\b',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (se != null) {
      return (int.tryParse(se.group(1)!), int.tryParse(se.group(2)!));
    }
    final x = RegExp(r'\b(\d{1,2})x(\d{2,3})\b').firstMatch(normalized);
    if (x != null) {
      return (int.tryParse(x.group(1)!), int.tryParse(x.group(2)!));
    }
    final words = RegExp(
      r'\bSEASON\s?(\d{1,2})(?:\s?EPISODE\s?(\d{1,3}))?\b',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (words != null) {
      return (
        int.tryParse(words.group(1)!),
        words.group(2) == null ? null : int.tryParse(words.group(2)!),
      );
    }
    final seasonOnly = RegExp(
      r'\bS(\d{1,2})\b',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (seasonOnly != null) return (int.tryParse(seasonOnly.group(1)!), null);
    // Anime style: `Title - 12 [1080p]`.
    final anime = RegExp(r'\s-\s(\d{1,3})\s').firstMatch(normalized);
    if (anime != null) return (null, int.tryParse(anime.group(1)!));
    return (null, null);
  }

  /// Last plausible release year in the string (release names sometimes
  /// contain a year inside the title itself, e.g. `Blade Runner 2049 2017`).
  static int? _year(String normalized) {
    final matches = RegExp(
      r'(?:^|[\s(\[])((?:19|20)\d{2})(?:[\s)\]]|$)',
    ).allMatches(normalized).toList();
    if (matches.isEmpty) return null;
    final now = DateTime.now().year + 2;
    for (final m in matches.reversed) {
      final y = int.tryParse(m.group(1)!);
      if (y != null && y >= 1900 && y <= now) return y;
    }
    return null;
  }

  /// Strip everything from the first technical token onward. This is what
  /// TMDB and the dedupe key want.
  static final RegExp _stopToken = RegExp(
    r'\b(\d{3,4}[pi]|4K|UHD|BLU-?RAY|BDRIP|BRRIP|WEB-?DL|WEB-?RIP|WEB|HDTV|'
    r'DVDRIP|DVDSCR|HDCAM|CAMRIP|CAM|HDTS|TS|REMUX|X264|X265|H ?264|H ?265|'
    r'HEVC|AVC|XVID|DIVX|AV1|AAC|AC-?3|DD[P+]?|DTS|TRUEHD|ATMOS|FLAC|OPUS|'
    r'HDR10\+?|HDR|DOVI|DOLBY ?VISION|10 ?BIT|MULTI|DUAL|PROPER|REPACK|'
    r'S\d{1,2}E\d{1,3}|S\d{1,2}\b|SEASON \d{1,2}|\d{1,2}x\d{2})\b',
    caseSensitive: false,
  );

  static String _cleanTitle(String normalized) {
    var s = normalized;
    // Drop bracketed prefixes/suffixes ([Group], (2024), {tag}).
    s = s.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    final stop = _stopToken.firstMatch(s);
    if (stop != null) s = s.substring(0, stop.start);
    // Trailing year in parens is part of the title for TMDB purposes but
    // we keep it out of the dedupe key.
    s = s.replaceAll(RegExp(r'[()]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Strip a dangling separator left behind by the cut.
    s = s.replaceAll(RegExp(r'[-–—:]+$'), '').trim();
    return s;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists user-supplied backend connection details and UI preferences.
///
/// API key is stored in the platform secure store (Keystore on Android,
/// Keychain on iOS) — never in plain prefs.
class SettingsStore extends ChangeNotifier {
  SettingsStore({FlutterSecureStorage? secure})
    : _secure = secure ?? const FlutterSecureStorage();

  static const _kBaseUrl = 'backend.baseUrl';
  static const _kIndexer = 'backend.indexer'; // e.g. "all" or a specific id
  static const _kThemeMode = 'ui.themeMode';
  static const _kApiKey = 'backend.apiKey';
  static const _kTmdbKey = 'tmdb.apiKey';
  static const _kOnboardingDone = 'ui.onboardingDone';
  static const _kCardChips = 'ui.cardChips';

  /// Default chips on the result card. Order = render order.
  /// Identifiers must stay in sync with [SearchResultChip.values].
  static const defaultCardChips = <String>['seeders', 'size', 'age'];

  final FlutterSecureStorage _secure;

  String _baseUrl = '';
  String _indexer = 'all';
  String _apiKey = '';
  String _tmdbKey = '';
  ThemeMode _themeMode = ThemeMode.dark;
  bool _onboardingDone = false;
  List<String> _cardChips = defaultCardChips;

  String get baseUrl => _baseUrl;
  String get indexer => _indexer;
  String get apiKey => _apiKey;
  String get tmdbKey => _tmdbKey;
  ThemeMode get themeMode => _themeMode;
  bool get onboardingDone => _onboardingDone;
  List<String> get cardChips => _cardChips;
  bool get hasTmdbKey => _tmdbKey.isNotEmpty;

  bool get isConfigured =>
      _baseUrl == 'demo' || (_baseUrl.isNotEmpty && _apiKey.isNotEmpty);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_kBaseUrl) ?? '';
    _indexer = prefs.getString(_kIndexer) ?? 'all';
    _themeMode = _decodeThemeMode(prefs.getString(_kThemeMode));
    _onboardingDone = prefs.getBool(_kOnboardingDone) ?? false;
    final savedChips = prefs.getStringList(_kCardChips);
    _cardChips = (savedChips == null || savedChips.isEmpty)
        ? defaultCardChips
        : savedChips;
    _apiKey = await _secure.read(key: _kApiKey) ?? '';
    _tmdbKey = await _secure.read(key: _kTmdbKey) ?? '';
    notifyListeners();
  }

  Future<void> update({
    String? baseUrl,
    String? indexer,
    String? apiKey,
    String? tmdbKey,
    ThemeMode? themeMode,
    bool? onboardingDone,
    List<String>? cardChips,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (baseUrl != null) {
      _baseUrl = baseUrl.trim();
      await prefs.setString(_kBaseUrl, _baseUrl);
    }
    if (indexer != null) {
      _indexer = indexer.trim().isEmpty ? 'all' : indexer.trim();
      await prefs.setString(_kIndexer, _indexer);
    }
    if (apiKey != null) {
      _apiKey = apiKey.trim();
      await _secure.write(key: _kApiKey, value: _apiKey);
    }
    if (tmdbKey != null) {
      _tmdbKey = tmdbKey.trim();
      await _secure.write(key: _kTmdbKey, value: _tmdbKey);
    }
    if (themeMode != null) {
      _themeMode = themeMode;
      await prefs.setString(_kThemeMode, _encodeThemeMode(themeMode));
    }
    if (onboardingDone != null) {
      _onboardingDone = onboardingDone;
      await prefs.setBool(_kOnboardingDone, onboardingDone);
    }
    if (cardChips != null) {
      // Filter to known chip ids only — defends against schema drift if a
      // user opens an older app version with a never-released chip key.
      _cardChips = cardChips
          .where((c) => defaultCardChips.contains(c) || _allKnownChips.contains(c))
          .toList(growable: false);
      if (_cardChips.isEmpty) _cardChips = defaultCardChips;
      await prefs.setStringList(_kCardChips, _cardChips);
    }
    notifyListeners();
  }

  /// Set of every chip id the app knows how to render. Kept in this file
  /// (instead of importing the search feature) to avoid a circular import.
  static const _allKnownChips = <String>{
    'seeders',
    'leechers',
    'size',
    'age',
    'indexer',
    'category',
    'magnet',
  };

  static ThemeMode _decodeThemeMode(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    // Unset → default to dark (Torrex's editorial palette is designed
    // dark-first; light/system are opt-in via Settings).
    _ => ThemeMode.dark,
  };

  static String _encodeThemeMode(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
}

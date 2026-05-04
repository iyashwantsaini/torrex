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

  final FlutterSecureStorage _secure;

  String _baseUrl = '';
  String _indexer = 'all';
  String _apiKey = '';
  ThemeMode _themeMode = ThemeMode.system;

  String get baseUrl => _baseUrl;
  String get indexer => _indexer;
  String get apiKey => _apiKey;
  ThemeMode get themeMode => _themeMode;

  bool get isConfigured => _baseUrl.isNotEmpty && _apiKey.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_kBaseUrl) ?? '';
    _indexer = prefs.getString(_kIndexer) ?? 'all';
    _themeMode = _decodeThemeMode(prefs.getString(_kThemeMode));
    _apiKey = await _secure.read(key: _kApiKey) ?? '';
    notifyListeners();
  }

  Future<void> update({
    String? baseUrl,
    String? indexer,
    String? apiKey,
    ThemeMode? themeMode,
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
    if (themeMode != null) {
      _themeMode = themeMode;
      await prefs.setString(_kThemeMode, _encodeThemeMode(themeMode));
    }
    notifyListeners();
  }

  static ThemeMode _decodeThemeMode(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  static String _encodeThemeMode(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
}

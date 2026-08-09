import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Most-recent-first list of queries the user actually ran.
///
/// Kept in plain `SharedPreferences` (not secure storage) — it's a
/// convenience feature, and putting it in the Keystore would make the
/// "clear history" affordance feel heavier than it is.
class SearchHistory extends ChangeNotifier {
  static const _key = 'search.history';
  static const int maxEntries = 12;

  List<String> _entries = const [];
  List<String> get entries => _entries;
  bool get isEmpty => _entries.isEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _entries = prefs.getStringList(_key) ?? const [];
    notifyListeners();
  }

  /// Record [query], moving it to the front if it was already there so the
  /// list reads as "recently used" rather than "first used".
  Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final next = [
      q,
      ..._entries.where((e) => e.toLowerCase() != q.toLowerCase()),
    ];
    _entries = next.length > maxEntries ? next.sublist(0, maxEntries) : next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _entries);
  }

  Future<void> remove(String query) async {
    _entries = _entries.where((e) => e != query).toList(growable: false);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _entries);
  }

  Future<void> clear() async {
    if (_entries.isEmpty) return;
    _entries = const [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

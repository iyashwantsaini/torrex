import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'settings_store.dart';

/// State of the on-startup backend warm-up ping.
///
/// Hugging Face Spaces sleep after ~48h idle and take ~30s to spin back up
/// when the next request hits them. We fire a cheap `GET /UI/Dashboard`
/// from the app at launch so the cold start happens *while the user is
/// still picking what to search for*, not after they hit the search button.
enum WarmupState {
  /// No warm-up needed (no backend configured, or `baseUrl == 'demo'`).
  idle,

  /// Ping is in flight — show the "waking backend" banner.
  waking,

  /// Backend responded OK — banner can hide.
  ready,

  /// Ping failed (still allow searches; user may have a typo, no network,
  /// etc.). Banner hides — the search-error path will show the real error.
  failed,
}

class BackendWarmer extends ChangeNotifier {
  BackendWarmer({Dio? dio}) : _dio = dio ?? _defaultDio();

  static Dio _defaultDio() => Dio(
    BaseOptions(
      // HF cold-start can take ~30s, so allow ample headroom.
      connectTimeout: const Duration(seconds: 45),
      receiveTimeout: const Duration(seconds: 45),
      // We don't care about the response body — any 2xx/3xx means the
      // Space is awake.
      responseType: ResponseType.plain,
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  final Dio _dio;
  WarmupState _state = WarmupState.idle;
  WarmupState get state => _state;

  /// Fire-and-forget warm-up ping. Safe to call at any time.
  Future<void> warm(SettingsStore settings) async {
    final base = settings.baseUrl.trim();
    if (base.isEmpty || base == 'demo') {
      _set(WarmupState.idle);
      return;
    }

    _set(WarmupState.waking);

    final trimmed = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    // `/UI/Dashboard` is a tiny static page that wakes the Space and proves
    // Jackett's web layer is up. We deliberately don't hit a Torznab
    // endpoint — that would require the API key and a real query.
    try {
      await _dio.get<void>('$trimmed/UI/Dashboard');
      _set(WarmupState.ready);
    } catch (_) {
      _set(WarmupState.failed);
    }
  }

  void _set(WarmupState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }
}

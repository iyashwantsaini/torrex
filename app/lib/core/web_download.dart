// Conditional-import shim. The actual `forceDownload` lives in
// `web_download_io.dart` (no-op) and `web_download_web.dart` (DOM anchor).
//
// On mobile we let `url_launcher` handle .torrent URLs (the OS hands them to
// the user's torrent client). On web `url_launcher` calls `window.open`,
// which gets popup-blocked and also fails when the server response lacks a
// `Content-Disposition` header. The web variant fetches the bytes and
// triggers a real download via a dynamically-inserted `<a download>`.
export 'web_download_io.dart' if (dart.library.html) 'web_download_web.dart';

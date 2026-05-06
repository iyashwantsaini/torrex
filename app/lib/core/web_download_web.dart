// `dart:html` is technically deprecated in favor of `package:web` +
// `dart:js_interop`, but we already depend on it transitively via
// `flutter_secure_storage_web` (which keeps us off `--wasm` for the time
// being). Once that package migrates, we can swap this file too.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Force a real file download in the browser without relying on the server's
/// `Content-Disposition`. Creates an anchor with the `download` attribute
/// pointing at the URL, clicks it, and removes it. Works for any HTTP(S) URL
/// the browser can fetch, even when CORS would block a direct `fetch` call —
/// because the anchor navigation isn't subject to CORS.
Future<bool> forceDownload(String url, {String? filename}) async {
  try {
    final anchor = html.AnchorElement(href: url)
      ..download = filename ?? ''
      ..rel = 'noopener'
      ..target = '_blank';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } catch (_) {
    return false;
  }
}

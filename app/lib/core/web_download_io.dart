/// Mobile / desktop fallback. We never need a DOM-blob download here:
/// `launchUrl(externalApplication)` already hands the URL to the OS, which
/// routes it to the user's torrent client.
Future<bool> forceDownload(String url, {String? filename}) async => false;

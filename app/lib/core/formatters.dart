/// Format a byte count as a short human-readable string ("1.4 GB").
String formatBytes(int bytes) {
  if (bytes <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final precision = size >= 100 || unit == 0 ? 0 : (size >= 10 ? 1 : 2);
  return '${size.toStringAsFixed(precision)} ${units[unit]}';
}

/// Short relative-time string ("2h", "3d", "5mo").
String formatRelative(DateTime? when) {
  if (when == null) return '—';
  final diff = DateTime.now().toUtc().difference(when.toUtc());
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  if (diff.inDays < 30) return '${diff.inDays}d';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo';
  return '${(diff.inDays / 365).floor()}y';
}

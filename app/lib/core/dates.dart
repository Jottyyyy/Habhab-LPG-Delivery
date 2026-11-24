import 'package:intl/intl.dart';

/// Dates shown the Filipino way ("Nov 24, 2026 · 3:15 PM"). The phone's clock is Manila time.
String formatDate(DateTime d) => DateFormat('MMM d, y').format(d);
String formatTime(DateTime d) => DateFormat('h:mm a').format(d);
String formatDateTime(DateTime d) {
  final now = DateTime.now();
  final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
  if (sameDay) return 'Today ${formatTime(d)}';
  final y = now.subtract(const Duration(days: 1));
  if (d.year == y.year && d.month == y.month && d.day == y.day) return 'Yesterday ${formatTime(d)}';
  return '${DateFormat('MMM d').format(d)} · ${formatTime(d)}';
}

/// "2026-11-24" for API date filters.
String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// "12s ago", "3 min ago".
String agoText(DateTime? d) {
  if (d == null) return '';
  final s = DateTime.now().difference(d).inSeconds;
  if (s < 5) return 'just now';
  if (s < 60) return '${s}s ago';
  if (s < 3600) return '${s ~/ 60} min ago';
  return formatDateTime(d);
}

String greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Magandang umaga';
  if (h < 18) return 'Magandang hapon';
  return 'Magandang gabi';
}

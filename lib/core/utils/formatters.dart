import 'package:intl/intl.dart';

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatDate(DateTime date) => DateFormat.yMMMd().format(date.toLocal());

String formatPages(int? pages) {
  if (pages == null) return '';
  return pages == 1 ? '1 page' : '$pages pages';
}

/// "Just now", "12m ago", "3h ago", "Yesterday", then a date.
String formatRelative(DateTime date, {DateTime? now}) {
  final difference = (now ?? DateTime.now()).difference(date);
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  if (difference.inDays < 2) return 'Yesterday';
  return formatDate(date);
}

String greeting({DateTime? now}) {
  final hour = (now ?? DateTime.now()).hour;
  if (hour < 12) return 'Good Morning';
  if (hour < 17) return 'Good Afternoon';
  return 'Good Evening';
}

/// Page reference for a source, e.g. "p. 5" or "pp. 5-6".
String formatPageRef(int page, int pageEnd) =>
    page == pageEnd ? 'p. $page' : 'pp. $page-$pageEnd';

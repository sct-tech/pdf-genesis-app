import '../../auth/data/app_user.dart';
import '../data/document.dart';

/// Why Ask AI cannot be used on [document], or null when it can. Unknown
/// usage never blocks: the API has the final say.
String? askAiBlockedReason(Document document, Usage? usage) {
  final maxPages = usage?.aiMaxPages;
  final pages = document.pageCount;
  if (maxPages != null && pages != null && pages > maxPages) {
    return 'Ask AI and summaries work with PDFs of up to $maxPages pages.';
  }
  return null;
}

/// Why a summary of [document] cannot be opened right now, or null when it
/// can. A summary that already exists is always available.
String? summaryBlockedReason(Document document, Usage? usage) {
  if (document.hasSummary) return null;
  final tooLong = askAiBlockedReason(document, usage);
  if (tooLong != null) return tooLong;
  if (usage?.summariesLeft == 0) {
    return "You have used today's summary. A new one is available tomorrow.";
  }
  return null;
}

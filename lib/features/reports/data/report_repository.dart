import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

/// Why a user flags an AI answer or summary.
enum ReportReason {
  offensive('OFFENSIVE', 'Offensive or hateful'),
  sexual('SEXUAL', 'Sexual content'),
  harmful('HARMFUL', 'Dangerous or harmful'),
  inaccurate('INACCURATE', 'Wrong or misleading'),
  other('OTHER', 'Something else');

  const ReportReason(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

/// The AI output being reported.
sealed class ReportTarget {
  const ReportTarget();

  /// Shown as the sheet title.
  String get title;

  Map<String, Object> get body;
}

class AnswerReport extends ReportTarget {
  const AnswerReport(this.messageId);

  final String messageId;

  @override
  String get title => 'Report answer';

  @override
  Map<String, Object> get body => {
    'target': 'CHAT_MESSAGE',
    'messageId': messageId,
  };
}

class SummaryReport extends ReportTarget {
  const SummaryReport(this.documentId);

  final String documentId;

  @override
  String get title => 'Report summary';

  @override
  Map<String, Object> get body => {
    'target': 'SUMMARY',
    'documentId': documentId,
  };
}

class ReportRepository {
  ReportRepository(this._api);

  final ApiClient _api;

  static const detailsMaxLength = 500;

  Future<void> submit(
    ReportTarget target, {
    required ReportReason reason,
    String details = '',
  }) async {
    final trimmed = details.trim();
    await _api.post(
      '/reports',
      body: {
        ...target.body,
        'reason': reason.apiValue,
        if (trimmed.isNotEmpty) 'details': trimmed,
      },
    );
  }
}

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(apiClientProvider)),
);

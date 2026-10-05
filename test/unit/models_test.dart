import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/core/utils/formatters.dart';
import 'package:pdf_genesis/features/auth/data/app_user.dart';
import 'package:pdf_genesis/features/chat/data/chat_models.dart';
import 'package:pdf_genesis/features/documents/data/document.dart';

void main() {
  group('Document', () {
    test('parses the API shape, including detail-only fields', () {
      final document = Document.fromJson({
        'id': 'doc-1',
        'title': 'Lease Agreement',
        'originalFilename': 'Lease Agreement.pdf',
        'fileSize': 1468006,
        'pageCount': 8,
        'processingStatus': 'READY',
        'processingStage': null,
        'processingError': null,
        'createdAt': '2026-10-02T09:30:00.000Z',
        'hasSummary': true,
        'recentConversations': [
          {
            'id': 'c1',
            'title': 'What is the notice period?',
            'updatedAt': '2026-10-02T10:00:00.000Z',
            'lastMessage': 'The notice period is 60 days (p. 3).',
          },
        ],
      });

      expect(document.isReady, isTrue);
      expect(document.isInProgress, isFalse);
      expect(document.pageCount, 8);
      expect(document.hasSummary, isTrue);
      expect(
        document.recentConversations.single.lastMessage,
        contains('60 days'),
      );
    });

    test('treats every pre-ready status as in progress', () {
      for (final status in ['UPLOADING', 'UPLOADED', 'PROCESSING']) {
        final document = Document.fromJson({
          'id': 'd',
          'title': 't',
          'processingStatus': status,
          'createdAt': '2026-10-02T09:30:00.000Z',
        });
        expect(document.isInProgress, isTrue, reason: status);
      }
    });

    test('failed is neither ready nor in progress', () {
      final document = Document.fromJson({
        'id': 'd',
        'title': 't',
        'processingStatus': 'FAILED',
        'processingError': 'This PDF has no readable text.',
        'createdAt': '2026-10-02T09:30:00.000Z',
      });
      expect(document.isFailed, isTrue);
      expect(document.isInProgress, isFalse);
      expect(document.error, contains('no readable text'));
    });
  });

  test('DocumentSummary builds plain text for copy and share', () {
    final summary = DocumentSummary.fromJson({
      'summary': 'Revenue grew 24%.',
      'keyPoints': ['ARR reached 42.8M', 'Churn fell to 1.1%'],
      'cached': true,
    });
    expect(
      summary.toPlainText('Q3 Report'),
      'Q3 Report\n\nDocument Summary\nRevenue grew 24%.\n\n'
      'Key Points\n- ARR reached 42.8M\n- Churn fell to 1.1%',
    );
  });

  test('ChatMessage de-duplicates and orders page sources', () {
    final message = ChatMessage.fromJson({
      'id': 'm1',
      'role': 'ASSISTANT',
      'content': 'Answer',
      'sources': [
        {'page': 16, 'pageEnd': 16, 'chunkId': 'b'},
        {'page': 5, 'pageEnd': 6, 'chunkId': 'a'},
        {'page': 16, 'pageEnd': 16, 'chunkId': 'c'},
      ],
    });
    expect(message.isUser, isFalse);
    expect(message.uniqueSources.map((s) => formatPageRef(s.page, s.pageEnd)), [
      'pp. 5-6',
      'p. 16',
    ]);
  });

  test('Usage reports the stored-document limit', () {
    final usage = Usage.fromJson({
      'plan': 'FREE',
      'documents': {'used': 3, 'limit': 3},
      'today': {'pdfUploads': 1, 'aiChats': 12, 'summaries': 2},
    });
    expect(usage.atDocumentLimit, isTrue);
    expect(usage.documentsFraction, 1);
    expect(usage.aiChatsToday, 12);
  });

  test('AppUser falls back sensibly for guests and missing names', () {
    final guest = AppUser.fromJson({
      'id': 'g',
      'isGuest': true,
      'plan': 'FREE',
    });
    expect(guest.displayName, 'Guest');
    expect(guest.isPro, isFalse);

    final pro = AppUser.fromJson({
      'id': 'u',
      'name': '  ',
      'email': 'milan@example.com',
      'isGuest': false,
      'plan': 'PRO',
    });
    expect(pro.displayName, 'milan@example.com');
    expect(pro.planLabel, 'Pro plan');
  });

  group('formatters', () {
    test('file sizes', () {
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(20 * 1024), '20 KB');
      expect(formatFileSize(8808038), '8.4 MB');
    });

    test('greeting follows the time of day', () {
      expect(greeting(now: DateTime(2026, 1, 1, 8)), 'Good Morning');
      expect(greeting(now: DateTime(2026, 1, 1, 14)), 'Good Afternoon');
      expect(greeting(now: DateTime(2026, 1, 1, 20)), 'Good Evening');
    });

    test('relative time', () {
      final now = DateTime(2026, 10, 3, 12);
      expect(formatRelative(now, now: now), 'Just now');
      expect(
        formatRelative(now.subtract(const Duration(minutes: 12)), now: now),
        '12m ago',
      );
      expect(
        formatRelative(now.subtract(const Duration(hours: 30)), now: now),
        'Yesterday',
      );
    });
  });
}

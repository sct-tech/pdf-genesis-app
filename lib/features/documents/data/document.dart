enum ProcessingStatus {
  uploading,
  uploaded,
  processing,
  ready,
  failed;

  static ProcessingStatus parse(String? value) => switch (value) {
    'UPLOADING' => uploading,
    'UPLOADED' => uploaded,
    'PROCESSING' => processing,
    'READY' => ready,
    'FAILED' => failed,
    _ => processing,
  };
}

class ConversationPreview {
  const ConversationPreview({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.lastMessage,
  });

  factory ConversationPreview.fromJson(Map<String, dynamic> json) {
    return ConversationPreview(
      id: json['id'] as String,
      title: json['title'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      lastMessage: json['lastMessage'] as String?,
    );
  }

  final String id;
  final String title;
  final DateTime updatedAt;
  final String? lastMessage;
}

class Document {
  const Document({
    required this.id,
    required this.title,
    required this.fileSize,
    required this.status,
    required this.createdAt,
    this.pageCount,
    this.stage,
    this.error,
    this.hasSummary = false,
    this.suggestedQuestions = const [],
    this.recentConversations = const [],
  });

  factory Document.fromJson(Map<String, dynamic> json) {
    final conversations = json['recentConversations'] as List<dynamic>?;
    return Document(
      id: json['id'] as String,
      title: json['title'] as String,
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      pageCount: (json['pageCount'] as num?)?.toInt(),
      status: ProcessingStatus.parse(json['processingStatus'] as String?),
      stage: json['processingStage'] as String?,
      error: json['processingError'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      hasSummary: (json['hasSummary'] as bool?) ?? false,
      suggestedQuestions: [
        for (final question
            in (json['suggestedQuestions'] as List<dynamic>? ?? const []))
          question as String,
      ],
      recentConversations: [
        for (final item in conversations ?? const [])
          ConversationPreview.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  final String id;
  final String title;
  final int fileSize;
  final int? pageCount;
  final ProcessingStatus status;

  /// Step reported by the worker while [status] is processing.
  final String? stage;

  /// Reason shown to the user when [status] is failed.
  final String? error;
  final DateTime createdAt;
  final bool hasSummary;

  /// Empty until the document has been used with Ask AI.
  final List<String> suggestedQuestions;
  final List<ConversationPreview> recentConversations;

  bool get isReady => status == ProcessingStatus.ready;

  bool get isFailed => status == ProcessingStatus.failed;

  bool get isInProgress => !isReady && !isFailed;
}

class DocumentSummary {
  const DocumentSummary({required this.summary, required this.keyPoints});

  factory DocumentSummary.fromJson(Map<String, dynamic> json) {
    return DocumentSummary(
      summary: json['summary'] as String,
      keyPoints: [
        for (final point in (json['keyPoints'] as List<dynamic>? ?? const []))
          point as String,
      ],
    );
  }

  final String summary;
  final List<String> keyPoints;

  /// Plain-text form used by Copy and Share.
  String toPlainText(String title) {
    final buffer = StringBuffer()
      ..writeln(title)
      ..writeln()
      ..writeln('Document Summary')
      ..writeln(summary);
    if (keyPoints.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Key Points');
      for (final point in keyPoints) {
        buffer.writeln('- $point');
      }
    }
    return buffer.toString().trim();
  }
}

enum DocumentSort { newest, oldest }

/// Search text and sort order for the Documents screen.
class DocumentsQuery {
  const DocumentsQuery({this.search = '', this.sort = DocumentSort.newest});

  final String search;
  final DocumentSort sort;

  DocumentsQuery copyWith({String? search, DocumentSort? sort}) =>
      DocumentsQuery(search: search ?? this.search, sort: sort ?? this.sort);

  @override
  bool operator ==(Object other) =>
      other is DocumentsQuery && other.search == search && other.sort == sort;

  @override
  int get hashCode => Object.hash(search, sort);
}

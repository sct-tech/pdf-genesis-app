class AppUser {
  const AppUser({
    required this.id,
    this.name,
    this.email,
    this.avatarUrl,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      name: json['name'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }

  final String id;
  final String? name;
  final String? email;
  final String? avatarUrl;

  String get displayName {
    final trimmed = name?.trim() ?? '';
    return trimmed.isEmpty ? (email ?? 'Account') : trimmed;
  }

  String get firstName => displayName.split(' ').first;
}

/// Stored documents against the storage cap, plus today's activity counters
/// and what is left of the daily Ask AI allowance.
class Usage {
  const Usage({
    required this.documentsUsed,
    required this.documentsLimit,
    required this.pdfUploadsToday,
    required this.aiChatsToday,
    required this.summariesToday,
    this.questionsLeft,
    this.questionsLimit,
    this.summariesLeft,
    this.aiMaxPages,
  });

  factory Usage.fromJson(Map<String, dynamic> json) {
    final documents = json['documents'] as Map<String, dynamic>;
    final today = json['today'] as Map<String, dynamic>;
    final limits = json['limits'] as Map<String, dynamic>?;
    final questions = limits?['questions'] as Map<String, dynamic>?;
    final summaries = limits?['summaries'] as Map<String, dynamic>?;
    return Usage(
      documentsUsed: documents['used'] as int,
      documentsLimit: documents['limit'] as int,
      pdfUploadsToday: today['pdfUploads'] as int,
      aiChatsToday: today['aiChats'] as int,
      summariesToday: today['summaries'] as int,
      questionsLeft: questions?['remaining'] as int?,
      questionsLimit: questions?['limit'] as int?,
      summariesLeft: summaries?['remaining'] as int?,
      aiMaxPages: limits?['aiMaxPages'] as int?,
    );
  }

  final int documentsUsed;
  final int documentsLimit;
  final int pdfUploadsToday;
  final int aiChatsToday;
  final int summariesToday;

  /// Questions the user can still ask today. Null when the API does not
  /// report an allowance.
  final int? questionsLeft;
  final int? questionsLimit;

  /// New summaries the user can still generate today.
  final int? summariesLeft;

  /// Longest PDF, in pages, that Ask AI and summaries accept.
  final int? aiMaxPages;

  bool get atDocumentLimit => documentsUsed >= documentsLimit;

  double get documentsFraction => documentsLimit == 0
      ? 0
      : (documentsUsed / documentsLimit).clamp(0, 1).toDouble();
}

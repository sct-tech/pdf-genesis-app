class AppUser {
  const AppUser({
    required this.id,
    required this.isGuest,
    required this.isPro,
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
      isGuest: (json['isGuest'] as bool?) ?? false,
      isPro: json['plan'] == 'PRO',
    );
  }

  final String id;
  final String? name;
  final String? email;
  final String? avatarUrl;
  final bool isGuest;
  final bool isPro;

  String get displayName {
    if (isGuest) return 'Guest';
    final trimmed = name?.trim() ?? '';
    return trimmed.isEmpty ? (email ?? 'Account') : trimmed;
  }

  String get firstName => displayName.split(' ').first;

  String get planLabel => isPro ? 'Pro plan' : 'Free plan';
}

/// Stored documents against the plan cap, plus today's activity counters.
class Usage {
  const Usage({
    required this.documentsUsed,
    required this.documentsLimit,
    required this.pdfUploadsToday,
    required this.aiChatsToday,
    required this.summariesToday,
  });

  factory Usage.fromJson(Map<String, dynamic> json) {
    final documents = json['documents'] as Map<String, dynamic>;
    final today = json['today'] as Map<String, dynamic>;
    return Usage(
      documentsUsed: documents['used'] as int,
      documentsLimit: documents['limit'] as int,
      pdfUploadsToday: today['pdfUploads'] as int,
      aiChatsToday: today['aiChats'] as int,
      summariesToday: today['summaries'] as int,
    );
  }

  final int documentsUsed;
  final int documentsLimit;
  final int pdfUploadsToday;
  final int aiChatsToday;
  final int summariesToday;

  bool get atDocumentLimit => documentsUsed >= documentsLimit;

  double get documentsFraction => documentsLimit == 0
      ? 0
      : (documentsUsed / documentsLimit).clamp(0, 1).toDouble();
}

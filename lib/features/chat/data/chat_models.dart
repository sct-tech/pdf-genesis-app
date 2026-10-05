class MessageSource {
  const MessageSource({required this.page, required this.pageEnd});

  factory MessageSource.fromJson(Map<String, dynamic> json) {
    final page = json['page'] as int;
    return MessageSource(
      page: page,
      pageEnd: (json['pageEnd'] as int?) ?? page,
    );
  }

  final int page;
  final int pageEnd;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.isUser,
    required this.content,
    this.sources = const [],
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      isUser: json['role'] == 'USER',
      content: json['content'] as String,
      sources: [
        for (final source in (json['sources'] as List<dynamic>? ?? const []))
          MessageSource.fromJson(source as Map<String, dynamic>),
      ],
    );
  }

  final String id;
  final bool isUser;
  final String content;
  final List<MessageSource> sources;

  /// Page references without repeats, in reading order.
  List<MessageSource> get uniqueSources {
    final seen = <String>{};
    final unique = [
      for (final source in sources)
        if (seen.add('${source.page}-${source.pageEnd}')) source,
    ];
    return unique..sort((a, b) => a.page.compareTo(b.page));
  }
}

/// What the API returns for one question.
class ChatReply {
  const ChatReply({
    required this.userMessage,
    required this.assistantMessage,
    required this.followUpQuestions,
    this.questionsLeftToday,
  });

  factory ChatReply.fromJson(Map<String, dynamic> json) {
    return ChatReply(
      userMessage: ChatMessage.fromJson(
        json['userMessage'] as Map<String, dynamic>,
      ),
      assistantMessage: ChatMessage.fromJson(
        json['assistantMessage'] as Map<String, dynamic>,
      ),
      followUpQuestions: [
        for (final question
            in (json['followUpQuestions'] as List<dynamic>? ?? const []))
          question as String,
      ],
      questionsLeftToday: json['questionsLeftToday'] as int?,
    );
  }

  final ChatMessage userMessage;
  final ChatMessage assistantMessage;
  final List<String> followUpQuestions;

  /// What is left of the daily allowance after this question.
  final int? questionsLeftToday;
}

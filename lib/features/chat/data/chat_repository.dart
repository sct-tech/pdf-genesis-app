import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'chat_models.dart';

class ChatRepository {
  ChatRepository(this._api);

  final ApiClient _api;

  /// Returns the new conversation's id.
  Future<String> createConversation(String documentId) async {
    final data = await _api.post(
      '/conversations',
      body: {'documentId': documentId},
    ) as Map<String, dynamic>;
    return data['id'] as String;
  }

  Future<List<ChatMessage>> messages(String conversationId) async {
    final data = await _api.get(
      '/conversations/$conversationId/messages',
    ) as Map<String, dynamic>;
    return [
      for (final message in (data['messages'] as List<dynamic>? ?? const []))
        ChatMessage.fromJson(message as Map<String, dynamic>),
    ];
  }

  Future<ChatReply> send(String conversationId, String content) async {
    final data = await _api.post(
      '/conversations/$conversationId/messages',
      body: {'content': content},
    );
    return ChatReply.fromJson(data as Map<String, dynamic>);
  }

  Future<void> clearAll() => _api.delete('/conversations');
}

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(apiClientProvider)),
);

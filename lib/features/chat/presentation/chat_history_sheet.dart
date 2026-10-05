import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../documents/data/document.dart';
import '../data/chat_repository.dart';

/// What the user picked in the history sheet.
sealed class ChatHistoryChoice {
  const ChatHistoryChoice();
}

class NewChat extends ChatHistoryChoice {
  const NewChat();
}

class OpenConversation extends ChatHistoryChoice {
  const OpenConversation(this.id);

  final String id;
}

/// Conversations about one document, most recently used first.
final conversationsProvider = FutureProvider.autoDispose
    .family<List<ConversationPreview>, String>(
      (ref, documentId) =>
          ref.watch(chatRepositoryProvider).conversations(documentId),
    );

/// Lists the conversations about a document. Resolves to the choice made, or
/// null when the sheet is dismissed.
Future<ChatHistoryChoice?> showChatHistorySheet(
  BuildContext context, {
  required String documentId,
  required String? currentId,
}) {
  return showModalBottomSheet<ChatHistoryChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scrollController) => _ChatHistory(
        documentId: documentId,
        currentId: currentId,
        scrollController: scrollController,
      ),
    ),
  );
}

class _ChatHistory extends ConsumerWidget {
  const _ChatHistory({
    required this.documentId,
    required this.currentId,
    required this.scrollController,
  });

  final String documentId;
  final String? currentId;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final conversations = ref.watch(conversationsProvider(documentId));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(
            children: [
              Expanded(child: Text('Chat history', style: text.titleLarge)),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(const NewChat()),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('New chat'),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: conversations.when(
            loading: () => const LoadingView(),
            error: (error, _) => MessageView.error(
              message: errorMessage(error),
              onRetry: () => ref.invalidate(conversationsProvider(documentId)),
            ),
            data: (items) => items.isEmpty
                ? const MessageView(
                    icon: Icons.forum_outlined,
                    title: 'No conversations yet',
                    message: 'Questions you ask about this PDF are kept here.',
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(indent: 20),
                    itemBuilder: (context, index) => _ConversationTile(
                      conversation: items[index],
                      current: items[index].id == currentId,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.current});

  final ConversationPreview conversation;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      selected: current,
      onTap: () => Navigator.of(context).pop(OpenConversation(conversation.id)),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conversation.title,
              style: text.titleSmall?.copyWith(
                color: current ? AppColors.primary : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(formatRelative(conversation.updatedAt), style: text.bodySmall),
        ],
      ),
      subtitle: conversation.lastMessage == null
          ? null
          : Text(
              conversation.lastMessage!,
              style: text.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: current
          ? const Icon(Icons.check_rounded, color: AppColors.primary, size: 20)
          : null,
    );
  }
}

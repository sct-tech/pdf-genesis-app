import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../auth/presentation/google_sign_in_flow.dart';
import '../../documents/data/documents_repository.dart';
import '../application/ask_ai_access.dart';
import '../data/chat_models.dart';
import '../data/chat_repository.dart';
import 'ask_ai_sign_in.dart';

/// Conversation about one document. Chat is always tied to a document, so
/// this screen is reached from a document, never from a global tab.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.documentId,
    this.conversationId,
    this.initialQuestion,
  });

  final String documentId;

  /// Resume this conversation; a new one is created on the first question.
  final String? conversationId;

  /// Sent as soon as the screen opens (a tapped suggested question).
  final String? initialQuestion;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  final List<ChatMessage> _messages = [];
  List<String> _followUps = const [];
  String? _conversationId;

  bool _loadingHistory = false;
  Object? _historyError;

  /// Question waiting for an answer, shown as a bubble with a typing row.
  String? _pendingQuestion;

  /// Question whose answer failed, kept so Retry can resend it.
  String? _failedQuestion;
  String? _sendError;

  bool get _sending => _pendingQuestion != null;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    // A guest sees the sign-in prompt instead; nothing is loaded or sent
    if (!ref.read(askAiAvailableProvider)) return;
    if (_conversationId != null) {
      _loadHistory();
    } else if (widget.initialQuestion != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _send(widget.initialQuestion!),
      );
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final messages = await ref
          .read(chatRepositoryProvider)
          .messages(_conversationId!);
      if (!mounted) return;
      setState(() => _messages.addAll(messages));
      _scrollToEnd();
    } catch (error) {
      if (mounted) setState(() => _historyError = error);
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String raw) async {
    final question = raw.trim();
    if (question.isEmpty || _sending) return;

    _input.clear();
    setState(() {
      _pendingQuestion = question;
      _failedQuestion = null;
      _sendError = null;
      _followUps = const [];
    });
    _scrollToEnd();

    try {
      final repository = ref.read(chatRepositoryProvider);
      _conversationId ??= await repository.createConversation(
        widget.documentId,
      );
      final reply = await repository.send(_conversationId!, question);
      ref.read(analyticsProvider).logEvent('ai_chat');
      if (!mounted) return;
      setState(() {
        _messages
          ..add(reply.userMessage)
          ..add(reply.assistantMessage);
        _followUps = reply.followUpQuestions;
        _pendingQuestion = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pendingQuestion = null;
        _failedQuestion = question;
        _sendError = errorMessage(error);
      });
    }
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    final title = ref
        .watch(documentDetailProvider(widget.documentId))
        .value
        ?.title;
    final isEmpty = _messages.isEmpty && !_sending && _failedQuestion == null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const PdfTile(size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title ?? 'Chat',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: ContentWidth(
        maxWidth: ContentWidths.chat,
        child: SafeArea(
          child: !ref.watch(askAiAvailableProvider)
              ? MessageView(
                  icon: Icons.lock_outline_rounded,
                  title: askAiSignInTitle,
                  message: askAiSignInMessage,
                  actionLabel: 'Continue with Google',
                  onAction: () => signInWithGoogleFlow(context, ref),
                )
              : Column(
                  children: [
                    Expanded(
                      child: _loadingHistory
                          ? const LoadingView()
                          : _historyError != null
                          ? MessageView.error(
                              message: errorMessage(_historyError!),
                              onRetry: _loadHistory,
                            )
                          : isEmpty
                          ? _EmptyChat(
                              documentId: widget.documentId,
                              onPick: _send,
                            )
                          : _buildMessages(),
                    ),
                    _InputBar(
                      controller: _input,
                      sending: _sending,
                      onSend: _send,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildMessages() {
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        for (final message in _messages)
          message.isUser
              ? _UserBubble(text: message.content)
              : _AssistantBubble(message: message),
        if (_pendingQuestion != null) ...[
          _UserBubble(text: _pendingQuestion!),
          const _TypingRow(),
        ],
        if (_failedQuestion != null) ...[
          _UserBubble(text: _failedQuestion!, failed: true),
          _RetryRow(
            message: _sendError ?? 'Could not get an answer.',
            onRetry: () => _send(_failedQuestion!),
          ),
        ],
        if (_followUps.isNotEmpty && !_sending)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final question in _followUps)
                  _SuggestionChip(
                    label: question,
                    onTap: () => _send(question),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyChat extends ConsumerWidget {
  const _EmptyChat({required this.documentId, required this.onPick});

  final String documentId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final questions =
        ref.watch(suggestedQuestionsProvider(documentId)).value ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
      children: [
        const Center(
          child: CircleAvatar(
            radius: 32,
            backgroundColor: AppColors.primaryTint,
            child: Icon(Icons.auto_awesome, color: AppColors.primary, size: 28),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Ask anything about this PDF',
          style: text.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Answers come only from this document, with page references.',
          style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        for (final question in questions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SuggestionChip(
              label: question,
              onTap: () => onPick(question),
              expanded: true,
            ),
          ),
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.label,
    required this.onTap,
    this.expanded = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final content = Text(label, style: Theme.of(context).textTheme.bodyMedium);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(expanded ? 14 : 999),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: expanded
              ? Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: content),
                  ],
                )
              : content,
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text, this.failed = false});

  final String text;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 48, bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: failed ? AppColors.textSubtle : AppColors.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.message});

  final ChatMessage message;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (context.mounted) showAppSnackBar(context, 'Answer copied');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sources = message.uniqueSources;

    return Container(
      margin: const EdgeInsets.only(right: 24, bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: MarkdownBody(
              data: message.content,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(p: text.bodyLarge, listBullet: text.bodyLarge),
            ),
          ),
          if (sources.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final source in sources)
                  Pill(
                    label: formatPageRef(source.page, source.pageEnd),
                    foreground: AppColors.primary,
                    background: AppColors.primaryTint,
                    leading: const Icon(
                      Icons.find_in_page_outlined,
                      size: 12,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => _copy(context),
              tooltip: 'Copy answer',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
              icon: const Icon(
                Icons.copy_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingRow extends StatelessWidget {
  const _TypingRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Reading the document…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RetryRow extends StatelessWidget {
  const _RetryRow({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.danger),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Ask anything from this PDF…',
                counterText: '',
                fillColor: AppColors.surfaceMuted,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const IconButton(
            // Voice input is planned; shown disabled as a preview
            onPressed: null,
            tooltip: 'Voice - Coming Soon',
            icon: Icon(Icons.mic_none_rounded),
          ),
          IconButton.filled(
            onPressed: sending ? null : () => onSend(controller.text),
            tooltip: 'Send',
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

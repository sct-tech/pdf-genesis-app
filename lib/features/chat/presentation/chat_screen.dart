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
import '../../auth/application/auth_controller.dart';
import '../../documents/data/documents_repository.dart';
import '../data/chat_models.dart';
import '../data/chat_repository.dart';
import 'chat_history_sheet.dart';

/// Conversation about one document. Chat is always tied to a document, so
/// this screen is reached from a document, never from a global tab.
///
/// Opening it continues the most recent conversation, so earlier questions
/// and answers are still there. The history button lists the others and
/// starts a new one.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.documentId,
    this.conversationId,
    this.initialQuestion,
  });

  final String documentId;

  /// Open this conversation instead of the most recent one.
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

  /// False when the failure is one that asking again today cannot fix.
  bool _canRetry = true;

  /// Questions left in today's allowance, once the API has reported it.
  int? _questionsLeft;
  int? _questionsLimit;

  bool get _sending => _pendingQuestion != null;

  bool get _outOfQuestions => _questionsLeft == 0;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    _begin();
  }

  Future<void> _begin() async {
    // The allowance is known before the first frame of the conversation, so
    // an exhausted one never shows as askable
    await Future.wait([_loadAllowance(), _restore()]);
    final question = widget.initialQuestion;
    if (question != null && mounted && _historyError == null) _send(question);
  }

  /// Best effort: the chat works without the count, it only loses the hint.
  Future<void> _loadAllowance() async {
    try {
      final usage = await ref.read(usageProvider.future);
      if (!mounted) return;
      setState(() {
        _questionsLeft = usage.questionsLeft;
        _questionsLimit = usage.questionsLimit;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Loads the conversation to show: the one asked for, else the most
  /// recent one about this document, else none (a new chat).
  Future<void> _restore() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final repository = ref.read(chatRepositoryProvider);
      var id = _conversationId;
      if (id == null) {
        final conversations = await repository.conversations(widget.documentId);
        id = conversations.firstOrNull?.id;
      }
      final messages = id == null
          ? const <ChatMessage>[]
          : await repository.messages(id);
      if (!mounted) return;
      setState(() {
        _conversationId = id;
        _messages
          ..clear()
          ..addAll(messages);
      });
      _scrollToEnd();
    } catch (error) {
      if (mounted) setState(() => _historyError = error);
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _resetThread(String? conversationId) {
    _conversationId = conversationId;
    _messages.clear();
    _followUps = const [];
    _failedQuestion = null;
    _sendError = null;
    _canRetry = true;
  }

  void _startNewChat() => setState(() => _resetThread(null));

  Future<void> _openHistory() async {
    final choice = await showChatHistorySheet(
      context,
      documentId: widget.documentId,
      currentId: _conversationId,
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case NewChat():
        _startNewChat();
      case OpenConversation(:final id):
        if (id == _conversationId) return;
        setState(() => _resetThread(id));
        await _restore();
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
      _canRetry = true;
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
        _questionsLeft = reply.questionsLeftToday ?? _questionsLeft;
      });
      ref.invalidate(usageProvider);
    } catch (error) {
      if (!mounted) return;
      final api = error is ApiException ? error : null;
      setState(() {
        _pendingQuestion = null;
        if (api?.isDailyLimit ?? false) {
          // The limit bar takes over from the input and says why
          _questionsLeft = 0;
          return;
        }
        _failedQuestion = question;
        _sendError = errorMessage(error);
        _canRetry = !(api?.isFinalForToday ?? false);
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
        actions: [
          IconButton(
            tooltip: 'New chat',
            // Nothing to start over from while the chat is still empty
            onPressed: _sending || _loadingHistory || isEmpty
                ? null
                : _startNewChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: 'Chat history',
            onPressed: _sending || _loadingHistory ? null : _openHistory,
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: ContentWidth(
        maxWidth: ContentWidths.chat,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _loadingHistory
                    ? const LoadingView()
                    : _historyError != null
                    ? MessageView.error(
                        message: errorMessage(_historyError!),
                        onRetry: _restore,
                      )
                    : isEmpty
                    ? _EmptyChat(
                        documentId: widget.documentId,
                        canAsk: !_outOfQuestions,
                        onPick: _send,
                      )
                    : _buildMessages(),
              ),
              if (_outOfQuestions)
                _LimitReachedBar(limit: _questionsLimit)
              else ...[
                if (_questionsLeft != null)
                  _AllowanceHint(
                    left: _questionsLeft!,
                    limit: _questionsLimit,
                  ),
                _InputBar(controller: _input, sending: _sending, onSend: _send),
              ],
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
            onRetry: _canRetry ? () => _send(_failedQuestion!) : null,
          ),
        ],
        if (_followUps.isNotEmpty && !_sending && !_outOfQuestions)
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
  const _EmptyChat({
    required this.documentId,
    required this.canAsk,
    required this.onPick,
  });

  final String documentId;

  /// False once today's questions are used: nothing is offered to tap, and
  /// the document is not prepared for questions that cannot be asked.
  final bool canAsk;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final questions = canAsk
        ? ref.watch(suggestedQuestionsProvider(documentId)).value ?? const []
        : const <String>[];

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

  /// Null when asking again cannot help, which hides the button.
  final VoidCallback? onRetry;

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
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// How much of today's free allowance is left, shown above the input.
class _AllowanceHint extends StatelessWidget {
  const _AllowanceHint({required this.left, required this.limit});

  final int left;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final label = limit == null
        ? '$left free ${left == 1 ? 'question' : 'questions'} left today'
        : '$left of $limit free questions left today';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bolt_rounded, size: 14, color: AppColors.textSubtle),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Takes the place of the input once today's questions are used.
class _LimitReachedBar extends StatelessWidget {
  const _LimitReachedBar({required this.limit});

  final int? limit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final asked = limit == null
        ? "today's free questions"
        : "today's $limit free questions";
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primaryTint,
            child: Icon(
              Icons.schedule_rounded,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Daily limit reached', style: text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'You have asked $asked. You can ask again tomorrow.',
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
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

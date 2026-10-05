import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_genesis/core/storage/token_storage.dart';
import 'package:pdf_genesis/core/theme/app_theme.dart';
import 'package:pdf_genesis/features/auth/application/auth_controller.dart';
import 'package:pdf_genesis/features/auth/data/app_user.dart';
import 'package:pdf_genesis/features/chat/data/chat_models.dart';
import 'package:pdf_genesis/features/chat/data/chat_repository.dart';
import 'package:pdf_genesis/features/documents/data/document.dart';

class FakeTokenStorage implements TokenStorage {
  FakeTokenStorage({this.access, this.refresh});

  String? access;
  String? refresh;

  @override
  Future<String?> get accessToken async => access;

  @override
  Future<String?> get refreshToken async => refresh;

  @override
  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }
}

typedef FakeHandler = ({int status, Object body}) Function(
  RequestOptions request,
);

/// Answers Dio requests from a function, recording each one.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final FakeHandler handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = handler(options);
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// An auth controller pinned to a fixed user (or signed out).
class FakeAuthController extends AuthController {
  FakeAuthController(this.user);

  final AppUser? user;

  @override
  Future<AppUser?> build() async => user;
}

const googleUser = AppUser(
  id: 'user-1',
  name: 'Milan Patel',
  email: 'milan@example.com',
);

Document document({
  String id = 'doc-1',
  String title = 'Q3 Financial Report',
  ProcessingStatus status = ProcessingStatus.ready,
  int? pageCount = 42,
  String? stage,
  String? error,
  bool hasSummary = false,
  List<String> suggestedQuestions = const [],
}) {
  return Document(
    id: id,
    title: title,
    fileSize: 12 * 1024 * 1024,
    pageCount: pageCount,
    status: status,
    stage: stage,
    error: error,
    hasSummary: hasSummary,
    suggestedQuestions: suggestedQuestions,
    createdAt: DateTime(2026, 10, 2),
  );
}

/// Pumps [child] in the app theme at a phone-sized surface, so a layout
/// overflow on a real device fails the test.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  required List<Override> overrides,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      // As in the app
      retry: (retryCount, error) => null,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, app) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: app!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
}

/// Unmounts the tree so periodic timers started by a screen are cancelled.
Future<void> unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

/// Chat backend held in memory: conversations by id, newest first.
class FakeChatRepository implements ChatRepository {
  FakeChatRepository({
    Map<String, List<ChatMessage>>? conversations,
    this.failListing = false,
    this.questionsLeft,
    this.sendError,
  }) : threads = {...?conversations};

  /// Insertion order is "most recently used first".
  final Map<String, List<ChatMessage>> threads;
  final bool failListing;

  /// Allowance before the next question; each answer takes one.
  int? questionsLeft;

  /// Thrown by [send] instead of answering.
  final Object? sendError;
  final List<String> created = [];
  final List<({String conversationId, String content})> sent = [];

  @override
  Future<List<ConversationPreview>> conversations(String documentId) async {
    if (failListing) throw Exception('offline');
    return [
      for (final MapEntry(key: id, value: messages) in threads.entries)
        ConversationPreview(
          id: id,
          title: messages.isEmpty ? 'New chat' : messages.first.content,
          updatedAt: DateTime(2026, 10, 5),
          lastMessage: messages.lastOrNull?.content,
        ),
    ];
  }

  @override
  Future<List<ChatMessage>> messages(String conversationId) async =>
      threads[conversationId] ?? const [];

  @override
  Future<String> createConversation(String documentId) async {
    final id = 'new-${created.length + 1}';
    created.add(id);
    threads[id] = [];
    return id;
  }

  @override
  Future<ChatReply> send(String conversationId, String content) async {
    if (sendError != null) throw sendError!;
    sent.add((conversationId: conversationId, content: content));
    final number = sent.length;
    if (questionsLeft != null) questionsLeft = questionsLeft! - 1;
    final reply = ChatReply(
      userMessage: ChatMessage(id: 'u$number', isUser: true, content: content),
      assistantMessage: ChatMessage(
        id: 'a$number',
        isUser: false,
        content: 'Answer to: $content',
      ),
      followUpQuestions: const [],
      questionsLeftToday: questionsLeft,
    );
    threads[conversationId] = [
      ...?threads[conversationId],
      reply.userMessage,
      reply.assistantMessage,
    ];
    return reply;
  }

  @override
  Future<void> clearAll() async => threads.clear();
}

ChatMessage chatMessage(String id, String content, {bool isUser = false}) =>
    ChatMessage(id: id, isUser: isUser, content: content);

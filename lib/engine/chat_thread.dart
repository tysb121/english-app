import '../net/chat_reply.dart';
import '../net/poster.dart';
import 'api_requests.dart';
import 'chat_context.dart';
import 'chat_message.dart';

typedef IdFactory = String Function();

class ChatThread {
  ChatThread({
    IdFactory? idFactory,
    this.budget = defaultProjectionBudget,
    this.keepUserTurns = defaultKeepUserTurns,
  }) : _nextId = idFactory ?? _defaultId;

  final IdFactory _nextId;
  final int budget;
  final int keepUserTurns;

  final List<ChatMessage> messages = [];
  ContextSummary? contextSummary;
  String? lastError;
  bool busy = false;
  /// Index of the assistant bubble currently streaming, if any.
  int? streamingIndex;

  static String _defaultId() =>
      'm${DateTime.now().microsecondsSinceEpoch}';

  String _id() => _nextId();

  Map<String, Object?> toJson() => {
        'messages': [for (final m in messages) m.toJson()],
        if (contextSummary != null) 'contextSummary': contextSummary!.toJson(),
      };

  void clear() {
    messages.clear();
    contextSummary = null;
    lastError = null;
    busy = false;
    streamingIndex = null;
  }

  void restore(Object? raw) {
    messages.clear();
    contextSummary = null;
    lastError = null;
    streamingIndex = null;
    if (raw is! Map) return;
    final list = raw['messages'];
    if (list is List) {
      for (final item in list) {
        final message = ChatMessage.fromJson(item);
        if (message != null) messages.add(message);
      }
    }
    contextSummary = ContextSummary.fromJson(raw['contextSummary']);
  }

  /// Append user text and request a coach reply. Does not touch lesson dates.
  Future<String?> send({
    required String text,
    required Poster poster,
    required String apiKey,
    required String baseUrl,
    required String model,
    required String installId,
    String reasoningEffort = 'off',
    String? systemPrompt,
    void Function()? onUpdate,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '空白不发送';
    if (busy) return '正在请求';
    if (apiKey.trim().isEmpty) return '密钥无效';
    if (!baseUrl.trim().toLowerCase().startsWith('https://')) {
      return '地址只接受 https';
    }

    busy = true;
    lastError = null;
    final user = ChatMessage(id: _id(), role: ChatRole.user, content: trimmed);
    messages.add(user);
    onUpdate?.call();
    try {
      return await _complete(
        poster: poster,
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
        installId: installId,
        reasoningEffort: reasoningEffort,
        systemPrompt: systemPrompt,
        onUpdate: onUpdate,
      );
    } finally {
      busy = false;
      streamingIndex = null;
      onUpdate?.call();
    }
  }

  /// Retry the last unanswered user message without appending another user turn.
  Future<String?> retry({
    required Poster poster,
    required String apiKey,
    required String baseUrl,
    required String model,
    required String installId,
    String reasoningEffort = 'off',
    String? systemPrompt,
    void Function()? onUpdate,
  }) async {
    if (busy) return '正在请求';
    if (messages.isEmpty || messages.last.role != ChatRole.user) {
      return '没有可重试的消息';
    }
    if (apiKey.trim().isEmpty) return '密钥无效';
    busy = true;
    lastError = null;
    try {
      return await _complete(
        poster: poster,
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
        installId: installId,
        reasoningEffort: reasoningEffort,
        systemPrompt: systemPrompt,
        onUpdate: onUpdate,
      );
    } finally {
      busy = false;
      streamingIndex = null;
      onUpdate?.call();
    }
  }

  Future<String?> _complete({
    required Poster poster,
    required String apiKey,
    required String baseUrl,
    required String model,
    required String installId,
    required String reasoningEffort,
    String? systemPrompt,
    void Function()? onUpdate,
  }) async {
    var projection = projectContext(
      messages,
      summary: contextSummary,
      budget: budget,
      keepUserTurns: keepUserTurns,
    );

    // Summary stays non-stream + thinking off so compression stays stable.
    if (projection.needsSummary &&
        projection.summarizeSource != null &&
        projection.cutUserId != null) {
      final summaryCall = deepSeekSummarize(
        apiKey: apiKey,
        source: projection.summarizeSource!,
        baseUrl: baseUrl,
        model: model,
        userId: installId,
      );
      try {
        final posted = await poster.send(summaryCall);
        if (posted.status == 200) {
          final reply = parseChatReply(posted.body);
          if (reply != null && reply.finishReason == 'stop') {
            contextSummary = decideSummaryResult(
              untilMessageId: projection.cutUserId!,
              source: projection.summarizeSource!,
              summaryText: reply.content,
            );
            projection = projectContext(
              messages,
              summary: contextSummary,
              budget: budget,
              keepUserTurns: keepUserTurns,
            );
          }
        }
      } on Object {
        // Keep full history on summary failure.
      }
    }

    final history = [
      {'role': 'system', 'content': systemPrompt ?? coachSystemPrompt},
      for (final message in projection.history)
        {
          'role': message.role == ChatRole.user ? 'user' : 'assistant',
          'content': message.content,
        },
    ];

    final call = deepSeekPlainChat(
      apiKey: apiKey,
      messages: history,
      baseUrl: baseUrl,
      model: model,
      userId: installId,
      stream: true,
      reasoningEffort: reasoningEffort,
    );

    String? fail(String reason) {
      lastError = reason;
      return reason;
    }

    final assistant = ChatMessage(
      id: _id(),
      role: ChatRole.assistant,
      content: '',
      reasoning: '',
    );
    messages.add(assistant);
    streamingIndex = messages.length - 1;
    onUpdate?.call();

    var content = '';
    var reasoning = '';
    String? finish;
    int? usageTokens;
    var sawError = false;
    String? errText;
    final started = DateTime.now();

    try {
      await for (final event in openChatStream(poster, call)) {
        if (event.isError) {
          sawError = true;
          errText = event.errorMessage ??
              deepSeekStatusText(event.httpStatus ?? 0);
          break;
        }
        if (event.reasoningDelta != null) {
          reasoning += event.reasoningDelta!;
        }
        if (event.contentDelta != null) {
          content += event.contentDelta!;
        }
        if (event.finishReason != null) {
          finish = event.finishReason;
        }
        if (event.totalTokens != null) {
          usageTokens = event.totalTokens;
        }
        messages[streamingIndex!] = assistant.copyWith(
          content: content,
          reasoning: reasoning,
          usageTokens: usageTokens,
        );
        onUpdate?.call();
      }
    } on Object {
      sawError = true;
      errText = '服务暂时不可用';
    }

    final elapsedMs = DateTime.now().difference(started).inMilliseconds;

    if (sawError || content.trim().isEmpty) {
      // Remove empty / partial assistant on hard failure; keep partial if any content.
      if (content.trim().isEmpty) {
        if (streamingIndex != null &&
            streamingIndex! >= 0 &&
            streamingIndex! < messages.length &&
            messages[streamingIndex!].id == assistant.id) {
          messages.removeAt(streamingIndex!);
        }
        streamingIndex = null;
        return fail(errText ?? '服务暂时不可用');
      }
    }

    messages[streamingIndex!] = assistant.copyWith(
      content: content.trim(),
      reasoning: reasoning.trim(),
      usageTokens: usageTokens,
      elapsedMs: elapsedMs,
      finishedAt: DateTime.now(),
    );
    streamingIndex = null;
    if (finish != null && finish != 'stop' && content.trim().isEmpty) {
      return fail('服务暂时不可用');
    }
    lastError = null;
    return null;
  }
}

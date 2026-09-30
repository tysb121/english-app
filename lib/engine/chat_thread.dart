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
  int _seq = 0;

  static String _defaultId() =>
      'm${DateTime.now().microsecondsSinceEpoch}';

  String _id() {
    _seq += 1;
    return _nextId();
  }

  Map<String, Object?> toJson() => {
        'messages': [for (final m in messages) m.toJson()],
        if (contextSummary != null) 'contextSummary': contextSummary!.toJson(),
      };

  void restore(Object? raw) {
    messages.clear();
    contextSummary = null;
    lastError = null;
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
    try {
      return await _complete(
        poster: poster,
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
        installId: installId,
      );
    } finally {
      busy = false;
    }
  }

  /// Retry the last unanswered user message without appending another user turn.
  Future<String?> retry({
    required Poster poster,
    required String apiKey,
    required String baseUrl,
    required String model,
    required String installId,
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
      );
    } finally {
      busy = false;
    }
  }

  Future<String?> _complete({
    required Poster poster,
    required String apiKey,
    required String baseUrl,
    required String model,
    required String installId,
  }) async {
    var projection = projectContext(
      messages,
      summary: contextSummary,
      budget: budget,
      keepUserTurns: keepUserTurns,
    );

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
      {'role': 'system', 'content': coachSystemPrompt},
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
    );

    String? fail(String reason) {
      lastError = reason;
      return reason;
    }

    Future<Posted?> once() async {
      try {
        return await poster.send(call);
      } on Object {
        return null;
      }
    }

    var posted = await once();
    if (posted == null) {
      posted = await once();
      if (posted == null) return fail('服务暂时不可用');
    }

    bool autoRetryable(int status) =>
        status == 0 || status == 500 || status == 503 || status == 200;

    if (posted.status != 200) {
      if (autoRetryable(posted.status) &&
          posted.status != 401 &&
          posted.status != 402 &&
          posted.status != 400 &&
          posted.status != 422 &&
          posted.status != 429) {
        final again = await once();
        if (again != null) posted = again;
      }
      if (posted!.status != 200) {
        return fail(deepSeekStatusText(posted.status));
      }
    }

    final reply = parseChatReply(posted.body);
    if (reply == null || reply.content == null || reply.content!.trim().isEmpty) {
      final again = await once();
      if (again != null && again.status == 200) {
        final second = parseChatReply(again.body);
        if (second != null &&
            second.finishReason == 'stop' &&
            second.content != null &&
            second.content!.trim().isNotEmpty) {
          messages.add(
            ChatMessage(
              id: _id(),
              role: ChatRole.assistant,
              content: second.content!.trim(),
            ),
          );
          lastError = null;
          return null;
        }
      }
      return fail('服务暂时不可用');
    }
    if (reply.finishReason != 'stop') {
      return fail('服务暂时不可用');
    }

    messages.add(
      ChatMessage(
        id: _id(),
        role: ChatRole.assistant,
        content: reply.content!.trim(),
      ),
    );
    lastError = null;
    return null;
  }
}

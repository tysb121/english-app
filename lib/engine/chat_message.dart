enum ChatRole { user, assistant }

class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  /// Model chain-of-thought when thinking mode is on. Not sent back without tools.
  final String reasoning;
  /// total_tokens from API usage when present.
  final int? usageTokens;
  /// Wall time for this assistant reply.
  final int? elapsedMs;
  /// Local finish time for footer display.
  final DateTime? finishedAt;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.reasoning = '',
    this.usageTokens,
    this.elapsedMs,
    this.finishedAt,
  });

  ChatMessage copyWith({
    String? content,
    String? reasoning,
    int? usageTokens,
    int? elapsedMs,
    DateTime? finishedAt,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      reasoning: reasoning ?? this.reasoning,
      usageTokens: usageTokens ?? this.usageTokens,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'role': role == ChatRole.user ? 'user' : 'assistant',
        'content': content,
        if (reasoning.trim().isNotEmpty) 'reasoning': reasoning,
        if (usageTokens != null) 'usageTokens': usageTokens,
        if (elapsedMs != null) 'elapsedMs': elapsedMs,
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
      };

  static ChatMessage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final role = raw['role'];
    final content = raw['content'];
    if (id is! String || content is! String) return null;
    final reasoning = raw['reasoning'];
    final usage = raw['usageTokens'];
    final elapsed = raw['elapsedMs'];
    final finished = raw['finishedAt'];
    DateTime? finishedAt;
    if (finished is String) {
      finishedAt = DateTime.tryParse(finished);
    }
    if (role == 'user') {
      return ChatMessage(id: id, role: ChatRole.user, content: content);
    }
    if (role == 'assistant') {
      return ChatMessage(
        id: id,
        role: ChatRole.assistant,
        content: content,
        reasoning: reasoning is String ? reasoning : '',
        usageTokens: usage is int ? usage : null,
        elapsedMs: elapsed is int ? elapsed : null,
        finishedAt: finishedAt,
      );
    }
    return null;
  }
}

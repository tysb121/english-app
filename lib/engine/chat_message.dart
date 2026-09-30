enum ChatRole { user, assistant }

class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  /// Model chain-of-thought when thinking mode is on. Not sent back without tools.
  final String reasoning;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.reasoning = '',
  });

  ChatMessage copyWith({String? content, String? reasoning}) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      reasoning: reasoning ?? this.reasoning,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'role': role == ChatRole.user ? 'user' : 'assistant',
        'content': content,
        if (reasoning.trim().isNotEmpty) 'reasoning': reasoning,
      };

  static ChatMessage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final role = raw['role'];
    final content = raw['content'];
    if (id is! String || content is! String) return null;
    final reasoning = raw['reasoning'];
    if (role == 'user') {
      return ChatMessage(id: id, role: ChatRole.user, content: content);
    }
    if (role == 'assistant') {
      return ChatMessage(
        id: id,
        role: ChatRole.assistant,
        content: content,
        reasoning: reasoning is String ? reasoning : '',
      );
    }
    return null;
  }
}

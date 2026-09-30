enum ChatRole { user, assistant }

class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'role': role == ChatRole.user ? 'user' : 'assistant',
        'content': content,
      };

  static ChatMessage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final role = raw['role'];
    final content = raw['content'];
    if (id is! String || id.isEmpty) return null;
    if (content is! String) return null;
    if (role == 'user') {
      return ChatMessage(id: id, role: ChatRole.user, content: content);
    }
    if (role == 'assistant') {
      return ChatMessage(id: id, role: ChatRole.assistant, content: content);
    }
    return null;
  }
}

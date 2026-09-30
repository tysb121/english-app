import 'dart:convert';

class ChatReply {
  final String? content;
  final String? finishReason;
  final int? tokens;

  const ChatReply({this.content, this.finishReason, this.tokens});
}

ChatReply? parseChatReply(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return null;
    }
    final first = choices.first as Map;
    final message = first['message'];
    final content = message is Map ? message['content'] : null;
    final reason = first['finish_reason'];
    final usage = decoded['usage'];
    int? tokens;
    if (usage is Map) {
      final total = usage['total_tokens'];
      if (total is int) tokens = total;
    }
    return ChatReply(
      content: content is String ? content : null,
      finishReason: reason is String ? reason : null,
      tokens: tokens,
    );
  } on FormatException {
    return null;
  }
}

bool plainTranslation(String text) {
  final value = text.trim();
  if (value.isEmpty || value.length > 400) return false;
  if (value.contains('\n')) return false;
  if (value.contains('不要额外解释')) return false;
  return true;
}

String deepSeekStatusText(int status) {
  return switch (status) {
    401 => '密钥无效',
    402 => '余额不足',
    400 || 422 => '地址或模型名不被接受',
    429 => '稍后再试',
    _ => '服务暂时不可用',
  };
}

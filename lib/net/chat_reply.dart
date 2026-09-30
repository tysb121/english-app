import 'dart:convert';

class ChatReply {
  final String? content;
  final String? reasoningContent;
  final String? finishReason;
  final int? tokens;

  const ChatReply({
    this.content,
    this.reasoningContent,
    this.finishReason,
    this.tokens,
  });
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
    final reasoning = message is Map
        ? (message['reasoning_content'] ?? message['reasoning'])
        : null;
    final reason = first['finish_reason'];
    final usage = decoded['usage'];
    int? tokens;
    if (usage is Map) {
      final total = usage['total_tokens'];
      if (total is int) tokens = total;
    }
    return ChatReply(
      content: content is String ? content : null,
      reasoningContent: reasoning is String ? reasoning : null,
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

String deepSeekStatusText(int status, {String? body}) {
  if (status == 401) return '密钥无效';
  if (status == 402) return '余额不足';
  if (status == 429) return '稍后再试';
  if (status == 400 || status == 422) {
    final hint = deepSeekBodyHint(body);
    if (hint != null) return hint;
    return '地址或模型名不被接受';
  }
  return '服务暂时不可用';
}

/// Extra Chinese hint from API error body when status alone is misleading.
String? deepSeekBodyHint(String? body) {
  if (body == null || body.isEmpty) return null;
  final lower = body.toLowerCase();
  if (lower.contains("must contain the word") && lower.contains('json')) {
    return '探测请求格式有误';
  }
  if (lower.contains('response_format') && lower.contains('json')) {
    return '探测请求格式有误';
  }
  return null;
}

/// One short line from OpenAI-style `error.message`, for debug under the status.
String? deepSeekErrorMessageLine(String? body, {int maxLen = 96}) {
  if (body == null || body.isEmpty) return null;
  try {
    final decoded = jsonDecode(body.trim());
    if (decoded is! Map) return null;
    final err = decoded['error'];
    String? message;
    if (err is Map && err['message'] is String) {
      message = (err['message'] as String).trim();
    } else if (decoded['message'] is String) {
      message = (decoded['message'] as String).trim();
    }
    if (message == null || message.isEmpty) return null;
    if (message.length <= maxLen) return message;
    return '${message.substring(0, maxLen)}…';
  } on FormatException {
    return null;
  } on Object {
    return null;
  }
}

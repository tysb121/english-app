import 'dart:convert';

/// One SSE /chat/completions event after `data: ` is stripped.
class SseChatEvent {
  final String? reasoningDelta;
  final String? contentDelta;
  final String? finishReason;
  final int? httpStatus;
  final String? errorMessage;

  const SseChatEvent({
    this.reasoningDelta,
    this.contentDelta,
    this.finishReason,
    this.httpStatus,
    this.errorMessage,
  });

  bool get isError => httpStatus != null || errorMessage != null;
  bool get isDone => finishReason != null || errorMessage == 'done';
}

/// Parse one `data:` payload (JSON object or `[DONE]`).
SseChatEvent? parseSseDataPayload(String payload) {
  final trimmed = payload.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed == '[DONE]') {
    return const SseChatEvent(finishReason: 'stop');
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      // usage-only chunk with empty choices
      return const SseChatEvent();
    }
    final first = choices.first;
    if (first is! Map) return null;
    final delta = first['delta'];
    final message = first['message'];
    String? reasoning;
    String? content;
    if (delta is Map) {
      final r = delta['reasoning_content'] ?? delta['reasoning'];
      final c = delta['content'];
      if (r is String && r.isNotEmpty) reasoning = r;
      if (c is String && c.isNotEmpty) content = c;
    } else if (message is Map) {
      final r = message['reasoning_content'] ?? message['reasoning'];
      final c = message['content'];
      if (r is String && r.isNotEmpty) reasoning = r;
      if (c is String && c.isNotEmpty) content = c;
    }
    final finish = first['finish_reason'];
    return SseChatEvent(
      reasoningDelta: reasoning,
      contentDelta: content,
      finishReason: finish is String ? finish : null,
    );
  } on FormatException {
    return null;
  }
}

/// Split an SSE body into events (also accepts a single JSON chat reply).
List<SseChatEvent> parseSseBody(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];
  if (trimmed.startsWith('{')) {
    final one = parseSseDataPayload(trimmed);
    return one == null ? const [] : [one];
  }
  final out = <SseChatEvent>[];
  for (final line in trimmed.split('\n')) {
    final t = line.trimRight();
    if (!t.startsWith('data:')) continue;
    final payload = t.substring(5).trimLeft();
    final event = parseSseDataPayload(payload);
    if (event != null) out.add(event);
  }
  return out;
}

class StreamedChatResult {
  final String content;
  final String reasoning;
  final String? finishReason;
  final int status;

  const StreamedChatResult({
    required this.content,
    required this.reasoning,
    this.finishReason,
    this.status = 200,
  });
}

/// Fold SSE events into final content + reasoning.
StreamedChatResult foldSseEvents(Iterable<SseChatEvent> events, {int status = 200}) {
  final content = StringBuffer();
  final reasoning = StringBuffer();
  String? finish;
  for (final event in events) {
    if (event.reasoningDelta != null) reasoning.write(event.reasoningDelta);
    if (event.contentDelta != null) content.write(event.contentDelta);
    if (event.finishReason != null) finish = event.finishReason;
  }
  return StreamedChatResult(
    content: content.toString(),
    reasoning: reasoning.toString(),
    finishReason: finish,
    status: status,
  );
}

import 'dart:convert';

class ToolCallDelta {
  final int index;
  final String? id;
  final String? name;
  final String? argumentsDelta;

  const ToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsDelta,
  });
}

class AssembledToolCall {
  final int index;
  final String id;
  final String name;
  final String arguments;

  const AssembledToolCall({
    required this.index,
    required this.id,
    required this.name,
    required this.arguments,
  });
}

/// One SSE /chat/completions event after `data: ` is stripped.
class SseChatEvent {
  final String? reasoningDelta;
  final String? contentDelta;
  final List<ToolCallDelta> toolCallDeltas;
  final String? finishReason;
  final int? totalTokens;
  final int? httpStatus;
  final String? errorMessage;

  const SseChatEvent({
    this.reasoningDelta,
    this.contentDelta,
    this.toolCallDeltas = const [],
    this.finishReason,
    this.totalTokens,
    this.httpStatus,
    this.errorMessage,
  });

  bool get isError => httpStatus != null || (errorMessage != null && errorMessage != 'done');
  bool get isDone => finishReason != null || errorMessage == 'done';
}

int? _usageTotal(Object? usage) {
  if (usage is! Map) return null;
  final total = usage['total_tokens'];
  if (total is int) return total;
  if (total is num) return total.toInt();
  return null;
}

String? _nonEmptyString(Object? raw) {
  if (raw is String && raw.isNotEmpty) return raw;
  return null;
}

int _toolIndex(Object? raw, int fallback) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return fallback;
}

/// Fragments from `delta.tool_calls` or `message.tool_calls`. Arguments stay raw pieces.
List<ToolCallDelta> _toolCallDeltas(Object? raw) {
  if (raw is! List) return const [];
  final out = <ToolCallDelta>[];
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    if (item is! Map) continue;
    final id = _nonEmptyString(item['id']);
    String? name;
    String? argumentsDelta;
    final function = item['function'];
    if (function is Map) {
      name = _nonEmptyString(function['name']);
      final args = function['arguments'];
      if (args is String && args.isNotEmpty) argumentsDelta = args;
    }
    if (id == null && name == null && argumentsDelta == null) continue;
    out.add(ToolCallDelta(
      index: _toolIndex(item['index'], i),
      id: id,
      name: name,
      argumentsDelta: argumentsDelta,
    ));
  }
  return out;
}

List<ToolCallDelta> _readToolCallDeltas(Object? delta, Object? message) {
  final fromDelta = delta is Map ? _toolCallDeltas(delta['tool_calls']) : const <ToolCallDelta>[];
  final fromMessage = message is Map ? _toolCallDeltas(message['tool_calls']) : const <ToolCallDelta>[];
  if (fromDelta.isEmpty) return fromMessage;
  if (fromMessage.isEmpty) return fromDelta;
  return [...fromDelta, ...fromMessage];
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
    final usageTokens = _usageTotal(decoded['usage']);
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      // usage-only chunk with empty choices
      return SseChatEvent(totalTokens: usageTokens);
    }
    final first = choices.first;
    if (first is! Map) {
      return SseChatEvent(totalTokens: usageTokens);
    }
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
      toolCallDeltas: _readToolCallDeltas(delta, message),
      finishReason: finish is String ? finish : null,
      totalTokens: usageTokens,
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
  final int? totalTokens;
  final int status;

  const StreamedChatResult({
    required this.content,
    required this.reasoning,
    this.finishReason,
    this.totalTokens,
    this.status = 200,
  });
}

/// Fold SSE events into final content + reasoning + usage.
StreamedChatResult foldSseEvents(Iterable<SseChatEvent> events, {int status = 200}) {
  final content = StringBuffer();
  final reasoning = StringBuffer();
  String? finish;
  int? tokens;
  for (final event in events) {
    if (event.reasoningDelta != null) reasoning.write(event.reasoningDelta);
    if (event.contentDelta != null) content.write(event.contentDelta);
    if (event.finishReason != null) finish = event.finishReason;
    if (event.totalTokens != null) tokens = event.totalTokens;
  }
  return StreamedChatResult(
    content: content.toString(),
    reasoning: reasoning.toString(),
    finishReason: finish,
    totalTokens: tokens,
    status: status,
  );
}

/// Join tool-call fragments by index. Later non-empty id and name replace earlier ones.
List<AssembledToolCall> assembleToolCalls(Iterable<SseChatEvent> events) {
  final ids = <int, String>{};
  final names = <int, String>{};
  final arguments = <int, StringBuffer>{};
  final seen = <int>{};
  for (final event in events) {
    for (final delta in event.toolCallDeltas) {
      seen.add(delta.index);
      final id = delta.id;
      if (id != null && id.isNotEmpty) ids[delta.index] = id;
      final name = delta.name;
      if (name != null && name.isNotEmpty) names[delta.index] = name;
      final piece = delta.argumentsDelta;
      if (piece != null) {
        (arguments[delta.index] ??= StringBuffer()).write(piece);
      }
    }
  }
  final indexes = seen.toList()..sort();
  return [
    for (final index in indexes)
      AssembledToolCall(
        index: index,
        id: ids[index] ?? '',
        name: names[index] ?? '',
        arguments: arguments[index]?.toString() ?? '',
      ),
  ];
}

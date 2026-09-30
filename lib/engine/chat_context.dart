import 'chat_message.dart';

const defaultProjectionBudget = 12000;
const defaultKeepUserTurns = 4;

class ContextSummary {
  final String untilMessageId;
  final String text;

  const ContextSummary({required this.untilMessageId, required this.text});

  bool get isEmptyText => text.trim().isEmpty;

  Map<String, Object?> toJson() => {
        'untilMessageId': untilMessageId,
        'text': text,
      };

  static ContextSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['untilMessageId'];
    final text = raw['text'];
    if (id is! String || id.isEmpty) return null;
    if (text is! String) return null;
    return ContextSummary(untilMessageId: id, text: text);
  }
}

class Projection {
  final List<ChatMessage> history;
  final List<ChatMessage> tail;
  final String? summarizeSource;
  final String? cutUserId;
  final bool needsSummary;

  const Projection({
    required this.history,
    required this.tail,
    this.summarizeSource,
    this.cutUserId,
    this.needsSummary = false,
  });
}

int projectedChars(Iterable<ChatMessage> messages) {
  var total = 0;
  for (final message in messages) {
    final body = message.content.trim();
    if (body.isEmpty) continue;
    if (message.role != ChatRole.user && message.role != ChatRole.assistant) {
      continue;
    }
    total += body.length;
  }
  return total;
}

List<ChatMessage> projectable(List<ChatMessage> messages) {
  return [
    for (final message in messages)
      if ((message.role == ChatRole.user || message.role == ChatRole.assistant) &&
          message.content.trim().isNotEmpty)
        message,
  ];
}

String wrapCheckpoint(String text) {
  return '以下是更早对话的检查点。把它当作已成立的背景，从后面的消息继续，不要复述这段检查点。\n'
      '\n'
      '<compacted-summary>\n'
      '${text.trim()}\n'
      '</compacted-summary>';
}

String formatSummarySource(
  List<ChatMessage> messages, {
  ContextSummary? previous,
  required String untilMessageId,
}) {
  final buf = StringBuffer();
  var started = false;
  if (previous != null && previous.text.trim().isNotEmpty) {
    final prevIndex = messages.indexWhere((m) => m.id == previous.untilMessageId);
    final cutIndex = messages.indexWhere((m) => m.id == untilMessageId);
    if (prevIndex >= 0 && cutIndex > prevIndex) {
      buf.writeln('已有检查点：');
      buf.writeln(previous.text.trim());
      buf.writeln();
      for (var i = prevIndex + 1; i < cutIndex; i++) {
        final message = messages[i];
        final body = message.content.trim();
        if (body.isEmpty) continue;
        final label = message.role == ChatRole.user ? '用户：' : '助手：';
        buf.writeln('$label$body');
        started = true;
      }
      return buf.toString().trim();
    }
  }
  for (final message in messages) {
    if (message.id == untilMessageId) break;
    final body = message.content.trim();
    if (body.isEmpty) continue;
    if (message.role != ChatRole.user && message.role != ChatRole.assistant) {
      continue;
    }
    final label = message.role == ChatRole.user ? '用户：' : '助手：';
    buf.writeln('$label$body');
    started = true;
  }
  return started ? buf.toString().trim() : '';
}

Projection projectContext(
  List<ChatMessage> rawMessages, {
  ContextSummary? summary,
  int budget = defaultProjectionBudget,
  int keepUserTurns = defaultKeepUserTurns,
}) {
  final messages = projectable(rawMessages);
  final userIds = [
    for (final message in messages)
      if (message.role == ChatRole.user) message.id,
  ];

  if (projectedChars(messages) <= budget || userIds.length <= keepUserTurns) {
    return Projection(history: messages, tail: messages);
  }

  final cutUserId = userIds[userIds.length - keepUserTurns];
  final cutIndex = messages.indexWhere((m) => m.id == cutUserId);
  final tail = messages.sublist(cutIndex);

  if (summary != null && summary.untilMessageId == cutUserId) {
    if (!summary.isEmptyText) {
      final checkpoint = ChatMessage(
        id: 'checkpoint:$cutUserId',
        role: ChatRole.user,
        content: wrapCheckpoint(summary.text),
      );
      return Projection(
        history: [checkpoint, ...tail],
        tail: tail,
        cutUserId: cutUserId,
      );
    }
    return Projection(history: messages, tail: messages, cutUserId: cutUserId);
  }

  final source = formatSummarySource(
    messages,
    previous: summary,
    untilMessageId: cutUserId,
  );
  if (source.trim().isEmpty) {
    return Projection(history: messages, tail: messages, cutUserId: cutUserId);
  }

  return Projection(
    history: messages,
    tail: tail,
    summarizeSource: source,
    cutUserId: cutUserId,
    needsSummary: true,
  );
}

ContextSummary decideSummaryResult({
  required String untilMessageId,
  required String source,
  required String? summaryText,
}) {
  final text = (summaryText ?? '').trim();
  if (text.isNotEmpty && text.length < source.trim().length) {
    return ContextSummary(untilMessageId: untilMessageId, text: text);
  }
  return ContextSummary(untilMessageId: untilMessageId, text: '');
}

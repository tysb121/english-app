import 'dart:convert';

import '../net/poster.dart';
import '../net/sse_chat.dart';
import 'agent_tools.dart';
import 'api_requests.dart';
import 'gradebook.dart';

const classOpenCue =
    '新的一节开始，学生还没说话。用工具读记录，不要把这一步说出来。然后只用中文跟他说第一句。';

/// 学生已经提交，但这一问还没有成功的 record_attempt。不画在屏幕上。
const recordNudge =
    '这次作答还没记下。不要再写给学生看的话。没有学习项就先 add_item，下一截用返回的 id 调用 record_attempt。';

/// 短系统提示。previousCloseNote 非空时附在末尾，标题为「上一节」。
String buildAgentSystem({String? previousCloseNote}) {
  final prompt = StringBuffer()
    ..writeln('你是「今日英语」的老师。')
    ..writeln('用工具决定下一题、难度和复习。成绩只有工具成功才算记下。')
    ..writeln('不要改写学生原话。标成「会用」之前，必须已经有一次答案没显示、并且判为通过的作答。')
    ..writeln('旧课不在这段对话里。要查过去，就用工具。')
    ..writeln('能点选的题用 present_card。要学生写出整句时，再让他打字。卡片参数里不要放正确答案。')
    ..writeln('同一类错误反复出现，先复习，不往前赶。')
    ..writeln('连续轻松，就加难度，并推迟复习。')
    ..writeln('连续吃力，就把这一步改短，并提前复习。')
    ..write('一次只推进一步。对学生说的话只用中文。英文只写正在练的那一句。')
    ..write('不要用英文开场。读记录、调用工具和思考不要说出来。')
    ..write('调用工具的那一截不要同时写给学生看的正文。')
    ..write('学生一提交句子或确认卡片，这一问先记下作答：没有学习项就先 add_item，下一截再用返回的 id 调用 record_attempt。')
    ..write('这两步完成前不要出卡片，也不要先讲解。没记成功不要当成已经记下。');
  final note = previousCloseNote?.trim();
  if (note != null && note.isNotEmpty) {
    prompt
      ..writeln()
      ..writeln()
      ..writeln('上一节')
      ..write(note);
  }
  return prompt.toString();
}

class AgentTurnUpdate {
  final String visibleText;
  final String? status;
  final AnswerCard? card;
  final String? error;
  final bool done;
  final bool endClass;

  const AgentTurnUpdate({
    required this.visibleText,
    this.status,
    this.card,
    this.error,
    this.done = false,
    this.endClass = false,
  });
}

/// 跑完一轮（最多 4 截）。通过 onUpdate 报告流式正文。
Future<AgentTurnUpdate> runAgentTurn({
  required Poster poster,
  required List<Map<String, Object?>> messages,
  required Gradebook book,
  required PendingSubmission? pending,
  required bool cardPending,
  required String apiKey,
  required String baseUrl,
  required String model,
  required String installId,
  void Function(AgentTurnUpdate update)? onUpdate,
  int maxSlices = 4,
  String? classId,
}) async {
  final visible = StringBuffer();
  var endClass = false;
  final thread = <Map<String, Object?>>[
    for (final message in messages) Map<String, Object?>.from(message),
  ];

  AgentTurnUpdate publish(AgentTurnUpdate update) {
    onUpdate?.call(update);
    return update;
  }

  AgentTurnUpdate snapshot({
    String? status,
    AnswerCard? card,
    String? error,
    bool done = false,
  }) {
    return AgentTurnUpdate(
      visibleText: visible.toString(),
      status: status,
      card: card,
      error: error,
      done: done,
      endClass: endClass,
    );
  }

  for (var slice = 0; slice < maxSlices; slice++) {
    final call = deepSeekAgentChat(
      apiKey: apiKey,
      messages: [
        for (final message in thread) Map<String, Object?>.from(message),
      ],
      tools: agentToolSchemas,
      baseUrl: baseUrl,
      model: model,
      userId: installId,
    );
    final events = <SseChatEvent>[];
    final sliceText = StringBuffer();
    String? errorText;
    await for (final event in openChatStream(poster, call)) {
      events.add(event);
      if (event.httpStatus != null ||
          (event.errorMessage != null && event.errorMessage != 'done')) {
        final raw = event.errorMessage;
        errorText = (raw == null || raw.isEmpty || raw == 'done')
            ? '服务暂时不可用'
            : raw;
        break;
      }
      final delta = event.contentDelta;
      if (delta != null && delta.isNotEmpty) {
        sliceText.write(delta);
        visible.write(delta);
        publish(snapshot());
      }
      if (event.finishReason != null) break;
    }
    if (errorText != null) {
      return publish(snapshot(error: errorText, done: true));
    }

    final toolCalls = assembleToolCalls(events);
    if (toolCalls.isEmpty) {
      final waitingRecord = pending != null && !pending.consumed;
      if (waitingRecord && slice < maxSlices - 1) {
        thread.add({
          'role': 'assistant',
          'content': sliceText.toString(),
        });
        thread.add({'role': 'user', 'content': recordNudge});
        continue;
      }
      return publish(snapshot(done: true));
    }

    publish(snapshot(status: '在看记录'));

    final assistantCalls = <Map<String, Object?>>[];
    final toolMessages = <Map<String, Object?>>[];
    AnswerCard? card;
    // Queries and writes run before the card. end_class still runs, but a
    // valid card in this slice keeps the class open until the student answers.
    final outcomes = List<ToolOutcome?>.filled(toolCalls.length, null);
    ToolOutcome execute(int index, {required bool cardAlready}) {
      final toolCall = toolCalls[index];
      final args = _objectArgs(toolCall.arguments);
      if (args == null) {
        return const ToolOutcome(
          content: '{"ok":false,"error":"参数不是 JSON"}',
          ok: false,
        );
      }
      return runTool(
        name: toolCall.name,
        args: args,
        book: book,
        pending: pending,
        cardPending: cardAlready,
        classId: classId,
      );
    }

    for (var i = 0; i < toolCalls.length; i++) {
      final name = toolCalls[i].name;
      if (name == 'present_card' || name == 'end_class') continue;
      outcomes[i] = execute(i, cardAlready: cardPending);
    }
    var raised = cardPending;
    for (var i = 0; i < toolCalls.length; i++) {
      if (toolCalls[i].name != 'present_card') continue;
      final outcome = execute(i, cardAlready: raised);
      outcomes[i] = outcome;
      if (outcome.card != null) {
        card = outcome.card;
        raised = true;
      }
    }
    for (var i = 0; i < toolCalls.length; i++) {
      if (toolCalls[i].name != 'end_class') continue;
      final outcome = execute(i, cardAlready: raised);
      outcomes[i] = outcome;
      if (outcome.endClass) endClass = true;
    }
    for (var i = 0; i < toolCalls.length; i++) {
      final toolCall = toolCalls[i];
      final outcome = outcomes[i]!;
      assistantCalls.add({
        'id': toolCall.id,
        'type': 'function',
        'function': {
          'name': toolCall.name,
          'arguments': toolCall.arguments,
        },
      });
      toolMessages.add({
        'role': 'tool',
        'tool_call_id': toolCall.id,
        'content': outcome.content,
      });
    }

    thread.add({
      'role': 'assistant',
      'content': sliceText.toString(),
      'tool_calls': assistantCalls,
    });
    thread.addAll(toolMessages);

    if (card != null) {
      return publish(snapshot(card: card, done: true));
    }
    if (endClass && visible.toString().trim().isNotEmpty) {
      return publish(snapshot(done: true));
    }
    if (pending != null &&
        pending.consumed &&
        visible.toString().trim().isNotEmpty) {
      return publish(snapshot(done: true));
    }
    if (slice == maxSlices - 1) {
      if (visible.isEmpty) {
        return publish(snapshot(error: '再发一次', done: true));
      }
      return publish(snapshot(done: true));
    }
  }

  if (visible.isEmpty) {
    return publish(snapshot(error: '再发一次', done: true));
  }
  return publish(snapshot(done: true));
}

/// Object arguments only. Invalid JSON or a non-object stays unparsed.
Map<String, Object?>? _objectArgs(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return null;
    return decoded.map((key, value) => MapEntry('$key', value as Object?));
  } on FormatException {
    return null;
  }
}

import 'dart:convert';

import 'package:english_app/app/app_model.dart';
import 'package:english_app/app/class_coach.dart';
import 'package:english_app/engine/agent_loop.dart';
import 'package:english_app/engine/agent_tools.dart';
import 'package:english_app/engine/api_requests.dart';
import 'package:english_app/engine/chat_message.dart';
import 'package:english_app/net/poster.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cefr_fixture.dart';

void main() {
  test('end_class closes and the next request drops the old bubble', () async {
    final poster = _ScriptPoster([
      _chat(
        content: '今天先到这',
        toolCalls: [_call('end_class', '{}')],
      ),
      _chat(content: '我们继续'),
    ]);
    final coach = _coach(poster);

    await coach.ensureGreeting();

    expect(poster.calls, hasLength(2));
    expect(coach.log.classes, hasLength(2));
    expect(coach.log.classes.first.isOpen, isFalse);
    expect(coach.log.classes.first.messages.single.content, '今天先到这');
    expect(coach.log.classes.last.isOpen, isTrue);
    expect(coach.log.classes.last.messages.single.content, '我们继续');
    expect(_body(poster.calls[1]).contains('今天先到这'), isFalse);
    expect(_body(poster.calls[1]), contains(classOpenCue));
  });

  test('a card delays end_class until the follow-up turn finishes', () async {
    final cardArgs = jsonEncode({
      'kind': 'choice',
      'prompt': '选一个',
      'options': [
        {'id': 'a', 'text': 'apple'},
        {'id': 'b', 'text': 'banana'},
      ],
    });
    final poster = _ScriptPoster([
      _chat(
        content: '来',
        toolCalls: [
          _call('present_card', cardArgs),
          _call('end_class', '{}'),
        ],
      ),
      _chat(content: '对了'),
      _chat(content: '下一节'),
    ]);
    final coach = _coach(poster);

    await coach.ensureGreeting();

    expect(coach.log.classes, hasLength(1));
    expect(coach.log.classes.single.isOpen, isTrue);
    expect(coach.pendingCard, isNotNull);
    expect(poster.calls, hasLength(1));

    await coach.confirmCard(optionId: 'a');

    expect(coach.pendingCard, isNull);
    expect(coach.log.classes, hasLength(2));
    expect(coach.log.classes.first.isOpen, isFalse);
    expect(
      coach.log.classes.first.messages.map((message) => message.content),
      ['来', 'apple', '对了'],
    );
    expect(coach.log.classes.last.messages.single.content, '下一节');
    expect(_body(poster.calls[1]), contains('apple'));
    expect(_body(poster.calls[2]).contains('apple'), isFalse);
    expect(_body(poster.calls[2]), contains(classOpenCue));
  });

  test('two hours later an open card is dropped and the old bubble stays home', () async {
    final poster = _ScriptPoster([_chat(content: '新的一节')]);
    final coach = _coach(poster);
    final open = coach.log.ensureOpen(DateTime.now());
    open.messages.add(
      const ChatMessage(id: 'old', role: ChatRole.assistant, content: '旧课气泡'),
    );
    open.lastMessageAt = DateTime.now().subtract(const Duration(hours: 2));
    coach.pendingCard = const AnswerCard(
      id: 'card-1',
      kind: CardKind.choice,
      prompt: '选',
      options: [
        CardOption(id: 'a', text: 'A'),
        CardOption(id: 'b', text: 'B'),
      ],
    );

    await coach.ensureGreeting();

    expect(coach.pendingCard, isNull);
    expect(coach.log.classes, hasLength(2));
    expect(coach.log.classes.first.isOpen, isFalse);
    expect(coach.log.classes.first.messages.single.content, '旧课气泡');
    expect(coach.log.classes.last.messages.single.content, '新的一节');
    expect(_body(poster.calls.single).contains('旧课气泡'), isFalse);
  });

  test('six judged attempts open the next class after the teacher finishes', () async {
    final poster = _ScriptPoster([
      _chat(content: '这一节先到这'),
      _chat(content: '下一节的第一句'),
    ]);
    final coach = _coach(poster);
    final open = coach.log.ensureOpen(DateTime.now());
    open.messages.add(
      const ChatMessage(id: 'u', role: ChatRole.user, content: 'hi'),
    );
    open.userTurns = 1;
    open.judged = 6;
    open.lastMessageAt = DateTime.now();

    await coach.retry();

    expect(coach.log.classes, hasLength(2));
    expect(coach.log.classes.first.isOpen, isFalse);
    expect(
      coach.log.classes.first.messages.map((message) => message.content),
      ['hi', '这一节先到这'],
    );
    expect(coach.log.classes.last.messages.single.content, '下一节的第一句');
    expect(_contents(poster.calls[1]), isNot(contains('hi')));
    expect(_contents(poster.calls[1]), contains(classOpenCue));
  });
}

ClassCoach _coach(_ScriptPoster poster) {
  final model = AppModel(
    store: fixtureStore(clock: () => DateTime(2026, 10, 4)),
    poster: poster,
    deepSeekKey: 'test-key',
    unlocked: true,
  );
  return model.classCoach;
}

String _body(ApiCall call) => jsonEncode(call.body);

List<String> _contents(ApiCall call) {
  final messages = call.body['messages'];
  if (messages is! List) return const [];
  return [
    for (final message in messages)
      if (message is Map && message['content'] is String)
        message['content'] as String,
  ];
}

String _chat({String? content, List<Map<String, Object?>>? toolCalls}) {
  return jsonEncode({
    'choices': [
      {
        'message': {
          'role': 'assistant',
          'content': content,
          if (toolCalls != null) 'tool_calls': toolCalls,
        },
        'finish_reason': toolCalls == null ? 'stop' : 'tool_calls',
      },
    ],
  });
}

Map<String, Object?> _call(String name, String arguments) {
  return {
    'id': name,
    'type': 'function',
    'function': {'name': name, 'arguments': arguments},
  };
}

class _ScriptPoster implements Poster {
  _ScriptPoster(this._replies);

  final List<String> _replies;
  final List<ApiCall> calls = [];

  @override
  Future<Posted> send(ApiCall call) async {
    calls.add(call);
    if (_replies.isEmpty) return const Posted(503, '');
    return Posted(200, _replies.removeAt(0));
  }
}

import 'dart:convert';

import 'package:english_app/engine/agent_loop.dart';
import 'package:english_app/engine/agent_tools.dart';
import 'package:english_app/engine/api_requests.dart';
import 'package:english_app/engine/gradebook.dart';
import 'package:english_app/net/poster.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stop slice shows text and sends tools without response_format', () async {
    final book = Gradebook();
    final before = book.toJson();
    final poster = _ScriptPoster([
      _chatJson(content: '看这题', finishReason: 'stop'),
    ]);
    final messages = _opening();
    final updates = <AgentTurnUpdate>[];

    final result = await runAgentTurn(
      poster: poster,
      messages: messages,
      book: book,
      pending: null,
      cardPending: false,
      apiKey: 'k',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      installId: 'install-1',
      onUpdate: updates.add,
    );

    expect(result.visibleText, '看这题');
    expect(result.card, isNull);
    expect(result.error, isNull);
    expect(result.done, isTrue);
    expect(book.toJson(), before);
    expect(updates.any((update) => update.visibleText == '看这题'), isTrue);

    final body = poster.calls.single.body;
    expect(body['tools'], agentToolSchemas);
    expect(body.containsKey('response_format'), isFalse);
    expect(body['stream'], isTrue);
    expect(body['temperature'], 0.4);
    expect(body['stream_options'], {'include_usage': true});
    expect(body['thinking'], {'type': 'disabled'});
    expect(body.containsKey('reasoning_effort'), isFalse);
    expect(body['user_id'], 'install-1');
    expect(body['messages'], messages);
  });

  test('present_card stops after one slice and hides option JSON', () async {
    final book = Gradebook();
    final args = jsonEncode({
      'kind': 'choice',
      'prompt': '选一个',
      'options': [
        {'id': 'a', 'text': 'apple'},
        {'id': 'b', 'text': 'banana'},
      ],
    });
    final poster = _ScriptPoster([
      _chatJson(
        content: '来',
        finishReason: 'tool_calls',
        toolCalls: [
          _functionCall(id: 'call_card', name: 'present_card', arguments: args),
        ],
      ),
    ]);

    final result = await runAgentTurn(
      poster: poster,
      messages: _opening(),
      book: book,
      pending: null,
      cardPending: false,
      apiKey: 'k',
      baseUrl: 'https://api.deepseek.com',
      model: 'm',
      installId: 'id',
    );

    expect(poster.calls, hasLength(1));
    expect(result.card, isNotNull);
    expect(result.card!.kind, CardKind.choice);
    expect(result.card!.options, hasLength(2));
    expect(result.visibleText, '来');
    expect(result.visibleText.contains('"kind"'), isFalse);
    expect(result.done, isTrue);
    expect(book.items, isEmpty);
  });

  test('add_item then a spoken slice keeps one item and the tool reply', () async {
    const oldBubble = '昨天的旧课气泡：I go to school yesterday';
    final book = Gradebook();
    final args = jsonEncode({
      'prompt_cn': '更难的一句',
      'target_en': 'This one is harder.',
      'difficulty': 3,
      'reason': '连续通过',
    });
    final poster = _ScriptPoster([
      _chatJson(
        finishReason: 'tool_calls',
        toolCalls: [
          _functionCall(id: 'call_add', name: 'add_item', arguments: args),
        ],
      ),
      _chatJson(content: '下一句更难', finishReason: 'stop'),
    ]);
    final updates = <AgentTurnUpdate>[];
    final messages = _opening();

    final result = await runAgentTurn(
      poster: poster,
      messages: messages,
      book: book,
      pending: null,
      cardPending: false,
      apiKey: 'k',
      baseUrl: 'https://api.deepseek.com',
      model: 'm',
      installId: 'id',
      onUpdate: updates.add,
    );

    expect(book.items, hasLength(1));
    expect(book.items.single.targetEn, 'This one is harder.');
    expect(result.visibleText, '下一句更难');
    expect(result.card, isNull);
    expect(result.done, isTrue);
    expect(updates.any((update) => update.status == '在看记录'), isTrue);
    expect(poster.calls, hasLength(2));

    final first = poster.calls[0].body['messages'] as List;
    final second = poster.calls[1].body['messages'] as List;
    expect(first.any((message) => message is Map && message['role'] == 'tool'), isFalse);
    expect(second.any((message) => message is Map && message['role'] == 'tool'), isTrue);
    expect(jsonEncode(second).contains(oldBubble), isFalse);
    expect(jsonEncode(first).contains(oldBubble), isFalse);
    expect(jsonEncode(messages).contains(oldBubble), isFalse);
  });

  test('four empty get_learner slices ask the student to send again', () async {
    final book = Gradebook();
    final slice = _chatJson(
      finishReason: 'tool_calls',
      toolCalls: [
        _functionCall(id: 'call_read', name: 'get_learner', arguments: '{}'),
      ],
    );
    final poster = _ScriptPoster([slice, slice, slice, slice]);

    final result = await runAgentTurn(
      poster: poster,
      messages: _opening(),
      book: book,
      pending: null,
      cardPending: false,
      apiKey: 'k',
      baseUrl: 'https://api.deepseek.com',
      model: 'm',
      installId: 'id',
    );

    expect(result.error, contains('再发一次'));
    expect(result.done, isTrue);
    expect(result.card, isNull);
    expect(result.visibleText, isEmpty);
    expect(book.items, isEmpty);
    expect(poster.calls, hasLength(4));
  });

  test('a card in the same slice still keeps earlier writes', () async {
    final book = Gradebook();
    final addArgs = jsonEncode({
      'prompt_cn': '更难的一句',
      'target_en': 'This one is harder.',
      'difficulty': 3,
    });
    final cardArgs = jsonEncode({
      'kind': 'choice',
      'prompt': '选一个',
      'options': [
        {'id': 'a', 'text': 'apple'},
        {'id': 'b', 'text': 'banana'},
      ],
    });
    final poster = _ScriptPoster([
      _chatJson(
        content: '来',
        finishReason: 'tool_calls',
        toolCalls: [
          _functionCall(id: 'call_card', name: 'present_card', arguments: cardArgs),
          _functionCall(id: 'call_add', name: 'add_item', arguments: addArgs),
        ],
      ),
      _chatJson(content: '不该再请求', finishReason: 'stop'),
    ]);

    final result = await runAgentTurn(
      poster: poster,
      messages: _opening(),
      book: book,
      pending: null,
      cardPending: false,
      apiKey: 'k',
      baseUrl: 'https://api.deepseek.com',
      model: 'm',
      installId: 'id',
    );

    expect(poster.calls, hasLength(1));
    expect(book.items, hasLength(1));
    expect(book.items.single.targetEn, 'This one is harder.');
    expect(result.card, isNotNull);
    expect(result.endClass, isFalse);
    expect(result.visibleText, '来');
  });

  test('end_class with speech does not request another slice', () async {
    final book = Gradebook();
    final poster = _ScriptPoster([
      _chatJson(
        content: '今天先到这',
        finishReason: 'tool_calls',
        toolCalls: [
          _functionCall(id: 'call_end', name: 'end_class', arguments: '{}'),
        ],
      ),
      _chatJson(content: '不该再请求', finishReason: 'stop'),
    ]);

    final result = await runAgentTurn(
      poster: poster,
      messages: _opening(),
      book: book,
      pending: null,
      cardPending: false,
      apiKey: 'k',
      baseUrl: 'https://api.deepseek.com',
      model: 'm',
      installId: 'id',
    );

    expect(poster.calls, hasLength(1));
    expect(result.endClass, isTrue);
    expect(result.card, isNull);
    expect(result.visibleText, '今天先到这');
    expect(book.items, isEmpty);
  });

  test('system prompt appends the previous close note', () {
    final prompt = buildAgentSystem();
    expect(prompt, contains('今日英语'));
    expect(prompt, contains('会用'));
    expect(prompt, contains('present_card'));
    expect(prompt, contains('不要改写'));
    expect(prompt, contains('先复习'));
    expect(prompt, contains('加难度'));
    expect(prompt, contains('只用中文'));
    expect(prompt, contains('不要用英文开场'));
    expect(prompt, contains('不要说出来'));
    expect(prompt, contains('add_item'));
    expect(prompt, contains('record_attempt'));
    expect(prompt, contains('这两步完成前不要出卡片'));
    expect(prompt.contains('上一节'), isFalse);

    final withNote = buildAgentSystem(previousCloseNote: '练了 apple\n最近一次：对\n无');
    expect(withNote, contains('上一节'));
    expect(withNote.indexOf('上一节'), greaterThan(withNote.indexOf('今日英语')));
    expect(withNote, endsWith('练了 apple\n最近一次：对\n无'));
    expect(buildAgentSystem(previousCloseNote: '  ').contains('上一节'), isFalse);
    expect(classOpenCue, contains('新的一节开始'));
    expect(classOpenCue, contains('不要把这一步说出来'));
    expect(classOpenCue, contains('只用中文'));
  });

  test('opening turn hides the cue and keeps record-reading narration out', () async {
    final book = Gradebook();
    final poster = _ScriptPoster([
      _chatJson(
        finishReason: 'tool_calls',
        toolCalls: [
          _functionCall(id: 'call_read', name: 'get_learner', arguments: '{}'),
        ],
      ),
      _chatJson(
        content: '你好。记录是空的，我们先练一句打招呼。',
        finishReason: 'stop',
      ),
    ]);
    final messages = _opening();

    final result = await runAgentTurn(
      poster: poster,
      messages: messages,
      book: book,
      pending: null,
      cardPending: false,
      apiKey: 'k',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      installId: 'install-1',
    );

    expect(result.done, isTrue);
    expect(result.card, isNull);
    expect(result.error, isNull);
    expect(result.visibleText, '你好。记录是空的，我们先练一句打招呼。');
    expect(result.visibleText.contains(classOpenCue), isFalse);
    expect(result.visibleText.contains("I'll start by reading"), isFalse);
    expect(result.visibleText.contains('reading the student'), isFalse);
    expect(result.visibleText.contains('reading the learner'), isFalse);
    expect(result.visibleText.contains('get_learner'), isFalse);
    expect(result.visibleText.contains('"arguments"'), isFalse);
    expect(poster.calls, hasLength(2));

    final sent = jsonEncode(poster.calls.first.body['messages']);
    expect(sent, contains(classOpenCue));
    expect(sent, contains('不要把这一步说出来'));
    expect(sent, contains('只用中文'));
    expect(sent, contains('不要用英文开场'));
    expect(book.items, isEmpty);
  });

  test('a spoken stop still records the submitted sentence before stopping', () async {
    var n = 0;
    final book = Gradebook(
      ids: () {
        n += 1;
        return 'id-$n';
      },
    );
    const submitted = '这句我不会，请用中文告诉我。';
    final pending = PendingSubmission(text: submitted);
    final poster = _ScriptPoster([
      _chatJson(
        content: '先看这句。英文是：I get up at seven every morning.',
        finishReason: 'stop',
      ),
      _chatJson(
        finishReason: 'tool_calls',
        toolCalls: [
          _functionCall(
            id: 'call_add',
            name: 'add_item',
            arguments: jsonEncode({
              'prompt_cn': '我每天早上七点起床。',
              'target_en': 'I get up at seven every morning.',
              'difficulty': 1,
            }),
          ),
        ],
      ),
      _chatJson(
        finishReason: 'tool_calls',
        toolCalls: [
          _functionCall(
            id: 'call_rec',
            name: 'record_attempt',
            arguments: jsonEncode({
              'item_id': 'id-1',
              'pass': false,
              'corrected_en': 'I get up at seven every morning.',
              'revealed': true,
              'error_tag': '其它',
              'submission': '模型改写的原文',
            }),
          ),
        ],
      ),
      _chatJson(content: '不该再写给学生', finishReason: 'stop'),
    ]);

    final result = await runAgentTurn(
      poster: poster,
      messages: _opening(),
      book: book,
      pending: pending,
      cardPending: false,
      apiKey: 'k',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      installId: 'install-1',
    );

    expect(result.done, isTrue);
    expect(result.card, isNull);
    expect(result.error, isNull);
    expect(result.visibleText, '先看这句。英文是：I get up at seven every morning.');
    expect(result.visibleText.contains(recordNudge), isFalse);
    expect(result.visibleText.contains('不该再写给学生'), isFalse);
    expect(poster.calls, hasLength(3));
    final nudged = jsonEncode(poster.calls[1].body['messages']);
    expect(nudged, contains(recordNudge));
    expect(book.attempts, hasLength(1));
    expect(book.attempts.single.submission, submitted);
    expect(book.attempts.single.submission.contains('模型改写的原文'), isFalse);
    expect(book.items.single.targetEn, 'I get up at seven every morning.');
    expect(pending.consumed, isTrue);
  });
}

List<Map<String, Object?>> _opening() {
  return [
    {'role': 'system', 'content': buildAgentSystem()},
    {'role': 'user', 'content': classOpenCue},
  ];
}

String _chatJson({
  String? content,
  required String finishReason,
  List<Map<String, Object?>>? toolCalls,
}) {
  return jsonEncode({
    'choices': [
      {
        'message': {
          'role': 'assistant',
          'content': content,
          if (toolCalls != null) 'tool_calls': toolCalls,
        },
        'finish_reason': finishReason,
      },
    ],
  });
}

Map<String, Object?> _functionCall({
  required String id,
  required String name,
  required String arguments,
}) {
  return {
    'id': id,
    'type': 'function',
    'function': {
      'name': name,
      'arguments': arguments,
    },
  };
}

class _ScriptPoster implements Poster {
  _ScriptPoster(this._replies);

  final List<String> _replies;
  final List<ApiCall> calls = [];

  @override
  Future<Posted> send(ApiCall call) async {
    calls.add(call);
    if (_replies.isEmpty) return const Posted(500, '');
    return Posted(200, _replies.removeAt(0));
  }
}

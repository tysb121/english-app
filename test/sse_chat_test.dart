import 'package:english_app/engine/api_requests.dart';
import 'package:english_app/engine/chat_message.dart';
import 'package:english_app/engine/chat_thread.dart';
import 'package:english_app/engine/reasoning_effort.dart';
import 'package:english_app/net/poster.dart';
import 'package:english_app/net/sse_chat.dart';
import 'package:english_app/ui/thinking_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseSseDataPayload splits reasoning and content deltas', () {
    final reasoning = parseSseDataPayload(
      '{"choices":[{"delta":{"reasoning_content":"先想一步"}}]}',
    );
    expect(reasoning?.reasoningDelta, '先想一步');
    expect(reasoning?.contentDelta, isNull);

    final content = parseSseDataPayload(
      '{"choices":[{"delta":{"content":"你好"},"finish_reason":null}]}',
    );
    expect(content?.contentDelta, '你好');

    final done = parseSseDataPayload('[DONE]');
    expect(done?.finishReason, 'stop');
  });

  test('parseSseBody folds multi-line SSE', () {
    const raw = '''
data: {"choices":[{"delta":{"reasoning_content":"A"}}]}

data: {"choices":[{"delta":{"reasoning_content":"B","content":"Hi"}}]}

data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

data: [DONE]
''';
    final folded = foldSseEvents(parseSseBody(raw));
    expect(folded.reasoning, 'AB');
    expect(folded.content, 'Hi');
    expect(folded.finishReason, 'stop');
  });

  test('deepSeekThinkingFields maps UI effort to API', () {
    expect(deepSeekThinkingFields('off')['thinking'], {'type': 'disabled'});
    expect(deepSeekThinkingFields('off').containsKey('reasoning_effort'), isFalse);

    expect(deepSeekThinkingFields('low')['thinking'], {'type': 'enabled'});
    expect(deepSeekThinkingFields('low')['reasoning_effort'], 'low');

    // API has no medium; docs map medium → high.
    expect(deepSeekThinkingFields('medium')['reasoning_effort'], 'high');
    expect(deepSeekThinkingFields('high')['reasoning_effort'], 'high');
  });

  test('plain chat stream request enables stream flag', () {
    final call = deepSeekPlainChat(
      apiKey: 'k',
      messages: [
        {'role': 'user', 'content': 'hi'},
      ],
      stream: true,
      reasoningEffort: 'high',
    );
    expect(call.body['stream'], isTrue);
    expect(call.body['thinking'], {'type': 'enabled'});
    expect(call.body['reasoning_effort'], 'high');
    expect(call.body.containsKey('response_format'), isFalse);
  });

  test('ChatThread streams reasoning into assistant message', () async {
    var ids = 0;
    final thread = ChatThread(idFactory: () => 's${++ids}');
    const sse = '''
data: {"choices":[{"delta":{"reasoning_content":"想一下"}}]}

data: {"choices":[{"delta":{"content":"练一句 "}}]}

data: {"choices":[{"delta":{"content":"OK。"},"finish_reason":"stop"}]}

data: [DONE]
''';
    final poster = ScriptPoster([const Posted(200, sse)]);
    final updates = <int>[];
    final err = await thread.send(
      text: 'hi',
      poster: poster,
      apiKey: 'k',
      baseUrl: 'https://api.deepseek.com',
      model: 'm',
      installId: 'id',
      reasoningEffort: 'low',
      onUpdate: () => updates.add(thread.messages.length),
    );
    expect(err, isNull);
    expect(poster.calls.single.body['stream'], isTrue);
    expect(poster.calls.single.body['reasoning_effort'], 'low');
    expect(thread.messages.last.role, ChatRole.assistant);
    expect(thread.messages.last.reasoning, '想一下');
    expect(thread.messages.last.content, '练一句 OK。');
    expect(updates, isNotEmpty);
  });

  testWidgets('ThinkingPanel shows collapsible reasoning', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThinkingPanel(reasoning: '逐步推理', streaming: false),
        ),
      ),
    );
    expect(find.text('思考过程'), findsOneWidget);
    await tester.tap(find.text('思考过程'));
    await tester.pumpAndSettle();
    expect(find.text('逐步推理'), findsOneWidget);
  });
}

class ScriptPoster implements Poster {
  ScriptPoster(this._replies);
  final List<Posted> _replies;
  final List<ApiCall> calls = [];

  @override
  Future<Posted> send(ApiCall call) async {
    calls.add(call);
    if (_replies.isEmpty) return const Posted(500, '');
    return _replies.removeAt(0);
  }
}

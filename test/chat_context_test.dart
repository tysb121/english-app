import 'package:english_app/app/progress_shell.dart';
import 'package:english_app/engine/api_requests.dart';
import 'package:english_app/engine/chat_context.dart';
import 'package:english_app/engine/chat_message.dart';
import 'package:english_app/engine/chat_thread.dart';
import 'package:english_app/net/poster.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cefr_fixture.dart';

ChatMessage u(String id, String text) =>
    ChatMessage(id: id, role: ChatRole.user, content: text);
ChatMessage a(String id, String text) =>
    ChatMessage(id: id, role: ChatRole.assistant, content: text);

void main() {
  test('projection stays full under budget or few user turns', () {
    final messages = [u('1', 'hi'), a('2', 'hello')];
    final p = projectContext(messages, budget: 12000);
    expect(p.needsSummary, isFalse);
    expect(p.history, messages);
  });

  test('over budget with many users keeps last four user turns as tail', () {
    final messages = <ChatMessage>[];
    for (var i = 1; i <= 6; i++) {
      messages.add(u('u$i', 'user-$i-${'x' * 3000}'));
      messages.add(a('a$i', 'asst-$i'));
    }
    final p = projectContext(messages, budget: 100);
    expect(p.needsSummary, isTrue);
    expect(p.cutUserId, 'u3');
    expect(p.tail.first.id, 'u3');
    expect(p.summarizeSource, isNotEmpty);
  });

  test('matching non-empty checkpoint uses checkpoint plus tail', () {
    final messages = <ChatMessage>[];
    for (var i = 1; i <= 6; i++) {
      messages.add(u('u$i', 'user-$i-${'x' * 3000}'));
      messages.add(a('a$i', 'asst-$i'));
    }
    final summary = ContextSummary(untilMessageId: 'u3', text: '检查点正文');
    final p = projectContext(messages, summary: summary, budget: 100);
    expect(p.needsSummary, isFalse);
    expect(p.history.first.content.contains('检查点正文'), isTrue);
    expect(p.history.skip(1).first.id, 'u3');
  });

  test('matching empty checkpoint keeps full history and skips summarize', () {
    final messages = <ChatMessage>[];
    for (var i = 1; i <= 6; i++) {
      messages.add(u('u$i', 'user-$i-${'x' * 3000}'));
      messages.add(a('a$i', 'asst-$i'));
    }
    final summary = ContextSummary(untilMessageId: 'u3', text: '');
    final p = projectContext(messages, summary: summary, budget: 100);
    expect(p.needsSummary, isFalse);
    expect(p.history.length, messages.length);
  });

  test('previous checkpoint feeds summarize source', () {
    final messages = [
      u('u1', 'one'),
      a('a1', 'A'),
      u('u2', 'two'),
      a('a2', 'B'),
      u('u3', 'three'),
      a('a3', 'C'),
      u('u4', 'four'),
      a('a4', 'D'),
      u('u5', 'five'),
    ];
    final previous = ContextSummary(untilMessageId: 'u1', text: '旧检查点');
    final source = formatSummarySource(
      messages,
      previous: previous,
      untilMessageId: 'u2',
    );
    expect(source.contains('已有检查点'), isTrue);
    expect(source.contains('旧检查点'), isTrue);
    expect(source.contains('用户：two'), isFalse); // cut is until u2 exclusive of u2
  });

  test('summary shorter is kept; not shorter stores empty text', () {
    final short = decideSummaryResult(
      untilMessageId: 'u3',
      source: '很长的原文内容在这里',
      summaryText: '短',
    );
    expect(short.text, '短');
    final long = decideSummaryResult(
      untilMessageId: 'u3',
      source: '短',
      summaryText: '没有更短的摘要内容',
    );
    expect(long.text, isEmpty);
  });

  test('plain chat builders do not force json_object', () {
    final call = deepSeekPlainChat(
      apiKey: 'k',
      messages: [
        {'role': 'user', 'content': 'hi'},
      ],
    );
    expect(call.body.containsKey('response_format'), isFalse);
    expect(call.body['temperature'], 0.4);
    final sum = deepSeekSummarize(apiKey: 'k', source: '源');
    expect(sum.body['temperature'], 0);
    expect(sum.body.containsKey('response_format'), isFalse);
  });

  test('send failure keeps one user message; retry does not add another', () async {
    var ids = 0;
    final thread = ChatThread(
      idFactory: () {
        ids += 1;
        return 'id$ids';
      },
      budget: 50,
      keepUserTurns: 4,
    );
    final poster = ScriptPoster([
      Posted(500, 'nope'),
      Posted(500, 'nope'),
      Posted(500, 'nope'),
      Posted(500, 'nope'),
    ]);
    final err = await thread.send(
      text: 'hello',
      poster: poster,
      apiKey: 'k',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      installId: 'install',
    );
    expect(err, isNotNull);
    expect(thread.messages.where((m) => m.role == ChatRole.user).length, 1);
    final before = thread.messages.length;
    await thread.retry(
      poster: poster,
      apiKey: 'k',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      installId: 'install',
    );
    expect(thread.messages.where((m) => m.role == ChatRole.user).length, 1);
    expect(thread.messages.length, before);
  });

  test('successful reply does not change lesson dates', () async {
    final store = fixtureStore(clock: () => DateTime(2026, 6, 1));
    store.ensureTodayPlan();
    final before = store.reviewSnapshot();
    final checked = store.checkedIn;
    var ids = 0;
    final thread = ChatThread(idFactory: () => 't${++ids}');
    final poster = ScriptPoster([
      Posted(
        200,
        '{"choices":[{"message":{"content":"练一句 sounds good。"},"finish_reason":"stop"}]}',
      ),
    ]);
    final err = await thread.send(
      text: '你好',
      poster: poster,
      apiKey: 'k',
      baseUrl: 'https://api.deepseek.com',
      model: 'm',
      installId: 'id',
    );
    expect(err, isNull);
    expect(thread.messages.last.role, ChatRole.assistant);
    expect(store.reviewSnapshot(), before);
    expect(store.checkedIn, checked);
  });

  test('progress shell restores legacy lesson json and keeps chat', () {
    final store = fixtureStore(clock: () => DateTime(2026, 7, 1));
    final shell = ProgressShell(store: store);
    final legacy = store.progressJson();
    shell.restore(legacy);
    expect(store.level, isNotEmpty);

    shell.chat.messages.add(u('m1', 'hi'));
    shell.chat.contextSummary =
        const ContextSummary(untilMessageId: 'm1', text: '摘要');
    final encoded = shell.encode();
    expect(encoded.contains('"kind":"english-app"'), isTrue);
    expect(encoded.contains('"lesson"'), isTrue);

    final store2 = fixtureStore(clock: () => DateTime(2026, 7, 1));
    final shell2 = ProgressShell(store: store2);
    shell2.restore(encoded);
    expect(shell2.chat.messages.single.content, 'hi');
    expect(shell2.chat.contextSummary!.text, '摘要');
  });

  test('blank text does not call poster', () async {
    final thread = ChatThread(idFactory: () => 'x');
    final poster = ScriptPoster([]);
    final err = await thread.send(
      text: '   ',
      poster: poster,
      apiKey: 'k',
      baseUrl: 'https://api.deepseek.com',
      model: 'm',
      installId: 'id',
    );
    expect(err, '空白不发送');
    expect(poster.calls, isEmpty);
    expect(thread.messages, isEmpty);
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

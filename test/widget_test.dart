import 'dart:async';
import 'dart:convert';

import 'package:english_app/app/app_model.dart';
import 'package:english_app/engine/api_requests.dart';
import 'package:english_app/engine/chat_message.dart';
import 'package:english_app/net/poster.dart';
import 'package:english_app/ui/english_app.dart';
import 'package:english_app/ui/practice_page.dart';
import 'package:english_app/ui/thinking_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cefr_fixture.dart';

void main() {
  testWidgets('first launch asks for a key', (tester) async {
    final model = AppModel(
      store: fixtureStore(clock: () => DateTime(2026, 1, 1)),
      poster: ThrowingPoster(),
    );
    await tester.pumpWidget(EnglishApp(model: model));
    expect(find.text('连接密钥'), findsOneWidget);
    expect(find.text('先选一个水平'), findsNothing);
    expect(find.text('今日练习'), findsNothing);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('先看看，稍后再填密钥'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('browse without key reaches shell tabs', (tester) async {
    final model = AppModel(
      store: fixtureStore(clock: () => DateTime(2026, 1, 1)),
      poster: ThrowingPoster(),
    );
    await tester.pumpWidget(EnglishApp(model: model));
    await tester.tap(find.text('先看看，稍后再填密钥'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('今日练习'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.textContaining('填写密钥后才能上课'), findsOneWidget);
    expect(find.textContaining('看过了'), findsNothing);
  });

  testWidgets('我的 shows product level labels and tomorrow tip when frozen', (
    tester,
  ) async {
    final store = fixtureStore(
      clock: () => DateTime(2026, 1, 1),
      levelChosen: true,
      level: '入门',
    );
    store.ensureTodayPlan();
    final model = AppModel(
      store: store,
      poster: ThrowingPoster(),
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    await tester.pumpWidget(EnglishApp(model: model));
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('日常交流'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('水平'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('入门'), findsWidgets);
    expect(find.text('基础'), findsOneWidget);
    expect(find.text('进阶'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('今日练习已开始'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('今日练习已开始'), findsOneWidget);
  });

  testWidgets('a saved key shows four tabs and the home label', (tester) async {
    final store = fixtureStore(
      clock: () => DateTime(2026, 1, 1),
      levelChosen: true,
    );
    final model = AppModel(
      store: store,
      poster: ThrowingPoster(),
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    await tester.pumpWidget(EnglishApp(model: model));
    expect(find.text('上课'), findsOneWidget);
    expect(find.text('今日练习'), findsOneWidget);
    expect(find.text('词'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('先到这'), findsOneWidget);
  });

  testWidgets('home labels follow the real store', (tester) async {
    final store = fixtureStore(
      clock: () => DateTime(2026, 7, 1),
      levelChosen: true,
    );
    final model = AppModel(
      store: store,
      poster: ThrowingPoster(),
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    store.ensureTodayPlan();
    for (final id in store.requiredTodayPlan.newWordIds) {
      store.acknowledgeWord(id);
    }
    await tester.pumpWidget(EnglishApp(model: model));
    expect(find.text('先到这'), findsOneWidget);
    expect(find.textContaining('看过了'), findsNothing);
    expect(store.checkedIn, isFalse);
  });

  testWidgets('class page draws only the open class', (tester) async {
    final store = fixtureStore(
      clock: () => DateTime(2026, 10, 4, 12),
      levelChosen: true,
    );
    final model = AppModel(
      store: store,
      poster: ThrowingPoster(),
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    final log = model.classCoach.log;
    final now = DateTime.now();
    final previous = log.ensureOpen(now);
    previous.messages.add(
      const ChatMessage(id: 'old', role: ChatRole.assistant, content: '旧课气泡'),
    );
    previous.lastMessageAt = now;
    log.closeOpen(now);
    final open = log.ensureOpen(now.add(const Duration(minutes: 1)));
    open.messages.add(
      const ChatMessage(
        id: 'new',
        role: ChatRole.assistant,
        content: '你好。我们开始这一节。',
      ),
    );
    open.lastMessageAt = now.add(const Duration(minutes: 1));

    await tester.pumpWidget(EnglishApp(model: model));
    await tester.pump();

    expect(find.text('你好。我们开始这一节。'), findsOneWidget);
    expect(find.text('旧课气泡'), findsNothing);
    expect(find.text('下一节'), findsNothing);
    expect(find.textContaining('新的一节开始'), findsNothing);
  });

  testWidgets('opening class raises a choice card before confirm', (
    tester,
  ) async {
    final view = tester.view;
    view.physicalSize = const Size(400, 960);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    final store = fixtureStore(
      clock: () => DateTime(2026, 1, 1),
      levelChosen: true,
    );
    final poster = RecordingPoster();
    poster.responses.add(
      Posted(
        200,
        '{"choices":[{"finish_reason":"tool_calls","message":{"content":"来选","tool_calls":[{"id":"c1","type":"function","function":{"name":"present_card","arguments":${jsonEncode(_choiceArgs)}}}]}}]}',
      ),
    );
    final model = AppModel(
      store: store,
      poster: poster,
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    await tester.pumpWidget(EnglishApp(model: model));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('answer-card')), findsOneWidget);
    expect(find.text('选一句'), findsWidgets);
    expect(find.text('I am a student.'), findsOneWidget);
    expect(find.text('I are student.'), findsOneWidget);
    expect(find.textContaining('"kind"'), findsNothing);
    expect(find.text('先到这'), findsOneWidget);
    await tester.tap(find.text('I are student.'));
    await tester.pump();
    await tester.tap(find.text('I am a student.'));
    await tester.pump();
    expect(find.text('确认'), findsOneWidget);
    expect(poster.calls, hasLength(1));
    expect(store.progressJson().contains('apiKey'), isFalse);
  });

  testWidgets('测试连接 shows progress, then the result', (tester) async {
    final poster = HeldPoster();
    final model = AppModel(
      store: fixtureStore(clock: () => DateTime(2026, 1, 2)),
      poster: poster,
    );
    await tester.pumpWidget(EnglishApp(model: model));
    await tester.enterText(_keyField, 'sk-test');
    await tester.tap(find.text('测试连接'));
    await tester.pump();
    expect(find.text('正在测试'), findsWidgets);
    expect(find.text('开始练习'), findsNothing);

    poster.finish(const Posted(401, '{"error":"bad"}'));
    await tester.pumpAndSettle();
    expect(find.text('密钥无效'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('开始练习'), findsNothing);
    expect(poster.calls, hasLength(1));

    await tester.tap(find.text('测试连接'));
    await tester.pump();
    expect(find.text('正在测试'), findsWidgets);
    poster.finish(const Posted(200, '{"choices":[]}'));
    await tester.pumpAndSettle();
    expect(find.text('已连通'), findsOneWidget);
    expect(find.text('开始练习'), findsOneWidget);

    await tester.tap(find.text('开始练习'));
    await tester.pump();
    expect(find.text('上课'), findsOneWidget);
    expect(find.text('今日练习'), findsOneWidget);
  });



  testWidgets('closing 错词 keeps the saved interval', (tester) async {
    var day = DateTime(2026, 2, 1);
    final store = fixtureStore(clock: () => day, levelChosen: true);
    store.ensureTodayPlan();
    store.submitVocab('wrong');
    day = DateTime(2026, 2, 2);
    final model = AppModel(
      store: store,
      poster: RecordingPoster(),
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(model: model, child: const PracticePage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('answer')), 'hello');
    await tester.tap(find.text('提交'));
    await tester.pump();
    expect(find.text('对了'), findsOneWidget);
    expect(find.text('3 天后再出现'), findsOneWidget);
    expect(find.text('下一条'), findsOneWidget);
    expect(
      store.nextErrorReview('cc_a1_hello_noun_ce4a5e'),
      DateTime(2026, 2, 5),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(model: model, child: const PracticePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('对了'), findsOneWidget);
    expect(find.text('下一条'), findsOneWidget);
    expect(find.text('3 天后再出现'), findsOneWidget);
    expect(find.text('提交'), findsNothing);
    expect(
      store.nextErrorReview('cc_a1_hello_noun_ce4a5e'),
      DateTime(2026, 2, 5),
    );
  });
  testWidgets('coach bubble renders markdown bold without raw markers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoachAnswerBubble(content: 'Try **I like chicken.** again.'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('I like chicken.'), findsOneWidget);
  });
}

final Finder _keyField = find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == '粘贴密钥',
);

class HeldPoster implements Poster {
  final List<ApiCall> calls = [];
  Completer<Posted>? _pending;

  void finish(Posted posted) {
    final pending = _pending;
    if (pending == null || pending.isCompleted) {
      throw StateError('no connection test is waiting');
    }
    pending.complete(posted);
  }

  @override
  Future<Posted> send(ApiCall call) {
    calls.add(call);
    final pending = Completer<Posted>();
    _pending = pending;
    return pending.future;
  }
}

class ThrowingPoster implements Poster {
  @override
  Future<Posted> send(ApiCall call) {
    throw StateError('network');
  }
}

class RecordingPoster implements Poster {
  final List<Posted> responses = [];
  final List<ApiCall> calls = [];

  @override
  Future<Posted> send(ApiCall call) async {
    calls.add(call);
    if (responses.isEmpty) return const Posted(503, '');
    return responses.removeAt(0);
  }
}

String _wrap(String content) {
  return '{"choices":[{"finish_reason":"stop","message":{"content":${jsonEncode(content)}}}],"usage":{"total_tokens":9}}';
}

const _choiceArgs =
    '{"kind":"choice","prompt":"选一句","options":[{"id":"a","text":"I am a student."},{"id":"b","text":"I are student."}]}';

const _passGrade =
    '{"pass":true,"errors":[],"corrected_en":"I finished the standup."}';

const _failGrade =
    '{"pass":false,"errors":[{"excerpt":"He go","fix":"He goes","why_cn":"第三人称单数要加 s。"}],"corrected_en":"He goes to the standup."}';

const _scene = '''
{
  "scenario_en": "Standup",
  "scenario_cn": "早会",
  "phrases": [{"en": "Let's start.", "cn": "我们开始。"}],
  "dialogue": [
    {"speaker": "A", "en": "What did you finish?", "cn": "你做完了什么？"},
    {"speaker": "B", "en": "I finished the standup.", "cn": "我开完了站会。"},
    {"speaker": "A", "en": "Any blocker?", "cn": "有阻碍吗？"},
    {"speaker": "B", "en": "No blocker.", "cn": "没有阻碍。"},
    {"speaker": "A", "en": "Please follow up.", "cn": "请跟进。"},
    {"speaker": "B", "en": "I will follow up.", "cn": "我会跟进。"}
  ],
  "grammar": {
    "point_cn": "说已经发生的事。",
    "examples": ["I finished the report.", "I sent the notes."]
  }
}
''';

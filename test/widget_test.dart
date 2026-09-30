import 'dart:async';
import 'dart:convert';

import 'package:english_app/app/app_model.dart';
import 'package:english_app/engine/api_requests.dart';
import 'package:english_app/engine/lesson_store.dart';
import 'package:english_app/net/poster.dart';
import 'package:english_app/ui/english_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('no DeepSeek key stays on settings', (tester) async {
    final model = AppModel(
      store: LessonStore(clock: () => DateTime(2026, 1, 1)),
      poster: ThrowingPoster(),
    );
    await tester.pumpWidget(EnglishApp(model: model));
    expect(find.text('今日英语'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('今天'), findsNothing);
    expect(find.text('词'), findsNothing);
    expect(find.text('记录'), findsNothing);
    expect(find.text('设置'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('a saved key shows four tabs and the home label', (tester) async {
    final store = LessonStore(clock: () => DateTime(2026, 1, 1));
    final model = AppModel(
      store: store,
      poster: ThrowingPoster(),
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    await tester.pumpWidget(EnglishApp(model: model));
    expect(find.text('今日英语'), findsWidgets);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('词'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('开始认词'), findsOneWidget);

    store.submitVocab('nope');
    model.commit();
    await tester.pump();
    expect(find.text('继续认词'), findsOneWidget);
  });

  testWidgets('home labels follow the real store', (tester) async {
    final store = LessonStore(clock: () => DateTime(2026, 7, 1));
    final model = AppModel(
      store: store,
      poster: ThrowingPoster(),
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    store.ensureTodayPlan();
    for (var i = 0; i < 4; i++) {
      store.submitVocab(store.word(store.currentVocabId!)!.en);
      store.advanceVocab();
    }
    store.submitVocab('nope');
    store.advanceVocab();
    await tester.pumpWidget(EnglishApp(model: model));
    expect(find.text('开始对话'), findsOneWidget);

    store.sceneInFlight = true;
    model.commit();
    await tester.pump();
    expect(find.text('正在写今天的场景'), findsOneWidget);

    store.sceneInFlight = false;
    expect(
      store.applyModelResponse(
        task: 'fill_scene',
        content: _scene,
        finishReason: 'stop',
      ),
      isTrue,
    );
    model.commit();
    await tester.pump();
    expect(find.text('继续对话'), findsOneWidget);

    store.markDialogueDone();
    model.commit();
    await tester.pump();
    expect(find.text('开始考核'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      store.applyModelResponse(
        task: 'grade_open',
        content: i == 3 ? _failGrade : _passGrade,
        finishReason: 'stop',
        quizIndex: i,
      );
    }
    model.commit();
    await tester.pump();
    expect(find.text('看今天的笔记'), findsOneWidget);
    expect(store.checkedIn, isTrue);
  });

  testWidgets('认词 accepts a padded answer with no network', (tester) async {
    final store = LessonStore(clock: () => DateTime(2026, 1, 1));
    final poster = RecordingPoster();
    final model = AppModel(
      store: store,
      poster: poster,
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    await tester.pumpWidget(EnglishApp(model: model));
    await tester.tap(find.text('开始认词'));
    await tester.pumpAndSettle();
    expect(find.text('站会'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('answer')), '  STANDUP  ');
    await tester.tap(find.text('提交'));
    await tester.pump();
    expect(find.text('对了'), findsOneWidget);
    expect(poster.calls, isEmpty);
    expect(store.successReviewOn('s01'), DateTime(2026, 1, 3));
    expect(store.progressJson().contains('apiKey'), isFalse);
  });

  testWidgets('quiz corrections use the real grade parser', (tester) async {
    final store = LessonStore(clock: () => DateTime(2026, 9, 1));
    store.ensureTodayPlan();
    for (var i = 0; i < 4; i++) {
      store.submitVocab(store.word(store.currentVocabId!)!.en);
      store.advanceVocab();
    }
    store.submitVocab('nope');
    store.advanceVocab();
    store.markDialogueDone();
    final poster = RecordingPoster();
    poster.responses.add(Posted(200, _wrap(_failGrade)));
    final model = AppModel(
      store: store,
      poster: poster,
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    await tester.pumpWidget(EnglishApp(model: model));
    expect(find.text('开始考核'), findsOneWidget);
    await tester.tap(find.text('开始考核'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 4'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('answer')), 'He go');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('He go'), findsWidgets);
    expect(find.text('He goes to the standup.'), findsOneWidget);
    expect(poster.calls, hasLength(1));
    final call = poster.calls.single;
    expect(call.body['max_tokens'], 400);
    expect(call.body['temperature'], 0);
    expect(call.body['thinking'], {'type': 'disabled'});
    expect(call.body.containsKey('tools'), isFalse);
    expect(call.headers['Authorization'], 'Bearer test-key');
    expect(store.quizSnapshot()[0], isFalse);
    expect(store.checkedIn, isFalse);
  });

  testWidgets('测试连接 shows progress, then the result', (tester) async {
    final poster = HeldPoster();
    final model = AppModel(
      store: LessonStore(clock: () => DateTime(2026, 1, 2)),
      poster: poster,
    );
    await tester.pumpWidget(EnglishApp(model: model));
    await tester.enterText(_keyField, 'sk-test');
    await tester.tap(find.text('测试连接'));
    await tester.pump();
    expect(find.text('正在测试'), findsWidgets);
    expect(find.text('开始今天'), findsNothing);

    poster.finish(const Posted(401, '{"error":"bad"}'));
    await tester.pumpAndSettle();
    expect(find.text('密钥无效'), findsOneWidget);
    expect(find.text('测试连接'), findsOneWidget);
    expect(find.text('开始今天'), findsNothing);
    expect(poster.calls, hasLength(1));

    await tester.tap(find.text('测试连接'));
    await tester.pump();
    expect(find.text('正在测试'), findsWidgets);
    poster.finish(const Posted(200, '{"choices":[]}'));
    await tester.pumpAndSettle();
    expect(find.text('已连通'), findsOneWidget);
    expect(find.text('开始今天'), findsOneWidget);

    await tester.tap(find.text('开始今天'));
    await tester.pumpAndSettle();
    expect(find.text('开始认词'), findsOneWidget);
  });

  testWidgets('closing 认词 shows the saved result without grading again', (
    tester,
  ) async {
    final store = LessonStore(clock: () => DateTime(2026, 1, 1));
    final poster = RecordingPoster();
    final model = AppModel(
      store: store,
      poster: poster,
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    await tester.pumpWidget(EnglishApp(model: model));
    await tester.tap(find.text('开始认词'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('answer')), '  STANDUP  ');
    await tester.tap(find.text('提交'));
    await tester.pump();
    expect(find.text('对了'), findsOneWidget);
    expect(store.successReviewOn('s01'), DateTime(2026, 1, 3));
    expect(store.successStage('s01'), 1);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('继续认词'), findsOneWidget);

    await tester.tap(find.text('继续认词'));
    await tester.pumpAndSettle();
    expect(find.text('对了'), findsOneWidget);
    expect(find.text('下一个'), findsOneWidget);
    expect(find.text('提交'), findsNothing);
    expect(store.successReviewOn('s01'), DateTime(2026, 1, 3));
    expect(store.successStage('s01'), 1);
    expect(poster.calls, isEmpty);
  });

  testWidgets('closing 错词 keeps the saved interval', (tester) async {
    var day = DateTime(2026, 2, 1);
    final store = LessonStore(clock: () => day);
    store.ensureTodayPlan();
    store.submitVocab('wrong');
    day = DateTime(2026, 2, 2);
    final model = AppModel(
      store: store,
      poster: RecordingPoster(),
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    await tester.pumpWidget(EnglishApp(model: model));
    await tester.tap(find.text('错词 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('answer')), 'standup');
    await tester.tap(find.text('提交'));
    await tester.pump();
    expect(find.text('对了'), findsOneWidget);
    expect(find.text('3 天后再出现'), findsOneWidget);
    expect(find.text('下一条'), findsOneWidget);
    expect(store.nextErrorReview('s01'), DateTime(2026, 2, 5));

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('错词 1'));
    await tester.pumpAndSettle();
    expect(find.text('对了'), findsOneWidget);
    expect(find.text('下一条'), findsOneWidget);
    expect(find.text('3 天后再出现'), findsOneWidget);
    expect(find.text('提交'), findsNothing);
    expect(store.nextErrorReview('s01'), DateTime(2026, 2, 5));
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

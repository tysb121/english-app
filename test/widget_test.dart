import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:english_app/app/app_model.dart';
import 'package:english_app/app/coach_database.dart';
import 'package:english_app/data/cefr_core.dart';
import 'package:english_app/engine/agent_tools.dart';
import 'package:english_app/engine/api_requests.dart';
import 'package:english_app/engine/chat_message.dart';
import 'package:english_app/engine/class_session.dart';
import 'package:english_app/engine/gradebook.dart';
import 'package:english_app/engine/pos_label.dart';
import 'package:english_app/net/poster.dart';
import 'package:english_app/ui/english_app.dart';
import 'package:english_app/ui/practice_page.dart';
import 'package:english_app/ui/thinking_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

  testWidgets('我的 keeps level and goal and the next teacher turn reads them', (
    tester,
  ) async {
    final store = fixtureStore(
      clock: () => DateTime(2026, 1, 1),
      levelChosen: true,
      level: '入门',
    );
    store.ensureTodayPlan();
    final poster = RecordingPoster();
    final model = AppModel(
      store: store,
      poster: poster,
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    final now = DateTime.now();
    final open = model.classCoach.log.ensureOpen(now);
    open.messages.add(
      const ChatMessage(id: 'seed', role: ChatRole.assistant, content: '已经开课'),
    );
    open.lastMessageAt = now;

    await tester.pumpWidget(EnglishApp(model: model));
    await tester.pump();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('日常交流'), findsNothing);
    expect(find.text('水平'), findsOneWidget);
    expect(find.text('目标'), findsOneWidget);
    expect(find.text('入门'), findsWidgets);
    expect(find.text('基础'), findsOneWidget);
    expect(find.text('进阶'), findsOneWidget);
    expect(find.text('职场'), findsOneWidget);
    expect(find.text('日常'), findsOneWidget);
    expect(find.text('考试'), findsOneWidget);
    expect(find.text('都要'), findsOneWidget);
    expect(find.text('DeepSeek 密钥'), findsOneWidget);
    expect(find.text('每天新词'), findsNothing);
    expect(find.text('语气'), findsNothing);
    expect(find.text('思考强度'), findsNothing);
    expect(find.textContaining('从明天'), findsNothing);
    expect(find.textContaining('今日练习已开始'), findsNothing);
    await tester.tap(find.text('进阶'));
    await tester.pump();
    await tester.tap(find.text('考试'));
    await tester.pump();
    expect(store.level, '进阶');
    expect(store.goal, '考试');

    await tester.scrollUntilVisible(
      find.text('清除数据重来'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('导出日志'), findsOneWidget);
    expect(find.text('清除数据重来'), findsOneWidget);
    expect(find.text('思考强度'), findsNothing);
    expect(find.text('每天新词'), findsNothing);
    expect(find.textContaining('从明天'), findsNothing);

    await tester.tap(find.text('今日练习'));
    await tester.pumpAndSettle();
    poster.responses.add(
      Posted(
        200,
        '{"choices":[{"finish_reason":"tool_calls","message":{"content":"","tool_calls":[{"id":"g1","type":"function","function":{"name":"get_learner","arguments":"{}"}}]}}]}',
      ),
    );
    poster.responses.add(Posted(200, _wrap('看到了。')));
    poster.responses.add(Posted(200, _wrap('看到了。')));
    poster.responses.add(Posted(200, _wrap('看到了。')));
    await tester.enterText(_sayField, '继续');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();

    expect(poster.calls, isNotEmpty);
    Map<String, Object?>? learner;
    for (final call in poster.calls) {
      final messages = call.body['messages'];
      if (messages is! List) continue;
      for (final message in messages) {
        if (message is! Map || message['role'] != 'tool') continue;
        final content = message['content'];
        if (content is! String) continue;
        final decoded = jsonDecode(content);
        if (decoded is Map && decoded['level'] != null) {
          learner = decoded.map((key, value) => MapEntry('$key', value));
        }
      }
    }
    expect(learner?['level'], '进阶');
    expect(learner?['settings_goal'], '考试');
    expect(learner?['band'], 'b1');
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
    expect(find.text('不会'), findsOneWidget);
    await tester.tap(find.text('I are student.'));
    await tester.pump();
    await tester.tap(find.text('I am a student.'));
    await tester.pump();
    expect(find.text('确认'), findsOneWidget);
    expect(poster.calls, hasLength(1));
    expect(store.progressJson().contains('apiKey'), isFalse);
  });

  testWidgets('不会 submits the fixed sentence and stores the answer as shown', (
    tester,
  ) async {
    final view = tester.view;
    view.physicalSize = const Size(400, 960);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    final poster = RecordingPoster();
    poster.responses.add(
      Posted(
        200,
        '{"choices":[{"finish_reason":"tool_calls","message":{"content":"看这张卡片。","tool_calls":[{"id":"c1","type":"function","function":{"name":"present_card","arguments":${jsonEncode(jsonEncode(_meetingArgs))}}}]}}]}',
      ),
    );
    final model = AppModel(
      store: fixtureStore(
        clock: () => DateTime(2026, 10, 4),
        levelChosen: true,
      ),
      poster: poster,
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    final item = model.classCoach.log.book.addItem(
      promptCn: '会议',
      targetEn: 'meeting',
      difficulty: 1,
    );
    poster.responses.add(
      Posted(
        200,
        _recordReply(
          itemId: item.id,
          content: '会议是 meeting。',
          revealed: false,
          pass: false,
        ),
      ),
    );

    await tester.pumpWidget(EnglishApp(model: model));
    await tester.pumpAndSettle();

    expect(find.text('哪个词是「会议」的意思？'), findsOneWidget);
    expect(find.byKey(const Key('option-a')), findsOneWidget);
    expect(find.text('morning'), findsOneWidget);
    expect(find.text('money'), findsOneWidget);
    expect(find.text('不会'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const Key('answer-confirm')),
    );
    expect(confirm.onPressed, isNull);

    await tester.tap(find.text('不会'));
    await tester.pumpAndSettle();

    expect(find.text(cardUnknownText), findsOneWidget);
    expect(find.byKey(const Key('option-a')), findsNothing);
    expect(find.byKey(const Key('answer-card')), findsNothing);
    expect(model.classCoach.log.book.attempts, hasLength(1));
    final attempt = model.classCoach.log.book.attempts.single;
    expect(attempt.submission, cardUnknownText);
    expect(attempt.optionId, isNull);
    expect(attempt.revealed, isTrue);
    expect(attempt.pass, isFalse);
  });

  testWidgets(
    'hiding the practiced English stores the typed sentence as unrevealed',
    (tester) async {
      final view = tester.view;
      view.physicalSize = const Size(400, 960);
      view.devicePixelRatio = 1.0;
      addTearDown(view.resetPhysicalSize);
      addTearDown(view.resetDevicePixelRatio);

      final model = AppModel(
        store: fixtureStore(
          clock: () => DateTime(2026, 10, 4),
          levelChosen: true,
        ),
        poster: RecordingPoster(),
        deepSeekKey: 'test-key',
        unlocked: true,
      );
      final coach = model.classCoach;
      final now = DateTime.now();
      final open = coach.log.ensureOpen(now);
      open.messages.add(
        const ChatMessage(
          id: 'hi',
          role: ChatRole.assistant,
          content: '我们练这一句。',
        ),
      );
      open.lastMessageAt = now;
      final item = coach.log.book.addItem(
        promptCn: '我六点起床。',
        targetEn: 'I get up at six.',
        difficulty: 1,
      );
      final poster = model.poster as RecordingPoster;
      poster.responses.add(
        Posted(
          200,
          _recordReply(
            itemId: item.id,
            content: '记下了。',
            revealed: true,
            pass: true,
          ),
        ),
      );
      poster.responses.add(
        Posted(
          200,
          _recordReply(
            itemId: item.id,
            content: '这句还看得到。',
            revealed: true,
            pass: false,
          ),
        ),
      );

      await tester.pumpWidget(EnglishApp(model: model));
      await tester.pump();

      expect(find.text('我六点起床。'), findsOneWidget);
      expect(find.text('I get up at six.'), findsOneWidget);
      await tester.tap(find.text('遮住英文'));
      await tester.pump();
      expect(find.text('I get up at six.'), findsNothing);
      expect(find.text('英文已遮住'), findsOneWidget);
      expect(find.text('我六点起床。'), findsOneWidget);

      await tester.tap(find.text('遮住中文'));
      await tester.pump();
      expect(find.text('我六点起床。'), findsNothing);
      expect(find.text('中文已遮住'), findsOneWidget);
      await tester.tap(find.text('显示中文'));
      await tester.pump();
      expect(find.text('我六点起床。'), findsOneWidget);
      expect(find.text('英文已遮住'), findsOneWidget);

      await tester.enterText(_sayField, 'I get up at six.');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();

      expect(coach.log.book.attempts, hasLength(1));
      expect(coach.log.book.attempts.single.submission, 'I get up at six.');
      expect(coach.log.book.attempts.single.revealed, isFalse);
      expect(coach.log.book.attempts.single.pass, isTrue);

      await tester.tap(find.text('显示英文'));
      await tester.pump();
      expect(find.text('遮住英文'), findsOneWidget);
      expect(find.text('英文已遮住'), findsNothing);
      await tester.enterText(_sayField, 'I get up at seven.');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();

      expect(coach.log.book.attempts, hasLength(2));
      expect(coach.log.book.attempts.last.submission, 'I get up at seven.');
      expect(coach.log.book.attempts.last.revealed, isTrue);
      expect(coach.log.book.attempts.last.pass, isFalse);
    },
  );

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
  testWidgets('词页 looks up the bundled wordbook and writes nothing', (
    tester,
  ) async {
    final loaded = await tester.runAsync(() async {
      ensureCoachDbFactory();
      final book = await loadCefrCore();
      final word = book.entries.firstWhere((entry) => entry.en == 'apple');
      final tmp = await Directory.systemTemp.createTemp('word_lookup_');
      final coach = await CoachDatabase.open(
        path: p.join(tmp.path, 'words.db'),
        seedBook: book.entries,
      );
      return (word: word, tmp: tmp, coach: coach);
    });
    final word = loaded!.word;
    final gloss = word.cn;
    final tmp = loaded.tmp;
    final coach = loaded.coach;
    addTearDown(() async {
      await coach.close();
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    final model = AppModel(
      store: fixtureStore(
        clock: () => DateTime(2026, 10, 5),
        levelChosen: true,
        level: '进阶',
      ),
      poster: ThrowingPoster(),
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    model.searchWords = coach.searchWordbook;
    final itemsBefore = model.classCoach.log.book.items.length;
    final attemptsBefore = model.classCoach.log.book.attempts.length;

    await tester.pumpWidget(EnglishApp(model: model));
    await tester.pump();
    await tester.tap(find.text('词'));
    await tester.pumpAndSettle();

    expect(find.text('今天的词'), findsNothing);
    expect(find.textContaining('还没排进某一天'), findsNothing);
    expect(find.textContaining('从明天开始练'), findsNothing);
    expect(find.text('查英文或中文'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.enterText(_lookupField, word.en);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.text(word.en), findsWidgets);
    expect(find.text(word.cn), findsWidgets);
    expect(find.text(posLabelZh(word.pos)), findsWidgets);

    await tester.runAsync(() async {
      await tester.enterText(_lookupField, gloss);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.text(word.en), findsWidgets);
    expect(find.text(word.cn), findsWidgets);

    expect(model.classCoach.log.book.items.length, itemsBefore);
    expect(model.classCoach.log.book.attempts.length, attemptsBefore);
    expect(find.text('今天的词'), findsNothing);
    expect(find.textContaining('还没排进某一天'), findsNothing);
    expect(find.textContaining('从明天开始练'), findsNothing);
  });

  testWidgets('记录 lists study items beside class transcripts without grading', (
    tester,
  ) async {
    final model = AppModel(
      store: fixtureStore(
        clock: () => DateTime(2026, 10, 5),
        levelChosen: true,
      ),
      poster: ThrowingPoster(),
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    final book = model.classCoach.log.book;
    final dueUnseen = DateTime.utc(2026, 11, 2, 8);
    final dueShaky = DateTime.utc(2026, 12, 3, 8);
    final dueKnown = DateTime.utc(2026, 8, 1, 8);
    final unseen = book.addItem(
      promptCn: '没练的提示',
      targetEn: 'an unseen line',
      difficulty: 1,
    );
    unseen.dueAt = dueUnseen;
    final shaky = book.addItem(
      promptCn: '不稳的提示',
      targetEn: 'a shaky line',
      difficulty: 2,
    );
    shaky.status = ItemStatus.shaky;
    shaky.dueAt = dueShaky;
    final known = book.addItem(
      promptCn: '会用的提示',
      targetEn: 'a known line',
      difficulty: 3,
    );
    known.status = ItemStatus.canUse;
    known.dueAt = dueKnown;

    final log = model.classCoach.log;
    final started = DateTime(2026, 10, 3, 9);
    log.classes.add(
      StudyClass(
        id: 'past-class',
        startedAt: started,
        endedAt: started.add(const Duration(minutes: 20)),
        closeNote: '练了三句',
        lastMessageAt: started,
        messages: const [
          ChatMessage(
            id: 'old-line',
            role: ChatRole.assistant,
            content: '上一节的原句',
          ),
        ],
      ),
    );
    final liveAt = DateTime.now();
    log.classes.add(
      StudyClass(
        id: 'live-class',
        startedAt: liveAt,
        lastMessageAt: liveAt,
        messages: const [
          ChatMessage(
            id: 'live-line',
            role: ChatRole.assistant,
            content: '这一节已经开始',
          ),
        ],
      ),
    );

    await tester.pumpWidget(EnglishApp(model: model));
    await tester.pump();
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();

    expect(find.text('没练的提示'), findsOneWidget);
    expect(find.text('an unseen line'), findsOneWidget);
    expect(find.text('没练过'), findsOneWidget);
    expect(find.text('不稳的提示'), findsOneWidget);
    expect(find.text('a shaky line'), findsOneWidget);
    expect(find.text('不稳'), findsOneWidget);
    expect(find.text('会用的提示'), findsOneWidget);
    expect(find.text('a known line'), findsOneWidget);
    expect(find.text('会用'), findsOneWidget);
    final recordsScroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('这一节还开着'),
      200,
      scrollable: recordsScroll,
    );
    await tester.scrollUntilVisible(
      find.text('练了三句'),
      200,
      scrollable: recordsScroll,
    );
    expect(find.text('练了三句'), findsOneWidget);
    expect(find.text('这一节还开着'), findsOneWidget);

    await tester.tap(find.text('练了三句'));
    await tester.pumpAndSettle();
    expect(find.text('上一节的原句'), findsOneWidget);
    expect(unseen.status, ItemStatus.unseen);
    expect(shaky.status, ItemStatus.shaky);
    expect(known.status, ItemStatus.canUse);
    expect(unseen.dueAt, dueUnseen);
    expect(shaky.dueAt, dueShaky);
    expect(known.dueAt, dueKnown);
    expect(book.items, hasLength(3));
    expect(book.attempts, isEmpty);
  });

  testWidgets('上课页 scrolls to the latest line and keeps 先到这 off the send row', (
    tester,
  ) async {
    final view = tester.view;
    view.physicalSize = const Size(800, 640);
    view.devicePixelRatio = 1;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    final poster = RecordingPoster();
    final model = AppModel(
      store: fixtureStore(
        clock: () => DateTime(2026, 10, 5),
        levelChosen: true,
      ),
      poster: poster,
      deepSeekKey: 'test-key',
      unlocked: true,
    );
    final coach = model.classCoach;
    final now = DateTime.now();
    final open = coach.log.ensureOpen(now);
    for (var i = 1; i <= 40; i++) {
      open.messages.add(
        ChatMessage(
          id: 'm$i',
          role: ChatRole.assistant,
          content: '句-${i.toString().padLeft(2, '0')}',
        ),
      );
    }
    open.lastMessageAt = now;
    coach.log.book.addItem(
      promptCn: '遮住用的中文',
      targetEn: 'HideThisEnglishLine',
      difficulty: 1,
    );

    await tester.pumpWidget(EnglishApp(model: model));
    await tester.pump();
    await tester.pump();

    _expectOnScreen(tester, '句-40');
    expect(find.text('句-01'), findsNothing);

    open.messages.add(
      const ChatMessage(id: 'm41', role: ChatRole.assistant, content: '句-41'),
    );
    model.tick();
    await tester.pump();
    await tester.pump();
    _expectOnScreen(tester, '句-41');

    double? bubbleWidth;
    for (final element
        in find
            .ancestor(of: find.text('句-41'), matching: find.byType(Container))
            .evaluate()) {
      final widget = element.widget;
      if (widget is Container && widget.constraints?.maxWidth != null) {
        bubbleWidth = widget.constraints!.maxWidth;
        break;
      }
    }
    expect(bubbleWidth, greaterThan(320));
    expect(_sharesRow(find.text('先到这'), find.text('发送')), isFalse);

    await tester.tap(find.text('遮住英文'));
    await tester.pump();
    expect(find.text('HideThisEnglishLine'), findsNothing);
    expect(find.text('英文已遮住'), findsOneWidget);
    expect(find.text('遮住用的中文'), findsOneWidget);

    final openId = coach.log.openClass!.id;
    coach.pendingCard = const AnswerCard(
      id: 'pending',
      kind: CardKind.choice,
      prompt: '先到这之前的卡片',
      options: [
        CardOption(id: 'a', text: 'left'),
        CardOption(id: 'b', text: 'right'),
      ],
    );
    model.tick();
    await tester.pump();
    expect(find.byKey(const Key('answer-card')), findsOneWidget);
    expect(coach.log.book.attempts, isEmpty);

    poster.responses.add(Posted(200, _wrap('新的一节。')));
    await tester.tap(find.text('先到这'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('answer-card')), findsNothing);
    expect(find.text('句-41'), findsNothing);
    expect(find.text('先到这之前的卡片'), findsNothing);
    expect(coach.log.openClass!.id, isNot(openId));
    expect(coach.log.book.attempts, isEmpty);
    expect(coach.pendingCard, isNull);
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

final Finder _sayField = find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == '跟老师说',
);

final Finder _lookupField = find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == '查英文或中文',
);

void _expectOnScreen(WidgetTester tester, String text) {
  final rect = tester.getRect(find.text(text));
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  expect(rect.top, greaterThanOrEqualTo(0), reason: text);
  expect(rect.bottom, lessThanOrEqualTo(height), reason: text);
}

bool _sharesRow(Finder a, Finder b) {
  final rowsA = find.ancestor(of: a, matching: find.byType(Row)).evaluate();
  final rowsB = find
      .ancestor(of: b, matching: find.byType(Row))
      .evaluate()
      .toSet();
  return rowsA.any(rowsB.contains);
}

String _recordReply({
  required String itemId,
  required String content,
  required bool revealed,
  required bool pass,
}) {
  final arguments = jsonEncode({
    'item_id': itemId,
    'pass': pass,
    'corrected_en': 'I get up at six.',
    'revealed': revealed,
    'submission': '模型改写的原文',
    'error_tag': pass ? '' : '其它',
  });
  return jsonEncode({
    'choices': [
      {
        'finish_reason': 'tool_calls',
        'message': {
          'content': content,
          'tool_calls': [
            {
              'id': 'rec',
              'type': 'function',
              'function': {'name': 'record_attempt', 'arguments': arguments},
            },
          ],
        },
      },
    ],
  });
}

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

const _meetingArgs = {
  'kind': 'choice',
  'prompt': '哪个词是「会议」的意思？',
  'options': [
    {'id': 'a', 'text': 'meeting'},
    {'id': 'b', 'text': 'morning'},
    {'id': 'c', 'text': 'money'},
  ],
};

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

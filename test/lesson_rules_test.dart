import 'package:english_app/engine/api_requests.dart';
import 'package:english_app/engine/lesson_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cefr_fixture.dart';

void main() {
  test('CEFR fixture covers A1/A2/B1 for product levels', () {
    expect(cefrFixture.where((w) => w.level == 'a1').length, greaterThanOrEqualTo(10));
    expect(cefrFixture.where((w) => w.level == 'a2'), isNotEmpty);
    expect(cefrFixture.where((w) => w.level == 'b1'), isNotEmpty);
    expect(normalizeLevel('新手'), '入门');
    expect(normalizeLevel('简单工作对话'), '基础');
    expect(normalizeLevel('更长的表达'), '进阶');
    expect(cefrCodeForLevel('入门'), 'a1');
    expect(cefrCodeForLevel('基础'), 'a2');
    expect(cefrCodeForLevel('进阶'), 'b1');
  });

  test('入门 picks only A1; level change freezes today', () {
    final store = fixtureStore(
      clock: () => DateTime(2026, 2, 1),
      level: '入门',
    );
    final plan = store.ensureTodayPlan();
    expect(plan.newWordIds, [
      'cc_a1_hello_noun_ce4a5e',
      'cc_a1_good_adjectiv_2bed5e',
      'cc_a1_time_noun_53674f',
      'cc_a1_day_noun_7f65b3',
      'cc_a1_work_noun_bf4aae',
    ]);
    for (final id in plan.newWordIds) {
      expect(store.word(id)!.level, 'a1');
    }

    store.level = '进阶';
    expect(store.ensureTodayPlan().newWordIds, plan.newWordIds);

    final day2 = DateTime(2026, 2, 2);
    final store2 = fixtureStore(clock: () => day2, level: '进阶');
    final advanced = store2.ensureTodayPlan();
    expect(advanced.newWordIds.first, 'cc_b1_abandon_verb_bb6626');
    for (final id in advanced.newWordIds) {
      expect(store2.word(id)!.level, 'b1');
    }
  });

  test('legacy 日常交流 level restores as 入门', () {
    final store = fixtureStore(clock: () => DateTime(2026, 3, 1));
    store.restore(
      '{"level":"日常交流","dailyWords":5,"plans":[],"userWords":[],"attempts":{},"errors":{},"reviews":{}}',
    );
    expect(store.level, '入门');
    expect(store.ensureTodayPlan().newWordIds.first, 'cc_a1_hello_noun_ce4a5e');
  });

  test('frozen plan, vocab, reviews, errors, check-in, and notes', () {
    var day = DateTime(2026, 1, 1);
    final store = fixtureStore(clock: () => day);

    final first = store.ensureTodayPlan();
    expect(first.newWordIds, [
      'cc_a1_hello_noun_ce4a5e',
      'cc_a1_good_adjectiv_2bed5e',
      'cc_a1_time_noun_53674f',
      'cc_a1_day_noun_7f65b3',
      'cc_a1_work_noun_bf4aae',
    ]);
    store.dailyWords = 20;
    final redraw = store.ensureTodayPlan();
    expect(redraw.newWordIds, first.newWordIds);

    final added = store.addUserWord(en: 'ship it', cn: '发布吧', pos: 'phrase');
    expect(store.todayContains(added), isFalse);

    for (var i = 0; i < 4; i++) {
      final id = store.currentVocabId!;
      final word = store.word(id)!;
      final feedback = store.submitVocab('  ${word.en.toUpperCase()}  ');
      expect(feedback!.correct, isTrue);
      store.advanceVocab();
    }
    final wrongId = store.currentVocabId!;
    final wrong = store.submitVocab('nope');
    expect(wrong!.correct, isFalse);
    expect(store.nextErrorReview(wrongId), DateTime(2026, 1, 2));
    store.advanceVocab();
    expect(store.vocabThresholdMet, isTrue);
    expect(store.successReviewOn('cc_a1_hello_noun_ce4a5e'), DateTime(2026, 1, 3));

    expect(store.checkedIn, isFalse);
    store.markDialogueDone();
    expect(store.checkedIn, isFalse);
    for (var i = 0; i < 4; i++) {
      final accepted = store.applyModelResponse(
        task: 'grade_open',
        content: i == 3 ? _failGrade : _passGrade,
        finishReason: 'stop',
        quizIndex: i,
      );
      expect(accepted, isTrue);
    }
    expect(store.quizPassCount, 3);
    expect(store.checkedIn, isTrue);

    store.skipNotes();
    expect(store.savedNotes, isEmpty);
    expect(store.checkedIn, isTrue);

    day = DateTime(2026, 1, 2);
    final next = store.ensureTodayPlan();
    expect(next.newWordIds.first, added);
    expect(next.newWordIds.skip(1).take(4), [
      'cc_a1_home_noun_b8d824',
      'cc_a1_friend_noun_c6552e',
      'cc_a1_water_noun_e21e30',
      'cc_a1_book_noun_5f36f6',
    ]);
    expect(next.errorWordIds, [wrongId]);
    expect(store.todayContains('cc_a1_hello_noun_ce4a5e'), isFalse);

    final before = store.reviewSnapshot();
    final quizBefore = store.quizSnapshot();
    expect(
      store.applyModelResponse(
        task: 'grade_open',
        content: '{',
        finishReason: 'stop',
        quizIndex: 0,
      ),
      isFalse,
    );
    expect(
      store.applyModelResponse(
        task: 'grade_open',
        content: _passGrade,
        finishReason: 'length',
        quizIndex: 0,
      ),
      isFalse,
    );
    expect(store.reviewSnapshot(), before);
    expect(store.quizSnapshot(), quizBefore);
    expect(store.checkedIn, isFalse);
  });

  test('error intervals reset and then leave the queue', () {
    var day = DateTime(2026, 2, 1);
    final store = fixtureStore(clock: () => day);
    store.ensureTodayPlan();
    final id = store.currentVocabId!;
    store.submitVocab('wrong');
    expect(store.nextErrorReview(id), DateTime(2026, 2, 2));

    day = DateTime(2026, 2, 2);
    store.ensureTodayPlan();
    _reviewError(store, id, correctly: true);
    expect(store.nextErrorReview(id), DateTime(2026, 2, 5));

    day = DateTime(2026, 2, 5);
    store.ensureTodayPlan();
    _reviewError(store, id, correctly: false);
    expect(store.nextErrorReview(id), DateTime(2026, 2, 6));

    day = DateTime(2026, 2, 6);
    store.ensureTodayPlan();
    _reviewError(store, id, correctly: true);
    expect(store.nextErrorReview(id), DateTime(2026, 2, 9));
    day = DateTime(2026, 2, 9);
    store.ensureTodayPlan();
    _reviewError(store, id, correctly: true);
    expect(store.nextErrorReview(id), DateTime(2026, 2, 16));
    day = DateTime(2026, 2, 16);
    store.ensureTodayPlan();
    _reviewError(store, id, correctly: true);
    expect(store.isErrorResolved(id), isTrue);
    expect(store.nextErrorReview(id), isNull);
  });

  test('a correct new word is due on days 2, 4, and 8', () {
    var day = DateTime(2026, 3, 1);
    final store = fixtureStore(clock: () => day);
    store.ensureTodayPlan();
    final id = store.currentVocabId!;
    _answerCurrent(store, correctly: true);
    expect(store.successReviewOn(id), DateTime(2026, 3, 3));

    day = DateTime(2026, 3, 3);
    final due = store.ensureTodayPlan();
    expect(due.reviewWordIds, contains(id));
    while (store.currentVocabId != id) {
      store.advanceVocab();
    }
    _answerCurrent(store, correctly: true);
    expect(store.successReviewOn(id), DateTime(2026, 3, 5));

    day = DateTime(2026, 3, 5);
    store.ensureTodayPlan();
    while (store.currentVocabId != id) {
      store.advanceVocab();
    }
    _answerCurrent(store, correctly: true);
    expect(store.successReviewOn(id), DateTime(2026, 3, 9));

    day = DateTime(2026, 3, 9);
    store.ensureTodayPlan();
    while (store.currentVocabId != id) {
      store.advanceVocab();
    }
    _answerCurrent(store, correctly: true);
    expect(store.successReviewOn(id), isNull);
  });

  test('notes confirm stores text and check-in stays', () {
    final store = fixtureStore(clock: () => DateTime(2026, 4, 1));
    _checkIn(store);
    store.confirmNotes(store.noteDrafts());
    expect(store.savedNotes, isNotEmpty);
    expect(store.checkedIn, isTrue);
    expect(store.progressJson().contains('apiKey'), isFalse);
    expect(store.progressJson().contains('Bearer'), isFalse);
  });

  test('DeepSeek responses do not move dates unless the body is accepted', () {
    final store = fixtureStore(clock: () => DateTime(2026, 5, 1));
    store.ensureTodayPlan();
    final before = store.reviewSnapshot();
    expect(
      store.applyModelResponse(
        task: 'fill_scene',
        content: _scene('Hello'),
        finishReason: 'stop',
      ),
      isTrue,
    );
    expect(store.scene!.scenarioEn, 'Hello');
    expect(store.scene!.scenarioCn, '打招呼');
    expect(store.shouldRequestScene, isFalse);
    expect(
      store.applyModelResponse(
        task: 'fill_scene',
        content: _scene('Other'),
        finishReason: 'stop',
      ),
      isTrue,
    );
    expect(store.scene!.scenarioEn, 'Hello');
    expect(store.reviewSnapshot(), before);

    final quizBefore = store.quizSnapshot();
    expect(
      store.applyModelResponse(
        task: 'grade_open',
        content: '{"pass":false,"errors":[],"corrected_en":"Ok."}',
        finishReason: 'stop',
        quizIndex: 0,
      ),
      isTrue,
    );
    expect(store.quizSnapshot()[0], isTrue);
    expect(
      store.applyModelResponse(
        task: 'explain',
        content: '{"answer_cn":"因为已经发生","example_en":"I finished."}',
        finishReason: 'stop',
      ),
      isTrue,
    );
    expect(store.quizSnapshot().sublist(1), quizBefore.sublist(1));
    expect(store.checkedIn, isFalse);
  });

  test('TokenHub translation is a separate request and not a grade', () {
    final call = tokenHubTranslation(
      apiKey: 'test-key',
      text: 'hello',
      toChinese: true,
    );
    expect(call.uri.host, tokenHubHost);
    expect(call.uri.path, tokenHubChatPath);
    expect(call.headers['Authorization'], 'Bearer test-key');
    expect(call.body['model'], 'hy-mt2-plus');
    expect(call.body.containsKey('response_format'), isFalse);
    expect(call.body.containsKey('tools'), isFalse);

    final deepSeek = deepSeekChat(
      apiKey: 'deepseek-key',
      task: 'fill_scene',
      messages: [
        {'role': 'user', 'content': 'fill'},
      ],
    );
    expect(deepSeek.uri.path, deepSeekChatPath);
    expect(deepSeek.body['thinking'], {'type': 'disabled'});
    expect(deepSeek.body['reasoning_effort'], 'none');
    expect(deepSeek.body['response_format'], {'type': 'json_object'});
    expect(deepSeek.body.containsKey('tools'), isFalse);
    expect(deepSeek.body['stream'], isFalse);

    final store = fixtureStore(clock: () => DateTime(2026, 6, 1));
    store.ensureTodayPlan();
    store.applyModelResponse(
      task: 'grade_open',
      content: _failGrade,
      finishReason: 'stop',
      quizIndex: 1,
    );
    final quiz = store.quizSnapshot();
    store.applyTranslation('你好');
    expect(store.referencePreview, '你好');
    expect(store.quizSnapshot(), quiz);
  });

  test('saved progress reloads the plan and keeps keys out', () {
    final store = fixtureStore(clock: () => DateTime(2026, 8, 2));
    store.ensureTodayPlan();
    store.addUserWord(en: 'ship it', cn: '发布吧', pos: 'phrase');
    expect(
      store.applyModelResponse(
        task: 'fill_scene',
        content: _scene('Hello'),
        finishReason: 'stop',
      ),
      isTrue,
    );
    store.advanceDialogue();
    final again = fixtureStore(clock: () => DateTime(2026, 8, 2));
    again.restore(store.progressJson());
    expect(again.scheduledNewWords(), store.scheduledNewWords());
    expect(again.scene!.scenarioCn, '打招呼');
    expect(again.dialogueCursor, 1);
    expect(
      again.catalog.any(
        (word) => word.en == 'ship it' && word.source == WordSource.user,
      ),
      isTrue,
    );
    expect(again.todayContains(again.catalog.last.id), isFalse);
    expect(again.progressJson().contains('apiKey'), isFalse);
    expect(again.progressJson().contains('Bearer'), isFalse);
  });

  test('a second submit without advancing does not move the review date', () {
    final day = DateTime(2026, 3, 1);
    final store = fixtureStore(clock: () => day);
    store.ensureTodayPlan();
    final id = store.currentVocabId!;
    final first = store.submitVocab(store.word(id)!.en);
    expect(first!.correct, isTrue);
    expect(store.successReviewOn(id), DateTime(2026, 3, 3));
    expect(store.successStage(id), 1);
    expect(store.pendingVocab?.wordId, id);
    expect(store.pendingVocab?.correct, isTrue);
    final dates = store.reviewSnapshot();

    final second = store.submitVocab('wrong');
    expect(second!.wordId, id);
    expect(second.correct, isTrue);
    expect(store.successReviewOn(id), DateTime(2026, 3, 3));
    expect(store.successStage(id), 1);
    expect(store.nextErrorReview(id), isNull);
    expect(store.pendingVocab?.correct, isTrue);
    expect(store.reviewSnapshot(), dates);

    final reloaded = fixtureStore(clock: () => day);
    reloaded.restore(store.progressJson());
    expect(reloaded.pendingVocab?.wordId, id);
    expect(reloaded.pendingVocab?.correct, isTrue);
    reloaded.submitVocab('again');
    expect(reloaded.successReviewOn(id), DateTime(2026, 3, 3));
    expect(reloaded.successStage(id), 1);
    expect(reloaded.reviewSnapshot(), dates);

    var errorDay = DateTime(2026, 2, 1);
    final errors = fixtureStore(clock: () => errorDay);
    errors.ensureTodayPlan();
    final errorId = errors.currentVocabId!;
    errors.submitVocab('wrong');
    expect(errors.nextErrorReview(errorId), DateTime(2026, 2, 2));

    errorDay = DateTime(2026, 2, 2);
    errors.ensureTodayPlan();
    final graded = errors.submitErrorReview(errorId, errors.word(errorId)!.en);
    expect(graded!.correct, isTrue);
    expect(errors.nextErrorReview(errorId), DateTime(2026, 2, 5));
    expect(errors.pendingError?.wordId, errorId);
    expect(errors.pendingError?.correct, isTrue);
    final errorDates = errors.reviewSnapshot();

    final repeated = errors.submitErrorReview(errorId, 'wrong');
    expect(repeated!.correct, isTrue);
    expect(errors.nextErrorReview(errorId), DateTime(2026, 2, 5));
    expect(errors.pendingError?.correct, isTrue);
    expect(errors.reviewSnapshot(), errorDates);

    final restoredErrors = fixtureStore(clock: () => errorDay);
    restoredErrors.restore(errors.progressJson());
    expect(restoredErrors.pendingError?.correct, isTrue);
    restoredErrors.submitErrorReview(errorId, 'wrong');
    expect(restoredErrors.nextErrorReview(errorId), DateTime(2026, 2, 5));
    expect(restoredErrors.reviewSnapshot(), errorDates);
  });
}

void _reviewError(LessonStore store, String id, {required bool correctly}) {
  final expected = store.word(id)!.en;
  final feedback = store.submitErrorReview(id, correctly ? expected : 'wrong');
  expect(feedback!.correct, correctly);
}

void _answerCurrent(LessonStore store, {required bool correctly}) {
  final id = store.currentVocabId!;
  final word = store.word(id)!;
  final feedback = store.submitVocab(correctly ? word.en : 'wrong');
  expect(feedback!.wordId, id);
  expect(feedback.correct, correctly);
  store.advanceVocab();
}

void _checkIn(LessonStore store) {
  store.ensureTodayPlan();
  for (var i = 0; i < 4; i++) {
    _answerCurrent(store, correctly: true);
  }
  store.submitVocab('wrong');
  store.markDialogueDone();
  for (var i = 0; i < 3; i++) {
    store.applyModelResponse(
      task: 'grade_open',
      content: _passGrade,
      finishReason: 'stop',
      quizIndex: i,
    );
  }
  store.applyModelResponse(
    task: 'grade_open',
    content: _failGrade,
    finishReason: 'stop',
    quizIndex: 3,
  );
  expect(store.checkedIn, isTrue);
}

const _passGrade =
    '{"pass":true,"errors":[],"corrected_en":"I said hello."}';

const _failGrade =
    '{"pass":false,"errors":[{"excerpt":"He go","fix":"He goes","why_cn":"第三人称单数要加 s。"}],"corrected_en":"He goes to school."}';

String _scene(String name) => '''
{
  "scenario_en": "$name",
  "scenario_cn": "打招呼",
  "phrases": [{"en": "Hello.", "cn": "你好。"}],
  "dialogue": [
    {"speaker": "A", "en": "Hello!", "cn": "你好！"},
    {"speaker": "B", "en": "Hi, good morning.", "cn": "嗨，早上好。"},
    {"speaker": "A", "en": "How are you?", "cn": "你好吗？"},
    {"speaker": "B", "en": "I am good.", "cn": "我很好。"},
    {"speaker": "A", "en": "See you at school.", "cn": "学校见。"},
    {"speaker": "B", "en": "See you.", "cn": "再见。"}
  ],
  "grammar": {
    "title_en": "Greeting",
    "title_cn": "打招呼",
    "point_cn": "用简单的问候开场。",
    "examples": ["Hello.", "Good morning."]
  }
}
''';

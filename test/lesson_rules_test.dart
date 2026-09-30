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

  test('upgrade nudge only when untaught stock is exhausted', () {
    final store = fixtureStore(
      clock: () => DateTime(2026, 4, 1),
      level: '入门',
    );
    expect(store.nextProductLevel, '基础');
    expect(store.untaughtInLevelCount(), 15);
    expect(store.shouldOfferLevelUpgrade, isFalse);

    // One day at default pace leaves stock; must not nudge yet.
    store.dailyWords = 5;
    final partial = store.ensureTodayPlan();
    expect(partial.newWordIds, hasLength(5));
    expect(store.untaughtInLevelCount(), 10);
    expect(store.shouldOfferLevelUpgrade, isFalse);

    // Exhaust the rest of A1 in one frozen plan.
    store.dailyWords = 15;
    // Plan already frozen for today — redraw on a fresh day.
    final dayExhaust = DateTime(2026, 4, 2);
    final exhausted = fixtureStore(clock: () => dayExhaust, level: '入门');
    exhausted.restore(store.progressJson());
    exhausted.dailyWords = 15;
    final plan = exhausted.ensureTodayPlan();
    expect(plan.newWordIds, hasLength(10));
    expect(exhausted.untaughtInLevelCount(), 0);
    expect(exhausted.shouldOfferLevelUpgrade, isTrue);

    exhausted.dismissUpgradeNudge();
    expect(exhausted.shouldOfferLevelUpgrade, isFalse);

    exhausted.upgradeNudgeDismissed = false;
    expect(exhausted.acceptLevelUpgrade(), isTrue);
    expect(exhausted.level, '基础');
    expect(exhausted.ensureTodayPlan().newWordIds, plan.newWordIds);
    // Fixture A2 has 5 words; none taught yet → not exhausted.
    expect(exhausted.nextProductLevel, '进阶');
    expect(exhausted.shouldOfferLevelUpgrade, isFalse);

    final day3 = DateTime(2026, 4, 3);
    final store2 = fixtureStore(clock: () => day3, level: '基础');
    store2.restore(exhausted.progressJson());
    expect(store2.level, '基础');
    final next = store2.ensureTodayPlan();
    for (final id in next.newWordIds) {
      expect(store2.word(id)!.level, 'a2');
    }
  });

  test('no upgrade nudge at top level or when stock remains', () {
    final top = fixtureStore(clock: () => DateTime(2026, 5, 1), level: '进阶');
    top.dailyWords = 5;
    top.ensureTodayPlan();
    // 5 B1 words → 0 left after one day, but no next band.
    expect(top.untaughtInLevelCount(), 0);
    expect(top.nextProductLevel, isNull);
    expect(top.shouldOfferLevelUpgrade, isFalse);

    final rich = fixtureStore(clock: () => DateTime(2026, 5, 2), level: '入门');
    rich.dailyWords = 5;
    // 15 A1 words still untaught → no nudge.
    expect(rich.shouldOfferLevelUpgrade, isFalse);
    rich.ensureTodayPlan();
    expect(rich.untaughtInLevelCount(), 10);
    expect(rich.shouldOfferLevelUpgrade, isFalse);
  });

  test('upgrade nudge flag round-trips in progress JSON', () {
    final store = fixtureStore(clock: () => DateTime(2026, 6, 1), level: '入门');
    store.dailyWords = 15;
    store.ensureTodayPlan();
    expect(store.untaughtInLevelCount(), 0);
    expect(store.shouldOfferLevelUpgrade, isTrue);
    store.dismissUpgradeNudge();
    final raw = store.progressJson();
    final copy = fixtureStore(clock: () => DateTime(2026, 6, 1), level: '入门');
    copy.restore(raw);
    expect(copy.upgradeNudgeDismissed, isTrue);
    expect(copy.shouldOfferLevelUpgrade, isFalse);
  });

  test('ensureTodayPlan uses pickUntaughtIds for book slots', () {
    final store = fixtureStore(clock: () => DateTime(2026, 6, 10), level: '入门');
    final manual = store.pickUntaughtIds(
      level: 'a1',
      limit: 5,
      exclude: const {},
    );
    expect(manual, hasLength(5));
    final plan = store.ensureTodayPlan();
    expect(plan.newWordIds, manual);
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
      final feedback = store.acknowledgeVocab();
      expect(feedback!.correct, isTrue);
      expect(feedback.wordId, id);
      store.advanceVocab();
    }
    // Leftover typed 中→英 can still seed the error queue; daily UI uses 认识了.
    final wrongId = store.currentVocabId!;
    final wrong = store.submitVocab('nope');
    expect(wrong!.correct, isFalse);
    expect(store.nextErrorReview(wrongId), DateTime(2026, 1, 2));
    store.advanceVocab();
    expect(store.vocabDone, isTrue);
    expect(store.vocabThresholdMet, isTrue);
    expect(store.successReviewOn('cc_a1_hello_noun_ce4a5e'), DateTime(2026, 1, 3));

    expect(store.checkedIn, isFalse);
    store.markDialogueDone();
    expect(store.checkedIn, isFalse);
    for (final id in first.newWordIds) {
      final accepted = store.applyModelResponse(
        task: 'grade_open',
        content: _passGrade,
        finishReason: 'stop',
        sentenceWordId: id,
      );
      expect(accepted, isTrue);
    }
    expect(store.sentencesDone, isTrue);
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
    final sentencesBefore = store.sentenceSnapshot();
    expect(
      store.applyModelResponse(
        task: 'grade_open',
        content: '{',
        finishReason: 'stop',
        sentenceWordId: next.newWordIds.first,
      ),
      isFalse,
    );
    expect(
      store.applyModelResponse(
        task: 'grade_open',
        content: _passGrade,
        finishReason: 'length',
        sentenceWordId: next.newWordIds.first,
      ),
      isFalse,
    );
    expect(store.reviewSnapshot(), before);
    expect(store.sentenceSnapshot(), sentencesBefore);
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
    store.ensureTodayPlan();
    // Leftover typed miss seeds a draft; daily 认词 no longer creates errors.
    store.submitVocab('wrong');
    store.advanceVocab();
    while (store.currentVocabId != null) {
      store.acknowledgeVocab();
      store.advanceVocab();
    }
    for (final id in store.scheduledNewWords()) {
      store.applyModelResponse(
        task: 'grade_open',
        content: _passGrade,
        finishReason: 'stop',
        sentenceWordId: id,
      );
    }
    store.markDialogueDone();
    expect(store.checkedIn, isTrue);
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

    final wordId = store.scheduledNewWords().first;
    final sentencesBefore = store.sentenceSnapshot();
    expect(
      store.applyModelResponse(
        task: 'grade_open',
        content: '{"pass":false,"errors":[],"corrected_en":"Ok."}',
        finishReason: 'stop',
        sentenceWordId: wordId,
      ),
      isTrue,
    );
    expect(store.sentenceSnapshot().first['done'], isTrue);
    expect(store.sentenceSnapshot().first['pass'], isTrue);  // empty errors => pass
    expect(
      store.applyModelResponse(
        task: 'explain',
        content: '{"answer_cn":"因为已经发生","example_en":"I finished."}',
        finishReason: 'stop',
      ),
      isTrue,
    );
    expect(store.sentenceSnapshot().sublist(1), sentencesBefore.sublist(1));
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
    final wordId = store.scheduledNewWords()[1];
    store.applyModelResponse(
      task: 'grade_open',
      content: _failGrade,
      finishReason: 'stop',
      sentenceWordId: wordId,
    );
    final sentences = store.sentenceSnapshot();
    store.applyTranslation('你好');
    expect(store.referencePreview, '你好');
    expect(store.sentenceSnapshot(), sentences);
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

  test('restore ignores legacy quiz field in day_plan', () {
    final store = fixtureStore(clock: () => DateTime(2026, 11, 1));
    store.restore(
      '{"level":"入门","dailyWords":5,"plans":[{"date":"2026-11-01","newWordIds":["cc_a1_hello_noun_ce4a5e"],"reviewWordIds":[],"errorWordIds":[],"dialogueDone":false,"quiz":[true,true,true,true],"sentenceResults":{}}],"userWords":[],"attempts":{},"errors":{},"reviews":{}}',
    );
    final raw = store.progressJson();
    expect(raw.contains('"quiz"'), isFalse);
    expect(store.ensureTodayPlan().newWordIds, ['cc_a1_hello_noun_ce4a5e']);
    expect(store.checkedIn, isFalse);
  });

  test('ensureTodayPlanAsync uses untaughtIdPicker when set', () async {
    final store = fixtureStore(clock: () => DateTime(2026, 11, 2), level: '入门');
    var calls = 0;
    store.untaughtIdPicker = ({
      required String level,
      required int limit,
      required Set<String> exclude,
    }) async {
      calls += 1;
      expect(level, 'a1');
      expect(limit, 5);
      return store.pickUntaughtIds(level: level, limit: limit, exclude: exclude);
    };
    final plan = await store.ensureTodayPlanAsync();
    expect(calls, 1);
    expect(plan.newWordIds, hasLength(5));
    await store.ensureTodayPlanAsync();
    expect(calls, 1);
  });
}

void _reviewError(LessonStore store, String id, {required bool correctly}) {
  final expected = store.word(id)!.en;
  final feedback = store.submitErrorReview(id, correctly ? expected : 'wrong');
  expect(feedback!.correct, correctly);
}

void _answerCurrent(LessonStore store, {required bool correctly}) {
  final id = store.currentVocabId!;
  if (correctly) {
    final feedback = store.acknowledgeVocab();
    expect(feedback!.wordId, id);
    expect(feedback.correct, isTrue);
  } else {
    final feedback = store.submitVocab('wrong');
    expect(feedback!.wordId, id);
    expect(feedback.correct, isFalse);
  }
  store.advanceVocab();
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

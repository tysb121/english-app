import 'package:english_app/data/seed_words.dart';
import 'package:english_app/engine/api_requests.dart';
import 'package:english_app/engine/lesson_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seed list is the project word list', () {
    expect(seedWords.length, 70);
    expect(seedWords.map((word) => word.id).toSet().length, 70);
    expect(seedWords.first.en, 'standup');
  });


  test('beginner level picks short phrases, not standup first', () {
    final store = LessonStore(
      clock: () => DateTime(2026, 2, 1),
    )..level = '新手';
    final plan = store.ensureTodayPlan();
    expect(plan.newWordIds, ['s24', 's25', 's44', 's45', 's46']);
    expect(plan.newWordIds.contains('s01'), isFalse);

    store.level = '更长的表达';
    // frozen today
    expect(store.ensureTodayPlan().newWordIds, plan.newWordIds);

    final day2 = DateTime(2026, 2, 2);
    final store2 = LessonStore(clock: () => day2)..level = '更长的表达';
    // fresh store day 2 with longer level starts at longer band
    final longer = store2.ensureTodayPlan();
    expect(longer.newWordIds.first, 's12');
  });

  test('legacy 日常交流 level restores as 新手', () {
    final store = LessonStore(clock: () => DateTime(2026, 3, 1));
    store.restore('{"level":"日常交流","dailyWords":5,"plans":[],"userWords":[],"attempts":{},"errors":{},"reviews":{}}');
    expect(store.level, '新手');
    expect(store.ensureTodayPlan().newWordIds.first, 's24');
  });

  test('frozen plan, vocab, reviews, errors, check-in, and notes', () {
    var day = DateTime(2026, 1, 1);
    final store = LessonStore(clock: () => day);

    final first = store.ensureTodayPlan();
    expect(first.newWordIds, ['s01', 's02', 's03', 's04', 's05']);
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
    expect(store.successReviewOn('s01'), DateTime(2026, 1, 3));

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
    expect(next.newWordIds.skip(1).take(4), ['s06', 's07', 's08', 's09']);
    expect(next.errorWordIds, [wrongId]);
    expect(store.todayContains('s01'), isFalse);

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
    final store = LessonStore(clock: () => day);
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
    final store = LessonStore(clock: () => day);
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
    final store = LessonStore(clock: () => DateTime(2026, 4, 1));
    _checkIn(store);
    store.confirmNotes(store.noteDrafts());
    expect(store.savedNotes, isNotEmpty);
    expect(store.checkedIn, isTrue);
    expect(store.progressJson().contains('apiKey'), isFalse);
    expect(store.progressJson().contains('Bearer'), isFalse);
  });

  test('DeepSeek responses do not move dates unless the body is accepted', () {
    final store = LessonStore(clock: () => DateTime(2026, 5, 1));
    store.ensureTodayPlan();
    final before = store.reviewSnapshot();
    expect(
      store.applyModelResponse(
        task: 'fill_scene',
        content: _scene('Standup'),
        finishReason: 'stop',
      ),
      isTrue,
    );
    expect(store.scene!.scenarioEn, 'Standup');
    expect(store.scene!.scenarioCn, '早会');
    expect(store.shouldRequestScene, isFalse);
    expect(
      store.applyModelResponse(
        task: 'fill_scene',
        content: _scene('Other'),
        finishReason: 'stop',
      ),
      isTrue,
    );
    expect(store.scene!.scenarioEn, 'Standup');
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

    final store = LessonStore(clock: () => DateTime(2026, 6, 1));
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
    final store = LessonStore(clock: () => DateTime(2026, 8, 2));
    store.ensureTodayPlan();
    store.addUserWord(en: 'ship it', cn: '发布吧', pos: 'phrase');
    expect(
      store.applyModelResponse(
        task: 'fill_scene',
        content: _scene('Standup'),
        finishReason: 'stop',
      ),
      isTrue,
    );
    store.advanceDialogue();
    final again = LessonStore(clock: () => DateTime(2026, 8, 2));
    again.restore(store.progressJson());
    expect(again.scheduledNewWords(), store.scheduledNewWords());
    expect(again.scene!.scenarioCn, '早会');
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
    final store = LessonStore(clock: () => day);
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

    final reloaded = LessonStore(clock: () => day);
    reloaded.restore(store.progressJson());
    expect(reloaded.pendingVocab?.wordId, id);
    expect(reloaded.pendingVocab?.correct, isTrue);
    reloaded.submitVocab('again');
    expect(reloaded.successReviewOn(id), DateTime(2026, 3, 3));
    expect(reloaded.successStage(id), 1);
    expect(reloaded.reviewSnapshot(), dates);

    var errorDay = DateTime(2026, 2, 1);
    final errors = LessonStore(clock: () => errorDay);
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

    final restoredErrors = LessonStore(clock: () => errorDay);
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
    '{"pass":true,"errors":[],"corrected_en":"I finished the standup."}';

const _failGrade =
    '{"pass":false,"errors":[{"excerpt":"He go","fix":"He goes","why_cn":"第三人称单数要加 s。"}],"corrected_en":"He goes to the standup."}';

String _scene(String name) => '''
{
  "scenario_en": "$name",
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
    "title_en": "Simple past",
    "title_cn": "一般过去时",
    "point_cn": "说已经发生的事。",
    "examples": ["I finished the report.", "I sent the notes."]
  }
}
''';

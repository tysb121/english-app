import 'dart:convert';
import 'dart:math';

import '../data/cefr_core.dart';
import 'reasoning_effort.dart';

/// Async untaught picker (SQL). Prefer this over the in-memory CEFR pool when set.
typedef UntaughtIdPicker = Future<List<String>> Function({
  required String level,
  required int limit,
  required Set<String> exclude,
});

/// Async untaught COUNT (SQL). Prefer this over scanning the in-memory book.
typedef UntaughtCountFn = Future<int> Function({
  required String level,
  required Set<String> exclude,
});

/// Batch load book lemmas by id (SQL). Used to hydrate the Lexeme cache.
typedef BookWordsByIds = Future<List<CefrWord>> Function(List<String> ids);

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime addDays(DateTime value, int days) {
  final day = dateOnly(value);
  return DateTime(day.year, day.month, day.day + days);
}

int vocabPassThreshold(int newWordCount) => (newWordCount * 8 + 9) ~/ 10;

String normalizeAnswer(String value) => value.trim().toLowerCase();

const productLevels = ['入门', '基础', '进阶'];

/// Maps product labels (and legacy workplace labels) to CEFR-J codes.
String cefrCodeForLevel(String level) {
  switch (normalizeLevel(level)) {
    case '基础':
      return 'a2';
    case '进阶':
      return 'b1';
    case '入门':
    default:
      return 'a1';
  }
}

String normalizeLevel(String level) {
  switch (level) {
    case '新手':
    case '日常交流':
      return '入门';
    case '简单工作对话':
      return '基础';
    case '更长的表达':
      return '进阶';
    case '入门':
    case '基础':
    case '进阶':
      return level;
    default:
      return '入门';
  }
}

String createInstallId() {
  const alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-';
  final random = Random.secure();
  return List.generate(
    24,
    (index) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

enum WordSource { book, user }

class Lexeme {
  final String id;
  final String en;
  final String cn;
  final String pos;
  final WordSource source;
  /// CEFR code a1|a2|b1 for book words; empty for user words.
  final String level;

  const Lexeme({
    required this.id,
    required this.en,
    required this.cn,
    required this.pos,
    required this.source,
    this.level = '',
  });
}

class SceneLine {
  final String speaker;
  final String en;
  final String cn;

  const SceneLine({
    required this.speaker,
    required this.en,
    required this.cn,
  });
}

class LessonScene {
  final String scenarioEn;
  final String scenarioCn;
  final List<SceneLine> dialogue;
  final String grammarCn;
  final List<String> grammarExamples;

  const LessonScene({
    required this.scenarioEn,
    required this.scenarioCn,
    required this.dialogue,
    required this.grammarCn,
    required this.grammarExamples,
  });
}

class GradeResult {
  final bool pass;
  final List<GradeError> errors;
  final String correctedEn;

  const GradeResult({
    required this.pass,
    required this.errors,
    required this.correctedEn,
  });
}

class GradeError {
  final String excerpt;
  final String fix;
  final String whyCn;

  const GradeError({
    required this.excerpt,
    required this.fix,
    required this.whyCn,
  });
}

class StudyNote {
  final String wrong;
  final String corrected;
  final String whyCn;

  const StudyNote({
    required this.wrong,
    required this.corrected,
    required this.whyCn,
  });
}

class VocabFeedback {
  final String wordId;
  final bool correct;
  final String correctEn;

  const VocabFeedback({
    required this.wordId,
    required this.correct,
    required this.correctEn,
  });
}

class _Attempt {
  final String wordId;
  final String answer;
  final bool correct;

  const _Attempt(this.wordId, this.answer, this.correct);
}

class _ErrorItem {
  String wrongAnswer;
  String correctAnswer;
  int round;
  DateTime nextReview;
  bool resolved;

  _ErrorItem({
    required this.wrongAnswer,
    required this.correctAnswer,
    required this.round,
    required this.nextReview,
    required this.resolved,
  });
}

class _Review {
  DateTime? introducedOn;
  int stage;
  DateTime? nextReview;

  _Review({this.introducedOn, this.stage = 0, this.nextReview});
}

class DayPlan {
  final DateTime date;
  final List<String> newWordIds;
  final List<String> reviewWordIds;
  final List<String> errorWordIds;
  LessonScene? scene;
  bool dialogueDone;
  /// Per new-word sentence grade (presence = done; value = pass).
  final Map<String, bool> sentenceResults = {};
  int vocabCursor;
  int dialogueCursor = 0;
  int errorCursor = 0;
  int? heldVocabCursor;
  String? heldVocabId;
  bool heldVocabCorrect = false;
  int? heldErrorCursor;
  String? heldErrorId;
  bool heldErrorCorrect = false;
  bool notesDismissed;
  final List<StudyNote> notes;
  final List<StudyNote> gradeNotes = [];
  DateTime? checkedInAt;
  String? referencePreview;

  DayPlan({
    required this.date,
    required this.newWordIds,
    required this.reviewWordIds,
    required this.errorWordIds,
  }) : dialogueDone = false,
       vocabCursor = 0,
       notesDismissed = false,
       notes = [];
}

class LessonStore {
  LessonStore({
    DateTime Function()? clock,
    List<CefrWord>? book,
    Random? random,
    String? installId,
    this.untaughtIdPicker,
    this.untaughtCountFn,
    this.bookWordsByIds,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random(),
       installId = installId ?? createInstallId() {
    for (final entry in book ?? const <CefrWord>[]) {
      cacheBookWord(entry);
    }
  }

  final DateTime Function() _clock;
  final Random _random;
  /// Prefer SQL-backed picking when set; [ensureTodayPlan] falls back to RAM.
  UntaughtIdPicker? untaughtIdPicker;
  /// Prefer SQL COUNT when set; [untaughtInLevelCount] uses cache + RAM fallback.
  UntaughtCountFn? untaughtCountFn;
  /// Lazy Lexeme hydrate from SQLite by id.
  BookWordsByIds? bookWordsByIds;
  final Map<String, Lexeme> _words = {};
  /// Warm SQL untaught count; null means not loaded (or invalidated).
  int? _untaughtInLevelCache;
  final Map<String, DayPlan> _plans = {};
  final Map<String, List<_Attempt>> _attempts = {};
  final Map<String, _ErrorItem> _errors = {};
  final Map<String, _Review> _reviews = {};

  int dailyWords = 5;
  String level = '入门';
  bool levelChosen = false;
  /// User dismissed the exhausted-level upgrade card for the current level.
  bool upgradeNudgeDismissed = false;
  String reasoningEffort = 'off';
  String goal = '职场';
  String tone = '简洁';
  bool sceneInFlight = false;
  String installId;
  GradeResult? lastGrade;
  String? lastExplainCn;
  String? lastExplainEn;
  final List<Map<String, Object?>> callLog = [];

  DateTime get today => dateOnly(_clock());

  /// Sync plan create/get. Uses in-memory [pickUntaughtIds] when freezing.
  /// Prefer [ensureTodayPlanAsync] in the app so book slots come from SQL.
  /// After startup freeze, this is a cheap map lookup (no re-pick).
  DayPlan ensureTodayPlan() {
    final existing = _plans[_key(today)];
    if (existing != null) return existing;
    return _freezeTodayPlan(_pickNewWordIdsSync());
  }

  /// Prefer SQL [untaughtIdPicker] for book slots; same freeze / user-first rules.
  Future<DayPlan> ensureTodayPlanAsync() async {
    final existing = _plans[_key(today)];
    if (existing != null) return existing;
    final plan = _freezeTodayPlan(await _pickNewWordIdsAsync());
    final loader = bookWordsByIds;
    if (loader != null) {
      await hydrateBookWords(loader);
    }
    await refreshUntaughtInLevelCount();
    return plan;
  }

  /// UI hot path after [ensureTodayPlanAsync]: returns today's frozen plan.
  /// Falls back to sync ensure only when no plan exists yet (tests / incomplete wiring).
  DayPlan get requiredTodayPlan {
    final existing = todayPlan;
    if (existing != null) return existing;
    return ensureTodayPlan();
  }

  List<String> _userWordCandidates(Set<String> used) {
    final picked = <String>[];
    for (final word in _words.values) {
      if (picked.length >= dailyWords) break;
      if (word.source != WordSource.user) continue;
      if (used.contains(word.id) || picked.contains(word.id)) continue;
      picked.add(word.id);
    }
    return picked;
  }

  Set<String> get _taughtNewWordIds => {
        for (final plan in _plans.values) ...plan.newWordIds,
      };

  List<String> _pickNewWordIdsSync() {
    final used = _taughtNewWordIds;
    final picked = _userWordCandidates(used);
    if (picked.length < dailyWords) {
      final need = dailyWords - picked.length;
      picked.addAll(
        pickUntaughtIds(
          level: cefrCodeForLevel(level),
          limit: need,
          exclude: {...used, ...picked},
        ),
      );
    }
    return picked;
  }

  Future<List<String>> _pickNewWordIdsAsync() async {
    final used = _taughtNewWordIds;
    final picked = _userWordCandidates(used);
    if (picked.length >= dailyWords) return picked;
    final need = dailyWords - picked.length;
    final exclude = {...used, ...picked};
    final code = cefrCodeForLevel(level);
    final picker = untaughtIdPicker;
    if (picker != null) {
      picked.addAll(
        await picker(level: code, limit: need, exclude: exclude),
      );
    } else {
      picked.addAll(
        pickUntaughtIds(level: code, limit: need, exclude: exclude),
      );
    }
    return picked;
  }

  DayPlan _freezeTodayPlan(List<String> picked) {
    final key = _key(today);
    final existing = _plans[key];
    if (existing != null) return existing;
    final reviews = <String>[];
    for (final entry in _reviews.entries) {
      final next = entry.value.nextReview;
      if (next == null || next.isAfter(today)) continue;
      if (_isActiveError(entry.key)) continue;
      if (picked.contains(entry.key)) continue;
      reviews.add(entry.key);
    }
    final dueErrors = _errors.entries
        .where(
          (entry) =>
              !entry.value.resolved && !entry.value.nextReview.isAfter(today),
        )
        .map((entry) => entry.key)
        .toList()
      ..sort();
    final plan = DayPlan(
      date: today,
      newWordIds: picked,
      reviewWordIds: reviews,
      errorWordIds: dueErrors.take(3).toList(),
    );
    _plans[key] = plan;
    for (final id in picked) {
      _reviews.putIfAbsent(id, () => _Review()).introducedOn ??= today;
    }
    _untaughtInLevelCache = null;
    return plan;
  }

  DayPlan? get todayPlan => _plans[_key(today)];

  /// Today already has a plan: level/word prefs apply tomorrow.
  bool get hasFrozenTodayPlan => todayPlan != null;

  List<DayPlan> get history {
    final plans = _plans.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return plans;
  }

  Lexeme? word(String id) => _words[id];

  /// Cache size of hydrated + user lexemes (not the full CEFR book).
  int get cachedLexemeCount => _words.length;

  List<Lexeme> get catalog => _words.values.toList();

  /// User words plus already-introduced book words (keeps 词本 UI off the full 5k list).
  List<Lexeme> get browsableWords => [
        for (final word in _words.values)
          if (word.source == WordSource.user ||
              (_reviews[word.id]?.introducedOn != null))
            word,
      ];

  void cacheBookWord(CefrWord entry) {
    _words.putIfAbsent(
      entry.id,
      () => Lexeme(
        id: entry.id,
        en: entry.en,
        cn: entry.cn,
        pos: entry.pos,
        source: WordSource.book,
        level: entry.level,
      ),
    );
  }

  void cacheBookWords(Iterable<CefrWord> words) {
    for (final entry in words) {
      cacheBookWord(entry);
    }
  }

  /// Ids referenced by plans / reviews / errors that may need SQL hydrate.
  Set<String> referencedBookIds() {
    final ids = <String>{
      for (final plan in _plans.values) ...[
        ...plan.newWordIds,
        ...plan.reviewWordIds,
        ...plan.errorWordIds,
      ],
      ..._errors.keys,
      ..._reviews.keys,
    };
    ids.removeWhere((id) {
      final existing = _words[id];
      return existing != null && existing.source == WordSource.user;
    });
    return ids;
  }

  /// Load missing book lexemes via [loader] (typically SQLite by id).
  Future<void> hydrateBookWords(BookWordsByIds loader) async {
    final missing = [
      for (final id in referencedBookIds())
        if (!_words.containsKey(id)) id,
    ];
    if (missing.isEmpty) return;
    cacheBookWords(await loader(missing));
  }

  int _untaughtInLevelCountSync() {
    final code = cefrCodeForLevel(level);
    final used = _taughtNewWordIds;
    var count = 0;
    for (final word in _words.values) {
      if (word.source != WordSource.book) continue;
      if (word.level != code) continue;
      if (used.contains(word.id)) continue;
      count += 1;
    }
    return count;
  }

  void invalidateUntaughtCount() => _untaughtInLevelCache = null;

  /// Warm or refresh the SQL/RAM untaught count used by nudge + 词本.
  Future<int> refreshUntaughtInLevelCount() async {
    final code = cefrCodeForLevel(level);
    final used = _taughtNewWordIds;
    final fn = untaughtCountFn;
    final count = fn != null
        ? await fn(level: code, exclude: used)
        : _untaughtInLevelCountSync();
    _untaughtInLevelCache = count;
    return count;
  }

  /// Prefer cached SQL count when [untaughtCountFn] is wired.
  int untaughtInLevelCount() {
    final cached = _untaughtInLevelCache;
    if (cached != null) return cached;
    if (untaughtCountFn != null) {
      // SQL mode but cache not warm: avoid false "exhausted" nudge (empty RAM book).
      return 1;
    }
    return _untaughtInLevelCountSync();
  }

  /// Next product level, or null at the top band.
  String? get nextProductLevel {
    final current = normalizeLevel(level);
    final index = productLevels.indexOf(current);
    if (index < 0 || index >= productLevels.length - 1) return null;
    return productLevels[index + 1];
  }

  /// Random untaught book ids for CEFR [level] (a1|a2|b1), excluding [exclude].
  /// In-memory twin of the SQL picker; sync fallback when no [untaughtIdPicker].
  List<String> pickUntaughtIds({
    required String level,
    required int limit,
    required Set<String> exclude,
  }) {
    if (limit <= 0) return [];
    final pool = [
      for (final word in _words.values)
        if (word.source == WordSource.book &&
            word.level == level &&
            !exclude.contains(word.id))
          word.id,
    ];
    pool.shuffle(_random);
    return pool.take(limit).toList();
  }

  /// Offer upgrade only when this CEFR band has zero untaught book words left.
  bool get shouldOfferLevelUpgrade {
    if (upgradeNudgeDismissed) return false;
    if (nextProductLevel == null) return false;
    return untaughtInLevelCount() == 0;
  }

  /// Confirm upgrade: level changes now; today's frozen plan is unchanged.
  bool acceptLevelUpgrade() {
    final next = nextProductLevel;
    if (next == null) return false;
    level = next;
    upgradeNudgeDismissed = false;
    _untaughtInLevelCache = null;
    return true;
  }

  void dismissUpgradeNudge() {
    upgradeNudgeDismissed = true;
  }

  List<String> vocabQueue(DayPlan plan) => [
    ...plan.newWordIds,
    ...plan.reviewWordIds,
  ];

  String? get currentVocabId {
    final plan = ensureTodayPlan();
    final queue = vocabQueue(plan);
    if (plan.vocabCursor >= 0 && plan.vocabCursor < queue.length) {
      return queue[plan.vocabCursor];
    }
    if (vocabThresholdMet) return null;
    final attempts = _attempts[_key(plan.date)] ?? [];
    for (final id in plan.newWordIds) {
      final own = attempts.where((item) => item.wordId == id).toList();
      if (own.isEmpty || !own.last.correct) return id;
    }
    return null;
  }

  VocabFeedback? get pendingVocab {
    final plan = todayPlan;
    if (plan == null) return null;
    final id = currentVocabId;
    if (id == null ||
        plan.heldVocabId != id ||
        plan.heldVocabCursor != plan.vocabCursor) {
      return null;
    }
    final lexeme = _words[id];
    if (lexeme == null) return null;
    return VocabFeedback(
      wordId: id,
      correct: plan.heldVocabCorrect,
      correctEn: lexeme.en,
    );
  }

  VocabFeedback? submitVocab(String answer) {
    final plan = ensureTodayPlan();
    final id = currentVocabId;
    if (id == null) return null;
    final lexeme = _words[id]!;
    final already =
        plan.heldVocabId == id && plan.heldVocabCursor == plan.vocabCursor;
    if (already) {
      return VocabFeedback(
        wordId: id,
        correct: plan.heldVocabCorrect,
        correctEn: lexeme.en,
      );
    }
    final correct = normalizeAnswer(answer) == normalizeAnswer(lexeme.en);
    _attempts.putIfAbsent(_key(plan.date), () => []).add(
      _Attempt(id, answer, correct),
    );
    if (correct) {
      if (_isActiveError(id)) {
        _advanceError(id, today);
      } else {
        _advanceSuccess(id, today);
      }
    } else {
      _markWrong(id, answer, lexeme.en, today);
    }
    plan.heldVocabId = id;
    plan.heldVocabCursor = plan.vocabCursor;
    plan.heldVocabCorrect = correct;
    return VocabFeedback(
      wordId: id,
      correct: correct,
      correctEn: lexeme.en,
    );
  }

  void advanceVocab() {
    final plan = ensureTodayPlan();
    final queue = vocabQueue(plan);
    if (plan.vocabCursor < queue.length) plan.vocabCursor += 1;
    plan.heldVocabId = null;
    plan.heldVocabCursor = null;
    plan.heldVocabCorrect = false;
  }

  bool get vocabThresholdMet {
    final plan = ensureTodayPlan();
    final ids = plan.newWordIds;
    if (ids.isEmpty) return false;
    var lastCorrect = 0;
    for (final id in ids) {
      final attempts = (_attempts[_key(plan.date)] ?? [])
          .where((item) => item.wordId == id)
          .toList();
      if (attempts.isEmpty) return false;
      if (attempts.last.correct) lastCorrect += 1;
    }
    return lastCorrect >= vocabPassThreshold(ids.length);
  }

  bool _isActiveError(String id) {
    final item = _errors[id];
    return item != null && !item.resolved;
  }

  void _markWrong(
    String id,
    String wrong,
    String correct,
    DateTime day,
  ) {
    _errors[id] = _ErrorItem(
      wrongAnswer: wrong,
      correctAnswer: correct,
      round: 0,
      nextReview: addDays(day, 1),
      resolved: false,
    );
    final review = _reviews[id];
    if (review != null) review.nextReview = null;
  }

  void _advanceError(String id, DateTime day) {
    final item = _errors[id]!;
    if (item.round <= 0) {
      item.round = 1;
      item.nextReview = addDays(day, 3);
    } else if (item.round == 1) {
      item.round = 2;
      item.nextReview = addDays(day, 7);
    } else {
      item.resolved = true;
    }
  }

  void _advanceSuccess(String id, DateTime day) {
    final review = _reviews.putIfAbsent(id, () => _Review());
    final intro = review.introducedOn ?? day;
    review.introducedOn = intro;
    if (review.stage <= 0) {
      review.stage = 1;
      review.nextReview = addDays(intro, 2);
    } else if (review.stage == 1) {
      review.stage = 2;
      review.nextReview = addDays(intro, 4);
    } else if (review.stage == 2) {
      review.stage = 3;
      review.nextReview = addDays(intro, 8);
    } else {
      review.nextReview = null;
    }
  }

  VocabFeedback? get pendingError {
    final plan = todayPlan;
    final id = currentErrorId;
    if (plan == null ||
        id == null ||
        plan.heldErrorId != id ||
        plan.heldErrorCursor != plan.errorCursor) {
      return null;
    }
    final item = _errors[id];
    if (item == null) return null;
    return VocabFeedback(
      wordId: id,
      correct: plan.heldErrorCorrect,
      correctEn: item.correctAnswer,
    );
  }

  VocabFeedback? submitErrorReview(String wordId, String answer) {
    final plan = ensureTodayPlan();
    final item = _errors[wordId];
    if (item == null) return null;
    final current = currentErrorId;
    final already =
        current == wordId &&
        plan.heldErrorId == wordId &&
        plan.heldErrorCursor == plan.errorCursor;
    if (already) {
      return VocabFeedback(
        wordId: wordId,
        correct: plan.heldErrorCorrect,
        correctEn: item.correctAnswer,
      );
    }
    if (item.resolved) return null;
    final savedCorrect = item.correctAnswer;
    final correct = normalizeAnswer(answer) == normalizeAnswer(savedCorrect);
    if (correct) {
      _advanceError(wordId, today);
    } else {
      _markWrong(wordId, answer, savedCorrect, today);
    }
    plan.heldErrorId = wordId;
    plan.heldErrorCursor = plan.errorCursor;
    plan.heldErrorCorrect = correct;
    return VocabFeedback(
      wordId: wordId,
      correct: correct,
      correctEn: savedCorrect,
    );
  }

  DateTime? nextErrorReview(String id) {
    final item = _errors[id];
    if (item == null || item.resolved) return null;
    return item.nextReview;
  }

  bool get errorResolved {
    if (_errors.isEmpty) return false;
    return _errors.values.every((item) => item.resolved);
  }

  bool isErrorResolved(String id) => _errors[id]?.resolved ?? false;

  int get activeErrorRound {
    final item = _errors.values.where((item) => !item.resolved).firstOrNull;
    return item?.round ?? -1;
  }

  DateTime? successReviewOn(String id) => _reviews[id]?.nextReview;

  int successStage(String id) => _reviews[id]?.stage ?? 0;

  void markDialogueDone() {
    ensureTodayPlan().dialogueDone = true;
  }

  bool get dialogueDone => ensureTodayPlan().dialogueDone;

  bool get sentencesDone {
    final plan = ensureTodayPlan();
    if (plan.newWordIds.isEmpty) return false;
    return plan.newWordIds.every(plan.sentenceResults.containsKey);
  }

  String? get currentSentenceWordId {
    final plan = ensureTodayPlan();
    for (final id in plan.newWordIds) {
      if (!plan.sentenceResults.containsKey(id)) return id;
    }
    return null;
  }

  int get sentenceDoneCount => ensureTodayPlan().sentenceResults.length;

  String sentencePrompt(String wordId) {
    final word = _words[wordId];
    if (word == null) return '用今天的一个新词造一句英文。';
    return '用「${word.en}」（${word.cn}）造一句英文。';
  }

  List<Map<String, Object?>> sentenceSnapshot() {
    final plan = ensureTodayPlan();
    return [
      for (final id in plan.newWordIds)
        {
          'wordId': id,
          'done': plan.sentenceResults.containsKey(id),
          'pass': plan.sentenceResults[id],
        },
    ];
  }

  bool get checkedIn => vocabThresholdMet && sentencesDone && dialogueDone;

  void skipNotes() {
    final plan = ensureTodayPlan();
    plan.notesDismissed = true;
    plan.checkedInAt ??= today;
  }

  void confirmNotes(List<StudyNote> notes) {
    final plan = ensureTodayPlan();
    plan.notes
      ..clear()
      ..addAll(notes.take(5));
    plan.notesDismissed = true;
    plan.checkedInAt ??= today;
  }

  List<StudyNote> get savedNotes =>
      List.unmodifiable(ensureTodayPlan().notes);

  bool get notesDismissed => ensureTodayPlan().notesDismissed;

  String addUserWord({
    required String en,
    required String cn,
    required String pos,
  }) {
    var n = 1;
    for (final word in _words.values) {
      if (word.source == WordSource.user) n += 1;
    }
    while (_words.containsKey('u$n')) {
      n += 1;
    }
    final id = 'u$n';
    _words[id] = Lexeme(
      id: id,
      en: en,
      cn: cn,
      pos: pos,
      source: WordSource.user,
    );
    return id;
  }

  bool todayContains(String id) =>
      ensureTodayPlan().newWordIds.contains(id);

  List<String> scheduledNewWords() =>
      List<String>.from(ensureTodayPlan().newWordIds);

  List<String> scheduledErrors() =>
      List<String>.from(ensureTodayPlan().errorWordIds);

  bool get shouldRequestScene => ensureTodayPlan().scene == null;

  LessonScene? get scene => ensureTodayPlan().scene;

  String? get referencePreview => ensureTodayPlan().referencePreview;

  /// Reference text is display-only (never part of grading).
  void applyTranslation(String text) {
    ensureTodayPlan().referencePreview = text.trim();
  }

  Map<String, String> reviewSnapshot() {
    return {
      for (final entry in _reviews.entries)
        if (entry.value.nextReview != null)
          entry.key: _key(entry.value.nextReview!),
      for (final entry in _errors.entries)
        if (!entry.value.resolved)
          'err:${entry.key}': _key(entry.value.nextReview),
    };
  }

  /// Accepts one DeepSeek task. Invalid JSON or a non-stop finish writes nothing.
  bool applyModelResponse({
    required String task,
    required String content,
    required String? finishReason,
    String? sentenceWordId,
  }) {
    if (finishReason != 'stop') return false;
    final json = _decodeObject(content);
    if (json == null) return false;
    final plan = ensureTodayPlan();
    switch (task) {
      case 'fill_scene':
        final parsed = _parseScene(json);
        if (parsed == null) return false;
        plan.scene ??= parsed;
        return true;
      case 'grade_open':
        final grade = _parseGrade(json);
        if (grade == null) return false;
        lastGrade = grade;
        if (grade.errors.isNotEmpty) {
          plan.gradeNotes.add(
            StudyNote(
              wrong: grade.errors.first.excerpt,
              corrected: grade.correctedEn,
              whyCn: grade.errors.first.whyCn,
            ),
          );
          if (plan.gradeNotes.length > 5) {
            plan.gradeNotes.removeRange(0, plan.gradeNotes.length - 5);
          }
        }
        if (sentenceWordId != null &&
            plan.newWordIds.contains(sentenceWordId) &&
            !plan.sentenceResults.containsKey(sentenceWordId)) {
          plan.sentenceResults[sentenceWordId] = grade.pass;
        }
        return true;
      case 'explain':
        if (json['answer_cn'] is! String || json['example_en'] is! String) {
          return false;
        }
        lastExplainCn = json['answer_cn'] as String;
        lastExplainEn = json['example_en'] as String;
        return true;
      default:
        return false;
    }
  }

  int streak() {
    var day = checkedIn ? today : addDays(today, -1);
    var count = 0;
    while (true) {
      final plan = _plans[_key(day)];
      if (plan == null || !_wasCheckedIn(plan)) break;
      count += 1;
      day = addDays(day, -1);
    }
    return count;
  }

  bool _wasCheckedIn(DayPlan plan) {
    if (plan.checkedInAt != null) return true;
    return _planCheckedIn(plan);
  }

  bool _planCheckedIn(DayPlan plan) {
    if (!plan.dialogueDone) return false;
    if (plan.newWordIds.isEmpty) return false;
    if (!plan.newWordIds.every(plan.sentenceResults.containsKey)) return false;
    return _vocabMet(plan);
  }

  bool _vocabMet(DayPlan plan) {
    final ids = plan.newWordIds;
    if (ids.isEmpty) return false;
    var lastCorrect = 0;
    final attempts = _attempts[_key(plan.date)] ?? [];
    for (final id in ids) {
      final own = attempts.where((item) => item.wordId == id).toList();
      if (own.isEmpty) return false;
      if (own.last.correct) lastCorrect += 1;
    }
    return lastCorrect >= vocabPassThreshold(ids.length);
  }

  bool vocabSeen(String wordId) {
    final attempts = _attempts[_key(today)] ?? [];
    return attempts.any((item) => item.wordId == wordId);
  }

  String homeActionLabel() {
    final plan = ensureTodayPlan();
    if (checkedIn) return '回看今天';
    if (!vocabThresholdMet) {
      final attempts = _attempts[_key(plan.date)] ?? [];
      if (attempts.isEmpty) return '开始今天';
      return '继续认词';
    }
    if (!sentencesDone) return '继续造句';
    if (sceneInFlight && plan.scene == null) return '正在写今天的场景';
    if (!plan.dialogueDone) return '继续对话';
    if (plan.errorWordIds.isNotEmpty) return '还有错词';
    return '回看今天';
  }

  List<StudyNote> noteDrafts() {
    final drafts = <StudyNote>[...ensureTodayPlan().gradeNotes];
    for (final item in _errors.values) {
      if (item.wrongAnswer.trim().isEmpty) continue;
      drafts.add(
        StudyNote(
          wrong: item.wrongAnswer,
          corrected: item.correctAnswer,
          whyCn: '认词时这句还不对。',
        ),
      );
    }
    return drafts.take(5).toList();
  }

  int get dialogueCursor => ensureTodayPlan().dialogueCursor;

  void advanceDialogue() {
    final plan = ensureTodayPlan();
    final total = plan.scene?.dialogue.length ?? 0;
    if (plan.dialogueCursor < total) plan.dialogueCursor += 1;
    if (total > 0 && plan.dialogueCursor >= total) {
      plan.dialogueDone = true;
    }
  }

  String? get currentErrorId {
    final plan = ensureTodayPlan();
    if (plan.errorCursor < 0 || plan.errorCursor >= plan.errorWordIds.length) {
      return null;
    }
    return plan.errorWordIds[plan.errorCursor];
  }

  void advanceErrorCursor() {
    final plan = ensureTodayPlan();
    plan.errorCursor += 1;
    plan.heldErrorId = null;
    plan.heldErrorCursor = null;
    plan.heldErrorCorrect = false;
  }

  String? errorSentence(String id) {
    final item = _errors[id];
    if (item == null || item.resolved) return null;
    final wrong = item.wrongAnswer.trim();
    if (!wrong.contains(' ')) return null;
    return wrong;
  }

  String errorGapLabel(String id) {
    if (isErrorResolved(id)) return '已移出';
    final next = nextErrorReview(id);
    if (next == null) return '已移出';
    final days = dateOnly(next).difference(today).inDays;
    if (days <= 1) return '明天再出现';
    return '$days 天后再出现';
  }

  bool planComplete(DayPlan plan) => _wasCheckedIn(plan);

  String formatDay(DateTime value) => _key(value);

  void recordCall({
    required String task,
    required bool ok,
    String? finishReason,
    int? tokens,
  }) {
    callLog.add({
      'task': task,
      'ok': ok,
      'finishReason': finishReason,
      'tokens': tokens,
    });
  }

  Map<String, Object?> toJson() {
    return {
      'installId': installId,
      'dailyWords': dailyWords,
      'level': level,
      'levelChosen': levelChosen,
      'upgradeNudgeDismissed': upgradeNudgeDismissed,
      'reasoningEffort': reasoningEffort,
      'goal': goal,
      'tone': tone,
      'userWords': [
        for (final word in _words.values)
          if (word.source == WordSource.user)
            {'id': word.id, 'en': word.en, 'cn': word.cn, 'pos': word.pos},
      ],
      'plans': [
        for (final plan in _plans.values)
          {
            'date': _key(plan.date),
            'newWordIds': plan.newWordIds,
            'reviewWordIds': plan.reviewWordIds,
            'errorWordIds': plan.errorWordIds,
            'dialogueDone': plan.dialogueDone,
            'sentenceResults': {
              for (final entry in plan.sentenceResults.entries) entry.key: entry.value,
            },
            'vocabCursor': plan.vocabCursor,
            'dialogueCursor': plan.dialogueCursor,
            'errorCursor': plan.errorCursor,
            'heldVocabCursor': plan.heldVocabCursor,
            'heldVocabId': plan.heldVocabId,
            'heldVocabCorrect': plan.heldVocabCorrect,
            'heldErrorCursor': plan.heldErrorCursor,
            'heldErrorId': plan.heldErrorId,
            'heldErrorCorrect': plan.heldErrorCorrect,
            'notesDismissed': plan.notesDismissed,
            'checkedInAt': plan.checkedInAt == null
                ? null
                : _key(plan.checkedInAt!),
            'referencePreview': plan.referencePreview,
            'notes': [
              for (final note in plan.notes)
                {
                  'wrong': note.wrong,
                  'corrected': note.corrected,
                  'whyCn': note.whyCn,
                },
            ],
            'gradeNotes': [
              for (final note in plan.gradeNotes)
                {
                  'wrong': note.wrong,
                  'corrected': note.corrected,
                  'whyCn': note.whyCn,
                },
            ],
            'scene': plan.scene == null
                ? null
                : {
                    'scenarioEn': plan.scene!.scenarioEn,
                    'scenarioCn': plan.scene!.scenarioCn,
                    'grammarCn': plan.scene!.grammarCn,
                    'grammarExamples': plan.scene!.grammarExamples,
                    'dialogue': [
                      for (final line in plan.scene!.dialogue)
                        {
                          'speaker': line.speaker,
                          'en': line.en,
                          'cn': line.cn,
                        },
                    ],
                  },
          },
      ],
      'attempts': {
        for (final entry in _attempts.entries)
          entry.key: [
            for (final attempt in entry.value)
              {
                'wordId': attempt.wordId,
                'answer': attempt.answer,
                'correct': attempt.correct,
              },
          ],
      },
      'errors': {
        for (final entry in _errors.entries)
          entry.key: {
            'wrongAnswer': entry.value.wrongAnswer,
            'correctAnswer': entry.value.correctAnswer,
            'round': entry.value.round,
            'nextReview': _key(entry.value.nextReview),
            'resolved': entry.value.resolved,
          },
      },
      'reviews': {
        for (final entry in _reviews.entries)
          entry.key: {
            'introducedOn': entry.value.introducedOn == null
                ? null
                : _key(entry.value.introducedOn!),
            'stage': entry.value.stage,
            'nextReview': entry.value.nextReview == null
                ? null
                : _key(entry.value.nextReview!),
          },
      },
      'calls': callLog,
    };
  }

  String progressJson() => jsonEncode(toJson());

  String _key(DateTime value) {
    final day = dateOnly(value);
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '${day.year}-$month-$date';
  }

  void restore(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    final json = decoded.map((key, value) => MapEntry(key.toString(), value));
    final savedId = json['installId'];
    if (savedId is String && savedId.isNotEmpty) installId = savedId;
    const wordCounts = {5, 10, 15, 20};
    if (wordCounts.contains(json['dailyWords'])) {
      dailyWords = json['dailyWords'] as int;
    }
    const legacyLevels = {'新手', '简单工作对话', '日常交流', '更长的表达'};
    const levels = {'入门', '基础', '进阶', ...legacyLevels};
    const goals = {'职场', '日常', '考试', '都要'};
    const tones = {'简洁', '朋友', '老师'};
    if (json['level'] is String && levels.contains(json['level'])) {
      level = normalizeLevel(json['level'] as String);
    }
    if (json['levelChosen'] == true) {
      levelChosen = true;
    } else if (json['level'] is String && levels.contains(json['level'])) {
      // Returning users who already had a level saved are treated as chosen.
      levelChosen = true;
    }
    upgradeNudgeDismissed = json['upgradeNudgeDismissed'] == true;
    if (json['reasoningEffort'] is String) {
      reasoningEffort = normalizeReasoningEffort(json['reasoningEffort'] as String);
    }
    if (goals.contains(json['goal'])) goal = json['goal'] as String;
    if (tones.contains(json['tone'])) tone = json['tone'] as String;

    _words.removeWhere((_, word) => word.source == WordSource.user);
    final users = json['userWords'];
    if (users is List) {
      for (final item in users) {
        if (item is! Map) continue;
        final id = item['id'];
        final en = item['en'];
        final cn = item['cn'];
        final pos = item['pos'];
        if (id is! String || en is! String || cn is! String || pos is! String) {
          continue;
        }
        if (_words.containsKey(id)) continue;
        _words[id] = Lexeme(
          id: id,
          en: en,
          cn: cn,
          pos: pos,
          source: WordSource.user,
        );
      }
    }

    _plans.clear();
    _attempts.clear();
    _errors.clear();
    _reviews.clear();
    callLog.clear();
    _untaughtInLevelCache = null;

    final plans = json['plans'];
    if (plans is List) {
      for (final item in plans) {
        if (item is! Map) continue;
        final day = _parseDay(item['date']);
        if (day == null) continue;
        final plan = DayPlan(
          date: day,
          newWordIds: _stringList(item['newWordIds']),
          reviewWordIds: _stringList(item['reviewWordIds']),
          errorWordIds: _stringList(item['errorWordIds']),
        );
        plan.dialogueDone = item['dialogueDone'] == true;
        plan.vocabCursor = _asInt(item['vocabCursor']);
        plan.dialogueCursor = _asInt(item['dialogueCursor']);
        plan.errorCursor = _asInt(item['errorCursor']);
        plan.heldVocabCursor = _asIntOrNull(item['heldVocabCursor']);
        plan.heldVocabId = item['heldVocabId'] is String
            ? item['heldVocabId'] as String
            : null;
        plan.heldVocabCorrect = item['heldVocabCorrect'] == true;
        plan.heldErrorCursor = _asIntOrNull(item['heldErrorCursor']);
        plan.heldErrorId = item['heldErrorId'] is String
            ? item['heldErrorId'] as String
            : null;
        plan.heldErrorCorrect = item['heldErrorCorrect'] == true;
        plan.notesDismissed = item['notesDismissed'] == true;
        plan.checkedInAt = _parseDay(item['checkedInAt']);
        final preview = item['referencePreview'];
        if (preview is String) plan.referencePreview = preview;
        // Legacy `quiz` payloads are ignored (four-question gate removed).
        final sentences = item['sentenceResults'];
        if (sentences is Map) {
          for (final entry in sentences.entries) {
            final key = entry.key.toString();
            if (entry.value is bool) {
              plan.sentenceResults[key] = entry.value as bool;
            }
          }
        }
        plan.notes.addAll(_notes(item['notes']));
        plan.gradeNotes.addAll(_notes(item['gradeNotes']));
        plan.scene = _sceneFrom(item['scene']);
        _plans[_key(day)] = plan;
      }
    }

    final attempts = json['attempts'];
    if (attempts is Map) {
      for (final entry in attempts.entries) {
        final day = _parseDay(entry.key);
        if (day == null || entry.value is! List) continue;
        final list = <_Attempt>[];
        for (final item in entry.value as List) {
          if (item is! Map) continue;
          final wordId = item['wordId'];
          final answer = item['answer'];
          final correct = item['correct'];
          if (wordId is! String || answer is! String || correct is! bool) {
            continue;
          }
          list.add(_Attempt(wordId, answer, correct));
        }
        _attempts[_key(day)] = list;
      }
    }

    final errors = json['errors'];
    if (errors is Map) {
      for (final entry in errors.entries) {
        final item = entry.value;
        if (item is! Map) continue;
        final next = _parseDay(item['nextReview']);
        final wrong = item['wrongAnswer'];
        final correct = item['correctAnswer'];
        if (next == null || wrong is! String || correct is! String) continue;
        _errors[entry.key.toString()] = _ErrorItem(
          wrongAnswer: wrong,
          correctAnswer: correct,
          round: _asInt(item['round']),
          nextReview: next,
          resolved: item['resolved'] == true,
        );
      }
    }

    final reviews = json['reviews'];
    if (reviews is Map) {
      for (final entry in reviews.entries) {
        final item = entry.value;
        if (item is! Map) continue;
        _reviews[entry.key.toString()] = _Review(
          introducedOn: _parseDay(item['introducedOn']),
          stage: _asInt(item['stage']),
          nextReview: _parseDay(item['nextReview']),
        );
      }
    }

    final calls = json['calls'];
    if (calls is List) {
      for (final item in calls) {
        if (item is! Map) continue;
        final task = item['task'];
        if (task is! String) continue;
        callLog.add({
          'task': task,
          'ok': item['ok'] == true,
          'finishReason': item['finishReason'],
          'tokens': item['tokens'],
        });
      }
    }
  }

  DateTime? _parseDay(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return dateOnly(parsed);
  }

  int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  int? _asIntOrNull(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }

  List<String> _stringList(Object? raw) {
    if (raw is! List) return [];
    return [for (final item in raw) if (item is String) item];
  }

  List<StudyNote> _notes(Object? raw) {
    if (raw is! List) return [];
    final notes = <StudyNote>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final wrong = item['wrong'];
      final corrected = item['corrected'];
      final why = item['whyCn'];
      if (wrong is! String || corrected is! String || why is! String) continue;
      notes.add(StudyNote(wrong: wrong, corrected: corrected, whyCn: why));
    }
    return notes;
  }

  LessonScene? _sceneFrom(Object? raw) {
    if (raw is! Map) return null;
    final scenarioEn = raw['scenarioEn'];
    final scenarioCn = raw['scenarioCn'];
    final grammarCn = raw['grammarCn'];
    final examples = raw['grammarExamples'];
    final dialogue = raw['dialogue'];
    if (scenarioEn is! String || scenarioCn is! String || grammarCn is! String) {
      return null;
    }
    if (examples is! List || dialogue is! List) return null;
    final lines = <SceneLine>[];
    for (final item in dialogue) {
      if (item is! Map) return null;
      final speaker = item['speaker'];
      final en = item['en'];
      final cn = item['cn'];
      if (speaker is! String || en is! String || cn is! String) return null;
      lines.add(SceneLine(speaker: speaker, en: en, cn: cn));
    }
    return LessonScene(
      scenarioEn: scenarioEn,
      scenarioCn: scenarioCn,
      dialogue: lines,
      grammarCn: grammarCn,
      grammarExamples: [for (final item in examples) item.toString()],
    );
  }
}

Map<String, Object?>? _decodeObject(String content) {
  var raw = content.trim();
  if (raw.startsWith('```')) {
    raw = raw.replaceFirst(RegExp(r'^```(?:json)?'), '');
    final end = raw.lastIndexOf('```');
    if (end >= 0) raw = raw.substring(0, end);
    raw = raw.trim();
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } on FormatException {
    return null;
  }
  return null;
}

LessonScene? _parseScene(Map<String, Object?> json) {
  if (json['scenario_en'] is! String || json['scenario_cn'] is! String) {
    return null;
  }
  final phrases = json['phrases'];
  final dialogue = json['dialogue'];
  final grammar = json['grammar'];
  if (phrases is! List || phrases.isEmpty || phrases.length > 5) return null;
  if (dialogue is! List || dialogue.length < 6 || dialogue.length > 10) {
    return null;
  }
  if (grammar is! Map) return null;
  final examples = grammar['examples'];
  if (examples is! List || examples.length != 2) return null;
  final lines = <SceneLine>[];
  for (final item in dialogue) {
    if (item is! Map) return null;
    final speaker = item['speaker'];
    final en = item['en'];
    final cn = item['cn'];
    if (speaker != 'A' && speaker != 'B') return null;
    if (en is! String || cn is! String) return null;
    lines.add(SceneLine(speaker: speaker, en: en, cn: cn));
  }
  final point = grammar['point_cn'];
  if (point is! String) return null;
  return LessonScene(
    scenarioEn: json['scenario_en'] as String,
    scenarioCn: json['scenario_cn'] as String,
    dialogue: lines,
    grammarCn: point,
    grammarExamples: [examples[0].toString(), examples[1].toString()],
  );
}

GradeResult? _parseGrade(Map<String, Object?> json) {
  final errorsRaw = json['errors'];
  if (errorsRaw is! List || errorsRaw.length > 2) return null;
  if (json['corrected_en'] is! String) return null;
  final errors = <GradeError>[];
  for (final item in errorsRaw) {
    if (item is! Map) return null;
    errors.add(
      GradeError(
        excerpt: '${item['excerpt'] ?? ''}',
        fix: '${item['fix'] ?? ''}',
        whyCn: '${item['why_cn'] ?? ''}',
      ),
    );
  }
  var pass = json['pass'] == true;
  if (errors.isEmpty) pass = true;
  return GradeResult(
    pass: pass,
    errors: errors,
    correctedEn: json['corrected_en'] as String,
  );
}

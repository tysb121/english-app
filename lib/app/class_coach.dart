import '../engine/agent_loop.dart';
import '../engine/agent_tools.dart';
import '../engine/gradebook.dart';
import '../engine/api_requests.dart';
import '../engine/chat_context.dart';
import '../engine/chat_message.dart';
import '../engine/class_session.dart';
import '../net/chat_reply.dart';
import 'app_model.dart';

/// One teacher turn: stream words, run tools, optionally raise a card.
class ClassCoach {
  ClassCoach(this.model);

  final AppModel model;
  StudyLog log = StudyLog();
  AnswerCard? pendingCard;
  PendingSubmission? pending;
  String draft = '';
  String? status;
  String? error;
  bool busy = false;
  bool hidePrompt = false;
  bool hideAnswer = false;
  int _seq = 0;

  /// end_class arrived with a card. Close after the student confirms and the
  /// teacher finishes the follow-up turn.
  bool _closeAfterAnswer = false;

  bool get hasKey => model.deepSeekKey.trim().isNotEmpty;

  void replaceLog(StudyLog next) {
    log = next;
    pendingCard = null;
    pending = null;
    draft = '';
    hidePrompt = false;
    hideAnswer = false;
    _closeAfterAnswer = false;
  }

  StudyItem? get practiced {
    final id = log.book.facts.currentItemId;
    if (id == null) return null;
    return log.book.findItem(id);
  }

  void toggleHidePrompt() {
    if (busy) return;
    hidePrompt = !hidePrompt;
    model.tick();
  }

  void toggleHideAnswer() {
    if (busy) return;
    hideAnswer = !hideAnswer;
    model.tick();
  }

  void clearLearning() {
    replaceLog(StudyLog());
  }

  /// Open a class and let the teacher speak when this class has no messages yet.
  /// A gap of two hours closes the old class and drops an unconfirmed card.
  Future<void> ensureGreeting() async {
    if (!hasKey || busy) return;
    final now = DateTime.now();
    final previous = log.openClass;
    final open = log.ensureOpen(now);
    if (previous != null && previous.id != open.id) {
      pendingCard = null;
      pending = null;
      draft = '';
      error = null;
      _closeAfterAnswer = false;
    }
    if (pendingCard != null || open.messages.isNotEmpty) return;
    await _turn(includeCue: true);
  }

  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || busy || pendingCard != null) return;
    if (!hasKey) {
      error = '填写密钥后才能上课';
      model.tick();
      return;
    }
    final now = DateTime.now();
    final open = log.ensureOpen(now);
    open.messages.add(
      ChatMessage(id: _id(), role: ChatRole.user, content: trimmed),
    );
    open.userTurns += 1;
    open.lastMessageAt = now;
    pending = PendingSubmission(text: trimmed, answerHidden: hideAnswer);
    model.noteStudyChanged();
    await _turn(includeCue: open.messages.length == 1);
  }

  Future<void> confirmCard({String? optionId, String text = ''}) async {
    final card = pendingCard;
    if (card == null || busy) return;
    final shown = _confirmedText(card, optionId: optionId, text: text);
    if (shown == null) return;
    final now = DateTime.now();
    final open = log.openClass;
    if (open == null) return;
    open.messages.add(ChatMessage(id: _id(), role: ChatRole.user, content: shown));
    open.userTurns += 1;
    open.lastMessageAt = now;
    pending = PendingSubmission(
      text: shown,
      optionId: optionId,
      answerHidden: hideAnswer,
    );
    pendingCard = null;
    model.noteStudyChanged();
    await _turn(includeCue: false);
  }

  /// The student does not know which option to pick. This is not an option.
  Future<void> unknownCard() async {
    if (pendingCard == null || busy) return;
    final open = log.openClass;
    if (open == null) return;
    final now = DateTime.now();
    open.messages.add(
      ChatMessage(id: _id(), role: ChatRole.user, content: cardUnknownText),
    );
    open.userTurns += 1;
    open.lastMessageAt = now;
    pending = PendingSubmission(
      text: cardUnknownText,
      answerShown: true,
    );
    pendingCard = null;
    model.noteStudyChanged();
    await _turn(includeCue: false);
  }

  /// Drop an unanswered card, close this class, and open the next one.
  /// Nothing is graded. The next class speaks on this same page.
  Future<void> stopHere() async {
    if (busy) return;
    pendingCard = null;
    pending = null;
    draft = '';
    error = null;
    _closeAfterAnswer = false;
    log.closeOpen(DateTime.now());
    model.noteStudyChanged();
    await ensureGreeting();
  }

  Future<void> retry() async {
    error = null;
    final open = log.openClass;
    if (open == null || open.messages.isEmpty) {
      await ensureGreeting();
      return;
    }
    await _turn(includeCue: false);
  }

  Future<void> _turn({required bool includeCue}) async {
    final open = log.openClass;
    if (open == null || !hasKey) return;
    busy = true;
    error = null;
    status = null;
    draft = '';
    model.tick();
    final beforeAttempts = log.book.attempts.length;
    try {
      await _foldSummary(open);
      final messages = _outbound(open, includeCue: includeCue);
      final update = await runAgentTurn(
        poster: model.poster,
        messages: messages,
        book: log.book,
        pending: pending,
        cardPending: pendingCard != null,
        apiKey: model.deepSeekKey,
        baseUrl: model.deepSeekBase,
        model: model.deepSeekModel,
        installId: model.store.installId,
        classId: open.id,
        settings: LearnerSettings(
          level: model.store.level,
          goal: model.store.goal,
        ),
        lookupWords: model.lookupWords,
        onUpdate: (next) {
          draft = next.visibleText;
          status = next.status;
          model.tick();
        },
      );
      open.judged += log.book.attempts.length - beforeAttempts;
      final spoken = update.visibleText.trim();
      if (update.card != null) {
        final bubble = spoken.isEmpty ? update.card!.prompt : spoken;
        open.messages.add(
          ChatMessage(id: _id(), role: ChatRole.assistant, content: bubble),
        );
        open.lastMessageAt = DateTime.now();
        pendingCard = update.card;
        draft = '';
        if (update.endClass) _closeAfterAnswer = true;
      } else if (spoken.isNotEmpty) {
        open.messages.add(
          ChatMessage(id: _id(), role: ChatRole.assistant, content: spoken),
        );
        open.lastMessageAt = DateTime.now();
        draft = '';
      }
      status = null;
      error = update.error;
      final failed = update.error != null;
      final shouldClose =
          !failed &&
          update.card == null &&
          (update.endClass || _closeAfterAnswer);
      if (shouldClose) {
        _closeAfterAnswer = false;
        pendingCard = null;
        pending = null;
        log.closeOpen(DateTime.now());
        log.ensureOpen(DateTime.now());
        model.noteStudyChanged();
        busy = false;
        await ensureGreeting();
        return;
      }
      if (!failed && pendingCard == null && log.closeIfFull(DateTime.now())) {
        _closeAfterAnswer = false;
        model.noteStudyChanged();
        busy = false;
        await ensureGreeting();
        return;
      }
    } on Object {
      error = '服务暂时不可用';
    } finally {
      busy = false;
      status = null;
      model.noteStudyChanged();
    }
  }

  Future<void> _foldSummary(StudyClass open) async {
    var projection = projectContext(
      open.messages,
      summary: open.checkpoint,
    );
    if (!projection.needsSummary ||
        projection.summarizeSource == null ||
        projection.cutUserId == null) {
      return;
    }
    final call = deepSeekSummarize(
      apiKey: model.deepSeekKey,
      source: projection.summarizeSource!,
      baseUrl: model.deepSeekBase,
      model: model.deepSeekModel,
      userId: model.store.installId,
    );
    try {
      final posted = await model.poster.send(call);
      if (posted.status != 200) return;
      final reply = parseChatReply(posted.body);
      if (reply == null || reply.finishReason != 'stop') return;
      open.checkpoint = decideSummaryResult(
        untilMessageId: projection.cutUserId!,
        source: projection.summarizeSource!,
        summaryText: reply.content,
      );
    } on Object {
      // Keep the full class text for this request.
    }
  }

  List<Map<String, Object?>> _outbound(
    StudyClass open, {
    required bool includeCue,
  }) {
    final previous = _previousCloseNote(open);
    final projection = projectContext(open.messages, summary: open.checkpoint);
    return [
      {
        'role': 'system',
        'content': buildAgentSystem(previousCloseNote: previous),
      },
      if (includeCue) {'role': 'user', 'content': classOpenCue},
      for (final message in projection.history)
        {
          'role': message.role == ChatRole.user ? 'user' : 'assistant',
          'content': message.content,
        },
    ];
  }

  String? _previousCloseNote(StudyClass open) {
    final index = log.classes.indexWhere((item) => item.id == open.id);
    if (index <= 0) return null;
    final note = log.classes[index - 1].closeNote.trim();
    return note.isEmpty ? null : note;
  }

  String? _confirmedText(
    AnswerCard card, {
    String? optionId,
    required String text,
  }) {
    if (card.kind == CardKind.blank) {
      final trimmed = text.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    for (final option in card.options) {
      if (option.id == optionId) return option.text;
    }
    return null;
  }

  String _id() {
    _seq += 1;
    return 'c$_seq';
  }
}

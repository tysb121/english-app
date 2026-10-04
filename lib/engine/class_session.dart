import 'chat_context.dart';
import 'chat_message.dart';
import 'class_policy.dart';
import 'gradebook.dart';

class StudyClass {
  StudyClass({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.closeNote = '',
    List<ChatMessage>? messages,
    this.checkpoint,
    this.userTurns = 0,
    this.judged = 0,
    this.lastMessageAt,
  }) : messages = messages ?? <ChatMessage>[];

  final String id;
  final DateTime startedAt;
  DateTime? endedAt;
  String closeNote;
  final List<ChatMessage> messages;
  ContextSummary? checkpoint;

  /// 这一节的用户消息数，由调用方累加。
  int userTurns;

  /// 成功记下的判断次数，由调用方累加。
  int judged;

  DateTime? lastMessageAt;

  bool get isOpen => endedAt == null;

  Map<String, Object?> toJson() => {
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'closeNote': closeNote,
    'messages': [for (final message in messages) message.toJson()],
    if (checkpoint != null) 'checkpoint': checkpoint!.toJson(),
    'userTurns': userTurns,
    'judged': judged,
    'lastMessageAt': lastMessageAt?.toIso8601String(),
  };

  static StudyClass? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final startedRaw = raw['startedAt'];
    if (id is! String || id.isEmpty || startedRaw is! String) return null;
    final startedAt = _parseTime(startedRaw);
    if (startedAt == null) return null;
    final endedRaw = raw['endedAt'];
    if (endedRaw != null && endedRaw is! String) return null;
    final endedAt = endedRaw is String ? _parseTime(endedRaw) : null;
    if (endedRaw is String && endedAt == null) return null;
    final lastRaw = raw['lastMessageAt'];
    if (lastRaw != null && lastRaw is! String) return null;
    final lastMessageAt = lastRaw is String ? _parseTime(lastRaw) : null;
    if (lastRaw is String && lastMessageAt == null) return null;
    final closeRaw = raw['closeNote'];
    if (closeRaw != null && closeRaw is! String) return null;
    final userTurns = raw['userTurns'];
    final judged = raw['judged'];
    if (userTurns != null && userTurns is! int) return null;
    if (judged != null && judged is! int) return null;
    final messagesRaw = raw['messages'];
    if (messagesRaw != null && messagesRaw is! List) return null;
    final messages = <ChatMessage>[];
    if (messagesRaw is List) {
      for (final entry in messagesRaw) {
        final message = ChatMessage.fromJson(entry);
        if (message == null) return null;
        messages.add(message);
      }
    }
    ContextSummary? checkpoint;
    if (raw.containsKey('checkpoint') && raw['checkpoint'] != null) {
      checkpoint = ContextSummary.fromJson(raw['checkpoint']);
      if (checkpoint == null) return null;
    }
    return StudyClass(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt,
      closeNote: closeRaw is String ? closeRaw : '',
      messages: messages,
      checkpoint: checkpoint,
      userTurns: userTurns is int ? userTurns : 0,
      judged: judged is int ? judged : 0,
      lastMessageAt: lastMessageAt,
    );
  }
}

class StudyLog {
  StudyLog({
    Gradebook? book,
    List<StudyClass>? classes,
    IdFactory? ids,
    DateTime Function()? clock,
  }) : book = book ?? Gradebook(clock: clock, ids: ids),
       classes = classes ?? <StudyClass>[],
       _clock = clock ?? DateTime.now {
    _ids = ids ?? _generatedId;
  }

  final Gradebook book;
  final List<StudyClass> classes;
  final DateTime Function() _clock;
  late final IdFactory _ids;
  int _seq = 0;

  /// 最后一节且未结束。
  StudyClass? get openClass {
    if (classes.isEmpty) return null;
    final last = classes.last;
    return last.isOpen ? last : null;
  }

  String _generatedId() {
    _seq += 1;
    return 'c${_clock().microsecondsSinceEpoch}$_seq';
  }

  /// 没有开着的课，或开着的课上一条消息距 now 已满 2 小时，就先收掉旧课再新开一节。
  /// 刚开的空课还没有消息，不会因为 lastMessageAt 为空而立刻再切。
  StudyClass ensureOpen(DateTime now) {
    final open = openClass;
    if (open != null) {
      final last = open.lastMessageAt;
      if (last != null && gapStartsNewClass(last, now)) {
        closeOpen(now);
      } else {
        return open;
      }
    }
    final created = StudyClass(id: _ids(), startedAt: now);
    classes.add(created);
    return created;
  }

  /// 收掉开着的课。未确认的卡片由调用方丢弃，这里不记作答。
  void closeOpen(DateTime now) {
    final open = openClass;
    if (open == null) return;
    open.endedAt = now;
    open.closeNote = book.closeNote();
  }

  /// 当前回合已经结束时调用。满了就收课并立刻新开一节。
  bool closeIfFull(DateTime now) {
    final open = openClass;
    if (open == null) return false;
    if (!classIsFull(judged: open.judged, userMessages: open.userTurns)) {
      return false;
    }
    closeOpen(now);
    ensureOpen(now);
    return true;
  }

  /// 从最后一节往前，相邻两节间隔不足 2 小时算同一次坐下。按时间正序返回。
  List<StudyClass> currentSitting(DateTime now) {
    if (classes.isEmpty) return <StudyClass>[];
    if (_sittingExpired(classes.last, now)) return <StudyClass>[];
    var start = classes.length - 1;
    while (start > 0 && _withinGap(classes[start - 1], classes[start])) {
      start -= 1;
    }
    return classes.sublist(start);
  }

  /// 只投影开着的这一节。needsSummary 时也不调用模型，原样返回当时的 history。
  List<Map<String, String>> openModelMessages() {
    final open = openClass;
    if (open == null) return <Map<String, String>>[];
    final projection = projectContext(
      open.messages,
      summary: open.checkpoint,
      budget: defaultProjectionBudget,
      keepUserTurns: defaultKeepUserTurns,
    );
    return [
      for (final message in projection.history)
        <String, String>{
          'role': message.role == ChatRole.user ? 'user' : 'assistant',
          'content': message.content,
        },
    ];
  }
}

DateTime? _parseTime(String raw) {
  try {
    return DateTime.parse(raw);
  } on FormatException {
    return null;
  }
}

bool _sittingExpired(StudyClass session, DateTime now) {
  final mark =
      session.lastMessageAt ?? (session.isOpen ? null : session.endedAt);
  if (mark == null) return false;
  return gapStartsNewClass(mark, now);
}

bool _withinGap(StudyClass prev, StudyClass next) {
  final mark = prev.lastMessageAt ?? prev.endedAt ?? prev.startedAt;
  return next.startedAt.difference(mark) < classGap;
}

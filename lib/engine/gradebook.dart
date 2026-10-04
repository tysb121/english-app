enum ItemStatus { unseen, shaky, canUse }

String itemStatusLabel(ItemStatus status) {
  switch (status) {
    case ItemStatus.unseen:
      return '没练过';
    case ItemStatus.shaky:
      return '不稳';
    case ItemStatus.canUse:
      return '会用';
  }
}

/// 接受中文标签或 enum 名。无法识别时返回 null。
ItemStatus? parseItemStatus(String raw) {
  switch (raw.trim()) {
    case '没练过':
    case 'unseen':
      return ItemStatus.unseen;
    case '不稳':
    case 'shaky':
      return ItemStatus.shaky;
    case '会用':
    case 'canUse':
      return ItemStatus.canUse;
    default:
      return null;
  }
}

const errorTags = <String>['缺冠词', '语序', '时态', '拼写', '用错词', '漏主语', '夹了中文', '其它'];

/// 不在表内或空 -> 其它。
String normalizeErrorTag(String? raw) {
  final text = raw?.trim() ?? '';
  if (errorTags.contains(text)) return text;
  return '其它';
}

int _clampDifficulty(int value) {
  if (value < 1) return 1;
  if (value > 5) return 5;
  return value;
}

String _oneLine(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

class StudyItem {
  StudyItem({
    required this.id,
    required this.promptCn,
    required this.targetEn,
    required int difficulty,
    this.status = ItemStatus.unseen,
    this.dueAt,
    this.lastErrorTag,
    this.lastSubmission,
    this.correctedEn,
    this.reason,
  }) : _difficulty = _clampDifficulty(difficulty);

  final String id;
  String promptCn;
  String targetEn;
  int _difficulty;
  ItemStatus status;
  DateTime? dueAt;
  String? lastErrorTag;
  String? lastSubmission;
  String? correctedEn;
  String? reason;

  int get difficulty => _difficulty;

  set difficulty(int value) => _difficulty = _clampDifficulty(value);

  Map<String, Object?> toJson() => {
    'id': id,
    'promptCn': promptCn,
    'targetEn': targetEn,
    'difficulty': difficulty,
    'status': itemStatusLabel(status),
    'dueAt': dueAt?.toIso8601String(),
    'lastErrorTag': lastErrorTag,
    'lastSubmission': lastSubmission,
    'correctedEn': correctedEn,
    'reason': reason,
  };

  static StudyItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final id = raw['id'];
      final promptCn = raw['promptCn'];
      final targetEn = raw['targetEn'];
      if (id is! String || id.isEmpty) return null;
      if (promptCn is! String || targetEn is! String) return null;
      final statusRaw = raw['status'];
      final ItemStatus status;
      if (statusRaw == null) {
        status = ItemStatus.unseen;
      } else if (statusRaw is String) {
        final parsed = parseItemStatus(statusRaw);
        if (parsed == null) return null;
        status = parsed;
      } else {
        return null;
      }
      DateTime? dueAt;
      final dueRaw = raw['dueAt'];
      if (dueRaw != null) {
        if (dueRaw is! String) return null;
        dueAt = DateTime.parse(dueRaw);
      }
      final difficultyRaw = raw['difficulty'];
      final int difficulty;
      if (difficultyRaw == null) {
        difficulty = 1;
      } else if (difficultyRaw is int) {
        difficulty = difficultyRaw;
      } else if (difficultyRaw is num) {
        difficulty = difficultyRaw.toInt();
      } else {
        return null;
      }
      return StudyItem(
        id: id,
        promptCn: promptCn,
        targetEn: targetEn,
        difficulty: difficulty,
        status: status,
        dueAt: dueAt,
        lastErrorTag: _optionalString(raw, 'lastErrorTag'),
        lastSubmission: _optionalString(raw, 'lastSubmission'),
        correctedEn: _optionalString(raw, 'correctedEn'),
        reason: _optionalString(raw, 'reason'),
      );
    } on Object {
      return null;
    }
  }
}

class StudyAttempt {
  StudyAttempt({
    required this.id,
    required this.at,
    required this.classId,
    required this.itemId,
    required this.submission,
    required this.optionId,
    required this.pass,
    required this.errorTag,
    required this.correctedEn,
    required this.revealed,
  });

  final String id;
  final DateTime at;
  final String? classId;
  final String itemId;
  final String submission;
  final String? optionId;
  final bool pass;
  final String errorTag;
  final String correctedEn;
  final bool revealed;

  Map<String, Object?> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'classId': classId,
    'itemId': itemId,
    'submission': submission,
    'optionId': optionId,
    'pass': pass,
    'errorTag': errorTag,
    'correctedEn': correctedEn,
    'revealed': revealed,
  };

  static StudyAttempt? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final id = raw['id'];
      final atRaw = raw['at'];
      final itemId = raw['itemId'];
      final submission = raw['submission'];
      final pass = raw['pass'];
      final errorTag = raw['errorTag'];
      final correctedEn = raw['correctedEn'];
      final revealed = raw['revealed'];
      if (id is! String || id.isEmpty) return null;
      if (atRaw is! String) return null;
      if (itemId is! String || itemId.isEmpty) return null;
      if (submission is! String) return null;
      if (pass is! bool || revealed is! bool) return null;
      if (errorTag is! String || correctedEn is! String) return null;
      final classId = raw['classId'];
      final optionId = raw['optionId'];
      if (classId != null && classId is! String) return null;
      if (optionId != null && optionId is! String) return null;
      final classText = classId is String && classId.isNotEmpty
          ? classId
          : null;
      final optionText = optionId is String && optionId.isNotEmpty
          ? optionId
          : null;
      return StudyAttempt(
        id: id,
        at: DateTime.parse(atRaw),
        classId: classText,
        itemId: itemId,
        submission: submission,
        optionId: optionText,
        pass: pass,
        errorTag: errorTag,
        correctedEn: correctedEn,
        revealed: revealed,
      );
    } on Object {
      return null;
    }
  }
}

class LearnerFacts {
  String name = '';
  String job = '';
  String goal = '';
  String? currentItemId;

  Map<String, Object?> toJson() => {
    'name': name,
    'job': job,
    'goal': goal,
    'currentItemId': currentItemId,
  };

  void loadJson(Map json) {
    final nameRaw = json['name'];
    final jobRaw = json['job'];
    final goalRaw = json['goal'];
    final currentRaw = json['currentItemId'];
    if (nameRaw is String) name = nameRaw;
    if (jobRaw is String) job = jobRaw;
    if (goalRaw is String) goal = goalRaw;
    if (currentRaw is String) {
      currentItemId = currentRaw.isEmpty ? null : currentRaw;
    } else if (json.containsKey('currentItemId') && currentRaw == null) {
      currentItemId = null;
    }
  }
}

typedef IdFactory = String Function();

class Gradebook {
  Gradebook({DateTime Function()? clock, IdFactory? ids})
    : clock = clock ?? DateTime.now,
      items = <StudyItem>[],
      attempts = <StudyAttempt>[],
      facts = LearnerFacts() {
    _ids = ids ?? _generatedId;
  }

  final DateTime Function() clock;
  final List<StudyItem> items;
  final List<StudyAttempt> attempts;
  final LearnerFacts facts;

  late final IdFactory _ids;
  int _seq = 0;

  String _generatedId() {
    _seq += 1;
    return 'g${clock().microsecondsSinceEpoch}$_seq';
  }

  StudyItem? findItem(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// 新建题，状态没练过，difficulty 夹到 1..5，并设为 currentItemId。
  StudyItem addItem({
    required String promptCn,
    required String targetEn,
    required int difficulty,
    String? reason,
  }) {
    final item = StudyItem(
      id: _ids(),
      promptCn: promptCn,
      targetEn: targetEn,
      difficulty: difficulty,
      reason: reason,
    );
    items.add(item);
    facts.currentItemId = item.id;
    return item;
  }

  /// 成功返回 null。没有这道题、状态无法识别、或标成「会用」但没有
  /// pass 且 revealed==false 的作答时，返回一句中文错误，且不修改。
  String? setPlan({
    required String itemId,
    String? statusLabel,
    DateTime? dueAt,
  }) {
    final item = findItem(itemId);
    if (item == null) return '没有这道题';
    ItemStatus? next;
    if (statusLabel != null) {
      next = parseItemStatus(statusLabel);
      if (next == null) return '状态无法识别';
      if (next == ItemStatus.canUse && !hasHiddenPass(itemId)) {
        return '还没有隐藏通过，不能标成会用';
      }
    }
    if (next != null) item.status = next;
    if (dueAt != null) item.dueAt = dueAt;
    return null;
  }

  /// 学生原文由调用方传入。成功后更新 lastSubmission、lastErrorTag、correctedEn。
  /// pass 且 !revealed 记为隐藏通过。题目不存在时返回中文错误，且不写入。
  String? recordAttempt({
    required String itemId,
    required String submission,
    String? optionId,
    required bool pass,
    required String errorTag,
    required String correctedEn,
    required bool revealed,
    String? classId,
    DateTime? at,
  }) {
    final item = findItem(itemId);
    if (item == null) return '没有这道题';
    final storedTag = _storedErrorTag(errorTag);
    final attempt = StudyAttempt(
      id: _ids(),
      at: at ?? clock(),
      classId: classId,
      itemId: itemId,
      submission: submission,
      optionId: optionId,
      pass: pass,
      errorTag: storedTag,
      correctedEn: correctedEn,
      revealed: revealed,
    );
    attempts.add(attempt);
    item.lastSubmission = submission;
    item.lastErrorTag = storedTag.isEmpty ? null : storedTag;
    item.correctedEn = correctedEn;
    return null;
  }

  /// 只接受 name、job、goal，以及中文 名字、工作、目标。其它 key 不写。
  String? noteFact(String key, String value) {
    switch (key.trim()) {
      case 'name':
      case '名字':
        facts.name = value;
        return null;
      case 'job':
      case '工作':
        facts.job = value;
        return null;
      case 'goal':
      case '目标':
        facts.goal = value;
        return null;
      default:
        return '只能记下名字、工作或目标';
    }
  }

  List<StudyItem> dueItems(DateTime now) {
    return [
      for (final item in items)
        if (item.dueAt != null &&
            !item.dueAt!.isAfter(now) &&
            item.status != ItemStatus.canUse)
          item,
    ];
  }

  /// 最新的在前。
  List<StudyAttempt> recentAttempts(int limit) {
    if (limit <= 0 || attempts.isEmpty) return <StudyAttempt>[];
    final ranked = attempts.asMap().entries.toList();
    ranked.sort((a, b) {
      final byTime = b.value.at.compareTo(a.value.at);
      if (byTime != 0) return byTime;
      return b.key.compareTo(a.key);
    });
    final count = limit < ranked.length ? limit : ranked.length;
    return [for (var i = 0; i < count; i++) ranked[i].value];
  }

  /// 全部作答的 errorTag 计数。空标签跳过，「其它」也计。
  Map<String, int> errorPatterns() {
    final counts = <String, int>{};
    for (final attempt in attempts) {
      final tag = attempt.errorTag.trim();
      if (tag.isEmpty) continue;
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
    return counts;
  }

  bool hasHiddenPass(String itemId) {
    for (final attempt in attempts) {
      if (attempt.itemId == itemId && attempt.pass && !attempt.revealed) {
        return true;
      }
    }
    return false;
  }

  /// 恰好三行：最近练了什么；最近一次对错；下一到期。空的写「无」。
  String closeNote() {
    final latest = _latestAttempt();
    var practiced = '无';
    if (latest != null) {
      final item = findItem(latest.itemId);
      if (item != null) {
        practiced = _itemLabel(item);
      } else {
        final submission = _oneLine(latest.submission);
        practiced = submission.isEmpty ? '无' : submission;
      }
    }
    var verdict = '无';
    if (latest != null) {
      if (latest.pass) {
        verdict = '对';
      } else if (latest.errorTag.trim().isEmpty) {
        verdict = '错';
      } else {
        verdict = '错（${_oneLine(latest.errorTag)}）';
      }
    }
    var nextDue = '无';
    final soonest = _nextDue();
    if (soonest != null) {
      final label = _itemLabel(soonest);
      final when = soonest.dueAt!.toIso8601String();
      nextDue = label == '无' ? when : '$when $label';
    }
    return '最近练了：$practiced\n最近一次：$verdict\n下一到期：$nextDue';
  }

  Map<String, Object?> toJson() => {
    'items': [for (final item in items) item.toJson()],
    'attempts': [for (final attempt in attempts) attempt.toJson()],
    'facts': facts.toJson(),
  };

  /// 坏数据就清空，不抛。
  void loadJson(Object? raw) {
    if (raw is! Map) {
      _clear();
      return;
    }
    try {
      final nextFacts = LearnerFacts();
      final nextItems = <StudyItem>[];
      final nextAttempts = <StudyAttempt>[];
      final factsRaw = raw['facts'];
      if (factsRaw != null) {
        if (factsRaw is! Map) throw const FormatException('facts');
        _readFactsStrict(factsRaw);
        nextFacts.loadJson(factsRaw);
      }
      final itemRaw = raw['items'];
      if (itemRaw != null) {
        if (itemRaw is! List) throw const FormatException('items');
        for (final entry in itemRaw) {
          final item = StudyItem.fromJson(entry);
          if (item == null) throw const FormatException('item');
          nextItems.add(item);
        }
      }
      final attemptRaw = raw['attempts'];
      if (attemptRaw != null) {
        if (attemptRaw is! List) throw const FormatException('attempts');
        for (final entry in attemptRaw) {
          final attempt = StudyAttempt.fromJson(entry);
          if (attempt == null) throw const FormatException('attempt');
          nextAttempts.add(attempt);
        }
      }
      _clear();
      facts.name = nextFacts.name;
      facts.job = nextFacts.job;
      facts.goal = nextFacts.goal;
      facts.currentItemId = nextFacts.currentItemId;
      items.addAll(nextItems);
      attempts.addAll(nextAttempts);
    } on Object {
      _clear();
    }
  }

  StudyAttempt? _latestAttempt() {
    final ranked = recentAttempts(1);
    if (ranked.isEmpty) return null;
    return ranked.first;
  }

  StudyItem? _nextDue() {
    StudyItem? soonest;
    for (final item in items) {
      final due = item.dueAt;
      if (due == null || item.status == ItemStatus.canUse) continue;
      if (soonest == null || due.isBefore(soonest.dueAt!)) soonest = item;
    }
    return soonest;
  }

  void _clear() {
    items.clear();
    attempts.clear();
    facts.name = '';
    facts.job = '';
    facts.goal = '';
    facts.currentItemId = null;
  }
}

String _itemLabel(StudyItem item) {
  final prompt = _oneLine(item.promptCn);
  if (prompt.isNotEmpty) return prompt;
  final target = _oneLine(item.targetEn);
  if (target.isNotEmpty) return target;
  return '无';
}

/// 空标签留空，便于计数时跳过。表外的非空值记成其它。
String _storedErrorTag(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  return normalizeErrorTag(text);
}

String? _optionalString(Map raw, String key) {
  if (!raw.containsKey(key) || raw[key] == null) return null;
  final value = raw[key];
  if (value is! String) throw FormatException(key);
  return value;
}

void _readFactsStrict(Map raw) {
  for (final key in ['name', 'job', 'goal']) {
    final value = raw[key];
    if (value != null && value is! String) throw FormatException(key);
  }
  final current = raw['currentItemId'];
  if (current != null && current is! String) {
    throw const FormatException('currentItemId');
  }
}

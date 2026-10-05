import 'dart:convert';

import '../data/cefr_core.dart';
import '../reading/left_word.dart';
import 'gradebook.dart';
import 'lesson_store.dart';

class CardOption {
  final String id;
  final String text;

  const CardOption({required this.id, required this.text});
}

enum CardKind { choice, judge, blank }

class AnswerCard {
  final String id;
  final CardKind kind;
  final String prompt;
  final List<CardOption> options;
  final String? placeholder;

  const AnswerCard({
    required this.id,
    required this.kind,
    required this.prompt,
    required this.options,
    this.placeholder,
  });
}

/// What the student submits by tapping 「不会」. Not an option on the card.
const cardUnknownText = '这题我不会';

class PendingSubmission {
  PendingSubmission({
    required this.text,
    this.optionId,
    this.answerHidden = false,
    this.answerShown = false,
  });

  final String text;
  final String? optionId;

  /// The English being practiced was hidden when the student submitted.
  final bool answerHidden;

  /// The student tapped 「不会」, so this attempt cannot count as unseen.
  final bool answerShown;
  bool consumed = false;
}

/// Product level and the goal chosen on the settings screen.
class LearnerSettings {
  const LearnerSettings({this.level = '入门', this.goal = '职场'});

  final String level;
  final String goal;
}

/// Capped read of the on-device wordbook. The teacher loop does not write.
typedef WordLookup = Future<List<CefrWord>> Function({
  required String query,
  required String band,
  required int limit,
});

/// Words the learner kept while reading. Read-only for the teacher.
typedef LeftWordLookup = Future<List<LeftWord>> Function({int limit});

class ToolOutcome {
  final String content;
  final bool ok;
  final AnswerCard? card;
  final bool endClass;

  const ToolOutcome({
    required this.content,
    required this.ok,
    this.card,
    this.endClass = false,
  });
}

const List<Map<String, Object?>> agentToolSchemas = [
  {
    'type': 'function',
    'function': {
      'name': 'get_learner',
      'description': '读取学生的名字、工作、自由目标、当前句子，以及「我的」里已选的水平和目标。',
      'parameters': {
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'lookup_words',
      'description':
          '在词库里查几条词作参考。默认只查学生当前水平。不写成绩，也不限制能教的句子。释义可能不准。',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '要查的英文或中文。'},
          'band': {
            'type': 'string',
            'description': 'a1、a2、b1，或入门、基础、进阶。不传则用学生当前水平。',
          },
          'limit': {'type': 'integer', 'description': '最多 8 条。'},
        },
        'required': ['query'],
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'get_due_items',
      'description': '读取到期时间不晚于现在、并且还不是「会用」的句子。',
      'parameters': {
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'get_recent_attempts',
      'description': '读取最近的作答。每条包含学生原文或选项、对错、错误类型、当时答案是否可见，以及难度。',
      'parameters': {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'description': '返回条数，默认 10，最多 20。'},
        },
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'get_error_patterns',
      'description': '统计作答里各错误类型的次数。',
      'parameters': {
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'add_item',
      'description': '记下你决定的下一句。需要中文提示和目标英文，难度 1 到 5，可选一句为什么出这题。',
      'parameters': {
        'type': 'object',
        'properties': {
          'prompt_cn': {'type': 'string', 'description': '给学生看的中文提示。'},
          'target_en': {'type': 'string', 'description': '目标英文。'},
          'difficulty': {'type': 'integer', 'description': '难度 1 到 5，缺省为 1。'},
          'reason': {'type': 'string', 'description': '为什么出这题。'},
        },
        'required': ['prompt_cn', 'target_en'],
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'set_plan',
      'description': '修改某句的状态或到期时间。状态只能是没练过、不稳、会用。标成会用之前，必须已有一次答案未显示且判为通过的作答。',
      'parameters': {
        'type': 'object',
        'properties': {
          'item_id': {'type': 'string', 'description': '句子 id。'},
          'status': {'type': 'string', 'description': '没练过、不稳或会用。不传则不改状态。'},
          'due_at': {
            'type': 'string',
            'description': 'ISO8601 到期时间。不传则不改到期时间。',
          },
        },
        'required': ['item_id'],
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'record_attempt',
      'description': '对刚刚确认的那一次作答下判断。学生原文和选项由程序填写，不要在参数里改写。',
      'parameters': {
        'type': 'object',
        'properties': {
          'item_id': {'type': 'string', 'description': '句子 id。'},
          'pass': {'type': 'boolean', 'description': '这次是否通过。'},
          'error_tag': {
            'type': 'string',
            'description': '缺冠词、语序、时态、拼写、用错词、漏主语、夹了中文、其它。不在表内记成其它。没有错误可以留空。',
          },
          'corrected_en': {'type': 'string', 'description': '改对后的英文。'},
          'revealed': {'type': 'boolean', 'description': '作答时答案是否已经显示在屏幕上。'},
        },
        'required': ['item_id', 'pass', 'corrected_en', 'revealed'],
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'note_fact',
      'description': '记下学生明确说过的名字、工作或目标。',
      'parameters': {
        'type': 'object',
        'properties': {
          'key': {
            'type': 'string',
            'description': 'name、job、goal，或中文名字、工作、目标。',
          },
          'value': {'type': 'string', 'description': '学生说的内容。'},
        },
        'required': ['key', 'value'],
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'get_left_words',
      'description':
          '读取学生在读书时留下的词。只是事实，不写成绩，也不排进今天的课。',
      'parameters': {
        'type': 'object',
        'properties': {
          'limit': {'type': 'integer', 'description': '返回条数，最多 20。'},
        },
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'end_class',
      'description': '结束这一节。三行收课条由程序按成绩册生成，不采用模型改写后的成绩。',
      'parameters': {
        'type': 'object',
        'properties': {
          'close_note': {
            'type': 'string',
            'description': '可选。程序仍以成绩册生成的三行收课条为准。',
          },
        },
        'additionalProperties': false,
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'present_card',
      'description':
          '出示一张卡片并暂停，等学生确认。choice 要 2 到 4 个选项，judge 恰好 2 个，blank 是填空。不要提供正确答案，也不要带 answer、correct 这类字段。',
      'parameters': {
        'type': 'object',
        'properties': {
          'id': {'type': 'string', 'description': '可选的卡片 id。'},
          'kind': {
            'type': 'string',
            'enum': ['choice', 'judge', 'blank'],
            'description': 'choice、judge 或 blank。',
          },
          'prompt': {'type': 'string', 'description': '题面。'},
          'options': {
            'type': 'array',
            'description': '选择题和判断题的选项。每项有 id 和 text。',
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'string'},
                'text': {'type': 'string'},
              },
              'required': ['id', 'text'],
            },
          },
          'placeholder': {'type': 'string', 'description': '填空的占位文字，可省略。'},
        },
        'required': ['kind', 'prompt'],
        'additionalProperties': false,
      },
    },
  },
];

ToolOutcome runTool({
  required String name,
  required Map<String, Object?> args,
  required Gradebook book,
  required PendingSubmission? pending,
  required bool cardPending,
  String? classId,
  DateTime? now,
  LearnerSettings settings = const LearnerSettings(),
}) {
  switch (name) {
    case 'get_learner':
      return _getLearner(book, settings);
    case 'lookup_words':
      return _fail('查词需要词库');
    case 'get_due_items':
      return _getDueItems(book, now ?? book.clock());
    case 'get_recent_attempts':
      return _getRecentAttempts(book, args);
    case 'get_error_patterns':
      return _ok({'counts': book.errorPatterns()});
    case 'add_item':
      return _addItem(book, args);
    case 'set_plan':
      return _setPlan(book, args);
    case 'record_attempt':
      return _recordAttempt(
        book: book,
        args: args,
        pending: pending,
        classId: classId,
        now: now,
      );
    case 'note_fact':
      return _noteFact(book, args);
    case 'get_left_words':
      return _fail('留下的词还没准备好');
    case 'end_class':
      return _endClass(book, args);
    case 'present_card':
      return _presentCard(
        args,
        cardPending: cardPending,
        now: now ?? book.clock(),
      );
    default:
      return _fail('未知工具');
  }
}

/// Same entry as [runTool], and the only path that can read the wordbook.
Future<ToolOutcome> runToolCall({
  required String name,
  required Map<String, Object?> args,
  required Gradebook book,
  required PendingSubmission? pending,
  required bool cardPending,
  String? classId,
  DateTime? now,
  LearnerSettings settings = const LearnerSettings(),
  WordLookup? lookupWords,
  LeftWordLookup? leftWords,
}) async {
  if (name == 'lookup_words') {
    return _lookupWords(args, settings: settings, lookupWords: lookupWords);
  }
  if (name == 'get_left_words') {
    return _readLeftWords(args, leftWords);
  }
  return runTool(
    name: name,
    args: args,
    book: book,
    pending: pending,
    cardPending: cardPending,
    classId: classId,
    now: now,
    settings: settings,
  );
}

ToolOutcome _fail(String error) {
  return ToolOutcome(
    content: jsonEncode({'ok': false, 'error': error}),
    ok: false,
  );
}

ToolOutcome _ok(
  Map<String, Object?> payload, {
  AnswerCard? card,
  bool endClass = false,
}) {
  return ToolOutcome(
    content: jsonEncode(<String, Object?>{'ok': true, ...payload}),
    ok: true,
    card: card,
    endClass: endClass,
  );
}

ToolOutcome _getLearner(Gradebook book, LearnerSettings settings) {
  final currentId = book.facts.currentItemId;
  final current = currentId == null ? null : book.findItem(currentId);
  final level = normalizeLevel(settings.level);
  const goals = {'职场', '日常', '考试', '都要'};
  final settingsGoal = goals.contains(settings.goal) ? settings.goal : '职场';
  return _ok({
    'name': book.facts.name,
    'job': book.facts.job,
    'goal': book.facts.goal,
    'level': level,
    'settings_goal': settingsGoal,
    'band': cefrCodeForLevel(level),
    'current_item': current == null ? null : _itemJson(current),
  });
}

Future<ToolOutcome> _lookupWords(
  Map<String, Object?> args, {
  required LearnerSettings settings,
  required WordLookup? lookupWords,
}) async {
  final lookup = lookupWords;
  if (lookup == null) return _fail('词库还没准备好');
  final query = args['query'];
  if (query is! String) return _fail('缺少要查的词');
  final text = query.trim();
  if (text.isEmpty) return _ok({'words': <Object?>[]});
  final band = _lookupBand(args['band'], settings);
  var limit = cefrLookupCap;
  final rawLimit = args['limit'];
  if (rawLimit is int) {
    limit = rawLimit;
  } else if (rawLimit is num) {
    limit = rawLimit.toInt();
  }
  if (limit < 1) limit = 1;
  if (limit > cefrLookupCap) limit = cefrLookupCap;
  try {
    final words = await lookup(query: text, band: band, limit: limit);
    final capped = words.length > cefrLookupCap
        ? words.sublist(0, cefrLookupCap)
        : words;
    return _ok({
      'words': [
        for (final word in capped)
          {
            'en': word.en,
            'cn': word.cn,
            'pos': word.pos,
            'level': word.level,
          },
      ],
    });
  } on Object {
    return _fail('查词失败');
  }
}

Future<ToolOutcome> _readLeftWords(
  Map<String, Object?> args,
  LeftWordLookup? leftWords,
) async {
  final lookup = leftWords;
  if (lookup == null) return _ok({'words': <Object?>[]});
  var limit = 20;
  final rawLimit = args['limit'];
  if (rawLimit is int) {
    limit = rawLimit;
  } else if (rawLimit is num) {
    limit = rawLimit.toInt();
  }
  if (limit < 0) limit = 0;
  if (limit > 20) limit = 20;
  try {
    final words = await lookup(limit: limit);
    final capped = words.length > 20 ? words.sublist(0, 20) : words;
    return _ok({
      'words': [
        for (final word in capped)
          {
            'word': word.word,
            'sentence': word.sentence,
            'gloss_cn': word.glossCn,
            'at': word.at,
          },
      ],
    });
  } on Object {
    return _fail('读留下的词失败');
  }
}

String _lookupBand(Object? raw, LearnerSettings settings) {
  if (raw is! String || raw.trim().isEmpty) {
    return cefrCodeForLevel(settings.level);
  }
  final text = raw.trim().toLowerCase();
  if (text == 'a1' || text == 'a2' || text == 'b1') return text;
  return cefrCodeForLevel(raw.trim());
}

ToolOutcome _getDueItems(Gradebook book, DateTime at) {
  return _ok({
    'items': [for (final item in book.dueItems(at)) _itemJson(item)],
  });
}

ToolOutcome _getRecentAttempts(Gradebook book, Map<String, Object?> args) {
  return _ok({
    'attempts': [
      for (final attempt in book.recentAttempts(_attemptLimit(args['limit'])))
        _attemptJson(book, attempt),
    ],
  });
}

int _attemptLimit(Object? raw) {
  var limit = 10;
  if (raw is int) {
    limit = raw;
  } else if (raw is num) {
    limit = raw.toInt();
  }
  if (limit > 20) return 20;
  if (limit < 0) return 0;
  return limit;
}

ToolOutcome _addItem(Gradebook book, Map<String, Object?> args) {
  final prompt = _nonEmpty(args['prompt_cn']);
  final target = _nonEmpty(args['target_en']);
  if (prompt == null) return _fail('缺少中文提示');
  if (target == null) return _fail('缺少目标英文');
  var difficulty = 1;
  if (args.containsKey('difficulty') && args['difficulty'] != null) {
    final raw = args['difficulty'];
    if (raw is! int) return _fail('难度不是整数');
    difficulty = raw;
  }
  String? reason;
  if (args.containsKey('reason') && args['reason'] != null) {
    final raw = args['reason'];
    if (raw is! String) return _fail('出题理由格式不对');
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty) reason = trimmed;
  }
  final item = book.addItem(
    promptCn: prompt,
    targetEn: target,
    difficulty: difficulty,
    reason: reason,
  );
  return _ok({'item_id': item.id, 'item': _itemJson(item)});
}

ToolOutcome _setPlan(Gradebook book, Map<String, Object?> args) {
  final itemId = _nonEmpty(args['item_id']);
  if (itemId == null) return _fail('缺少题目');
  String? status;
  if (args.containsKey('status') && args['status'] != null) {
    final raw = args['status'];
    if (raw is! String) return _fail('状态无法识别');
    status = raw;
  }
  DateTime? dueAt;
  if (args.containsKey('due_at') && args['due_at'] != null) {
    final raw = args['due_at'];
    if (raw is! String || raw.trim().isEmpty) return _fail('到期时间无法识别');
    try {
      dueAt = DateTime.parse(raw.trim());
    } on FormatException {
      return _fail('到期时间无法识别');
    }
  }
  final error = book.setPlan(itemId: itemId, statusLabel: status, dueAt: dueAt);
  if (error != null) return _fail(error);
  final item = book.findItem(itemId);
  return _ok({
    'item_id': itemId,
    'item': item == null ? null : _itemJson(item),
  });
}

ToolOutcome _recordAttempt({
  required Gradebook book,
  required Map<String, Object?> args,
  required PendingSubmission? pending,
  required String? classId,
  required DateTime? now,
}) {
  if (pending == null) return _fail('没有待记录的作答');
  if (pending.consumed) return _fail('这句作答已经记过');
  final itemId = _nonEmpty(args['item_id']);
  if (itemId == null) return _fail('缺少题目');
  final pass = args['pass'];
  if (pass is! bool) return _fail('缺少对错');
  final revealedArg = args['revealed'];
  if (revealedArg is! bool) return _fail('缺少答案是否可见');
  // 「不会」算答案已经显示。遮住英文后再交，答案算没显示。其余沿用模型给出的 revealed。
  final bool revealed;
  if (pending.answerShown) {
    revealed = true;
  } else if (pending.answerHidden) {
    revealed = false;
  } else {
    revealed = revealedArg;
  }
  final corrected = args['corrected_en'];
  if (corrected is! String) return _fail('缺少改对的英文');
  var errorTag = '';
  if (args.containsKey('error_tag') && args['error_tag'] != null) {
    final raw = args['error_tag'];
    if (raw is! String) return _fail('错误类型格式不对');
    errorTag = raw;
  }
  // 学生原文只来自 pending，忽略参数里的 submission / option_id。
  final error = book.recordAttempt(
    itemId: itemId,
    submission: pending.text,
    optionId: pending.optionId,
    pass: pass,
    errorTag: errorTag,
    correctedEn: corrected,
    revealed: revealed,
    classId: classId,
    at: now,
  );
  if (error != null) return _fail(error);
  pending.consumed = true;
  final attempt = book.attempts.last;
  return _ok({
    'attempt_id': attempt.id,
    'item_id': attempt.itemId,
    'submission': attempt.submission,
    'option_id': attempt.optionId,
    'pass': attempt.pass,
    'error_tag': attempt.errorTag,
    'corrected_en': attempt.correctedEn,
    'revealed': attempt.revealed,
  });
}

ToolOutcome _noteFact(Gradebook book, Map<String, Object?> args) {
  final key = args['key'];
  if (key is! String || key.trim().isEmpty) return _fail('缺少要记的项目');
  final value = args['value'];
  if (value is! String) return _fail('缺少内容');
  final error = book.noteFact(key, value);
  if (error != null) return _fail(error);
  return _ok({'key': key.trim(), 'value': value});
}

ToolOutcome _endClass(Gradebook book, Map<String, Object?> args) {
  final payload = <String, Object?>{'close_note': book.closeNote()};
  final requested = args['close_note'];
  if (requested is String) payload['model_close_note'] = requested;
  return _ok(payload, endClass: true);
}

ToolOutcome _presentCard(
  Map<String, Object?> args, {
  required bool cardPending,
  required DateTime now,
}) {
  if (cardPending) return _fail('已经有一张卡片在等确认');
  final marked = _answerKey(args);
  if (marked != null) return _fail(marked);
  final prompt = _nonEmpty(args['prompt']);
  if (prompt == null) return _fail('题面不能为空');
  final kind = _cardKind(args['kind']);
  if (kind == null) return _fail('题型无法识别');
  final options = <CardOption>[];
  if (kind == CardKind.blank) {
    final rawOptions = args['options'];
    if (rawOptions is List && rawOptions.isNotEmpty) return _fail('填空不要选项');
  } else {
    if (args['options'] != null) {
      final error = _fillOptions(args['options'], options);
      if (error != null) return _fail(error);
    }
    if (kind == CardKind.choice && (options.length < 2 || options.length > 4)) {
      return _fail('选择题需要 2 到 4 个选项');
    }
    if (kind == CardKind.judge && options.length != 2) {
      return _fail('判断题需要恰好 2 个选项');
    }
  }
  String? placeholder;
  final placeholderRaw = args['placeholder'];
  if (kind == CardKind.blank && placeholderRaw is String) {
    placeholder = placeholderRaw;
  }
  final requestedId = args['id'];
  final id = requestedId is String && requestedId.trim().isNotEmpty
      ? requestedId.trim()
      : 'card${now.microsecondsSinceEpoch}';
  return _ok(
    {'waiting': true},
    card: AnswerCard(
      id: id,
      kind: kind,
      prompt: prompt,
      options: List<CardOption>.unmodifiable(options),
      placeholder: placeholder,
    ),
  );
}

CardKind? _cardKind(Object? raw) {
  if (raw is! String) return null;
  switch (raw.trim()) {
    case 'choice':
      return CardKind.choice;
    case 'judge':
      return CardKind.judge;
    case 'blank':
      return CardKind.blank;
    default:
      return null;
  }
}

const _answerKeys = <String>{'answer', 'correct', 'is_correct', 'answer_id'};

String? _answerKey(Map raw) {
  for (final key in raw.keys) {
    if (_answerKeys.contains('$key')) return '卡片里不能带正确答案';
  }
  return null;
}

String? _fillOptions(Object? raw, List<CardOption> into) {
  if (raw is! List) return '选项格式不对';
  final seen = <String>{};
  for (final entry in raw) {
    if (entry is! Map) return '选项格式不对';
    final marked = _answerKey(entry);
    if (marked != null) return marked;
    final id = entry['id'];
    final text = entry['text'];
    if (id is! String ||
        id.trim().isEmpty ||
        text is! String ||
        text.trim().isEmpty) {
      return '选项缺少 id 或文字';
    }
    final trimmed = id.trim();
    if (!seen.add(trimmed)) return '选项 id 重复';
    into.add(CardOption(id: trimmed, text: text.trim()));
  }
  return null;
}

String? _nonEmpty(Object? raw) {
  if (raw is! String) return null;
  final text = raw.trim();
  if (text.isEmpty) return null;
  return text;
}

Map<String, Object?> _itemJson(StudyItem item) {
  return {
    'id': item.id,
    'prompt_cn': item.promptCn,
    'target_en': item.targetEn,
    'difficulty': item.difficulty,
    'status': itemStatusLabel(item.status),
    'due_at': item.dueAt?.toIso8601String(),
    'last_error_tag': item.lastErrorTag,
    'reason': item.reason,
  };
}

Map<String, Object?> _attemptJson(Gradebook book, StudyAttempt attempt) {
  final item = book.findItem(attempt.itemId);
  return {
    'id': attempt.id,
    'at': attempt.at.toIso8601String(),
    'class_id': attempt.classId,
    'item_id': attempt.itemId,
    'submission': attempt.submission,
    'option_id': attempt.optionId,
    'pass': attempt.pass,
    'error_tag': attempt.errorTag,
    'corrected_en': attempt.correctedEn,
    'revealed': attempt.revealed,
    'difficulty': item?.difficulty,
  };
}

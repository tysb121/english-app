import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import '../data/cefr_core.dart';
import '../engine/chat_context.dart';
import '../engine/chat_message.dart';
import '../engine/class_session.dart';
import '../engine/gradebook.dart';
import '../reading/book_text.dart';
import '../reading/left_word.dart';
import '../reading/reader_book.dart';
import 'local_progress.dart';
import 'progress_shell.dart';

const coachDbFileName = 'english_coach.db';
const coachSchemaVersion = 4;

const _learnerNameKey = 'learner_name';
const _learnerJobKey = 'learner_job';
const _learnerGoalKey = 'learner_goal';
const _learnerCurrentItemKey = 'learner_current_item';

bool _factoryReady = false;

/// Desktop / test: FFI SQLite. Android / iOS: sqflite plugin default factory.
void ensureCoachDbFactory() {
  if (_factoryReady) return;
  if (!Platform.isAndroid && !Platform.isIOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  _factoryReady = true;
}

class CoachDatabase {
  CoachDatabase(this.db);

  final Database db;

  static Future<String> defaultPath() async {
    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } on Object {
      final home = Platform.environment['HOME'] ?? '/tmp';
      dir = Directory('$home/.local/share/english_app');
    }
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return p.join(dir.path, coachDbFileName);
  }

  static Future<CoachDatabase> open({
    String? path,
    List<CefrWord>? seedBook,
  }) async {
    ensureCoachDbFactory();
    final dbPath = path ?? await defaultPath();
    final database = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: coachSchemaVersion,
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _ensureWordbookIndexes(db);
          }
          if (oldVersion < 3) {
            await _createStudyTables(db);
          }
          if (oldVersion < 4) {
            await _createReaderTables(db);
          }
          // Schema 2 fixtures and any pre-meta file have no meta table.
          // Fresh installs create it in onCreate; upgrades must too.
          await _ensureMeta(db);
          await db.insert('meta', {
            'key': 'schema',
            'value': '$newVersion',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        },
      ),
    );
    final coach = CoachDatabase(database);
    if (seedBook != null && seedBook.isNotEmpty) {
      await coach.ensureWordbook(seedBook);
    }
    return coach;
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
CREATE TABLE meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE wordbook (
  id TEXT PRIMARY KEY NOT NULL,
  en TEXT NOT NULL,
  cn TEXT NOT NULL,
  pos TEXT NOT NULL,
  level TEXT NOT NULL,
  book_id TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE user_words (
  id TEXT PRIMARY KEY NOT NULL,
  en TEXT NOT NULL,
  cn TEXT NOT NULL,
  pos TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE settings (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE day_plan (
  date TEXT PRIMARY KEY NOT NULL,
  payload TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE attempts (
  day TEXT NOT NULL,
  seq INTEGER NOT NULL,
  word_id TEXT NOT NULL,
  answer TEXT NOT NULL,
  correct INTEGER NOT NULL,
  PRIMARY KEY (day, seq)
)''');
    await db.execute('''
CREATE TABLE error_log (
  word_id TEXT PRIMARY KEY NOT NULL,
  wrong_answer TEXT NOT NULL,
  correct_answer TEXT NOT NULL,
  round INTEGER NOT NULL,
  next_review TEXT NOT NULL,
  resolved INTEGER NOT NULL
)''');
    await db.execute('''
CREATE TABLE word_progress (
  word_id TEXT PRIMARY KEY NOT NULL,
  introduced_on TEXT,
  stage INTEGER NOT NULL,
  next_review TEXT
)''');
    await db.execute('''
CREATE TABLE call_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task TEXT NOT NULL,
  ok INTEGER NOT NULL,
  finish_reason TEXT,
  tokens INTEGER
)''');
    await db.execute('''
CREATE TABLE chat_messages (
  id TEXT PRIMARY KEY NOT NULL,
  seq INTEGER NOT NULL,
  payload TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE chat_checkpoints (
  id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1),
  payload TEXT NOT NULL
)''');
    await db.insert('meta', {'key': 'schema', 'value': '$coachSchemaVersion'});
    await _ensureWordbookIndexes(db);
    await _createStudyTables(db);
    await _createReaderTables(db);
  }

  static Future<void> _ensureMeta(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
)''');
  }

  static Future<void> _ensureWordbookIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_wordbook_level ON wordbook(level)',
    );
  }

  static Future<void> _createStudyTables(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS study_items (
  id TEXT PRIMARY KEY NOT NULL,
  prompt_cn TEXT NOT NULL,
  target_en TEXT NOT NULL,
  difficulty INTEGER NOT NULL,
  status TEXT NOT NULL,
  due_at TEXT,
  last_error_tag TEXT,
  last_submission TEXT,
  corrected_en TEXT,
  reason TEXT
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS study_attempts (
  id TEXT PRIMARY KEY NOT NULL,
  at TEXT NOT NULL,
  class_id TEXT,
  item_id TEXT NOT NULL,
  submission TEXT NOT NULL,
  option_id TEXT,
  pass INTEGER NOT NULL,
  error_tag TEXT NOT NULL,
  corrected_en TEXT NOT NULL,
  revealed INTEGER NOT NULL
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS study_classes (
  id TEXT PRIMARY KEY NOT NULL,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  close_note TEXT NOT NULL,
  user_turns INTEGER NOT NULL,
  judged INTEGER NOT NULL,
  last_message_at TEXT
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS study_class_messages (
  class_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  payload TEXT NOT NULL,
  PRIMARY KEY (class_id, seq)
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS study_class_checkpoints (
  class_id TEXT PRIMARY KEY NOT NULL,
  payload TEXT NOT NULL
)''');
  }

  static Future<void> _createReaderTables(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS reader_books (
  id TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL,
  file_name TEXT NOT NULL,
  text TEXT NOT NULL,
  place INTEGER NOT NULL,
  updated_at TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS reader_glosses (
  word TEXT NOT NULL,
  sentence TEXT NOT NULL,
  gloss_cn TEXT NOT NULL,
  PRIMARY KEY (word, sentence)
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS left_words (
  id TEXT PRIMARY KEY NOT NULL,
  word TEXT NOT NULL,
  sentence TEXT NOT NULL,
  gloss_cn TEXT NOT NULL,
  created_at TEXT NOT NULL
)''');
  }

  Future<int> wordbookCount() async {
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM wordbook'),
        ) ??
        0;
  }

  Future<void> ensureWordbook(List<CefrWord> words) async {
    if (await wordbookCount() > 0) return;
    final batch = db.batch();
    for (final w in words) {
      batch.insert('wordbook', {
        'id': w.id,
        'en': w.en,
        'cn': w.cn,
        'pos': w.pos,
        'level': w.level,
        'book_id': w.bookId,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<CefrWord>> loadWordbook() async {
    final rows = await db.query('wordbook', orderBy: 'id');
    return [for (final row in rows) _rowToWord(row)];
  }

  CefrWord _rowToWord(Map<String, Object?> row) {
    return CefrWord(
      id: row['id']! as String,
      en: row['en']! as String,
      cn: row['cn']! as String,
      pos: row['pos']! as String,
      level: row['level']! as String,
      bookId: row['book_id']! as String,
    );
  }

  /// Capped read of the on-device wordbook. Writes nothing.
  /// [band] is `a1`, `a2`, or `b1`. Empty [query] returns no rows.
  Future<List<CefrWord>> lookupWords({
    required String query,
    required String band,
    required int limit,
  }) async {
    final text = query.trim();
    if (text.isEmpty || limit <= 0) return const [];
    final cap = limit > cefrLookupCap ? cefrLookupCap : limit;
    final escaped = text
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final rows = await db.rawQuery(
      '''
      SELECT id, en, cn, pos, level, book_id
      FROM wordbook
      WHERE level = ?
        AND (
          lower(en) = lower(?)
          OR lower(en) LIKE lower(?) || '%' ESCAPE '\\'
          OR cn LIKE '%' || ? || '%' ESCAPE '\\'
        )
      ORDER BY
        CASE
          WHEN lower(en) = lower(?) THEN 0
          WHEN lower(en) LIKE lower(?) || '%' ESCAPE '\\' THEN 1
          ELSE 2
        END,
        length(en),
        en
      LIMIT ?
      ''',
      [band, text, escaped, escaped, text, escaped, cap],
    );
    return [for (final row in rows) _rowToWord(row)];
  }

  /// Read the whole on-device wordbook by English or Chinese. Writes nothing.
  /// An empty query returns no rows. [limit] is capped at [cefrLookupCap].
  Future<List<CefrWord>> searchWordbook({
    required String query,
    required int limit,
  }) async {
    final text = query.trim();
    if (text.isEmpty || limit <= 0) return const [];
    final cap = limit > cefrLookupCap ? cefrLookupCap : limit;
    final escaped = text
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final rows = await db.rawQuery(
      '''
      SELECT id, en, cn, pos, level, book_id
      FROM wordbook
      WHERE lower(en) = lower(?)
        OR lower(en) LIKE lower(?) || '%' ESCAPE '\\'
        OR cn LIKE '%' || ? || '%' ESCAPE '\\'
      ORDER BY
        CASE
          WHEN lower(en) = lower(?) THEN 0
          WHEN lower(en) LIKE lower(?) || '%' ESCAPE '\\' THEN 1
          ELSE 2
        END,
        length(en),
        en
      LIMIT ?
      ''',
      [text, escaped, escaped, text, escaped, cap],
    );
    return [for (final row in rows) _rowToWord(row)];
  }

  /// Load one lemma by id (lazy Lexeme hydrate).
  Future<CefrWord?> wordById(String id) async {
    final rows = await db.query(
      'wordbook',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToWord(rows.first);
  }

  /// Batch load lemmas by id; missing ids are omitted.
  Future<List<CefrWord>> wordsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final unique = ids.toSet().toList();
    final out = <CefrWord>[];
    const chunkSize = 900;
    for (var i = 0; i < unique.length; i += chunkSize) {
      final chunk = unique.sublist(i, min(i + chunkSize, unique.length));
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT id, en, cn, pos, level, book_id FROM wordbook '
        'WHERE id IN ($placeholders)',
        chunk,
      );
      for (final row in rows) {
        out.add(_rowToWord(row));
      }
    }
    return out;
  }

  /// Random untaught book ids for [level] (a1|a2|b1), excluding [exclude].
  /// Preferred by [LessonStore.ensureTodayPlanAsync] when wired as untaughtIdPicker.
  Future<List<String>> pickUntaughtIds({
    required String level,
    required int limit,
    required Set<String> exclude,
    Random? random,
  }) async {
    if (limit <= 0) return [];
    if (exclude.isEmpty) {
      final rows = await db.rawQuery(
        'SELECT id FROM wordbook WHERE level = ? ORDER BY RANDOM() LIMIT ?',
        [level, limit],
      );
      return [for (final row in rows) row['id']! as String];
    }
    if (exclude.length <= 900) {
      final placeholders = List.filled(exclude.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT id FROM wordbook WHERE level = ? AND id NOT IN ($placeholders) '
        'ORDER BY RANDOM() LIMIT ?',
        [level, ...exclude, limit],
      );
      return [for (final row in rows) row['id']! as String];
    }
    // Large exclude: filter in Dart after a SQL level scan of ids only.
    final rows = await db.query(
      'wordbook',
      columns: ['id'],
      where: 'level = ?',
      whereArgs: [level],
    );
    final pool = [
      for (final row in rows)
        if (!exclude.contains(row['id'] as String)) row['id']! as String,
    ];
    pool.shuffle(random ?? Random());
    return pool.take(limit).toList();
  }

  /// SQL COUNT of book lemmas in [level] not listed in [exclude].
  Future<int> untaughtCount({
    required String level,
    required Set<String> exclude,
  }) async {
    if (exclude.isEmpty) {
      return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM wordbook WHERE level = ?', [
              level,
            ]),
          ) ??
          0;
    }
    if (exclude.length <= 900) {
      final placeholders = List.filled(exclude.length, '?').join(',');
      return Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM wordbook WHERE level = ? '
              'AND id NOT IN ($placeholders)',
              [level, ...exclude],
            ),
          ) ??
          0;
    }
    final total =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM wordbook WHERE level = ?', [
            level,
          ]),
        ) ??
        0;
    var taughtInLevel = 0;
    final list = exclude.toList();
    const chunkSize = 900;
    for (var i = 0; i < list.length; i += chunkSize) {
      final chunk = list.sublist(i, min(i + chunkSize, list.length));
      final placeholders = List.filled(chunk.length, '?').join(',');
      taughtInLevel +=
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM wordbook WHERE level = ? '
              'AND id IN ($placeholders)',
              [level, ...chunk],
            ),
          ) ??
          0;
    }
    final left = total - taughtInLevel;
    return left < 0 ? 0 : left;
  }

  Future<void> saveShell(ProgressShell shell) async {
    final lesson = shell.store.toJson();
    final chat = shell.chat.toJson();
    await db.transaction((txn) async {
      // Learner facts share settings with the lesson shell. Keep them.
      await txn.delete(
        'settings',
        where: 'key NOT IN (?, ?, ?, ?)',
        whereArgs: const [
          _learnerNameKey,
          _learnerJobKey,
          _learnerGoalKey,
          _learnerCurrentItemKey,
        ],
      );
      await txn.delete('user_words');
      await txn.delete('day_plan');
      await txn.delete('attempts');
      await txn.delete('error_log');
      await txn.delete('word_progress');
      await txn.delete('call_log');
      await txn.delete('chat_messages');
      await txn.delete('chat_checkpoints');

      Future<void> putSetting(String key, Object? value) async {
        if (value == null) return;
        await txn.insert('settings', {
          'key': key,
          'value': value is String ? value : jsonEncode(value),
        });
      }

      await putSetting('installId', lesson['installId']);
      await putSetting('dailyWords', lesson['dailyWords']);
      await putSetting('level', lesson['level']);
      await putSetting('levelChosen', lesson['levelChosen'] == true);
      await putSetting(
        'upgradeNudgeDismissed',
        lesson['upgradeNudgeDismissed'] == true,
      );
      await putSetting('reasoningEffort', lesson['reasoningEffort']);
      await putSetting('goal', lesson['goal']);
      await putSetting('tone', lesson['tone']);

      final users = lesson['userWords'];
      if (users is List) {
        for (final item in users) {
          if (item is! Map) continue;
          await txn.insert('user_words', {
            'id': '${item['id']}',
            'en': '${item['en']}',
            'cn': '${item['cn']}',
            'pos': '${item['pos']}',
          });
        }
      }

      final plans = lesson['plans'];
      if (plans is List) {
        for (final item in plans) {
          if (item is! Map) continue;
          final date = item['date'];
          if (date is! String) continue;
          await txn.insert('day_plan', {
            'date': date,
            'payload': jsonEncode(item),
          });
        }
      }

      final attempts = lesson['attempts'];
      if (attempts is Map) {
        for (final entry in attempts.entries) {
          final day = entry.key.toString();
          final list = entry.value;
          if (list is! List) continue;
          for (var i = 0; i < list.length; i++) {
            final item = list[i];
            if (item is! Map) continue;
            await txn.insert('attempts', {
              'day': day,
              'seq': i,
              'word_id': '${item['wordId']}',
              'answer': '${item['answer']}',
              'correct': item['correct'] == true ? 1 : 0,
            });
          }
        }
      }

      final errors = lesson['errors'];
      if (errors is Map) {
        for (final entry in errors.entries) {
          final item = entry.value;
          if (item is! Map) continue;
          await txn.insert('error_log', {
            'word_id': entry.key.toString(),
            'wrong_answer': '${item['wrongAnswer']}',
            'correct_answer': '${item['correctAnswer']}',
            'round': item['round'] is int ? item['round'] : 0,
            'next_review': '${item['nextReview']}',
            'resolved': item['resolved'] == true ? 1 : 0,
          });
        }
      }

      final reviews = lesson['reviews'];
      if (reviews is Map) {
        for (final entry in reviews.entries) {
          final item = entry.value;
          if (item is! Map) continue;
          await txn.insert('word_progress', {
            'word_id': entry.key.toString(),
            'introduced_on': item['introducedOn'],
            'stage': item['stage'] is int ? item['stage'] : 0,
            'next_review': item['nextReview'],
          });
        }
      }

      final calls = lesson['calls'];
      if (calls is List) {
        for (final item in calls) {
          if (item is! Map) continue;
          await txn.insert('call_log', {
            'task': '${item['task']}',
            'ok': item['ok'] == true ? 1 : 0,
            'finish_reason': item['finishReason']?.toString(),
            'tokens': item['tokens'] is int ? item['tokens'] : null,
          });
        }
      }

      final messages = chat['messages'];
      if (messages is List) {
        for (var i = 0; i < messages.length; i++) {
          final item = messages[i];
          if (item is! Map) continue;
          final id = item['id'];
          if (id is! String) continue;
          await txn.insert('chat_messages', {
            'id': id,
            'seq': i,
            'payload': jsonEncode(item),
          });
        }
      }
      final summary = chat['contextSummary'];
      if (summary != null) {
        await txn.insert('chat_checkpoints', {
          'id': 1,
          'payload': jsonEncode(summary),
        });
      }

      await txn.insert('meta', {
        'key': 'persisted_at',
        'value': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<bool> hasProgress() async {
    final rows = await db.query(
      'settings',
      columns: ['key'],
      where: 'key = ?',
      whereArgs: ['installId'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> loadShell(ProgressShell shell) async {
    final settingsRows = await db.query('settings');
    if (settingsRows.isEmpty) return;

    final settings = {
      for (final row in settingsRows)
        row['key']! as String: row['value']! as String,
    };

    Object? decodeSetting(String key) {
      final raw = settings[key];
      if (raw == null) return null;
      if (raw == 'true') return true;
      if (raw == 'false') return false;
      final asInt = int.tryParse(raw);
      if (asInt != null) return asInt;
      try {
        return jsonDecode(raw);
      } on Object {
        return raw;
      }
    }

    final userRows = await db.query('user_words');
    final planRows = await db.query('day_plan');
    final attemptRows = await db.query('attempts', orderBy: 'day, seq');
    final errorRows = await db.query('error_log');
    final reviewRows = await db.query('word_progress');
    final callRows = await db.query('call_log', orderBy: 'id');

    final attempts = <String, List<Map<String, Object?>>>{};
    for (final row in attemptRows) {
      final day = row['day']! as String;
      attempts.putIfAbsent(day, () => []).add({
        'wordId': row['word_id'],
        'answer': row['answer'],
        'correct': (row['correct'] as int) == 1,
      });
    }

    final lesson = <String, Object?>{
      'installId': settings['installId'] ?? '',
      'dailyWords': decodeSetting('dailyWords') ?? 5,
      'level': settings['level'] ?? '入门',
      'levelChosen': decodeSetting('levelChosen') == true,
      'upgradeNudgeDismissed': decodeSetting('upgradeNudgeDismissed') == true,
      'reasoningEffort': settings['reasoningEffort'] ?? 'off',
      'goal': settings['goal'] ?? '职场',
      'tone': settings['tone'] ?? '简洁',
      'userWords': [
        for (final row in userRows)
          {
            'id': row['id'],
            'en': row['en'],
            'cn': row['cn'],
            'pos': row['pos'],
          },
      ],
      'plans': [
        for (final row in planRows) jsonDecode(row['payload']! as String),
      ],
      'attempts': attempts,
      'errors': {
        for (final row in errorRows)
          row['word_id']! as String: {
            'wrongAnswer': row['wrong_answer'],
            'correctAnswer': row['correct_answer'],
            'round': row['round'],
            'nextReview': row['next_review'],
            'resolved': (row['resolved'] as int) == 1,
          },
      },
      'reviews': {
        for (final row in reviewRows)
          row['word_id']! as String: {
            'introducedOn': row['introduced_on'],
            'stage': row['stage'],
            'nextReview': row['next_review'],
          },
      },
      'calls': [
        for (final row in callRows)
          {
            'task': row['task'],
            'ok': (row['ok'] as int) == 1,
            'finishReason': row['finish_reason'],
            'tokens': row['tokens'],
          },
      ],
    };

    shell.store.restore(jsonEncode(lesson));

    final chatRows = await db.query('chat_messages', orderBy: 'seq');
    final checkpoint = await db.query('chat_checkpoints', where: 'id = 1');
    final chatJson = <String, Object?>{
      'messages': [
        for (final row in chatRows) jsonDecode(row['payload']! as String),
      ],
    };
    if (checkpoint.isNotEmpty) {
      chatJson['contextSummary'] = jsonDecode(
        checkpoint.first['payload']! as String,
      );
    }
    shell.chat.restore(chatJson);
  }

  /// Import legacy `english_progress.json` once, then stop writing it.
  /// [legacyFile] overrides the default documents path (tests).
  Future<bool> migrateLegacyJsonIfNeeded(
    ProgressShell shell, {
    File? legacyFile,
  }) async {
    final flag = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['json_migrated'],
      limit: 1,
    );
    if (flag.isNotEmpty) return false;

    File file;
    if (legacyFile != null) {
      file = legacyFile;
    } else {
      final progress = await LocalProgress.open();
      file = progress.file;
    }
    String? raw;
    if (file.existsSync()) {
      raw = await file.readAsString();
    }
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        shell.restore(raw);
        await saveShell(shell);
      } on Object {
        // Ignore corrupt JSON; mark migrated so we do not loop.
      }
    }
    await db.insert('meta', {
      'key': 'json_migrated',
      'value': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    // Leave the JSON file in place as a one-time backup; do not write it again.
    return raw != null && raw.trim().isNotEmpty;
  }

  /// Replace the on-device study log. One user, one phone: full swap is enough.
  Future<void> saveStudyLog(StudyLog log) async {
    final book = log.book.toJson();
    await db.transaction((txn) async {
      await txn.delete('study_items');
      await txn.delete('study_attempts');
      await txn.delete('study_classes');
      await txn.delete('study_class_messages');
      await txn.delete('study_class_checkpoints');

      final items = book['items'];
      if (items is List) {
        for (final item in items) {
          if (item is! Map) continue;
          final id = item['id'];
          if (id is! String || id.isEmpty) continue;
          await txn.insert('study_items', {
            'id': id,
            'prompt_cn': _text(item['promptCn']),
            'target_en': _text(item['targetEn']),
            'difficulty': _int(item['difficulty']),
            'status': _statusText(item['status']),
            'due_at': _optionalText(item['dueAt']),
            'last_error_tag': _optionalText(item['lastErrorTag']),
            'last_submission': _optionalText(item['lastSubmission']),
            'corrected_en': _optionalText(item['correctedEn']),
            'reason': _optionalText(item['reason']),
          });
        }
      }

      final attempts = book['attempts'];
      if (attempts is List) {
        for (final attempt in attempts) {
          if (attempt is! Map) continue;
          final id = attempt['id'];
          if (id is! String || id.isEmpty) continue;
          await txn.insert('study_attempts', {
            'id': id,
            'at': _text(attempt['at']),
            'class_id': _optionalText(attempt['classId']),
            'item_id': _text(attempt['itemId']),
            'submission': _text(attempt['submission']),
            'option_id': _optionalText(attempt['optionId']),
            'pass': _boolInt(attempt['pass']),
            'error_tag': _text(attempt['errorTag']),
            'corrected_en': _text(attempt['correctedEn']),
            'revealed': _boolInt(attempt['revealed']),
          });
        }
      }

      for (final studyClass in log.classes) {
        final encoded = studyClass.toJson();
        final id = encoded['id'];
        if (id is! String || id.isEmpty) continue;
        await txn.insert('study_classes', {
          'id': id,
          'started_at': _text(encoded['startedAt']),
          'ended_at': _optionalText(encoded['endedAt']),
          'close_note': _text(encoded['closeNote']),
          'user_turns': _int(encoded['userTurns']),
          'judged': _int(encoded['judged']),
          'last_message_at': _optionalText(encoded['lastMessageAt']),
        });

        final messages = encoded['messages'];
        if (messages is List) {
          var seq = 0;
          for (final message in messages) {
            if (message is! Map) continue;
            await txn.insert('study_class_messages', {
              'class_id': id,
              'seq': seq,
              'payload': jsonEncode(message),
            });
            seq += 1;
          }
        }

        final checkpoint = encoded['checkpoint'];
        if (checkpoint is Map) {
          await txn.insert('study_class_checkpoints', {
            'class_id': id,
            'payload': jsonEncode(checkpoint),
          });
        }
      }

      final facts = book['facts'];
      final factMap = facts is Map ? facts : const <String, Object?>{};
      await _putSetting(txn, _learnerNameKey, _text(factMap['name']));
      await _putSetting(txn, _learnerJobKey, _text(factMap['job']));
      await _putSetting(txn, _learnerGoalKey, _text(factMap['goal']));
      await _putSetting(
        txn,
        _learnerCurrentItemKey,
        _text(factMap['currentItemId']),
      );
    });
  }

  /// Rebuild [StudyLog] from study tables. No rows means an empty log.
  Future<StudyLog> loadStudyLog() async {
    final itemRows = await db.query('study_items', orderBy: 'rowid');
    final attemptRows = await db.query('study_attempts', orderBy: 'rowid');
    final classRows = await db.query('study_classes', orderBy: 'rowid');
    final messageRows = await db.query(
      'study_class_messages',
      orderBy: 'class_id, seq',
    );
    final checkpointRows = await db.query('study_class_checkpoints');
    final settingRows = await db.query(
      'settings',
      where: 'key IN (?, ?, ?, ?)',
      whereArgs: const [
        _learnerNameKey,
        _learnerJobKey,
        _learnerGoalKey,
        _learnerCurrentItemKey,
      ],
    );
    final settings = {
      for (final row in settingRows)
        row['key']! as String: row['value']! as String,
    };
    final facts = <String, Object?>{
      'name': settings[_learnerNameKey] ?? '',
      'job': settings[_learnerJobKey] ?? '',
      'goal': settings[_learnerGoalKey] ?? '',
      'currentItemId': _blankToNull(settings[_learnerCurrentItemKey]),
    };
    final hasFacts =
        _text(facts['name']).isNotEmpty ||
        _text(facts['job']).isNotEmpty ||
        _text(facts['goal']).isNotEmpty ||
        facts['currentItemId'] != null;
    if (itemRows.isEmpty &&
        attemptRows.isEmpty &&
        classRows.isEmpty &&
        !hasFacts) {
      return StudyLog();
    }

    final messagesByClass = <String, List<Map<String, Object?>>>{};
    for (final row in messageRows) {
      final classId = row['class_id'];
      if (classId is! String) continue;
      final decoded = jsonDecode(row['payload']! as String);
      final message = ChatMessage.fromJson(decoded);
      if (message == null) continue;
      messagesByClass.putIfAbsent(classId, () => []).add(message.toJson());
    }

    final checkpoints = <String, Map<String, Object?>>{};
    for (final row in checkpointRows) {
      final classId = row['class_id'];
      if (classId is! String) continue;
      final decoded = jsonDecode(row['payload']! as String);
      final summary = ContextSummary.fromJson(decoded);
      if (summary == null) continue;
      checkpoints[classId] = summary.toJson();
    }

    final book = Gradebook();
    book.loadJson({
      'items': [
        for (final row in itemRows)
          {
            'id': row['id'],
            'promptCn': row['prompt_cn'],
            'targetEn': row['target_en'],
            'difficulty': row['difficulty'],
            'status': row['status'],
            'dueAt': row['due_at'],
            'lastErrorTag': row['last_error_tag'],
            'lastSubmission': row['last_submission'],
            'correctedEn': row['corrected_en'],
            'reason': row['reason'],
          },
      ],
      'attempts': [
        for (final row in attemptRows)
          {
            'id': row['id'],
            'at': row['at'],
            'classId': row['class_id'],
            'itemId': row['item_id'],
            'submission': row['submission'],
            'optionId': row['option_id'],
            'pass': (row['pass'] as int) == 1,
            'errorTag': row['error_tag'],
            'correctedEn': row['corrected_en'],
            'revealed': (row['revealed'] as int) == 1,
          },
      ],
      'facts': facts,
    });

    final classes = <StudyClass>[];
    for (final row in classRows) {
      final id = row['id'];
      if (id is! String) continue;
      final checkpoint = checkpoints[id];
      final parsed = StudyClass.fromJson({
        'id': id,
        'startedAt': row['started_at'],
        'endedAt': row['ended_at'],
        'closeNote': row['close_note'],
        'userTurns': row['user_turns'],
        'judged': row['judged'],
        'lastMessageAt': row['last_message_at'],
        'messages': messagesByClass[id] ?? const <Map<String, Object?>>[],
        if (checkpoint != null) 'checkpoint': checkpoint,
      });
      if (parsed != null) classes.add(parsed);
    }
    return StudyLog(book: book, classes: classes);
  }

  Future<List<ReaderBookSummary>> listReaderBooks() async {
    final rows = await db.query(
      'reader_books',
      columns: ['id', 'title', 'place'],
      orderBy: 'updated_at DESC',
    );
    return [
      for (final row in rows)
        ReaderBookSummary(
          id: row['id']! as String,
          title: row['title']! as String,
          place: (row['place'] as int?) ?? 0,
        ),
    ];
  }

  Future<ReaderBook?> readerBook(String id) async {
    final rows = await db.query(
      'reader_books',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return ReaderBook(
      id: row['id']! as String,
      title: row['title']! as String,
      text: row['text']! as String,
      place: (row['place'] as int?) ?? 0,
    );
  }

  Future<ReaderBook> insertReaderBook({
    required String id,
    required String title,
    required String fileName,
    required String text,
  }) async {
    final now = DateTime.now().toIso8601String();
    await db.insert('reader_books', {
      'id': id,
      'title': title,
      'file_name': fileName,
      'text': text,
      'place': 0,
      'updated_at': now,
    });
    return ReaderBook(id: id, title: title, text: text, place: 0);
  }

  Future<void> touchReaderBook(String id) async {
    await db.update(
      'reader_books',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> saveReaderPlace(String id, int place) async {
    final rows = await db.query(
      'reader_books',
      columns: ['text'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final text = rows.first['text'] as String? ?? '';
    await db.update(
      'reader_books',
      {
        'place': clampPlace(place, text.length),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Exact lemma, any level. Writes nothing. A prefix is not a hit.
  Future<CefrWord?> exactWord(String word) async {
    final text = word.trim();
    if (text.isEmpty) return null;
    final rows = await db.rawQuery(
      '''
      SELECT id, en, cn, pos, level, book_id
      FROM wordbook
      WHERE lower(en) = lower(?)
      ORDER BY length(en), id
      LIMIT 1
      ''',
      [text],
    );
    if (rows.isEmpty) return null;
    return _rowToWord(rows.first);
  }

  Future<String?> cachedGloss({
    required String word,
    required String sentence,
  }) async {
    final key = word.trim().toLowerCase();
    final line = sentence.trim();
    if (key.isEmpty || line.isEmpty) return null;
    final rows = await db.query(
      'reader_glosses',
      columns: ['gloss_cn'],
      where: 'word = ? AND sentence = ?',
      whereArgs: [key, line],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final gloss = rows.first['gloss_cn'];
    return gloss is String && gloss.trim().isNotEmpty ? gloss : null;
  }

  Future<void> saveGloss({
    required String word,
    required String sentence,
    required String glossCn,
  }) async {
    final key = word.trim().toLowerCase();
    final line = sentence.trim();
    final gloss = glossCn.trim();
    if (key.isEmpty || line.isEmpty || gloss.isEmpty) return;
    await db.insert('reader_glosses', {
      'word': key,
      'sentence': line,
      'gloss_cn': gloss,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// A fact from 「留下这个词」. Does not write a study item, grade, or due time.
  Future<void> leaveWord({
    required String word,
    required String sentence,
    required String glossCn,
  }) async {
    final kept = word.trim();
    final line = sentence.trim();
    final gloss = glossCn.trim();
    if (kept.isEmpty || line.isEmpty || gloss.isEmpty) return;
    await db.insert('left_words', {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'word': kept,
      'sentence': line,
      'gloss_cn': gloss,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<LeftWord>> leftWords({int limit = 20}) async {
    final cap = limit < 0 ? 0 : (limit > 20 ? 20 : limit);
    if (cap == 0) return const [];
    final rows = await db.query(
      'left_words',
      orderBy: 'created_at DESC',
      limit: cap,
    );
    return [
      for (final row in rows)
        LeftWord(
          word: row['word']! as String,
          sentence: row['sentence']! as String,
          glossCn: row['gloss_cn']! as String,
          at: row['created_at']! as String,
        ),
    ];
  }

  Future<void> close() => db.close();
}

Future<void> _putSetting(Transaction txn, String key, String value) {
  return txn.insert('settings', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

String _text(Object? value) => value is String ? value : '';

String? _optionalText(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

String? _blankToNull(String? value) {
  if (value == null || value.isEmpty) return null;
  return value;
}

int _int(Object? value) => value is int ? value : 0;

int _boolInt(Object? value) {
  if (value == true || value == 1) return 1;
  return 0;
}

String _statusText(Object? value) {
  if (value is String) {
    final parsed = parseItemStatus(value);
    if (parsed != null) return itemStatusLabel(parsed);
  }
  return '没练过';
}

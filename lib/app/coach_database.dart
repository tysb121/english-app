import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;

import '../data/cefr_core.dart';
import 'local_progress.dart';
import 'progress_shell.dart';

const coachDbFileName = 'english_coach.db';
const coachSchemaVersion = 2;

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
  }

  static Future<void> _ensureWordbookIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_wordbook_level ON wordbook(level)',
    );
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
    return [
      for (final row in rows) _rowToWord(row),
    ];
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
            await db.rawQuery(
              'SELECT COUNT(*) FROM wordbook WHERE level = ?',
              [level],
            ),
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
          await db.rawQuery(
            'SELECT COUNT(*) FROM wordbook WHERE level = ?',
            [level],
          ),
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
      await txn.delete('settings');
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

  Future<void> close() => db.close();
}

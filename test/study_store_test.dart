import 'dart:io';

import 'package:english_app/app/coach_database.dart';
import 'package:english_app/app/progress_shell.dart';
import 'package:english_app/engine/chat_context.dart';
import 'package:english_app/engine/chat_message.dart';
import 'package:english_app/engine/class_session.dart';
import 'package:english_app/engine/gradebook.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'support/cefr_fixture.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    ensureCoachDbFactory();
    tmp = await Directory.systemTemp.createTemp('study_store_');
  });

  tearDown(() async {
    if (tmp.existsSync()) {
      await tmp.delete(recursive: true);
    }
  });

  test('empty study log when the new tables have no rows', () async {
    final dbPath = p.join(tmp.path, 'empty.db');
    final coach = await CoachDatabase.open(path: dbPath);
    final loaded = await coach.loadStudyLog();
    expect(loaded.book.items, isEmpty);
    expect(loaded.book.attempts, isEmpty);
    expect(loaded.classes, isEmpty);
    expect(loaded.book.facts.name, isEmpty);
    await coach.close();
  });

  test('study log survives close and reopen', () async {
    final dbPath = p.join(tmp.path, 'study.db');
    final coach = await CoachDatabase.open(path: dbPath);
    expect(await coach.loadStudyLog(), predicate<StudyLog>(
      (log) => log.book.items.isEmpty && log.classes.isEmpty,
    ));

    const itemId = 'item-1';
    final due = DateTime.utc(2026, 10, 5, 9);
    final attemptedAt = DateTime.utc(2026, 10, 4, 8, 1);
    final started = DateTime.utc(2026, 10, 4, 8);
    final ended = DateTime.utc(2026, 10, 4, 8, 30);
    final lastMessage = DateTime.utc(2026, 10, 4, 8, 20);

    final book = Gradebook();
    book.items.add(
      StudyItem(
        id: itemId,
        promptCn: '向别人问好',
        targetEn: 'Hello!',
        difficulty: 4,
        status: ItemStatus.shaky,
        dueAt: due,
        lastErrorTag: '拼写',
        lastSubmission: 'helo',
        correctedEn: 'Hello!',
        reason: '打招呼',
      ),
    );
    book.attempts.add(
      StudyAttempt(
        id: 'att-1',
        at: attemptedAt,
        classId: 'class-1',
        itemId: itemId,
        submission: 'helo',
        optionId: 'opt-b',
        pass: false,
        errorTag: '拼写',
        correctedEn: 'Hello!',
        revealed: false,
      ),
    );
    book.facts.name = '林夏';
    book.facts.job = '编辑';
    book.facts.goal = '开会';
    book.facts.currentItemId = itemId;

    final studyClass = StudyClass(
      id: 'class-1',
      startedAt: started,
      endedAt: ended,
      closeNote: '练了问好\n最近写错\n明天再练',
      messages: const [
        ChatMessage(id: 'm1', role: ChatRole.user, content: 'helo'),
      ],
      checkpoint: const ContextSummary(
        untilMessageId: 'm1',
        text: '上一节在练问好',
      ),
      userTurns: 1,
      judged: 1,
      lastMessageAt: lastMessage,
    );
    await coach.saveStudyLog(StudyLog(book: book, classes: [studyClass]));
    await coach.close();

    final coach2 = await CoachDatabase.open(path: dbPath);
    final loaded = await coach2.loadStudyLog();

    final item = loaded.book.items.single;
    expect(item.id, itemId);
    expect(item.promptCn, '向别人问好');
    expect(item.targetEn, 'Hello!');
    expect(item.difficulty, 4);
    expect(item.status, ItemStatus.shaky);
    expect(item.dueAt, due);
    expect(item.lastErrorTag, '拼写');
    expect(item.lastSubmission, 'helo');
    expect(item.correctedEn, 'Hello!');
    expect(item.reason, '打招呼');

    final attempt = loaded.book.attempts.single;
    expect(attempt.id, 'att-1');
    expect(attempt.at, attemptedAt);
    expect(attempt.classId, 'class-1');
    expect(attempt.itemId, itemId);
    expect(attempt.submission, 'helo');
    expect(attempt.optionId, 'opt-b');
    expect(attempt.pass, isFalse);
    expect(attempt.errorTag, '拼写');
    expect(attempt.correctedEn, 'Hello!');
    expect(attempt.revealed, isFalse);

    expect(loaded.book.facts.name, '林夏');
    expect(loaded.book.facts.job, '编辑');
    expect(loaded.book.facts.goal, '开会');
    expect(loaded.book.facts.currentItemId, itemId);

    final klass = loaded.classes.single;
    expect(klass.id, 'class-1');
    expect(klass.startedAt, started);
    expect(klass.endedAt, ended);
    expect(klass.closeNote, '练了问好\n最近写错\n明天再练');
    expect(klass.userTurns, 1);
    expect(klass.judged, 1);
    expect(klass.lastMessageAt, lastMessage);
    expect(klass.messages, hasLength(1));
    expect(klass.messages.single.id, 'm1');
    expect(klass.messages.single.role, ChatRole.user);
    expect(klass.messages.single.content, 'helo');
    expect(klass.checkpoint, isNotNull);
    expect(klass.checkpoint!.untilMessageId, 'm1');
    expect(klass.checkpoint!.text, '上一节在练问好');

    final statusRows = await coach2.db.query('study_items', columns: ['status']);
    expect(statusRows.single['status'], '不稳');

    final replaced = Gradebook()..facts.name = '只留名字';
    await coach2.saveStudyLog(StudyLog(book: replaced));
    final again = await coach2.loadStudyLog();
    expect(again.book.items, isEmpty);
    expect(again.book.attempts, isEmpty);
    expect(again.classes, isEmpty);
    expect(again.book.facts.name, '只留名字');
    expect(again.book.facts.job, isEmpty);
    expect(again.book.facts.currentItemId, isNull);
    await coach2.close();
  });

  test('schema 2 upgrade keeps wordbook rows and accepts a study log', () async {
    final dbPath = p.join(tmp.path, 'v2.db');
    final raw = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
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
CREATE TABLE settings (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
)''');
          await db.insert('wordbook', {
            'id': 'w1',
            'en': 'hello',
            'cn': '你好',
            'pos': 'noun',
            'level': 'a1',
            'book_id': 'cefr',
          });
        },
      ),
    );
    await raw.close();

    final coach = await CoachDatabase.open(path: dbPath);
    expect((await coach.loadWordbook()).single.en, 'hello');
    final book = Gradebook();
    book.items.add(
      StudyItem(
        id: 'up-1',
        promptCn: '升级',
        targetEn: 'upgrade',
        difficulty: 1,
        status: ItemStatus.unseen,
      ),
    );
    book.facts.name = '升级后';
    await coach.saveStudyLog(StudyLog(book: book));
    await coach.close();

    final coach2 = await CoachDatabase.open(path: dbPath);
    expect((await coach2.loadWordbook()).single.id, 'w1');
    final loaded = await coach2.loadStudyLog();
    expect(loaded.book.items.single.targetEn, 'upgrade');
    expect(loaded.book.items.single.status, ItemStatus.unseen);
    expect(loaded.book.facts.name, '升级后');
    await coach2.close();
  });

  test('lesson shell save does not wipe learner facts', () async {
    final dbPath = p.join(tmp.path, 'shell.db');
    final coach = await CoachDatabase.open(path: dbPath, seedBook: cefrFixture);
    final book = Gradebook();
    book.facts.name = '林夏';
    book.facts.currentItemId = 'item-9';
    await coach.saveStudyLog(StudyLog(book: book));

    final store = fixtureStore(
      clock: () => DateTime(2026, 10, 4),
      levelChosen: true,
      installId: 'keep_learner',
    );
    await coach.saveShell(ProgressShell(store: store));
    final loaded = await coach.loadStudyLog();
    expect(loaded.book.facts.name, '林夏');
    expect(loaded.book.facts.currentItemId, 'item-9');
    expect(await coach.hasProgress(), isTrue);
    await coach.close();
  });
}

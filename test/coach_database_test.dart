import 'dart:convert';
import 'dart:io';

import 'package:english_app/app/coach_database.dart';
import 'package:english_app/app/progress_shell.dart';
import 'package:english_app/engine/chat_message.dart';
import 'package:english_app/engine/chat_thread.dart';
import 'package:english_app/engine/lesson_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/cefr_fixture.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    ensureCoachDbFactory();
    tmp = await Directory.systemTemp.createTemp('coach_db_');
  });

  tearDown(() async {
    if (tmp.existsSync()) {
      await tmp.delete(recursive: true);
    }
  });

  test('imports wordbook and picks untaught by level', () async {
    final dbPath = p.join(tmp.path, 't1.db');
    final coach = await CoachDatabase.open(
      path: dbPath,
      seedBook: cefrFixture,
    );
    final loaded = await coach.loadWordbook();
    expect(loaded.length, cefrFixture.length);

    final picked = await coach.pickUntaughtIds(
      level: 'a1',
      limit: 5,
      exclude: {'cc_a1_hello_noun_ce4a5e'},
    );
    expect(picked, hasLength(5));
    expect(picked, isNot(contains('cc_a1_hello_noun_ce4a5e')));
    for (final id in picked) {
      expect(id, startsWith('cc_a1_'));
    }

    final left = await coach.untaughtCount(
      level: 'a1',
      exclude: {for (final w in cefrFixture.where((w) => w.level == 'a1')) w.id},
    );
    expect(left, 0);
    await coach.close();
  });

  test('round-trips lesson settings, plan, errors, and chat', () async {
    final dbPath = p.join(tmp.path, 't2.db');
    final coach = await CoachDatabase.open(
      path: dbPath,
      seedBook: cefrFixture,
    );

    final store = fixtureStore(
      clock: () => DateTime(2026, 7, 1),
      level: '入门',
      levelChosen: true,
      installId: 'install_test_1',
    );
    final plan = store.ensureTodayPlan();
    expect(plan.newWordIds, hasLength(5));
    store.submitVocab('nope');
    store.advanceVocab();
    store.dismissUpgradeNudge();

    final chat = ChatThread(idFactory: () => 'm1');
    chat.messages.add(
      const ChatMessage(id: 'm1', role: ChatRole.user, content: 'hello'),
    );
    final shell = ProgressShell(store: store, chat: chat);
    await coach.saveShell(shell);
    await coach.close();

    final coach2 = await CoachDatabase.open(path: dbPath);
    final store2 = fixtureStore(clock: () => DateTime(2026, 7, 1));
    final shell2 = ProgressShell(store: store2, chat: ChatThread());
    expect(await coach2.hasProgress(), isTrue);
    await coach2.loadShell(shell2);

    expect(shell2.store.installId, 'install_test_1');
    expect(shell2.store.level, '入门');
    expect(shell2.store.levelChosen, isTrue);
    expect(shell2.store.upgradeNudgeDismissed, isTrue);
    expect(shell2.store.ensureTodayPlan().newWordIds, plan.newWordIds);
    expect(shell2.store.nextErrorReview(plan.newWordIds.first), isNotNull);
    expect(shell2.chat.messages, hasLength(1));
    expect(shell2.chat.messages.first.content, 'hello');
    await coach2.close();
  });

  test('migrates legacy english_progress.json once', () async {
    final dbPath = p.join(tmp.path, 't3.db');
    final store = fixtureStore(
      clock: () => DateTime(2026, 8, 1),
      level: '基础',
      levelChosen: true,
      installId: 'from_json',
    );
    store.ensureTodayPlan();
    final shell = ProgressShell(store: store, chat: ChatThread());
    final jsonFile = File(p.join(tmp.path, 'english_progress.json'))
      ..writeAsStringSync(shell.encode());

    final coach = await CoachDatabase.open(
      path: dbPath,
      seedBook: cefrFixture,
    );
    final empty = ProgressShell(
      store: fixtureStore(clock: () => DateTime(2026, 8, 1)),
      chat: ChatThread(),
    );
    final migrated = await coach.migrateLegacyJsonIfNeeded(
      empty,
      legacyFile: jsonFile,
    );
    expect(migrated, isTrue);
    expect(empty.store.installId, 'from_json');
    expect(empty.store.level, '基础');
    expect(await coach.hasProgress(), isTrue);

    final again = ProgressShell(
      store: fixtureStore(clock: () => DateTime(2026, 8, 1)),
      chat: ChatThread(),
    );
    final second = await coach.migrateLegacyJsonIfNeeded(
      again,
      legacyFile: jsonFile,
    );
    expect(second, isFalse);
    await coach.close();
  });

  test('progress JSON no longer required after sqlite save', () async {
    final dbPath = p.join(tmp.path, 't4.db');
    final coach = await CoachDatabase.open(
      path: dbPath,
      seedBook: cefrFixture,
    );
    final store = fixtureStore(
      clock: () => DateTime(2026, 9, 1),
      levelChosen: true,
      installId: 'sqlite_only',
    );
    store.dailyWords = 10;
    store.ensureTodayPlan();
    await coach.saveShell(ProgressShell(store: store, chat: ChatThread()));

    final raw = store.progressJson();
    expect(jsonDecode(raw), isA<Map>());
    // Keys stay out of business DB: no deepseek fields in settings.
    final settings = await coach.db.query('settings');
    final keys = {for (final row in settings) row['key']};
    expect(keys, isNot(contains('deepseek_key')));
    expect(keys, contains('dailyWords'));
    expect(keys, contains('installId'));
    await coach.close();
  });
}

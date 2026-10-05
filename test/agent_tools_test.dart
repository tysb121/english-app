import 'dart:convert';
import 'dart:io';

import 'package:english_app/app/coach_database.dart';
import 'package:english_app/data/cefr_core.dart';
import 'package:english_app/engine/agent_tools.dart';
import 'package:english_app/engine/gradebook.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('agentToolSchemas lists the teacher tools', () {
    expect(
      [for (final tool in agentToolSchemas) (tool['function'] as Map)['name']],
      [
        'get_learner',
        'lookup_words',
        'get_due_items',
        'get_recent_attempts',
        'get_error_patterns',
        'add_item',
        'set_plan',
        'record_attempt',
        'note_fact',
        'end_class',
        'present_card',
      ],
    );
    for (final tool in agentToolSchemas) {
      expect(tool['type'], 'function');
      final function = tool['function']! as Map;
      expect(function['description'], isA<String>());
      expect(function['parameters'], isA<Map>());
    }
  });

  test('record_attempt stores the pending text and rejects a second write', () {
    final book = Gradebook(ids: _ids('item'));
    final item = book.addItem(
      promptCn: '问好',
      targetEn: 'Hello there',
      difficulty: 1,
    );
    final blocked = runTool(
      name: 'set_plan',
      args: {
        'item_id': item.id,
        'status': '会用',
        'due_at': '2026-12-01T00:00:00.000',
      },
      book: book,
      pending: null,
      cardPending: false,
    );
    expect(blocked.ok, isFalse);
    expect(item.status, ItemStatus.unseen);
    expect(item.dueAt, isNull);

    final pending = PendingSubmission(
      text: 'student sentence',
      optionId: 'opt-1',
    );
    final recorded = runTool(
      name: 'record_attempt',
      args: {
        'item_id': item.id,
        'submission': 'model rewritten',
        'option_id': 'zzz',
        'text': 'also wrong',
        'pass': true,
        'error_tag': '',
        'corrected_en': 'Hello there',
        'revealed': false,
      },
      book: book,
      pending: pending,
      cardPending: false,
      classId: 'class-9',
    );
    expect(recorded.ok, isTrue);
    expect(pending.consumed, isTrue);
    expect(book.attempts, hasLength(1));
    expect(book.attempts.single.submission, 'student sentence');
    expect(book.attempts.single.optionId, 'opt-1');
    expect(book.attempts.single.pass, isTrue);
    expect(book.attempts.single.revealed, isFalse);
    expect(book.attempts.single.classId, 'class-9');
    expect(book.items.single.lastSubmission, 'student sentence');
    expect(
      book.attempts.single.submission.contains('model rewritten'),
      isFalse,
    );

    final again = runTool(
      name: 'record_attempt',
      args: {
        'item_id': item.id,
        'pass': false,
        'error_tag': '语序',
        'corrected_en': 'Hello',
        'revealed': false,
        'submission': 'second fake',
      },
      book: book,
      pending: pending,
      cardPending: false,
    );
    expect(again.ok, isFalse);
    expect(book.attempts, hasLength(1));
    expect(book.items.single.lastSubmission, 'student sentence');

    final marked = runTool(
      name: 'set_plan',
      args: {'item_id': item.id, 'status': '会用'},
      book: book,
      pending: null,
      cardPending: false,
    );
    expect(marked.ok, isTrue);
    expect(item.status, ItemStatus.canUse);
  });

  test('present_card rejects a short choice and a second card', () {
    final book = Gradebook(
      clock: () => DateTime(2026, 10, 4, 12),
      ids: _ids('item'),
    );
    final choice = runTool(
      name: 'present_card',
      args: {
        'kind': 'choice',
        'prompt': 'Pick one',
        'answer': 'secret',
        'options': [
          {'id': 'a', 'text': 'A'},
        ],
      },
      book: book,
      pending: null,
      cardPending: false,
    );
    expect(choice.ok, isFalse);
    expect(choice.card, isNull);
    final choiceBody = jsonDecode(choice.content) as Map;
    expect(choiceBody['ok'], isFalse);
    expect(choiceBody['error'], isA<String>());

    final leaked = runTool(
      name: 'present_card',
      args: {
        'kind': 'judge',
        'prompt': 'Is this ok?',
        'correct': 'y',
        'options': [
          {'id': 'y', 'text': '对'},
          {'id': 'n', 'text': '不对'},
        ],
      },
      book: book,
      pending: null,
      cardPending: false,
    );
    expect(leaked.ok, isFalse);
    expect(leaked.card, isNull);

    final duplicated = runTool(
      name: 'present_card',
      args: {
        'kind': 'choice',
        'prompt': 'Pick',
        'options': [
          {'id': 'a', 'text': 'One'},
          {'id': 'a', 'text': 'Two'},
        ],
      },
      book: book,
      pending: null,
      cardPending: false,
    );
    expect(duplicated.ok, isFalse);
    expect(duplicated.card, isNull);

    final blankWithOptions = runTool(
      name: 'present_card',
      args: {
        'kind': 'blank',
        'prompt': 'Write it',
        'options': [
          {'id': 'a', 'text': 'nope'},
        ],
      },
      book: book,
      pending: null,
      cardPending: false,
    );
    expect(blankWithOptions.ok, isFalse);
    expect(blankWithOptions.card, isNull);

    final judge = runTool(
      name: 'present_card',
      args: {
        'id': 'card-judge',
        'kind': 'judge',
        'prompt': 'Is this ok?',
        'options': [
          {'id': 'y', 'text': '对'},
          {'id': 'n', 'text': '不对'},
        ],
      },
      book: book,
      pending: null,
      cardPending: false,
    );
    expect(judge.ok, isTrue);
    expect(judge.card, isNotNull);
    expect(judge.card!.kind, CardKind.judge);
    expect(judge.card!.id, 'card-judge');
    expect(judge.card!.options, hasLength(2));
    expect(judge.card!.options[0].text, '对');
    expect(jsonDecode(judge.content), {'ok': true, 'waiting': true});
    expect(judge.endClass, isFalse);

    final blocked = runTool(
      name: 'present_card',
      args: {
        'kind': 'judge',
        'prompt': 'Again?',
        'options': [
          {'id': 'y', 'text': '对'},
          {'id': 'n', 'text': '不对'},
        ],
      },
      book: book,
      pending: null,
      cardPending: true,
    );
    expect(blocked.ok, isFalse);
    expect(blocked.card, isNull);

    final blank = runTool(
      name: 'present_card',
      args: {'kind': 'blank', 'prompt': 'Write it', 'placeholder': '英文'},
      book: book,
      pending: null,
      cardPending: false,
    );
    expect(blank.ok, isTrue);
    expect(blank.card!.kind, CardKind.blank);
    expect(blank.card!.options, isEmpty);
    expect(blank.card!.placeholder, '英文');
    expect(blank.card!.id.startsWith('card'), isTrue);
  });

  test('queries use the gradebook clock and end_class keeps the book', () {
    final clock = DateTime(2099, 1, 2, 3, 4);
    final book = Gradebook(clock: () => clock, ids: _ids('item'));
    book.noteFact('name', '周');
    final due = book.addItem(promptCn: '到期', targetEn: 'Due', difficulty: 2);
    book.setPlan(itemId: due.id, dueAt: clock);
    final later = book.addItem(
      promptCn: '以后',
      targetEn: 'Later',
      difficulty: 4,
    );
    book.setPlan(
      itemId: later.id,
      dueAt: clock.add(const Duration(minutes: 1)),
    );

    final found = runTool(
      name: 'get_due_items',
      args: {},
      book: book,
      pending: null,
      cardPending: false,
    );
    final foundBody = jsonDecode(found.content) as Map;
    expect(found.ok, isTrue);
    expect(foundBody['items'], hasLength(1));
    expect((foundBody['items'] as List).first['id'], due.id);

    final early = runTool(
      name: 'get_due_items',
      args: {},
      book: book,
      pending: null,
      cardPending: false,
      now: clock.subtract(const Duration(days: 1)),
    );
    expect((jsonDecode(early.content) as Map)['items'], isEmpty);

    final learner = jsonDecode(
      runTool(
        name: 'get_learner',
        args: {},
        book: book,
        pending: null,
        cardPending: false,
      ).content,
    ) as Map;
    expect(learner['name'], '周');
    expect(learner['current_item']['target_en'], 'Later');

    final before = book.attempts.length;
    final ended = runTool(
      name: 'end_class',
      args: {'close_note': '模型想写的收课条'},
      book: book,
      pending: null,
      cardPending: false,
    );
    expect(ended.ok, isTrue);
    expect(ended.endClass, isTrue);
    expect(book.attempts, hasLength(before));
    expect(book.items, hasLength(2));
    final endedBody = jsonDecode(ended.content) as Map;
    expect((endedBody['close_note'] as String).split('\n'), hasLength(3));
    expect(endedBody['model_close_note'], '模型想写的收课条');

    final unknown = runTool(
      name: 'make_homework',
      args: {},
      book: book,
      pending: null,
      cardPending: false,
    );
    expect(unknown.ok, isFalse);
    expect(unknown.card, isNull);
    expect(jsonDecode(unknown.content), {'ok': false, 'error': '未知工具'});
  });

  test('learner read returns the chosen level, settings goal, and free-text goal', () {
    final book = Gradebook();
    book.noteFact('name', '周');
    book.noteFact('job', '老师');
    book.noteFact('goal', '能开会');
    final body = jsonDecode(
      runTool(
        name: 'get_learner',
        args: {},
        book: book,
        pending: null,
        cardPending: false,
        settings: const LearnerSettings(level: '基础', goal: '考试'),
      ).content,
    ) as Map;
    expect(body['name'], '周');
    expect(body['job'], '老师');
    expect(body['goal'], '能开会');
    expect(body['level'], '基础');
    expect(body['settings_goal'], '考试');
    expect(body['band'], 'a2');
  });

  test('lookup reads the on-device wordbook and still allows an outside sentence', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    ensureCoachDbFactory();
    final source = await loadCefrCore();
    final tmp = await Directory.systemTemp.createTemp('lookup_words_');
    CoachDatabase? db;
    try {
      db = await CoachDatabase.open(
        path: p.join(tmp.path, 'words.db'),
        seedBook: source.entries,
      );
      final book = Gradebook(ids: _ids('item'));
      const settings = LearnerSettings(level: '入门', goal: '日常');

      final known = source.entries.firstWhere(
        (word) => word.en == 'good' && word.pos == 'adjective' && word.level == 'a1',
      );
      final found = await runToolCall(
        name: 'lookup_words',
        args: {'query': known.en, 'limit': 100},
        book: book,
        pending: null,
        cardPending: false,
        settings: settings,
        lookupWords: db.lookupWords,
      );
      expect(found.ok, isTrue);
      final words = (jsonDecode(found.content) as Map)['words'] as List;
      expect(words, isNotEmpty);
      expect(words.length, lessThanOrEqualTo(cefrLookupCap));
      final row = words.cast<Map>().firstWhere(
        (word) => word['en'] == known.en && word['pos'] == known.pos,
      );
      expect(row['cn'], known.cn);
      expect(row['level'], known.level);
      expect(book.items, isEmpty);
      expect(book.attempts, isEmpty);

      final higher = source.entries.firstWhere(
        (word) =>
            word.level == 'b1' &&
            source.byLevel('a1').every((other) => other.en != word.en),
      );
      final stayed = await runToolCall(
        name: 'lookup_words',
        args: {'query': higher.en},
        book: book,
        pending: null,
        cardPending: false,
        settings: settings,
        lookupWords: db.lookupWords,
      );
      final stayedWords = (jsonDecode(stayed.content) as Map)['words'] as List;
      expect(
        stayedWords.cast<Map>().where((word) => word['en'] == higher.en),
        isEmpty,
      );

      final raised = await runToolCall(
        name: 'lookup_words',
        args: {'query': higher.en, 'band': 'b1'},
        book: book,
        pending: null,
        cardPending: false,
        settings: settings,
        lookupWords: db.lookupWords,
      );
      final raisedRow = ((jsonDecode(raised.content) as Map)['words'] as List)
          .cast<Map>()
          .firstWhere((word) => word['en'] == higher.en && word['pos'] == higher.pos);
      expect(raisedRow['cn'], higher.cn);
      expect(raisedRow['level'], 'b1');

      final missing = await runToolCall(
        name: 'lookup_words',
        args: {'query': 'zzzznotaword'},
        book: book,
        pending: null,
        cardPending: false,
        settings: settings,
        lookupWords: db.lookupWords,
      );
      expect((jsonDecode(missing.content) as Map)['words'], isEmpty);

      final gloss = source.entries.firstWhere(
        (word) => word.en == 'a' && word.pos == 'determiner' && word.level == 'a1',
      );
      final glossed = await runToolCall(
        name: 'lookup_words',
        args: {'query': gloss.en, 'band': 'a1'},
        book: book,
        pending: null,
        cardPending: false,
        settings: settings,
        lookupWords: db.lookupWords,
      );
      final glossRow = ((jsonDecode(glossed.content) as Map)['words'] as List)
          .cast<Map>()
          .firstWhere((word) => word['en'] == gloss.en && word['pos'] == gloss.pos);
      expect(glossRow['cn'], gloss.cn);

      final added = runTool(
        name: 'add_item',
        args: {
          'prompt_cn': '请安排这次季度协同。',
          'target_en': 'Please schedule the quarterly synergy review.',
          'difficulty': 4,
        },
        book: book,
        pending: null,
        cardPending: false,
      );
      expect(added.ok, isTrue);
      expect(book.attempts, isEmpty);
      expect(book.items.single.targetEn, 'Please schedule the quarterly synergy review.');
    } finally {
      await db?.close();
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    }
  });

  test('a hidden answer is stored unrevealed and a visible one is not forced', () {
    final book = Gradebook(ids: _ids('item'));
    final item = book.addItem(
      promptCn: '我六点起床。',
      targetEn: 'I get up at six.',
      difficulty: 1,
    );
    final hidden = PendingSubmission(
      text: 'I get up at six.',
      answerHidden: true,
    );
    final recorded = runTool(
      name: 'record_attempt',
      args: {
        'item_id': item.id,
        'submission': '模型改写的原文',
        'pass': true,
        'corrected_en': 'I get up at six.',
        'revealed': true,
      },
      book: book,
      pending: hidden,
      cardPending: false,
    );
    expect(recorded.ok, isTrue);
    expect(book.attempts.single.submission, 'I get up at six.');
    expect(book.attempts.single.submission.contains('模型改写的原文'), isFalse);
    expect(book.attempts.single.revealed, isFalse);
    expect(book.attempts.single.pass, isTrue);

    final visible = PendingSubmission(
      text: 'I get up at seven.',
      answerHidden: false,
    );
    final again = runTool(
      name: 'record_attempt',
      args: {
        'item_id': item.id,
        'submission': '又改写',
        'pass': false,
        'error_tag': '其它',
        'corrected_en': 'I get up at six.',
        'revealed': true,
      },
      book: book,
      pending: visible,
      cardPending: false,
    );
    expect(again.ok, isTrue);
    expect(book.attempts.last.submission, 'I get up at seven.');
    expect(book.attempts.last.revealed, isTrue);
    expect(book.attempts.last.pass, isFalse);

    final before = book.attempts.length;
    final broken = runTool(
      name: 'record_attempt',
      args: {
        'item_id': item.id,
        'submission': '不该写进来',
        'corrected_en': 'I get up at six.',
        'revealed': false,
      },
      book: book,
      pending: PendingSubmission(text: '半截', answerHidden: true),
      cardPending: false,
    );
    expect(broken.ok, isFalse);
    expect(book.attempts, hasLength(before));

    final unknown = PendingSubmission(
      text: cardUnknownText,
      answerHidden: true,
      answerShown: true,
    );
    final shown = runTool(
      name: 'record_attempt',
      args: {
        'item_id': item.id,
        'submission': 'morning',
        'option_id': 'b',
        'pass': false,
        'error_tag': '用错词',
        'corrected_en': 'meeting',
        'revealed': false,
      },
      book: book,
      pending: unknown,
      cardPending: false,
    );
    expect(shown.ok, isTrue);
    expect(book.attempts.last.submission, cardUnknownText);
    expect(book.attempts.last.optionId, isNull);
    expect(book.attempts.last.revealed, isTrue);
    expect(book.attempts.last.pass, isFalse);
  });
}

IdFactory _ids(String prefix) {
  var n = 0;
  return () {
    n += 1;
    return '$prefix-$n';
  };
}

import 'package:english_app/engine/gradebook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('illegal setPlan does not change status or due date', () {
    final book = Gradebook(ids: _ids('item'));
    final item = book.addItem(
      promptCn: '早上好',
      targetEn: 'Good morning',
      difficulty: 9,
    );
    expect(item.difficulty, 5);
    expect(item.status, ItemStatus.unseen);
    final due = DateTime(2026, 10, 4, 8);
    item.status = ItemStatus.shaky;
    item.dueAt = due;

    expect(book.setPlan(itemId: 'missing', statusLabel: '不稳'), isNotNull);
    expect(
      book.setPlan(
        itemId: item.id,
        statusLabel: '掌握了',
        dueAt: DateTime(2026, 11, 1),
      ),
      isNotNull,
    );
    expect(book.setPlan(itemId: item.id, statusLabel: '会用'), isNotNull);
    expect(item.status, ItemStatus.shaky);
    expect(item.dueAt, due);
    expect(book.attempts, isEmpty);
  });

  test('会用 requires a hidden pass and then sticks', () {
    final book = Gradebook(ids: _ids('item'));
    final item = book.addItem(
      promptCn: '早上好',
      targetEn: 'Good morning',
      difficulty: 0,
    );
    expect(item.difficulty, 1);

    expect(
      book.recordAttempt(
        itemId: 'missing',
        submission: 'nope',
        pass: true,
        errorTag: '',
        correctedEn: 'Good morning',
        revealed: false,
      ),
      isNotNull,
    );
    expect(book.attempts, isEmpty);

    expect(
      book.recordAttempt(
        itemId: item.id,
        submission: 'Good morning',
        pass: true,
        errorTag: '',
        correctedEn: 'Good morning',
        revealed: true,
      ),
      isNull,
    );
    expect(book.hasHiddenPass(item.id), isFalse);
    expect(book.setPlan(itemId: item.id, statusLabel: '会用'), isNotNull);
    expect(item.status, ItemStatus.unseen);

    expect(
      book.recordAttempt(
        itemId: item.id,
        submission: 'morning good',
        pass: false,
        errorTag: '标点',
        correctedEn: 'Good morning.',
        revealed: false,
      ),
      isNull,
    );
    expect(book.attempts.last.errorTag, '其它');
    expect(book.hasHiddenPass(item.id), isFalse);
    expect(book.setPlan(itemId: item.id, statusLabel: 'canUse'), isNotNull);
    expect(item.status, ItemStatus.unseen);

    expect(
      book.recordAttempt(
        itemId: item.id,
        submission: 'Good morning.',
        pass: true,
        errorTag: '',
        correctedEn: 'Good morning.',
        revealed: false,
      ),
      isNull,
    );
    expect(book.hasHiddenPass(item.id), isTrue);
    expect(book.attempts.last.errorTag, isEmpty);
    final nextDue = DateTime(2026, 10, 6, 8);
    expect(
      book.setPlan(itemId: item.id, statusLabel: '会用', dueAt: nextDue),
      isNull,
    );
    expect(item.status, ItemStatus.canUse);
    expect(item.dueAt, nextDue);
    expect(item.lastSubmission, 'Good morning.');
    expect(book.errorPatterns(), {'其它': 1});
  });

  test('closeNote is exactly three lines', () {
    final book = Gradebook(ids: _ids('item'));
    final empty = book.closeNote();
    expect(empty.endsWith('\n'), isFalse);
    expect(empty.split('\n'), hasLength(3));
    for (final line in empty.split('\n')) {
      expect(line.contains('无'), isTrue);
    }

    final item = book.addItem(
      promptCn: '打招呼',
      targetEn: 'Hello',
      difficulty: 2,
    );
    book.setPlan(itemId: item.id, dueAt: DateTime(2026, 10, 5, 9));
    book.recordAttempt(
      itemId: item.id,
      submission: 'Hi',
      pass: false,
      errorTag: '用错词',
      correctedEn: 'Hello',
      revealed: true,
    );
    final lines = book.closeNote().split('\n');
    expect(lines, hasLength(3));
    expect(lines[0], '最近练了：打招呼');
    expect(lines[1], '最近一次：错（用错词）');
    expect(lines[2].startsWith('下一到期：2026-10-05T09:00:00.000'), isTrue);
    expect(lines[2].contains('打招呼'), isTrue);
  });

  test('noteFact only writes name job and goal', () {
    final book = Gradebook();
    book.facts.name = '安';
    expect(book.noteFact('年龄', '10'), isNotNull);
    expect(book.facts.name, '安');
    expect(book.noteFact('名字', '李'), isNull);
    expect(book.facts.name, '李');
    expect(book.noteFact('job', '教师'), isNull);
    expect(book.facts.job, '教师');
    expect(book.noteFact('目标', '出差'), isNull);
    expect(book.facts.goal, '出差');
  });

  test('loadJson round-trips and blanks bad payloads', () {
    final book = Gradebook(ids: _ids('item'));
    final due = DateTime(2026, 10, 4, 8, 30);
    final item = book.addItem(
      promptCn: '你好',
      targetEn: 'Hello',
      difficulty: 3,
      reason: '摸底',
    );
    book.noteFact('goal', '出差');
    book.setPlan(itemId: item.id, statusLabel: '不稳', dueAt: due);
    book.recordAttempt(
      itemId: item.id,
      submission: 'Hi',
      optionId: 'a',
      pass: false,
      errorTag: '语序',
      correctedEn: 'Hello',
      revealed: false,
      classId: 'class-1',
      at: due,
    );

    final copy = Gradebook();
    copy.loadJson(book.toJson());
    expect(copy.items.single.promptCn, '你好');
    expect(copy.items.single.targetEn, 'Hello');
    expect(copy.items.single.difficulty, 3);
    expect(copy.items.single.status, ItemStatus.shaky);
    expect(copy.items.single.dueAt, due);
    expect(copy.items.single.reason, '摸底');
    expect(itemStatusLabel(copy.items.single.status), '不稳');
    expect(copy.facts.goal, '出差');
    expect(copy.attempts.single.submission, 'Hi');
    expect(copy.attempts.single.optionId, 'a');
    expect(copy.attempts.single.errorTag, '语序');
    expect(copy.attempts.single.at, due);
    expect(parseItemStatus('canUse'), ItemStatus.canUse);
    expect(normalizeErrorTag(''), '其它');
    expect(normalizeErrorTag(null), '其它');

    copy.loadJson('bad');
    expect(copy.items, isEmpty);
    expect(copy.attempts, isEmpty);
    expect(copy.facts.goal, isEmpty);

    copy.loadJson({
      'items': [
        {'id': 'x'},
      ],
    });
    expect(copy.items, isEmpty);
  });

  test('due items skip future dates and 会用', () {
    final now = DateTime(2026, 10, 4, 12);
    final book = Gradebook(clock: () => now, ids: _ids('item'));
    final open = book.addItem(
      promptCn: '没到期',
      targetEn: 'Later',
      difficulty: 1,
    );
    book.setPlan(itemId: open.id, dueAt: now.add(const Duration(minutes: 1)));
    final due = book.addItem(promptCn: '到了', targetEn: 'Now', difficulty: 1);
    book.setPlan(itemId: due.id, dueAt: now);
    final used = book.addItem(promptCn: '会了', targetEn: 'Done', difficulty: 1);
    book.recordAttempt(
      itemId: used.id,
      submission: 'Done',
      pass: true,
      errorTag: '',
      correctedEn: 'Done',
      revealed: false,
      at: now,
    );
    book.setPlan(itemId: used.id, statusLabel: '会用', dueAt: now);
    book.addItem(promptCn: '无日期', targetEn: 'None', difficulty: 1);

    expect(book.dueItems(now).map((item) => item.id), [due.id]);
    expect(book.recentAttempts(10).first.itemId, used.id);
  });
}

IdFactory _ids(String prefix) {
  var n = 0;
  return () {
    n += 1;
    return '$prefix-$n';
  };
}

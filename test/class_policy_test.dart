import 'package:english_app/engine/chat_context.dart';
import 'package:english_app/engine/chat_message.dart';
import 'package:english_app/engine/class_policy.dart';
import 'package:english_app/engine/class_session.dart';
import 'package:english_app/engine/gradebook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('two hours starts a class and a shorter gap does not', () {
    final start = DateTime(2026, 10, 4, 10);
    expect(classGap, const Duration(hours: 2));
    expect(
      gapStartsNewClass(
        start,
        start.add(const Duration(hours: 1, minutes: 59)),
      ),
      isFalse,
    );
    expect(
      gapStartsNewClass(start, start.add(const Duration(hours: 2))),
      isTrue,
    );
    expect(gapStartsNewClass(null, start), isTrue);
    expect(classIsFull(judged: 5, userMessages: 11), isFalse);
    expect(classIsFull(judged: 6, userMessages: 0), isTrue);
    expect(classIsFull(judged: 0, userMessages: 12), isTrue);
    expect(maxJudgedPerClass, 6);
    expect(maxUserMessagesPerClass, 12);
  });

  test('thirty minutes across midnight stays the same class', () {
    final last = DateTime(2026, 10, 4, 23, 50);
    final now = DateTime(2026, 10, 5, 0, 20);
    expect(now.difference(last), const Duration(minutes: 30));
    expect(gapStartsNewClass(last, now), isFalse);

    final log = StudyLog(ids: _ids('class'));
    final open = log.ensureOpen(last);
    open.lastMessageAt = last;
    open.messages.add(
      ChatMessage(id: 'night', role: ChatRole.user, content: 'NIGHT_BUBBLE'),
    );
    final still = log.ensureOpen(now);
    expect(still.id, open.id);
    expect(log.classes, hasLength(1));
    expect(still.isOpen, isTrue);
  });

  test('open model messages omit the previous class', () {
    final log = StudyLog(ids: _ids('class'));
    final start = DateTime(2026, 10, 4, 9);
    final first = log.ensureOpen(start);
    first.messages.add(
      ChatMessage(
        id: 'old-user',
        role: ChatRole.user,
        content: 'OLD_BUBBLE_should_not_leak',
      ),
    );
    first.messages.add(
      ChatMessage(
        id: 'old-assistant',
        role: ChatRole.assistant,
        content: 'OLD_REPLY_should_not_leak',
      ),
    );
    first.lastMessageAt = start;
    first.userTurns = 1;

    final second = log.ensureOpen(start.add(const Duration(hours: 2)));
    expect(first.isOpen, isFalse);
    expect(first.closeNote.split('\n'), hasLength(3));
    expect(second.id, isNot(first.id));
    second.messages.add(
      ChatMessage(
        id: 'new-user',
        role: ChatRole.user,
        content: 'NEW_BUBBLE_only',
      ),
    );

    final projected = log.openModelMessages();
    final blob = projected.map((message) => message['content']).join('\n');
    expect(blob.contains('OLD_BUBBLE_should_not_leak'), isFalse);
    expect(blob.contains('OLD_REPLY_should_not_leak'), isFalse);
    expect(blob.contains('NEW_BUBBLE_only'), isTrue);
    expect(
      projected.every(
        (message) =>
            message['role'] == 'user' || message['role'] == 'assistant',
      ),
      isTrue,
    );
  });

  test('closeIfFull opens the next class without dropping the sitting', () {
    final log = StudyLog(ids: _ids('class'));
    final now = DateTime(2026, 10, 4, 8);
    final open = log.ensureOpen(now);
    open.judged = 5;
    open.userTurns = 11;
    open.lastMessageAt = now;
    expect(log.closeIfFull(now), isFalse);
    expect(log.classes, hasLength(1));

    open.judged = 6;
    expect(log.closeIfFull(now), isTrue);
    expect(open.isOpen, isFalse);
    expect(log.classes, hasLength(2));
    expect(log.openClass, isNotNull);
    expect(log.openClass!.id, isNot(open.id));
    expect(log.currentSitting(now).map((item) => item.id), [
      open.id,
      log.openClass!.id,
    ]);
  });

  test('StudyClass round-trips messages and checkpoint', () {
    final started = DateTime(2026, 10, 4, 8, 15);
    final session = StudyClass(
      id: 'class-1',
      startedAt: started,
      closeNote: '最近练了：无\n最近一次：无\n下一到期：无',
      userTurns: 1,
      judged: 0,
      lastMessageAt: started,
      checkpoint: const ContextSummary(untilMessageId: 'u1', text: '要点'),
      messages: [ChatMessage(id: 'u1', role: ChatRole.user, content: 'hello')],
    );
    final restored = StudyClass.fromJson(session.toJson());
    expect(restored, isNotNull);
    expect(restored!.messages.single.content, 'hello');
    expect(restored.checkpoint!.text, '要点');
    expect(restored.userTurns, 1);
    expect(restored.lastMessageAt, started);
    expect(restored.isOpen, isTrue);
    expect(StudyClass.fromJson('x'), isNull);
    expect(StudyClass.fromJson({}), isNull);
  });
}

IdFactory _ids(String prefix) {
  var n = 0;
  return () {
    n += 1;
    return '$prefix-$n';
  };
}

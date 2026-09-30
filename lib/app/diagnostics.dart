import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../engine/chat_thread.dart';
import '../engine/lesson_store.dart';

/// Shareable diagnostic text for developers (no secrets).
String buildDiagnosticReport({
  required String appVersion,
  required LessonStore store,
  ChatThread? chat,
  String? connectionMessage,
  String? deepSeekBase,
  String? deepSeekModel,
}) {
  final buf = StringBuffer();
  buf.writeln('今日英语 诊断日志');
  buf.writeln('version: $appVersion');
  buf.writeln('builtAt: ${DateTime.now().toIso8601String()}');
  buf.writeln(
    'platform: ${kIsWeb ? 'web' : Platform.operatingSystem} '
    '${kIsWeb ? '' : Platform.operatingSystemVersion}'.trim(),
  );
  buf.writeln('installId: ${store.installId}');
  buf.writeln('level: ${store.level} (chosen=${store.levelChosen})');
  buf.writeln('dailyWords: ${store.dailyWords}');
  buf.writeln('goal: ${store.goal} · tone: ${store.tone}');
  buf.writeln('reasoningEffort: ${store.reasoningEffort}');
  if (deepSeekBase != null && deepSeekBase.isNotEmpty) {
    buf.writeln('deepSeekBase: $deepSeekBase');
  }
  if (deepSeekModel != null && deepSeekModel.isNotEmpty) {
    buf.writeln('deepSeekModel: $deepSeekModel');
  }
  if (connectionMessage != null && connectionMessage.isNotEmpty) {
    buf.writeln('connectionMessage: $connectionMessage');
  }
  buf.writeln('');
  buf.writeln('--- 进度摘要 ---');
  buf.writeln('today: ${store.today.toIso8601String().split('T').first}');
  buf.writeln('progress: ${store.progressRemainderLine()}');
  buf.writeln(
    'vocabDone=${store.vocabDone} sentencesDone=${store.sentencesDone} '
    'dialogueDone=${store.dialogueDone} rounds=${store.practiceRounds}',
  );
  buf.writeln('checkedIn=${store.checkedIn}');
  final plan = store.hasFrozenTodayPlan ? store.requiredTodayPlan : null;
  if (plan != null) {
    buf.writeln('todayNewWords: ${plan.newWordIds.length}');
  }
  buf.writeln('scheduledErrorsToday: ${store.scheduledErrors().length}');
  buf.writeln('');
  buf.writeln('--- 最近 API 调用 (callLog, 最多 30) ---');
  final calls = store.callLog;
  if (calls.isEmpty) {
    buf.writeln('(empty)');
  } else {
    final start = calls.length > 30 ? calls.length - 30 : 0;
    for (var i = start; i < calls.length; i++) {
      final c = calls[i];
      buf.writeln(
        '${i + 1}. task=${c['task']} ok=${c['ok']} '
        'finish=${c['finishReason']} tokens=${c['tokens']}',
      );
    }
  }
  buf.writeln('');
  buf.writeln('--- 聊天 ---');
  if (chat == null) {
    buf.writeln('(no chat)');
  } else {
    buf.writeln('messages: ${chat.messages.length}');
    if (chat.lastError != null && chat.lastError!.isNotEmpty) {
      buf.writeln('lastError: ${chat.lastError}');
    }
    if (chat.contextSummary != null) {
      buf.writeln(
        'checkpoint: empty=${chat.contextSummary!.isEmptyText}',
      );
    }
  }
  buf.writeln('');
  buf.writeln('(密钥未包含在本日志中)');
  return buf.toString();
}

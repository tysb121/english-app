import 'dart:convert';

import '../engine/chat_thread.dart';
import '../engine/lesson_store.dart';

const progressKind = 'english-app';

class ProgressShell {
  ProgressShell({required this.store, ChatThread? chat})
      : chat = chat ?? ChatThread();

  final LessonStore store;
  final ChatThread chat;

  String encode() {
    return jsonEncode({
      'kind': progressKind,
      'lesson': store.toJson(),
      'chat': chat.toJson(),
    });
  }

  void restore(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return;
    final map = decoded.map((key, value) => MapEntry(key.toString(), value));
    final lesson = map['lesson'];
    if (lesson is Map) {
      store.restore(jsonEncode(lesson));
      chat.restore(map['chat']);
      return;
    }
    // Legacy bare LessonStore JSON.
    store.restore(trimmed);
    chat.restore(null);
  }
}

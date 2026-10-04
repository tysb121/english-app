import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app_model.dart';
import 'app/coach_database.dart';
import 'app/progress_shell.dart';
import 'app/secrets.dart';
import 'data/cefr_core.dart';
import 'engine/lesson_store.dart';
import 'engine/chat_thread.dart';
import 'net/io_poster.dart';
import 'ui/english_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final secrets = await SecureSecrets().load();

  // Open DB first; skip full JSON/asset parse when wordbook already imported.
  final coachDb = await CoachDatabase.open();
  if (await coachDb.wordbookCount() == 0) {
    final book = await loadCefrCore();
    await coachDb.ensureWordbook(book.entries);
  }

  // Keep only user + hydrated book lexemes in RAM (not the full ~5k).
  final store = LessonStore();
  store.untaughtIdPicker =
      ({
        required String level,
        required int limit,
        required Set<String> exclude,
      }) {
        return coachDb.pickUntaughtIds(
          level: level,
          limit: limit,
          exclude: exclude,
        );
      };
  store.untaughtCountFn =
      ({required String level, required Set<String> exclude}) {
        return coachDb.untaughtCount(level: level, exclude: exclude);
      };
  store.bookWordsByIds = coachDb.wordsByIds;

  final shell = ProgressShell(store: store, chat: ChatThread());

  final hadSqlite = await coachDb.hasProgress();
  if (hadSqlite) {
    try {
      await coachDb.loadShell(shell);
    } on Object {
      // Keep fresh store if DB rows cannot be read.
    }
  } else {
    await coachDb.migrateLegacyJsonIfNeeded(shell);
  }

  // Freeze today's plan via SQL untaught pick before first frame.
  await store.ensureTodayPlanAsync();
  await store.hydrateBookWords(coachDb.wordsByIds);
  await store.refreshUntaughtInLevelCount();

  Timer? persistDebounce;
  late final AppModel model;
  Future<void> persist() async {
    try {
      await coachDb.saveShell(shell);
      await coachDb.saveStudyLog(model.classCoach.log);
    } on Object {
      // Disk errors must not roll back in-memory answers.
    }
  }

  void schedulePersist() {
    persistDebounce?.cancel();
    persistDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(persist());
    });
  }

  model = AppModel(
    store: store,
    poster: IoPoster(),
    chat: shell.chat,
    deepSeekKey: secrets.deepSeekKey,
    deepSeekBase: secrets.deepSeekBase,
    deepSeekModel: secrets.deepSeekModel,
    unlocked: secrets.deepSeekKey.trim().isNotEmpty,
    persistProgress: (_) {
      // Debounce full SQLite rewrites on rapid vocab taps.
      schedulePersist();
    },
    persistSecrets: SecureSecrets().save,
    persistStudy: schedulePersist,
  );
  try {
    model.adoptStudyLog(await coachDb.loadStudyLog());
  } on Object {
    // A missing or older study log starts a fresh class.
  }
  if (!hadSqlite) {
    await persist();
  }
  runApp(EnglishApp(model: model));
}

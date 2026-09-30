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
  final book = await loadCefrCore();
  final coachDb = await CoachDatabase.open(seedBook: book.entries);
  final fromDb = await coachDb.loadWordbook();
  final store = LessonStore(book: fromDb.isNotEmpty ? fromDb : book.entries);
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

  Future<void> persist() async {
    try {
      await coachDb.saveShell(shell);
    } on Object {
      // Disk errors must not roll back in-memory answers.
    }
  }

  final model = AppModel(
    store: store,
    poster: IoPoster(),
    chat: shell.chat,
    deepSeekKey: secrets.deepSeekKey,
    deepSeekBase: secrets.deepSeekBase,
    deepSeekModel: secrets.deepSeekModel,
    tokenHubKey: secrets.tokenHubKey,
    tokenHubBase: secrets.tokenHubBase,
    tokenHubModel: secrets.tokenHubModel,
    unlocked: secrets.deepSeekKey.trim().isNotEmpty,
    persistProgress: (_) {
      // Fire-and-forget; AppModel.commit already swallows sync errors.
      persist();
    },
    persistSecrets: SecureSecrets().save,
  );
  if (!hadSqlite) {
    await persist();
  }
  runApp(EnglishApp(model: model));
}

import 'package:flutter/material.dart';

import 'app/app_model.dart';
import 'app/local_progress.dart';
import 'app/progress_shell.dart';
import 'app/secrets.dart';
import 'engine/lesson_store.dart';
import 'engine/chat_thread.dart';
import 'net/io_poster.dart';
import 'ui/english_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final secrets = await SecureSecrets().load();
  final progress = await LocalProgress.open();
  final store = LessonStore();
  final shell = ProgressShell(store: store, chat: ChatThread());
  final saved = await progress.read();
  if (saved != null && saved.trim().isNotEmpty) {
    try {
      shell.restore(saved);
    } on Object {
      // Keep the fresh store when the file cannot be read.
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
    persistProgress: (ignored) => progress.save(shell.encode()),
    persistSecrets: SecureSecrets().save,
  );
  if (saved == null || saved.trim().isEmpty) {
    progress.save(shell.encode());
  }
  runApp(EnglishApp(model: model));
}

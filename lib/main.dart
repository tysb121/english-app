import 'package:flutter/material.dart';

import 'app/app_model.dart';
import 'app/local_progress.dart';
import 'app/secrets.dart';
import 'engine/lesson_store.dart';
import 'net/io_poster.dart';
import 'ui/english_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final secrets = await SecureSecrets().load();
  final progress = await LocalProgress.open();
  final store = LessonStore();
  final saved = await progress.read();
  if (saved != null && saved.trim().isNotEmpty) {
    try {
      store.restore(saved);
    } on Object {
      // Keep the fresh store when the file cannot be read.
    }
  }
  final model = AppModel(
    store: store,
    poster: IoPoster(),
    deepSeekKey: secrets.deepSeekKey,
    deepSeekBase: secrets.deepSeekBase,
    deepSeekModel: secrets.deepSeekModel,
    tokenHubKey: secrets.tokenHubKey,
    tokenHubBase: secrets.tokenHubBase,
    tokenHubModel: secrets.tokenHubModel,
    unlocked: secrets.deepSeekKey.trim().isNotEmpty,
    persistProgress: progress.save,
    persistSecrets: SecureSecrets().save,
  );
  if (saved == null || saved.trim().isEmpty) {
    progress.save(store.progressJson());
  }
  runApp(EnglishApp(model: model));
}

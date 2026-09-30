import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Legacy JSON progress file (read-only migration into SQLite).
class LocalProgress {
  LocalProgress(this.file);

  final File file;

  static Future<LocalProgress> open() async {
    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } on Object {
      // Linux smoke: path_provider may fail without XDG app dirs.
      final home = Platform.environment['HOME'] ?? '/tmp';
      dir = Directory('$home/.local/share/english_app');
    }
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return LocalProgress(
      File('${dir.path}${Platform.pathSeparator}english_progress.json'),
    );
  }

  Future<String?> read() async {
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  void save(String json) {
    file.writeAsString(json).ignore();
  }
}

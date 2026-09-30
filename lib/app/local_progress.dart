import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LocalProgress {
  LocalProgress(this.file);

  final File file;

  static Future<LocalProgress> open() async {
    final dir = await getApplicationDocumentsDirectory();
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

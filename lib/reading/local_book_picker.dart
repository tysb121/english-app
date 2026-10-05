import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'reader_library.dart';

/// System picker for a local txt or epub. Returns null when the learner backs out.
Future<PickedLocalBook?> pickLocalBookFile() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['txt', 'epub'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final name = file.name.trim();
  if (name.isEmpty) return null;
  var bytes = file.bytes;
  if (bytes == null) {
    final path = file.path;
    if (path == null || path.isEmpty) return null;
    bytes = await File(path).readAsBytes();
  }
  if (bytes.isEmpty) return null;
  return PickedLocalBook(name: name, bytes: bytes);
}

/// Prepare GitHub Release Markdown bodies for in-app update UI.
library;

/// Soften harsh shipping jargon users should not see raw.
const _harshFullApk = '完整 APK 更新（非增量）';
const _softFullApk = '本次需下载完整安装包。';

/// Keep GitHub Markdown (headers, bold, lists) for [MarkdownBody] rendering.
///
/// Softens「完整 APK 更新（非增量）」and drops trailing meta lines that repeat
/// the Flutter `version+build` (dialog already shows `vX.Y.Z`).
String formatReleaseNotesForDisplay(String raw) {
  var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (text.isEmpty) return '有新版本可用。';

  final out = <String>[];
  for (var line in text.split('\n')) {
    final trimmed = line.trimRight();
    final stripped = trimmed.trim();
    if (stripped.isEmpty) {
      if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
      continue;
    }

    // Drop whole-line version meta — dialog already shows the tag.
    if (_isVersionMetaLine(stripped)) continue;

    // Soften full-APK shipping line; drop any trailing「版本：…」on same line.
    if (stripped.contains(_harshFullApk)) {
      out.add(_softFullApk);
      continue;
    }

    out.add(trimmed);
  }

  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  final joined = out.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return joined.isEmpty ? '有新版本可用。' : joined;
}

bool _isVersionMetaLine(String trimmed) {
  final onlyVersion = RegExp(
    r'^版本\s*[：:]\s*`?v?\d+(?:\.\d+)*(?:\+\d+)?`?\s*[。．]?$',
  );
  if (onlyVersion.hasMatch(trimmed)) return true;
  final onlyBuild = RegExp(r'^`?v?\d+\.\d+\.\d+\+\d+`?\s*[。．]?$');
  return onlyBuild.hasMatch(trimmed);
}

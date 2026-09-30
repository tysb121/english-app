/// Plain-text formatting of GitHub Release bodies for in-app update UI.
library;

/// Soften harsh shipping jargon users should not see raw.
const _harshFullApk = '完整 APK 更新（非增量）';
const _softFullApk = '本次需下载完整安装包。';

/// Turn GitHub Markdown release notes into readable plain Chinese bullets.
///
/// Strips headings (`##`), bold (`**`), backticks, and trailing meta lines
/// that repeat the Flutter `version+build`. Softens「完整 APK 更新（非增量）」.
String formatReleaseNotesForDisplay(String raw) {
  var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (text.isEmpty) return '有新版本可用。';

  final out = <String>[];
  for (var line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
      continue;
    }

    // Drop whole-line version meta — dialog already shows the tag.
    if (_isVersionMetaLine(trimmed)) continue;

    var s = _stripInlineMarkdown(trimmed);

    // Soften full-APK shipping line; drop any trailing「版本：…」on same line.
    if (s.contains(_harshFullApk)) {
      s = _softFullApk;
      out.add(s);
      continue;
    }

    // ATX headings → plain title line (no ##).
    final heading = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(s);
    if (heading != null) {
      final title = heading.group(1)!.trim();
      if (title.isNotEmpty) out.add(title);
      continue;
    }

    // Unordered list markers → Chinese-friendly bullet.
    final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(s);
    if (bullet != null) {
      out.add('• ${bullet.group(1)!.trim()}');
      continue;
    }

    // Ordered list: keep number.
    final ordered = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(s);
    if (ordered != null) {
      out.add('${ordered.group(1)}. ${ordered.group(2)!.trim()}');
      continue;
    }

    out.add(s);
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

String _stripInlineMarkdown(String s) {
  var out = s;
  out = out.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!);
  out = out.replaceAllMapped(RegExp(r'__(.+?)__'), (m) => m.group(1)!);
  out = out.replaceAllMapped(
    RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)'),
    (m) => m.group(1)!,
  );
  out = out.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1)!);
  out = out.replaceAll('`', '');
  out = out.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (m) => m.group(1)!,
  );
  return out.trim();
}

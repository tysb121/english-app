import 'dart:convert';

/// Parsed GitHub Releases `/releases/latest` payload (fields we care about).
class GithubRelease {
  const GithubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.apkName,
    required this.apkDownloadUrl,
    this.apkSize,
  });

  final String tagName;
  final String name;
  final String body;
  final String apkName;
  final String apkDownloadUrl;
  final int? apkSize;

  String get displayTitle {
    final t = name.trim();
    if (t.isNotEmpty) return t;
    return tagName;
  }
}

/// Parse GitHub release JSON. Returns null if no `.apk` asset is present.
GithubRelease? parseGithubReleaseJson(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final map = Map<String, dynamic>.from(decoded);

  final tag = (map['tag_name'] as String?)?.trim() ?? '';
  if (tag.isEmpty) return null;

  final name = (map['name'] as String?)?.trim() ?? '';
  final body = (map['body'] as String?)?.trim() ?? '';

  final assets = map['assets'];
  if (assets is! List) return null;

  Map<String, dynamic>? apk;
  for (final item in assets) {
    if (item is! Map) continue;
    final m = Map<String, dynamic>.from(item);
    final assetName = (m['name'] as String?) ?? '';
    if (assetName.toLowerCase().endsWith('.apk')) {
      apk = m;
      break;
    }
  }
  if (apk == null) return null;

  final url = (apk['browser_download_url'] as String?)?.trim() ?? '';
  if (url.isEmpty) return null;
  final apkName = (apk['name'] as String?)?.trim() ?? 'update.apk';
  final size = apk['size'];
  final apkSize = size is int ? size : (size is num ? size.toInt() : null);

  return GithubRelease(
    tagName: tag,
    name: name,
    body: body,
    apkName: apkName,
    apkDownloadUrl: url,
    apkSize: apkSize,
  );
}

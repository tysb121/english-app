/// Semver-ish helpers for GitHub release tags vs pubspec version names.
///
/// Convention: GitHub Release tags must be `vX.Y.Z` (optional leading `v`),
/// and the `X.Y.Z` part must match the version **name** in `pubspec.yaml`
/// (`version: X.Y.Z+build`). Build number (`+N`) is not compared against tags.
library;

/// Strip optional leading `v`/`V` and optional `+build`, return `X.Y.Z`.
String normalizeVersionName(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  if (s.startsWith('v') || s.startsWith('V')) {
    s = s.substring(1).trim();
  }
  final plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus);
  return s.trim();
}

/// Parse `1.2.3` / `1.2` / `1` into integer parts (missing → 0).
List<int> versionParts(String name) {
  final n = normalizeVersionName(name);
  if (n.isEmpty) return const [0, 0, 0];
  final bits = n.split('.');
  final out = <int>[];
  for (final b in bits) {
    out.add(int.tryParse(b.trim()) ?? 0);
  }
  while (out.length < 3) {
    out.add(0);
  }
  return out;
}

/// Compare two version names. Returns negative if [a] < [b], 0 if equal,
/// positive if [a] > [b]. Extra segments beyond 3 are compared too.
int compareVersionNames(String a, String b) {
  final pa = versionParts(a);
  final pb = versionParts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final ai = i < pa.length ? pa[i] : 0;
    final bi = i < pb.length ? pb[i] : 0;
    if (ai != bi) return ai.compareTo(bi);
  }
  return 0;
}

/// True when [remoteTag] is strictly newer than [localVersionName].
bool isRemoteNewer({
  required String remoteTag,
  required String localVersionName,
}) {
  return compareVersionNames(remoteTag, localVersionName) > 0;
}

/// User-facing label: always `vX.Y.Z` (no `+build`). Empty → empty.
String formatDisplayVersion(String raw) {
  final name = normalizeVersionName(raw);
  if (name.isEmpty) return '';
  return 'v$name';
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'github_release.dart';
import 'version.dart';

const kGithubLatestReleaseUrl =
    'https://api.github.com/repos/tysb121/english-app/releases/latest';

const _prefsLastCheckKey = 'update_last_check_ms';
const _softCheckInterval = Duration(days: 1);

/// Outcome of a non-throwing update check.
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable(this.release, this.localVersion);
  final GithubRelease release;
  final String localVersion;
}

class UpdateUpToDate extends UpdateCheckResult {
  const UpdateUpToDate(this.localVersion, {this.remoteTag});
  final String localVersion;
  final String? remoteTag;
}

class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed(this.message);
  final String message;
}

class UpdateNoRelease extends UpdateCheckResult {
  const UpdateNoRelease(this.localVersion);
  final String localVersion;
}

typedef ProgressFn = void Function(int received, int? total);

class AppUpdateChecker {
  AppUpdateChecker({
    this.latestUrl = kGithubLatestReleaseUrl,
    this._client,
    Future<PackageInfo> Function()? packageInfoLoader,
  }) : _packageInfoLoader =
            packageInfoLoader ?? PackageInfo.fromPlatform;

  final String latestUrl;
  final HttpClient? _client;
  final Future<PackageInfo> Function() _packageInfoLoader;

  Future<String> currentVersionName() async {
    final info = await _packageInfoLoader();
    return info.version;
  }

  /// Soft launch check: at most once per day. Returns null when skipped.
  Future<UpdateCheckResult?> softCheckIfDue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_prefsLastCheckKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < _softCheckInterval.inMilliseconds) {
        return null;
      }
      final result = await checkLatest();
      await prefs.setInt(_prefsLastCheckKey, now);
      return result;
    } on Object {
      return null;
    }
  }

  Future<UpdateCheckResult> checkLatest() async {
    try {
      final local = await currentVersionName();
      final raw = await _get(latestUrl);
      if (raw == null) {
        return const UpdateCheckFailed('无法连接更新服务，请稍后再试');
      }
      if (raw.statusCode == 404) {
        return UpdateNoRelease(local);
      }
      if (raw.statusCode != 200) {
        return UpdateCheckFailed('检查更新失败（${raw.statusCode}）');
      }
      final release = parseGithubReleaseJson(raw.body);
      if (release == null) {
        return UpdateNoRelease(local);
      }
      if (isRemoteNewer(
        remoteTag: release.tagName,
        localVersionName: local,
      )) {
        return UpdateAvailable(release, local);
      }
      return UpdateUpToDate(local, remoteTag: release.tagName);
    } on Object {
      return const UpdateCheckFailed('检查更新失败，请稍后再试');
    }
  }

  /// Download APK to cache and open the system installer. Null = success.
  Future<String?> downloadAndInstall(
    GithubRelease release, {
    ProgressFn? onProgress,
  }) async {
    try {
      Directory dir;
      try {
        dir = await getTemporaryDirectory();
      } on Object {
        dir = Directory.systemTemp;
      }
      final out = File(
        '${dir.path}${Platform.pathSeparator}${release.apkName}',
      );
      final ok = await _download(
        release.apkDownloadUrl,
        out,
        onProgress: onProgress,
      );
      if (!ok) return '下载失败，请稍后再试';
      if (!Platform.isAndroid) {
        return '请在安卓手机上安装更新包';
      }
      final result = await OpenFilex.open(
        out.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        final msg = result.message.trim();
        return msg.isEmpty ? '无法打开安装程序' : msg;
      }
      return null;
    } on Object {
      return '下载或安装失败，请稍后再试';
    }
  }

  Future<_HttpBody?> _get(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return null;
    final owned = _client == null;
    final client = _client ?? HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'english-app-update');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));
      return _HttpBody(response.statusCode, body);
    } on Object {
      return null;
    } finally {
      if (owned) client.close(force: true);
    }
  }

  Future<bool> _download(
    String url,
    File dest, {
    ProgressFn? onProgress,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    final owned = _client == null;
    final client = _client ?? HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 30));
      request.headers.set(HttpHeaders.userAgentHeader, 'english-app-update');
      request.followRedirects = true;
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final total = response.contentLength >= 0 ? response.contentLength : null;
      final sink = dest.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.flush();
        await sink.close();
      } on Object {
        try {
          await sink.close();
        } on Object {
          // ignore
        }
        if (dest.existsSync()) {
          try {
            dest.deleteSync();
          } on Object {
            // ignore
          }
        }
        return false;
      }
      return dest.existsSync() && dest.lengthSync() > 0;
    } on Object {
      return false;
    } finally {
      if (owned) client.close(force: true);
    }
  }
}

class _HttpBody {
  const _HttpBody(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

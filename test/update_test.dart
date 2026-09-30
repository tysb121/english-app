import 'dart:io';

import 'package:english_app/update/github_release.dart';
import 'package:english_app/update/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeVersionName', () {
    test('strips v prefix and +build', () {
      expect(normalizeVersionName('v1.2.3'), '1.2.3');
      expect(normalizeVersionName('V1.0.0'), '1.0.0');
      expect(normalizeVersionName('1.0.0+12'), '1.0.0');
      expect(normalizeVersionName(' v2.0.0+1 '), '2.0.0');
    });
  });

  group('compareVersionNames', () {
    test('orders semver-ish triples', () {
      expect(compareVersionNames('1.0.0', '1.0.1'), lessThan(0));
      expect(compareVersionNames('1.0.1', '1.0.0'), greaterThan(0));
      expect(compareVersionNames('v1.0.0', '1.0.0'), 0);
      expect(compareVersionNames('1.0.0+9', 'v1.0.0'), 0);
      expect(compareVersionNames('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersionNames('2.0', '1.9.9'), greaterThan(0));
    });

    test('isRemoteNewer', () {
      expect(
        isRemoteNewer(remoteTag: 'v1.0.1', localVersionName: '1.0.0'),
        isTrue,
      );
      expect(
        isRemoteNewer(remoteTag: 'v1.0.0', localVersionName: '1.0.0'),
        isFalse,
      );
      expect(
        isRemoteNewer(remoteTag: 'v1.0.0', localVersionName: '1.0.1'),
        isFalse,
      );
    });
  });

  group('parseGithubReleaseJson', () {
    test('parses fixture and picks first apk asset', () {
      final raw = File('test/fixtures/github_release_latest.json').readAsStringSync();
      final release = parseGithubReleaseJson(raw);
      expect(release, isNotNull);
      expect(release!.tagName, 'v1.0.1');
      expect(release.name, '今日英语 1.0.1');
      expect(release.body, contains('修复更新检查'));
      expect(release.apkName, 'english-app-v1.0.1.apk');
      expect(
        release.apkDownloadUrl,
        'https://github.com/tysb121/english-app/releases/download/v1.0.1/english-app-v1.0.1.apk',
      );
      expect(release.apkSize, 23456789);
      expect(release.displayTitle, '今日英语 1.0.1');
    });

    test('returns null without apk asset', () {
      const raw = '''
{"tag_name":"v1.0.0","name":"x","body":"","assets":[{"name":"a.zip","browser_download_url":"https://x/a.zip"}]}
''';
      expect(parseGithubReleaseJson(raw), isNull);
    });

    test('returns null on bad json', () {
      expect(parseGithubReleaseJson('not-json'), isNull);
      expect(parseGithubReleaseJson('[]'), isNull);
      expect(parseGithubReleaseJson('{"assets":[]}'), isNull);
    });
  });
}

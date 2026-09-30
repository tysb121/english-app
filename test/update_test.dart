import 'dart:io';

import 'package:english_app/update/github_release.dart';
import 'package:english_app/update/release_notes.dart';
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

  group('formatDisplayVersion', () {
    test('always vX.Y.Z without build', () {
      expect(formatDisplayVersion('1.0.4+5'), 'v1.0.4');
      expect(formatDisplayVersion('v1.0.4'), 'v1.0.4');
      expect(formatDisplayVersion('1.0.4'), 'v1.0.4');
      expect(formatDisplayVersion(' V1.0.0+9 '), 'v1.0.0');
      expect(formatDisplayVersion(''), '');
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

  group('formatReleaseNotesForDisplay', () {
    test('keeps markdown and softens full-APK line from real v1.0.4 body', () {
      const raw = '''
## 改动
- **新手首页词卡**：今日词默认全亮展示英文 + 中文 + 词性（EN+CN 完整呈现）
- **「看过了」记账**：勾选框或点整卡只记「看过了」，不再靠点才揭英文
- **一行进度**：去掉顶部三枚胶囊，改为一行 `还差：还没看× / 还没用× / 还差×轮`（完成则「今日练习完成」）
- 软文案：「看一眼，再跟教练聊几句就行。」

完整 APK 更新（非增量）。版本：`1.0.4+5`
''';
      final notes = formatReleaseNotesForDisplay(raw);
      expect(notes, contains('## 改动'));
      expect(notes, contains('- **新手首页词卡**：'));
      expect(notes, contains('**「看过了」记账**'));
      expect(notes, contains('`还差：还没看×'));
      expect(notes, isNot(contains('•')));
      expect(notes, isNot(contains('1.0.4+5')));
      expect(notes, isNot(contains('非增量')));
      expect(notes, contains('本次需下载完整安装包。'));
      expect(notes.split('\n').first, '## 改动');
    });

    test('empty body falls back', () {
      expect(formatReleaseNotesForDisplay(''), '有新版本可用。');
      expect(formatReleaseNotesForDisplay('   '), '有新版本可用。');
    });

    test('drops standalone version meta lines', () {
      const raw = '版本：`1.0.4+5`\n- 修复闪退';
      final notes = formatReleaseNotesForDisplay(raw);
      expect(notes, isNot(contains('1.0.4+5')));
      expect(notes, '- 修复闪退');
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

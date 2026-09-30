import 'package:flutter/material.dart';

import 'github_release.dart';
import 'update_checker.dart';
import '../ui/theme.dart';

/// Run a manual「检查更新」from settings. Never throws.
Future<void> runManualUpdateCheck(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    const SnackBar(content: Text('正在检查更新…'), duration: Duration(seconds: 2)),
  );
  final checker = AppUpdateChecker();
  final result = await checker.checkLatest();
  if (!context.mounted) return;
  messenger.hideCurrentSnackBar();
  switch (result) {
    case UpdateAvailable(:final release, :final localVersion):
      await showUpdateDialog(
        context,
        release: release,
        localVersion: localVersion,
        checker: checker,
      );
    case UpdateUpToDate(:final localVersion):
      messenger.showSnackBar(
        SnackBar(content: Text('已是最新版本（$localVersion）')),
      );
    case UpdateNoRelease(:final localVersion):
      messenger.showSnackBar(
        SnackBar(content: Text('暂无发布版本（当前 $localVersion）')),
      );
    case UpdateCheckFailed(:final message):
      messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Soft check after home shell mounts. Only prompts when an update exists.
Future<void> runSoftUpdateCheck(BuildContext context) async {
  final checker = AppUpdateChecker();
  final result = await checker.softCheckIfDue();
  if (result == null || !context.mounted) return;
  if (result is UpdateAvailable) {
    await showUpdateDialog(
      context,
      release: result.release,
      localVersion: result.localVersion,
      checker: checker,
    );
  }
}

Future<void> showUpdateDialog(
  BuildContext context, {
  required GithubRelease release,
  required String localVersion,
  required AppUpdateChecker checker,
}) async {
  final notes = release.body.trim().isEmpty ? '有新版本可用。' : release.body.trim();
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return _UpdateDialog(
        release: release,
        localVersion: localVersion,
        notes: notes,
        checker: checker,
      );
    },
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({
    required this.release,
    required this.localVersion,
    required this.notes,
    required this.checker,
  });

  final GithubRelease release;
  final String localVersion;
  final String notes;
  final AppUpdateChecker checker;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double? _progress; // null = indeterminate
  String? _error;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = null;
      _error = null;
    });
    final err = await widget.checker.downloadAndInstall(
      widget.release,
      onProgress: (received, total) {
        if (!mounted) return;
        if (total == null || total <= 0) {
          setState(() => _progress = null);
        } else {
          setState(() => _progress = received / total);
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _progress = null;
      _error = err;
    });
    if (err == null) {
      // Installer opened; close dialog.
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('发现新版本 ${widget.release.tagName}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '当前 ${widget.localVersion}',
              style: const TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Text(widget.notes, style: const TextStyle(fontSize: 14, height: 1.4)),
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                _progress == null
                    ? '正在下载…'
                    : '正在下载 ${(_progress! * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: wrongRed, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.of(context).pop(),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: _downloading ? null : _download,
          child: Text(_downloading ? '下载中' : '下载更新'),
        ),
      ],
    );
  }
}

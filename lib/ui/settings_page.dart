import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../app/app_model.dart';
import '../app/diagnostics.dart';
import '../engine/lesson_store.dart';
import 'english_app.dart';
import 'theme.dart';
import '../update/update_ui.dart';
import '../update/version.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.gate = false});

  final bool gate;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _key = TextEditingController();
  late final TextEditingController _base = TextEditingController();
  late final TextEditingController _modelName = TextEditingController();
  String? _message;
  bool _busy = false;
  bool _filled = false;
  bool _obscureDeepSeek = true;
  String _appVersion = '…';
  String _diagnosticVersion = '未知';

  static const _levels = productLevels;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        // Users see vX.Y.Z only; +build stays in diagnostic export.
        _appVersion = formatDisplayVersion(info.version);
        _diagnosticVersion = '${info.version}+${info.buildNumber}';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _appVersion = '未知';
        _diagnosticVersion = '未知';
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final model = AppScope.of(context);
    _key.text = model.deepSeekKey;
    _base.text = model.deepSeekBase;
    _modelName.text = model.deepSeekModel;
  }

  @override
  void dispose() {
    _key.dispose();
    _base.dispose();
    _modelName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final store = model.store;
    final showStart = widget.gate && model.connectionOk && model.hasDeepSeekKey;
    final level = normalizeLevel(store.level);
    return SoftScaffold(
      title: widget.gate ? '连接密钥' : '我的',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (widget.gate) ...[
            const Text(
              '填写 DeepSeek 密钥后，教练才能回复和轻纠错。也可以先浏览界面。',
              style: TextStyle(color: ink, fontSize: 14),
            ),
            const SizedBox(height: 12),
          ],
          const SectionTitle('DeepSeek 密钥', icon: Icons.key_rounded),
          TextField(
            controller: _key,
            obscureText: _obscureDeepSeek,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: '粘贴密钥',
              suffixIcon: IconButton(
                tooltip: _obscureDeepSeek ? '显示' : '隐藏',
                icon: Icon(
                  _obscureDeepSeek
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscureDeepSeek = !_obscureDeepSeek),
              ),
            ),
          ),
          ExpansionTile(
            title: const Text('高级'),
            children: [
              TextField(
                controller: _base,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  hintText: 'https://api.deepseek.com',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _modelName,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(hintText: 'deepseek-flash'),
              ),
            ],
          ),
          if (showStart)
            FilledButton(onPressed: model.unlock, child: const Text('开始练习'))
          else
            FilledButton(
              onPressed: _busy ? null : () => _test(model),
              child: Text(_busy ? '正在测试' : '测试连接'),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _message!,
                style: TextStyle(color: _statusColor(_message!), fontSize: 16),
              ),
            ),
          if (!showStart)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : () => _saveDeepSeek(model),
                child: const Text('保存'),
              ),
            ),
          if (widget.gate && !showStart)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: model.browseWithoutKey,
                child: const Text('先看看，稍后再填密钥'),
              ),
            ),
          if (!widget.gate) ...[
            const SizedBox(height: 16),
            const SectionTitle('水平', icon: Icons.stairs_outlined),
            _choices<String>(
              values: _levels,
              label: (value) => value,
              selected: level,
              onPick: (value) {
                store.level = value;
                model.commit();
              },
            ),
            const SizedBox(height: 16),
            const SectionTitle('目标', icon: Icons.flag_outlined),
            _choices<String>(
              values: const ['职场', '日常', '考试', '都要'],
              label: (value) => value,
              selected: store.goal,
              onPick: (value) {
                store.goal = value;
                model.commit();
              },
            ),
            const SizedBox(height: 16),
            const SectionTitle('关于与数据', icon: Icons.info_outline_rounded),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('版本'),
              subtitle: Text(_appVersion),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('检查更新'),
              subtitle: const Text('查看是否有新版本可安装'),
              trailing: const Icon(Icons.system_update_alt_rounded),
              onTap: () => runManualUpdateCheck(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('导出日志'),
              subtitle: const Text('生成可发给开发者的诊断文本（不含密钥）'),
              trailing: const Icon(Icons.ios_share_rounded),
              onTap: _busy ? null : () => _exportLogs(model),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('清除数据重来'),
              subtitle: const Text('清空练习进度与聊天，保留密钥、水平和目标'),
              trailing: const Icon(
                Icons.delete_outline_rounded,
                color: wrongRed,
              ),
              onTap: _busy ? null : () => _confirmClear(model),
            ),
          ],
          const SizedBox(height: 28),
          Text(
            _deviceRecordHint,
            style: const TextStyle(color: ink, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _choices<T>({
    required List<T> values,
    required String Function(T value) label,
    required T selected,
    required void Function(T value) onPick,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          ChoiceChip(
            label: Text(label(value)),
            selected: value == selected,
            onSelected: (_) => onPick(value),
          ),
      ],
    );
  }

  void _saveDeepSeek(AppModel model) {
    final error = model.updateDeepSeek(
      key: _key.text,
      base: _base.text,
      modelName: _modelName.text,
    );
    setState(() => _message = error);
  }

  Future<void> _test(AppModel model) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final error = model.updateDeepSeek(
      key: _key.text,
      base: _base.text,
      modelName: _modelName.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _message = error;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = '正在测试';
    });
    final message = await model.testConnection();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
  }

  Future<void> _exportLogs(AppModel model) async {
    setState(() => _busy = true);
    try {
      final report = buildDiagnosticReport(
        appVersion: _diagnosticVersion,
        store: model.store,
        chat: model.chat,
        connectionMessage: model.connectionMessage,
        deepSeekBase: model.deepSeekBase,
        deepSeekModel: model.deepSeekModel,
      );
      await Clipboard.setData(ClipboardData(text: report));
      String? path;
      try {
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}${Platform.pathSeparator}english_app_diagnostics.txt',
        );
        await file.writeAsString(report, flush: true);
        path = file.path;
        await OpenFilex.open(path);
      } on Object {
        // Clipboard alone is enough.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(path == null ? '诊断日志已复制' : '诊断日志已复制，并尝试打开文件')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmClear(AppModel model) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除数据重来？'),
        content: const Text('将清空练习进度与教练聊天。密钥、水平和目标会保留。此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await model.clearLocalLearning();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清除，可以重新开始练习')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

String get _deviceRecordHint {
  final mobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (mobile) return '学习记录只保存在这台手机上，卸载应用会一并删除。';
  return '学习记录只保存在本机，清除应用数据会删除。';
}

Color _statusColor(String message) {
  if (message == '已连通' || message == '正在测试' || message.startsWith('已连通')) {
    return pine;
  }
  return wrongRed;
}

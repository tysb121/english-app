import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../engine/lesson_store.dart';
import '../engine/reasoning_effort.dart';
import 'english_app.dart';
import 'theme.dart';

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
  late final TextEditingController _translateKey = TextEditingController();
  late final TextEditingController _translateBase = TextEditingController();
  late final TextEditingController _translateModel = TextEditingController();
  String? _message;
  bool _busy = false;
  bool _filled = false;

  static const _levels = ['新手', '简单工作对话', '更长的表达'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final model = AppScope.of(context);
    _key.text = model.deepSeekKey;
    _base.text = model.deepSeekBase;
    _modelName.text = model.deepSeekModel;
    _translateKey.text = model.tokenHubKey;
    _translateBase.text = model.tokenHubBase;
    _translateModel.text = model.tokenHubModel;
  }

  @override
  void dispose() {
    _key.dispose();
    _base.dispose();
    _modelName.dispose();
    _translateKey.dispose();
    _translateBase.dispose();
    _translateModel.dispose();
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
              '填写 DeepSeek 密钥后才能生成场景和批改。也可以先看看界面。',
              style: TextStyle(color: ink, fontSize: 14),
            ),
            const SizedBox(height: 12),
          ],
          const SectionTitle('DeepSeek 密钥', icon: Icons.key_rounded),
          TextField(
            controller: _key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(hintText: '粘贴密钥'),
          ),
          ExpansionTile(
            title: const Text('高级'),
            children: [
              TextField(
                controller: _base,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(hintText: 'https://api.deepseek.com'),
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
            FilledButton(onPressed: model.unlock, child: const Text('开始今天'))
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
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('参考翻译密钥'),
            children: [
              TextField(
                controller: _translateKey,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(hintText: '不填也能开始'),
              ),
              ExpansionTile(
                title: const Text('高级'),
                children: [
                  TextField(
                    controller: _translateBase,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      hintText: 'https://tokenhub.tencentmaas.com/v1',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _translateModel,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(hintText: 'hy-mt2-plus'),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _saveTokenHub(model),
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
          if (!widget.gate) ...[
            const SizedBox(height: 16),
            const SectionTitle('每天新词', icon: Icons.numbers_rounded),
            _choices<int>(
              values: const [5, 10, 15, 20],
              label: (value) => '$value',
              selected: store.dailyWords,
              onPick: (value) {
                store.dailyWords = value;
                model.commit();
              },
            ),
            const SizedBox(height: 16),
            const SectionTitle('水平', icon: Icons.stairs_outlined),
            _choices<String>(
              values: _levels,
              label: (value) => value,
              selected: level,
              onPick: (value) {
                store.level = value;
                model.commit();
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            Text(
              store.hasFrozenTodayPlan
                  ? '今天的计划已定，改水平与词数从明天生效。'
                  : '已经开始的今天不变，这些改动从明天生效。',
              style: const TextStyle(color: muted, fontSize: 13),
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
            const SectionTitle('语气', icon: Icons.chat_outlined),
            _choices<String>(
              values: const ['简洁', '朋友', '老师'],
              label: (value) => value,
              selected: store.tone,
              onPick: (value) {
                store.tone = value;
                model.commit();
              },
            ),
            const SizedBox(height: 16),
            const SectionTitle('思考强度', icon: Icons.psychology_outlined),
            _choices<String>(
              values: reasoningEfforts,
              label: reasoningEffortLabel,
              selected: normalizeReasoningEffort(store.reasoningEffort),
              onPick: (value) {
                store.reasoningEffort = normalizeReasoningEffort(value);
                model.commit();
              },
            ),
            const SizedBox(height: 8),
            const Text(
              '关闭则不展示思考过程。中/高会调用 DeepSeek thinking（medium 按接口映射为 high）。',
              style: TextStyle(color: ink, fontSize: 12),
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

  void _saveTokenHub(AppModel model) {
    final error = model.updateTokenHub(
      key: _translateKey.text,
      base: _translateBase.text,
      modelName: _translateModel.text,
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
}

String get _deviceRecordHint {
  final mobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (mobile) return '学习记录只在这台手机上，卸载即删除。';
  return '学习记录只在本机，清除应用数据会删除。';
}

Color _statusColor(String message) {
  if (message == '已连通' || message == '正在测试') return pine;
  return wrongRed;
}

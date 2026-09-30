import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../engine/lesson_store.dart';
import 'english_app.dart';
import 'practice_page.dart';
import 'theme.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  bool _showNotes = false;
  bool _autoOpened = false;
  List<StudyNote> _drafts = [];

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final store = model.store;
    final plan = store.ensureTodayPlan();
    if (!_autoOpened && store.checkedIn && !store.notesDismissed) {
      _autoOpened = true;
      _showNotes = true;
      _drafts = [...store.noteDrafts()];
    }
    final preview = plan.newWordIds.take(2).toList();
    final rest = [
      ...plan.newWordIds.skip(2),
      ...plan.reviewWordIds,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('今日英语')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Wrap(
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(store.formatDay(store.today)),
                  const Text('连续'),
                  Text('${store.streak()}'),
                  if (store.checkedIn) const Text('已完成'),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                children: [
                  _dot('认词', store.vocabThresholdMet),
                  _dot('对话', store.dialogueDone),
                  _dot('考核', store.quizGate),
                ],
              ),
              const SizedBox(height: 8),
              Text('场景：${_sceneStatus(store)}', style: const TextStyle(color: ink)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _openPrimary(context, model),
                child: Text(store.homeActionLabel()),
              ),
              if (plan.errorWordIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _open(context, PracticeKind.errors),
                    child: Text('错词 ${plan.errorWordIds.length}'),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              for (final id in preview) _card(store, id),
              if (rest.isNotEmpty)
                ExpansionTile(
                  title: Text('其余 ${rest.length} 个'),
                  children: [for (final id in rest) _card(store, id)],
                ),
            ],
          ),
          if (_showNotes) HalfSheet(child: _notes(model)),
        ],
      ),
    );
  }

  Widget _notes(AppModel model) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_drafts.isEmpty) const Text('今天没有要记的句子'),
        for (var i = 0; i < _drafts.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${_drafts[i].wrong} → ${_drafts[i].corrected} → ${_drafts[i].whyCn}',
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _drafts.removeAt(i)),
                child: const Text('去掉'),
              ),
            ],
          ),
        FilledButton(
          onPressed: () {
            model.store.confirmNotes(_drafts);
            model.commit();
            setState(() => _showNotes = false);
          },
          child: const Text('保存'),
        ),
        TextButton(
          onPressed: () {
            model.store.skipNotes();
            model.commit();
            setState(() => _showNotes = false);
          },
          child: const Text('跳过'),
        ),
      ],
    );
  }

  Widget _card(LessonStore store, String id) {
    final word = store.word(id);
    if (word == null) return const SizedBox.shrink();
    return Card(
      color: Colors.white,
      child: ListTile(
        title: Text(word.en),
        subtitle: Text('${word.cn} · ${word.pos}'),
      ),
    );
  }

  Widget _dot(String label, bool on) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          on ? Icons.circle : Icons.circle_outlined,
          size: 14,
          color: on ? pine : ink,
        ),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }

  String _sceneStatus(LessonStore store) {
    if (store.sceneInFlight && store.scene == null) return '生成中';
    if (store.scene == null) return '未生成';
    return '已生成';
  }

  void _openPrimary(BuildContext context, AppModel model) {
    final label = model.store.homeActionLabel();
    if (label == '看今天的笔记') {
      setState(() {
        _drafts = model.store.notesDismissed && model.store.savedNotes.isNotEmpty
            ? [...model.store.savedNotes]
            : [...model.store.noteDrafts()];
        _showNotes = true;
      });
      return;
    }
    final kind = switch (label) {
      '开始对话' || '继续对话' || '正在写今天的场景' => PracticeKind.dialogue,
      '开始考核' => PracticeKind.quiz,
      _ => PracticeKind.vocab,
    };
    _open(context, kind);
  }

  void _open(BuildContext context, PracticeKind kind) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PracticePage(kind: kind)),
    );
  }
}

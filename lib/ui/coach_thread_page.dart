import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../engine/chat_message.dart';
import '../engine/lesson_store.dart';
import 'english_app.dart';
import 'theme.dart';

/// Single coach thread: vocab → scene → dialogue → quiz → errors → notes.
class CoachThreadPage extends StatefulWidget {
  const CoachThreadPage({super.key, this.readOnly = false});

  final bool readOnly;

  @override
  State<CoachThreadPage> createState() => _CoachThreadPageState();
}

class _CoachThreadPageState extends State<CoachThreadPage> {
  final _controller = TextEditingController();
  final Map<String, TextEditingController> _vocabInputs = {};
  final List<_Bubble> _local = [];
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    for (final controller in _vocabInputs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final store = model.store;
    store.ensureTodayPlan();
    final stage = _stage(store);
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日英语'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                if (model.chat?.contextSummary != null &&
                    !model.chat!.contextSummary!.isEmptyText)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      '更早的对话已收成检查点',
                      style: TextStyle(fontSize: 12, color: Color(0xFF4E4A43)),
                    ),
                  ),
                for (final bubble in _local) _bubble(bubble),
                if (model.chat != null)
                  for (final message in model.chat!.messages)
                    _bubble(
                      _Bubble(
                        role: message.role == ChatRole.user
                            ? _BubbleRole.user
                            : _BubbleRole.coach,
                        text: message.content,
                      ),
                    ),
                ..._stageBody(model, store, stage),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_status!, style: const TextStyle(color: Color(0xFF8E2F2F))),
                  ),
              ],
            ),
          ),
          if (!widget.readOnly && _allowsInput(stage))
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: !_busy,
                        decoration: const InputDecoration(hintText: '输入英文或中文'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : () => _onSend(model, stage),
                      child: Text(_busy ? '…' : '发送'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _stageBody(AppModel model, LessonStore store, _Stage stage) {
    switch (stage) {
      case _Stage.vocab:
        return [_vocabBlock(model, store)];
      case _Stage.scene:
        return [
          const Text('接下来写今天的场景。'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : () => _fillScene(model),
            child: Text(_busy ? '写入中' : '生成场景'),
          ),
        ];
      case _Stage.dialogue:
        return [_dialogueBlock(store)];
      case _Stage.quiz:
        return [_quizBlock(model, store)];
      case _Stage.errors:
        return [_errorsBlock(model, store)];
      case _Stage.notes:
        return [_notesBlock(model, store)];
      case _Stage.done:
        return const [Text('今天已完成。关闭回到今天。')];
    }
  }

  Widget _vocabBlock(AppModel model, LessonStore store) {
    final ids = store.vocabQueue(store.ensureTodayPlan());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '用英文写出下面的说法（本地比对，忽略大小写）',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        for (final id in ids) ...[
          Text(store.word(id)?.cn ?? id),
          TextField(
            controller: _vocabInputs.putIfAbsent(id, TextEditingController.new),
            enabled: !widget.readOnly && !_busy,
            decoration: const InputDecoration(hintText: '英文'),
          ),
          const SizedBox(height: 10),
        ],
        FilledButton(
          onPressed: widget.readOnly || _busy
              ? null
              : () => _submitVocab(model, store, ids),
          child: const Text('提交认词'),
        ),
      ],
    );
  }

  Widget _dialogueBlock(LessonStore store) {
    final scene = store.ensureTodayPlan().scene;
    if (scene == null) return const SizedBox.shrink();
    final cursor = store.ensureTodayPlan().dialogueCursor;
    final line = scene.dialogue.isEmpty
        ? null
        : scene.dialogue[cursor.clamp(0, scene.dialogue.length - 1)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(scene.scenarioCn, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (line != null) ...[
          Text('${line.speaker}: ${line.en}'),
          Text(line.cn, style: const TextStyle(color: Color(0xFF4E4A43))),
          const SizedBox(height: 8),
          const Text('用英文接一句，发送后交给批改。'),
        ],
        TextButton(
          onPressed: widget.readOnly
              ? null
              : () {
                  store.markDialogueDone();
                  AppScope.of(context).commit();
                  setState(() {});
                },
          child: const Text('对话做完了'),
        ),
      ],
    );
  }

  Widget _quizBlock(AppModel model, LessonStore store) {
    final index = store.openQuizIndex;
    if (index == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('考核进度 ${store.quizPassCount}/4'),
          if (store.quizPassCount < 3)
            FilledButton(
              onPressed: () {
                store.redoFailedQuiz();
                model.commit();
                setState(() {});
              },
              child: const Text('重做未过的题'),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('考核 ${index + 1}/4'),
        Text(store.quizPrompt(index)),
        const SizedBox(height: 8),
        const Text('在底部输入框作答并发送。'),
      ],
    );
  }

  Widget _errorsBlock(AppModel model, LessonStore store) {
    final plan = store.ensureTodayPlan();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('到期错词（最多 3 条）'),
        for (final id in plan.errorWordIds)
          Text('${store.word(id)?.en ?? id} · ${store.word(id)?.cn ?? ''}'),
        FilledButton(
          onPressed: () {
            for (final id in [...plan.errorWordIds]) {
              final word = store.word(id);
              if (word == null) continue;
              store.submitErrorReview(id, word.en);
            }
            model.commit();
            setState(() {});
          },
          child: const Text('我已看过错词'),
        ),
      ],
    );
  }

  Widget _notesBlock(AppModel model, LessonStore store) {
    final drafts = store.noteDrafts();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('笔记草稿（可保存或跳过）'),
        for (final note in drafts)
          Text('${note.wrong} → ${note.corrected}（${note.whyCn}）'),
        Row(
          children: [
            FilledButton(
              onPressed: () {
                store.confirmNotes(drafts);
                model.commit();
                setState(() {});
              },
              child: const Text('保存'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                store.skipNotes();
                model.commit();
                setState(() {});
              },
              child: const Text('跳过'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submitVocab(
    AppModel model,
    LessonStore store,
    List<String> ids,
  ) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    for (final id in ids) {
      var guard = 0;
      while (store.currentVocabId != null &&
          store.currentVocabId != id &&
          guard < 40) {
        store.advanceVocab();
        guard += 1;
      }
      if (store.currentVocabId != id) continue;
      final answer = _vocabInputs[id]?.text ?? '';
      final feedback = store.submitVocab(answer);
      if (feedback != null) {
        _local.add(
          _Bubble(
            role: _BubbleRole.coach,
            text: feedback.correct
                ? '✓ ${feedback.correctEn}'
                : '✗ 正确是 ${feedback.correctEn}',
          ),
        );
      }
      store.advanceVocab();
    }
    model.commit();
    if (!store.vocabThresholdMet) {
      _status = '认词未到通过线。错的明天再出现；对话和考核仍可继续，今天不打卡。';
    }
    setState(() => _busy = false);
  }

  Future<void> _fillScene(AppModel model) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    final err = await model.fillScene();
    if (err != null) _status = err;
    model.commit();
    setState(() => _busy = false);
  }

  Future<void> _onSend(AppModel model, _Stage stage) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final store = model.store;
    setState(() {
      _busy = true;
      _status = null;
    });
    if (stage == _Stage.quiz) {
      final index = store.openQuizIndex;
      if (index != null) {
        final err = await model.gradeQuiz(index, text);
        _controller.clear();
        if (err != null) _status = err;
        model.commit();
        setState(() => _busy = false);
        return;
      }
    }
    if (stage == _Stage.dialogue) {
      final scene = store.ensureTodayPlan().scene;
      final cursor = store.ensureTodayPlan().dialogueCursor;
      final line = scene?.dialogue.isNotEmpty == true
          ? scene!.dialogue[cursor.clamp(0, scene.dialogue.length - 1)]
          : null;
      final words = store
          .scheduledNewWords()
          .map((id) => store.word(id)?.en ?? id)
          .join(', ');
      final err = await model.gradeLine(
        prompt: '用英文接话',
        requiredWords: '要表达的意思：${line?.cn ?? ''}。今天的词：$words',
        answer: text,
      );
      _controller.clear();
      if (err != null) {
        _status = err;
      } else {
        final grade = store.lastGrade;
        if (grade != null) {
          _local.add(
            _Bubble(
              role: _BubbleRole.coach,
              text: grade.pass
                  ? '通过。${grade.correctedEn}'
                  : grade.errors
                      .take(2)
                      .map((e) => '${e.excerpt} → ${e.fix}（${e.whyCn}）')
                      .join('\n'),
            ),
          );
        }
        store.advanceDialogue();
        model.commit();
      }
      setState(() => _busy = false);
      return;
    }
    final chat = model.chat;
    if (chat == null) {
      setState(() {
        _busy = false;
        _status = '聊天未就绪';
      });
      return;
    }
    final err = await chat.send(
      text: text,
      poster: model.poster,
      apiKey: model.deepSeekKey,
      baseUrl: model.deepSeekBase,
      model: model.deepSeekModel,
      installId: store.installId,
    );
    _controller.clear();
    if (err != null) _status = err;
    model.commit();
    setState(() => _busy = false);
  }

  _Stage _stage(LessonStore store) {
    final plan = store.ensureTodayPlan();
    if (!store.vocabThresholdMet) return _Stage.vocab;
    if (plan.scene == null) return _Stage.scene;
    if (!plan.dialogueDone) return _Stage.dialogue;
    if (!store.quizGate) return _Stage.quiz;
    if (plan.errorWordIds.isNotEmpty) return _Stage.errors;
    if (!store.notesDismissed) return _Stage.notes;
    return _Stage.done;
  }

  bool _allowsInput(_Stage stage) =>
      stage == _Stage.dialogue || stage == _Stage.quiz;

  Widget _bubble(_Bubble bubble) {
    final mine = bubble.role == _BubbleRole.user;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? pine.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3DDD2)),
        ),
        child: Text(bubble.text, style: const TextStyle(color: ink)),
      ),
    );
  }
}

enum _Stage { vocab, scene, dialogue, quiz, errors, notes, done }

enum _BubbleRole { user, coach }

class _Bubble {
  final _BubbleRole role;
  final String text;
  const _Bubble({required this.role, required this.text});
}

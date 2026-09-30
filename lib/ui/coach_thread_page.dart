import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../engine/chat_message.dart';
import '../engine/lesson_store.dart';
import 'english_app.dart';
import 'theme.dart';
import 'thinking_panel.dart';

/// Single coach thread: vocab → sentences → scene → dialogue → errors → notes.
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
  Future<void> Function()? _retry;

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
    final stage = _stage(store);
    final sceneLoading = (_busy && stage == _Stage.scene) || store.sceneInFlight;
    return SoftScaffold(
      title: widget.readOnly ? '回看今天' : '今日教练',
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                if (model.chat?.contextSummary != null &&
                    !model.chat!.contextSummary!.isEmptyText)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.bookmark_outline_rounded, size: 16, color: pine),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              '更早的对话已收成检查点',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final bubble in _local) _bubble(bubble),
                if (model.chat != null)
                  for (var i = 0; i < model.chat!.messages.length; i++)
                    CoachAnswerBubble(
                      mine: model.chat!.messages[i].role == ChatRole.user,
                      content: model.chat!.messages[i].content,
                      reasoning: model.chat!.messages[i].reasoning,
                      streaming: model.chat!.streamingIndex == i,
                      usageTokens: model.chat!.messages[i].usageTokens,
                      elapsedMs: model.chat!.messages[i].elapsedMs,
                      finishedAt: model.chat!.messages[i].finishedAt,
                    ),
                ..._stageBody(model, store, stage, sceneLoading: sceneLoading),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _status!,
                            style: const TextStyle(color: wrongRed),
                          ),
                        ),
                        if (_retry != null && !widget.readOnly)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    final action = _retry;
                                    if (action == null) return;
                                    await action();
                                  },
                            child: const Text('重试'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (!widget.readOnly && _allowsInput(stage))
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: mist.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: softBorder),
                    boxShadow: [
                      BoxShadow(
                        color: indigo.withValues(alpha: 0.06),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              hintText: '输入英文或中文',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _onSend(model, stage),
                          icon: Icon(
                            _busy ? Icons.hourglass_top_rounded : Icons.send_rounded,
                            size: 18,
                          ),
                          label: Text(_busy ? '批改中' : '发送'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _stageBody(
    AppModel model,
    LessonStore store,
    _Stage stage, {
    required bool sceneLoading,
  }) {
    switch (stage) {
      case _Stage.vocab:
        return [_vocabBlock(model, store)];
      case _Stage.sentences:
        return [_sentencesBlock(model, store)];
      case _Stage.scene:
        return [_sceneBlock(model, sceneLoading: sceneLoading)];
      case _Stage.dialogue:
        return [_dialogueBlock(store)];
      case _Stage.errors:
        return [_errorsBlock(model, store)];
      case _Stage.notes:
        return [_notesBlock(model, store)];
      case _Stage.done:
        return const [Text('今天已完成。关闭回到今天。')];
    }
  }

  Widget _keyCta(String why) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(why, style: const TextStyle(color: ink)),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭后到「我的」填写密钥'),
        ),
      ],
    );
  }

  Widget _sceneBlock(AppModel model, {required bool sceneLoading}) {
    if (!model.hasDeepSeekKey) {
      return _keyCta('生成场景需要 DeepSeek 密钥。');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('接下来写今天的场景。'),
        const SizedBox(height: 8),
        if (sceneLoading) ...[
          const Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('正在写今天的场景…'),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '可以离开，回来仍停在这一步。',
            style: TextStyle(fontSize: 13, color: Color(0xFF4E4A43)),
          ),
        ] else
          FilledButton(
            onPressed: widget.readOnly || _busy
                ? null
                : () => _fillScene(model),
            child: const Text('生成场景'),
          ),
      ],
    );
  }

  Widget _vocabBlock(AppModel model, LessonStore store) {
    final ids = store.vocabQueue(store.requiredTodayPlan);
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
    final scene = store.requiredTodayPlan.scene;
    if (scene == null) return const SizedBox.shrink();
    final cursor = store.requiredTodayPlan.dialogueCursor;
    final line = scene.dialogue.isEmpty
        ? null
        : scene.dialogue[cursor.clamp(0, scene.dialogue.length - 1)];
    final model = AppScope.of(context);
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
        if (!model.hasDeepSeekKey) ...[
          const SizedBox(height: 8),
          _keyCta('对话批改需要 DeepSeek 密钥。'),
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

  Widget _sentencesBlock(AppModel model, LessonStore store) {
    final plan = store.requiredTodayPlan;
    final total = plan.newWordIds.length;
    final done = store.sentenceDoneCount;
    final wordId = store.currentSentenceWordId;
    final word = wordId == null ? null : store.word(wordId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '造句 ${done.clamp(0, total)}/$total',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const Text(
          '每个新词造一句；批改后才算做完，不能跳过。',
          style: TextStyle(fontSize: 13, color: Color(0xFF4E4A43)),
        ),
        const SizedBox(height: 8),
        if (wordId != null) ...[
          Text(store.sentencePrompt(wordId)),
          if (word != null)
            Text(
              '${word.en} · ${word.cn} · ${word.pos}',
              style: const TextStyle(color: Color(0xFF4E4A43)),
            ),
          const SizedBox(height: 8),
          const Text('在底部输入框造句并发送。'),
        ] else
          const Text('今天的造句已做完。'),
        if (!model.hasDeepSeekKey) ...[
          const SizedBox(height: 8),
          _keyCta('造句批改需要 DeepSeek 密钥。'),
        ],
      ],
    );
  }

  Widget _errorsBlock(AppModel model, LessonStore store) {
    final plan = store.requiredTodayPlan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '到期错词（最多 3 条）',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const Text(
          '这些是认错或到期的词，排在短对话之后再练。',
          style: TextStyle(fontSize: 13, color: Color(0xFF4E4A43)),
        ),
        const SizedBox(height: 8),
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
        const Text(
          '笔记草稿',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const Text(
          '可保存或跳过；跳过仍算今天完成。',
          style: TextStyle(fontSize: 13, color: Color(0xFF4E4A43)),
        ),
        const SizedBox(height: 8),
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
              child: const Text('跳过（仍算今天完成）'),
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
      _retry = null;
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
      _status = '认词未到通过线。错的明天再出现；造句和对话仍可继续，今天不打卡。';
    }
    setState(() => _busy = false);
  }

  Future<void> _fillScene(AppModel model) async {
    setState(() {
      _busy = true;
      _status = null;
      _retry = () => _fillScene(model);
    });
    final err = await model.fillScene();
    if (err != null) {
      _status = err;
    } else {
      _retry = null;
    }
    model.commit();
    setState(() => _busy = false);
  }

  Future<void> _onSend(AppModel model, _Stage stage) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final store = model.store;
    if (!model.hasDeepSeekKey &&
        (stage == _Stage.dialogue || stage == _Stage.sentences)) {
      setState(() {
        _status = '需要 DeepSeek 密钥才能批改。关闭后到「我的」填写。';
        _retry = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    if (stage == _Stage.sentences) {
      final wordId = store.currentSentenceWordId;
      if (wordId != null) {
        final total = store.requiredTodayPlan.newWordIds.length;
        final ordinal = store.sentenceDoneCount + 1;
        _local.add(_Bubble(role: _BubbleRole.user, text: text));
        final err = await model.gradeSentence(wordId, text);
        _controller.clear();
        if (err != null) {
          _status = err;
          _retry = () async {
            _controller.text = text;
            await _onSend(model, stage);
          };
        } else {
          _retry = null;
          final grade = store.lastGrade;
          if (grade != null) {
            _local.add(
              _Bubble(
                role: _BubbleRole.coach,
                text: grade.pass
                    ? '✓ 通过（造句 $ordinal/$total）\n${grade.correctedEn}'
                    : '✗ 未通过（造句 $ordinal/$total，仍算做完）\n'
                        '${grade.errors.take(2).map((e) => '${e.excerpt} → ${e.fix}（${e.whyCn}）').join('\n')}\n'
                        '改写：${grade.correctedEn}',
              ),
            );
          }
        }
        model.commit();
        setState(() => _busy = false);
        return;
      }
    }
    if (stage == _Stage.dialogue) {
      final scene = store.requiredTodayPlan.scene;
      final cursor = store.requiredTodayPlan.dialogueCursor;
      final line = scene?.dialogue.isNotEmpty == true
          ? scene!.dialogue[cursor.clamp(0, scene.dialogue.length - 1)]
          : null;
      final words = store
          .scheduledNewWords()
          .map((id) => store.word(id)?.en ?? id)
          .join(', ');
      _local.add(_Bubble(role: _BubbleRole.user, text: text));
      final err = await model.gradeLine(
        prompt: '用英文接话',
        requiredWords: '要表达的意思：${line?.cn ?? ''}。今天的词：$words',
        answer: text,
      );
      _controller.clear();
      if (err != null) {
        _status = err;
        _retry = () async {
          _controller.text = text;
          await _onSend(model, stage);
        };
      } else {
        _retry = null;
        final grade = store.lastGrade;
        if (grade != null) {
          _local.add(
            _Bubble(
              role: _BubbleRole.coach,
              text: grade.pass
                  ? '✓ 通过\n${grade.correctedEn}\n可以继续下一句。'
                  : '✗ 未通过，对照后再接下一句\n'
                      '${grade.errors.take(2).map((e) => '${e.excerpt} → ${e.fix}（${e.whyCn}）').join('\n')}\n'
                      '改写：${grade.correctedEn}',
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
      reasoningEffort: store.reasoningEffort,
      onUpdate: () {
        if (mounted) {
          model.tick();
          setState(() {});
        }
      },
    );
    _controller.clear();
    if (err != null) {
      _status = err;
      _retry = () async {
        _controller.text = text;
        await _onSend(model, stage);
      };
    } else {
      _retry = null;
    }
    model.commit();
    setState(() => _busy = false);
  }

  _Stage _stage(LessonStore store) {
    final plan = store.requiredTodayPlan;
    if (!store.vocabThresholdMet) return _Stage.vocab;
    if (!store.sentencesDone) return _Stage.sentences;
    if (plan.scene == null) return _Stage.scene;
    if (!plan.dialogueDone) return _Stage.dialogue;
    if (plan.errorWordIds.isNotEmpty) return _Stage.errors;
    if (!store.notesDismissed) return _Stage.notes;
    return _Stage.done;
  }

  bool _allowsInput(_Stage stage) =>
      stage == _Stage.sentences ||
      stage == _Stage.dialogue ||
      stage == _Stage.errors ||
      stage == _Stage.notes ||
      stage == _Stage.done;

  Widget _bubble(_Bubble bubble) {
    return CoachAnswerBubble(
      mine: bubble.role == _BubbleRole.user,
      content: bubble.text,
    );
  }
}

enum _Stage { vocab, sentences, scene, dialogue, errors, notes, done }

enum _BubbleRole { user, coach }

class _Bubble {
  final _BubbleRole role;
  final String text;
  const _Bubble({required this.role, required this.text});
}

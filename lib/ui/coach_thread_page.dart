import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../engine/chat_message.dart';
import '../engine/lesson_store.dart';
import '../engine/pos_label.dart';
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
  final List<_Bubble> _local = [];
  String? _status;
  bool _busy = false;
  Future<void> Function()? _retry;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final store = model.store;
    final stage = _stage(store);
    final sceneLoading = (_busy && stage == _Stage.scene) || store.sceneInFlight;
    return SoftScaffold(
      title: widget.readOnly ? '回看今天' : _titleFor(store, stage),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
      body: Column(
        children: [
          if (!widget.readOnly &&
              (stage == _Stage.sentences || stage == _Stage.dialogue))
            _stepTopBar(store, stage),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (stage == _Stage.sentences) _todayWordChips(store),
                    if (stage == _Stage.dialogue &&
                        store.requiredTodayPlan.dialogueCursor == 0)
                      _dialogueOpeningChips(store),
                    DecoratedBox(
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
                                decoration: InputDecoration(
                                  hintText: stage == _Stage.sentences
                                      ? '写一句英文就能进下一步'
                                      : stage == _Stage.dialogue &&
                                              store.requiredTodayPlan
                                                      .dialogueCursor ==
                                                  0
                                          ? '接一句，或点上方开口'
                                          : '输入英文或中文',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            FilledButton.icon(
                              onPressed:
                                  _busy ? null : () => _onSend(model, stage),
                              icon: Icon(
                                _busy
                                    ? Icons.hourglass_top_rounded
                                    : Icons.send_rounded,
                                size: 18,
                              ),
                              label: Text(_busy ? '批改中' : '发送'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
    final plan = store.requiredTodayPlan;
    final queue = store.vocabQueue(plan);
    final total = queue.length;
    final id = store.currentVocabId;
    final word = id == null ? null : store.word(id);
    final doneCount = plan.vocabCursor.clamp(0, total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '认词 ${doneCount.clamp(0, total)}/$total',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const Text(
          '看一眼今天的词：英文、中文和词性。不用默写。',
          style: TextStyle(fontSize: 13, color: Color(0xFF4E4A43)),
        ),
        const SizedBox(height: 16),
        if (word == null)
          const Text('今天的词都看过了。')
        else ...[
          Text(
            word.en,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            word.cn,
            style: const TextStyle(fontSize: 18, color: Color(0xFF4E4A43)),
          ),
          const SizedBox(height: 4),
          Text(
            posLabelZh(word.pos),
            style: const TextStyle(fontSize: 14, color: Color(0xFF4E4A43)),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: widget.readOnly || _busy
                ? null
                : () => _acknowledgeVocab(model, store),
            child: const Text('认识了'),
          ),
        ],
      ],
    );
  }

  Widget _dialogueBlock(LessonStore store) {
    final scene = store.requiredTodayPlan.scene;
    if (scene == null) return const SizedBox.shrink();
    final cursor = store.requiredTodayPlan.dialogueCursor;
    final total = scene.dialogue.length;
    final line = scene.dialogue.isEmpty
        ? null
        : scene.dialogue[cursor.clamp(0, scene.dialogue.length - 1)];
    final model = AppScope.of(context);
    final firstTurn = cursor == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(scene.scenarioCn, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          total == 0 ? '对话' : '对话 ${(cursor + 1).clamp(1, total)}/$total',
          style: const TextStyle(fontSize: 13, color: Color(0xFF4E4A43)),
        ),
        const SizedBox(height: 8),
        if (line != null) ...[
          Text('${line.speaker}: ${line.en}'),
          Text(line.cn, style: const TextStyle(color: Color(0xFF4E4A43))),
          const SizedBox(height: 8),
          Text(
            firstTurn
                ? '第一句：可点下方开口，或自己写一句接上。'
                : '用英文接一句，发送后交给批改。',
            style: const TextStyle(fontSize: 13, color: Color(0xFF4E4A43)),
          ),
          if (firstTurn) ...[
            const SizedBox(height: 8),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                _dialogueSentenceSlot(store, line),
                style: const TextStyle(fontSize: 14, color: muted),
              ),
            ),
          ],
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
          '写一句就能进下一步；点输入框上方的今天词可填入。',
          style: TextStyle(fontSize: 13, color: Color(0xFF4E4A43)),
        ),
        const SizedBox(height: 8),
        if (wordId != null) ...[
          Text(store.sentencePrompt(wordId)),
          if (word != null)
            Text(
              '${word.en} · ${word.cn} · ${posLabelZh(word.pos)}',
              style: const TextStyle(color: Color(0xFF4E4A43)),
            ),
          const SizedBox(height: 6),
          Text(
            store.sentenceHintDirection(wordId),
            style: const TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 8),
          const Text(
            '在底部输入框写一句并发送。',
            style: TextStyle(fontSize: 13, color: Color(0xFF4E4A43)),
          ),
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

  void _acknowledgeVocab(AppModel model, LessonStore store) {
    final feedback = store.acknowledgeVocab();
    if (feedback != null) {
      _local.add(
        _Bubble(
          role: _BubbleRole.coach,
          text: '已看过 ${feedback.correctEn}',
        ),
      );
    }
    store.advanceVocab();
    model.commit();
    setState(() {
      _status = null;
      _retry = null;
    });
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
                    ? '这句可以 · 造句 $ordinal/$total\n${grade.correctedEn}'
                    : '对照一下 · 造句 $ordinal/$total（已记下，可继续）\n'
                        '${grade.errors.take(2).map((e) => '${e.excerpt} → ${e.fix}（${e.whyCn}）').join('\n')}\n'
                        '改写：${grade.correctedEn}',
              ),
            );
            _flashProgress('造句 $ordinal/$total');
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
        final totalLines = scene?.dialogue.length ?? 0;
        final turn = (cursor + 1).clamp(1, totalLines == 0 ? 1 : totalLines);
        if (grade != null) {
          _local.add(
            _Bubble(
              role: _BubbleRole.coach,
              text: grade.pass
                  ? '这句可以 · 对话 $turn/${totalLines == 0 ? turn : totalLines}\n${grade.correctedEn}'
                  : '对照一下 · 对话 $turn/${totalLines == 0 ? turn : totalLines}（可继续下一句）\n'
                      '${grade.errors.take(2).map((e) => '${e.excerpt} → ${e.fix}（${e.whyCn}）').join('\n')}\n'
                      '改写：${grade.correctedEn}',
            ),
          );
          _flashProgress(
            '对话 $turn/${totalLines == 0 ? turn : totalLines}',
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
    if (store.currentVocabId != null || !store.vocabDone) return _Stage.vocab;
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

  String _titleFor(LessonStore store, _Stage stage) {
    final plan = store.requiredTodayPlan;
    switch (stage) {
      case _Stage.vocab:
        final total = store.vocabQueue(plan).length;
        final done = plan.vocabCursor.clamp(0, total);
        return '认词 $done/$total';
      case _Stage.sentences:
        final total = plan.newWordIds.length;
        final done = store.sentenceDoneCount.clamp(0, total);
        return '今天词 / 造句 $done/$total';
      case _Stage.scene:
        return '写场景';
      case _Stage.dialogue:
        final total = plan.scene?.dialogue.length ?? 0;
        final cur = plan.dialogueCursor.clamp(0, total);
        if (total == 0) return '对话';
        return '对话 ${(cur + 1).clamp(1, total)}/$total';
      case _Stage.errors:
        return '错词';
      case _Stage.notes:
        return '笔记';
      case _Stage.done:
        return '今天完成';
    }
  }

  Widget _stepTopBar(LessonStore store, _Stage stage) {
    final plan = store.requiredTodayPlan;
    final words = <Widget>[
      for (final id in plan.newWordIds)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: stage == _Stage.sentences && !_busy
                ? () => _insertIntoInput(store.word(id)?.en ?? id)
                : null,
            child: Text(
              store.word(id)?.en ?? id,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: stage == _Stage.sentences &&
                        id == store.currentSentenceWordId
                    ? pine
                    : muted,
                decoration: stage == _Stage.sentences
                    ? TextDecoration.underline
                    : TextDecoration.none,
                decorationColor: softBorder,
              ),
            ),
          ),
        ),
    ];
    String progress;
    if (stage == _Stage.sentences) {
      final total = plan.newWordIds.length;
      final done = store.sentenceDoneCount.clamp(0, total);
      progress = '造句 $done/$total';
    } else {
      final total = plan.scene?.dialogue.length ?? 0;
      final cur = plan.dialogueCursor;
      progress = total == 0
          ? '对话'
          : '对话 ${(cur + 1).clamp(1, total)}/$total';
    }
    return Material(
      color: mist.withValues(alpha: 0.9),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Row(
          children: [
            const Text(
              '今天词',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: pine),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: words),
              ),
            ),
            Text(
              progress,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _todayWordChips(LessonStore store) {
    final plan = store.requiredTodayPlan;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final id in plan.newWordIds)
            ActionChip(
              label: Text(store.word(id)?.en ?? id),
              onPressed: _busy
                  ? null
                  : () => _insertIntoInput(store.word(id)?.en ?? id),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
    );
  }

  Widget _dialogueOpeningChips(LessonStore store) {
    final openings = store.dialogueOpeningHints();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '可选开口（点一下填入）',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final opening in openings)
                ActionChip(
                  label: Text(opening),
                  onPressed: _busy ? null : () => _insertIntoInput(opening),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _dialogueSentenceSlot(LessonStore store, SceneLine line) {
    final word = store.scheduledNewWords()
        .map(store.word)
        .whereType<Lexeme>()
        .map((w) => w.en)
        .take(1)
        .toList();
    final hintWord = word.isEmpty ? '…' : word.first;
    return '句子槽：________（可用 $hintWord）· 对方在说「${line.cn}」';
  }

  void _insertIntoInput(String piece) {
    final text = _controller.text;
    final needsSpace = text.isNotEmpty && !text.endsWith(' ');
    final next = '$text${needsSpace ? ' ' : ''}$piece';
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() {});
  }

  void _flashProgress(String label) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(label),
        duration: const Duration(milliseconds: 1200),
      ),
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

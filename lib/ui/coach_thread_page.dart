import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../engine/api_requests.dart';
import '../engine/chat_message.dart';
import '../engine/lesson_store.dart';
import '../engine/pos_label.dart';
import 'english_app.dart';
import 'theme.dart';
import 'thinking_panel.dart';

/// Single coach chat for the day: 懂了 + 用过 + rounds, no stage switching.
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
  bool _closingShown = false;
  bool _showPhraseChips = false;
  Future<void> Function()? _retry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final model = AppScope.of(context);
      final chatEmpty = model.chat == null || model.chat!.messages.isEmpty;
      if (chatEmpty && _local.isEmpty) {
        setState(() {
          _local.add(
            const _Bubble(
              role: _BubbleRole.coach,
              text: '今天要练这几个词。先点「懂了」看一眼，再试着在对话里用上——聊几轮就行。',
            ),
          );
        });
      }
      _maybeShowClosing(model.store);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final store = model.store;
    final checkedIn = store.checkedIn;
    return SoftScaffold(
      title: widget.readOnly
          ? '回看练习'
          : (checkedIn ? '今日练习完成' : '跟教练练习'),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
      body: Column(
        children: [
          if (!widget.readOnly) _progressBar(store),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                if (!widget.readOnly) ...[
                  _wordMiniCards(model, store),
                  const SizedBox(height: 8),
                ],
                if (model.chat?.contextSummary != null &&
                    !model.chat!.contextSummary!.isEmptyText)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.bookmark_outline_rounded,
                            size: 16,
                            color: pine,
                          ),
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
                if (!model.hasDeepSeekKey && !widget.readOnly) ...[
                  const SizedBox(height: 8),
                  _keyCta('跟教练对话需要 DeepSeek 密钥。点「懂了」可以先看今天的词。'),
                ],
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
          if (!widget.readOnly && !checkedIn)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _todayWordChips(store),
                    _quickReplyChips(store),
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
                                decoration: const InputDecoration(
                                  hintText: '用今天的词写一句，或点上方提示',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            FilledButton.icon(
                              onPressed: _busy ? null : () => _onSend(model),
                              icon: Icon(
                                _busy
                                    ? Icons.hourglass_top_rounded
                                    : Icons.send_rounded,
                                size: 18,
                              ),
                              label: Text(_busy ? '回复中' : '发送'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!widget.readOnly && checkedIn)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('回到今日练习'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _progressBar(LessonStore store) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              store.progressRemainderLine(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: muted,
              ),
            ),
          ),
          Text(
            '轮 ${store.practiceRounds}/$targetPracticeRounds',
            style: const TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _wordMiniCards(AppModel model, LessonStore store) {
    final plan = store.requiredTodayPlan;
    final count = plan.newWordIds.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 32;
        const gap = 8.0;
        // Prefer ~3 per row so ~5 words show fully in two short rows.
        final cols = count <= 3 ? (count == 0 ? 1 : count) : 3;
        final width = ((maxW - gap * (cols - 1)) / cols).clamp(96.0, 200.0);
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final id in plan.newWordIds)
                SizedBox(
                  width: width,
                  child: _miniCard(model, store, id),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _miniCard(AppModel model, LessonStore store, String id) {
    final word = store.word(id);
    if (word == null) return const SizedBox.shrink();
    final seen = store.vocabSeen(id);
    final used = store.wordUsed(id);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: mist,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: used
              ? pine.withValues(alpha: 0.35)
              : seen
                  ? pine.withValues(alpha: 0.18)
                  : softBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              word.en,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${word.cn} · ${posLabelZh(word.pos)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: muted),
            ),
            const SizedBox(height: 4),
            if (!seen)
              GestureDetector(
                onTap: widget.readOnly || _busy
                    ? null
                    : () => _onUnderstood(model, store, id),
                child: Text(
                  '懂了',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: widget.readOnly || _busy ? muted : pine,
                  ),
                ),
              )
            else
              _statusChip(used ? '已用' : '已懂', filled: used),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, {required bool filled}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? pine.withValues(alpha: 0.14) : indigo.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: filled ? pine : muted,
        ),
      ),
    );
  }

  Widget _todayWordChips(LessonStore store) {
    final plan = store.requiredTodayPlan;
    final openings = store.dialogueOpeningHints();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: plan.newWordIds.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final id = plan.newWordIds[i];
                  final used = store.wordUsed(id);
                  return ActionChip(
                    label: Text(
                      store.word(id)?.en ?? id,
                      style: TextStyle(
                        color: used ? pine : ink,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: _busy ? null : () => _insertWordChip(store, id),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  );
                },
              ),
            ),
          ),
          if (openings.isNotEmpty) ...[
            const SizedBox(width: 4),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _busy
                  ? null
                  : () => setState(() => _showPhraseChips = !_showPhraseChips),
              child: Text(
                _showPhraseChips ? '收起提示' : '例句提示',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickReplyChips(LessonStore store) {
    if (!_showPhraseChips) return const SizedBox.shrink();
    final openings = store.dialogueOpeningHints();
    if (openings.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: openings.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final opening = openings[i];
            return ActionChip(
              label: Text(opening, style: const TextStyle(fontSize: 12)),
              onPressed: _busy ? null : () => _insertIntoInput(opening),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            );
          },
        ),
      ),
    );
  }

  Widget _keyCta(String why) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(why, style: const TextStyle(color: ink)),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('去「我的」填写密钥'),
        ),
      ],
    );
  }

  Widget _bubble(_Bubble bubble) {
    return CoachAnswerBubble(
      mine: bubble.role == _BubbleRole.user,
      content: bubble.text,
    );
  }

  void _onUnderstood(AppModel model, LessonStore store, String id) {
    final feedback = store.acknowledgeWord(id);
    if (feedback != null) {
      _local.add(
        _Bubble(
          role: _BubbleRole.coach,
          text: '已看过 ${feedback.correctEn}',
        ),
      );
    }
    model.commit();
    setState(() {
      _status = null;
      _retry = null;
    });
    _maybeShowClosing(store);
  }

  void _insertWordChip(LessonStore store, String id) {
    final en = store.word(id)?.en ?? id;
    store.markWordUsed(id);
    _insertIntoInput(en);
    AppScope.of(context).commit();
    setState(() {});
    _maybeShowClosing(store);
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

  Future<void> _onSend(AppModel model) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await _sendOrRetry(model, text: text, isRetry: false);
  }

  Future<void> _sendOrRetry(
    AppModel model, {
    required String text,
    required bool isRetry,
  }) async {
    final store = model.store;
    if (!model.hasDeepSeekKey) {
      setState(() {
        _status = '需要 DeepSeek 密钥才能对话。请到「我的」填写。';
        _retry = null;
      });
      return;
    }
    final chat = model.chat;
    if (chat == null) {
      setState(() {
        _status = '聊天未就绪';
        _retry = null;
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
    });

    // Local ledger: 用过 from text match (chip insert already marked).
    store.markWordsUsedInText(text);
    model.commit();

    final wordLines = store.scheduledNewWords().map((id) {
      final w = store.word(id);
      if (w == null) return id;
      return '${w.en}（${w.cn}）';
    }).toList();
    final system = coachPracticeSystemPrompt(
      todayWordLines: wordLines,
      tone: store.tone,
    );

    final onUpdate = () {
      if (mounted) {
        model.tick();
        setState(() {});
      }
    };

    final String? err;
    if (isRetry) {
      err = await chat.retry(
        poster: model.poster,
        apiKey: model.deepSeekKey,
        baseUrl: model.deepSeekBase,
        model: model.deepSeekModel,
        installId: store.installId,
        reasoningEffort: store.reasoningEffort,
        systemPrompt: system,
        onUpdate: onUpdate,
      );
    } else {
      err = await chat.send(
        text: text,
        poster: model.poster,
        apiKey: model.deepSeekKey,
        baseUrl: model.deepSeekBase,
        model: model.deepSeekModel,
        installId: store.installId,
        reasoningEffort: store.reasoningEffort,
        systemPrompt: system,
        onUpdate: onUpdate,
      );
      _controller.clear();
    }

    if (err != null) {
      _status = err;
      _retry = () => _sendOrRetry(model, text: text, isRetry: true);
    } else {
      _retry = null;
      store.recordPracticeRound();
      model.commit();
      _maybeShowClosing(store);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _maybeShowClosing(LessonStore store) {
    if (_closingShown || !store.checkedIn || widget.readOnly) return;
    _closingShown = true;
    _local.add(
      const _Bubble(
        role: _BubbleRole.coach,
        text: '今日练习完成，辛苦啦。可以回去看看笔记，或者明天再来。',
      ),
    );
    if (mounted) setState(() {});
  }
}

enum _BubbleRole { user, coach }

class _Bubble {
  final _BubbleRole role;
  final String text;
  const _Bubble({required this.role, required this.text});
}

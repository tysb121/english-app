import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../engine/lesson_store.dart';
import '../engine/pos_label.dart';
import 'english_app.dart';
import 'coach_thread_page.dart';
import 'practice_page.dart';
import 'theme.dart';
import 'upgrade_nudge.dart';

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
    final plan = store.requiredTodayPlan;
    if (!_autoOpened && store.checkedIn && !store.notesDismissed) {
      _autoOpened = true;
      _showNotes = true;
      _drafts = [...store.noteDrafts()];
    }
    final todayWords = plan.newWordIds;
    final reviewExtra = plan.reviewWordIds;
    final tomorrowLine = store.checkedIn
        ? store.tomorrowReviewPreviewLine()
        : null;
    return SoftScaffold(
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.today_rounded, color: pine, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          store.formatDay(store.today),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        Text(
                          '连续 ${store.streak()}',
                          style: const TextStyle(
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (store.checkedIn) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: pine.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              '已完成',
                              style: TextStyle(
                                color: pine,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ProgressChip(
                          label: '懂了',
                          done: store.vocabDone,
                          icon: Icons.visibility_rounded,
                        ),
                        ProgressChip(
                          label: '用过',
                          done: store.sentencesDone,
                          icon: Icons.chat_bubble_outline_rounded,
                        ),
                        ProgressChip(
                          label: '轮次',
                          done: store.dialogueDone,
                          icon: Icons.forum_outlined,
                        ),
                      ],
                    ),
                    if (!store.checkedIn) ...[
                      const SizedBox(height: 10),
                      Text(
                        store.progressRemainderLine(),
                        style: const TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              PrimaryCta(
                label: store.homeActionLabel(),
                onPressed: () => _openPrimary(context, model),
              ),
              if (store.shouldOfferLevelUpgrade) ...[
                const SizedBox(height: 10),
                const UpgradeNudgeCard(),
              ],
              if (!model.hasDeepSeekKey) ...[
                const SizedBox(height: 10),
                const Text(
                  '还没填写 DeepSeek 密钥：可以先在下方词卡点「懂了」；要和教练对话，请到「我的」填写。',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              ],
              if (plan.errorWordIds.isNotEmpty) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openErrors(context),
                    icon: const Icon(Icons.replay_circle_filled_outlined),
                    label: Text('错词 ${plan.errorWordIds.length}（练完对话后再练）'),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              const SectionTitle(
                '今日练习的词',
                icon: Icons.chat_bubble_outline_rounded,
              ),
              for (final id in todayWords) _card(model, store, id),
              if (reviewExtra.isNotEmpty) ...[
                const SizedBox(height: 4),
                const SectionTitle('复习', icon: Icons.replay_rounded),
                for (final id in reviewExtra) _card(model, store, id),
              ],
              const SizedBox(height: 8),
              const Text(
                '先在词卡上点「懂了」，再进教练聊天「用过」并聊几轮。',
                style: TextStyle(fontSize: 13, color: muted),
              ),
              if (tomorrowLine != null) ...[
                const SizedBox(height: 8),
                Text(
                  tomorrowLine,
                  style: const TextStyle(fontSize: 13, color: pine),
                ),
              ],
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
        const SectionTitle('笔记草稿', icon: Icons.edit_note_rounded),
        if (_drafts.isEmpty)
          const Text('今天没有要记的句子', style: TextStyle(color: muted)),
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

  Widget _card(AppModel model, LessonStore store, String id) {
    final word = store.word(id);
    if (word == null) return const SizedBox.shrink();
    final known = store.vocabSeen(id);
    final used = store.wordUsed(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: mist,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: used
                ? pine.withValues(alpha: 0.35)
                : known
                ? pine.withValues(alpha: 0.18)
                : softBorder,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (used || known ? pine : indigo).withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  used
                      ? Icons.check_circle_rounded
                      : known
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_outlined,
                  color: used || known ? pine : indigo,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      known ? word.en : word.cn,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      known
                          ? '${word.cn} · ${posLabelZh(word.pos)}'
                          : posLabelZh(word.pos),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (!known)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    store.acknowledgeWord(id);
                    model.commit();
                    setState(() {});
                  },
                  child: const Text('懂了'),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    used ? '已用' : '已懂',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: used ? pine : muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPrimary(BuildContext context, AppModel model) {
    final label = model.store.homeActionLabel();
    if (label == '回看练习' && model.store.checkedIn) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const CoachThreadPage(readOnly: true),
        ),
      );
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const CoachThreadPage()));
  }

  void _openErrors(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const PracticePage()));
  }
}

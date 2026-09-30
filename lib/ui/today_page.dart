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
    final preview = plan.newWordIds.take(2).toList();
    final rest = [
      ...plan.newWordIds.skip(2),
      ...plan.reviewWordIds,
    ];
    final tomorrowLine =
        store.checkedIn ? store.tomorrowReviewPreviewLine() : null;
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
                          style: const TextStyle(color: muted, fontWeight: FontWeight.w600),
                        ),
                        if (store.checkedIn) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: pine.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              '已完成',
                              style: TextStyle(color: pine, fontSize: 12, fontWeight: FontWeight.w700),
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
                          label: '认词',
                          done: store.vocabDone,
                          icon: Icons.menu_book_rounded,
                        ),
                        ProgressChip(
                          label: '造句',
                          done: store.sentencesDone,
                          icon: Icons.edit_note_rounded,
                        ),
                        ProgressChip(
                          label: '对话',
                          done: store.dialogueDone,
                          icon: Icons.forum_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          store.scene == null
                              ? Icons.movie_creation_outlined
                              : Icons.movie_filter_rounded,
                          size: 16,
                          color: muted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '场景：${_sceneStatus(store)}',
                          style: const TextStyle(color: muted),
                        ),
                      ],
                    ),
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
                  '还没填 DeepSeek 密钥：可以认词，生成场景和批改需到「我的」填写。',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              ],
              if (plan.errorWordIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _openErrors(context),
                    icon: const Icon(Icons.replay_circle_filled_outlined),
                    label: Text('错词 ${plan.errorWordIds.length}（对话后再练）'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                '认词只看词卡；造句和短对话才动笔。到期错词排在对话后再练。',
                style: TextStyle(fontSize: 13, color: muted),
              ),
              if (tomorrowLine != null) ...[
                const SizedBox(height: 8),
                Text(
                  tomorrowLine,
                  style: const TextStyle(fontSize: 13, color: pine),
                ),
              ],
              const SizedBox(height: 8),
              const SectionTitle('今天的说法', icon: Icons.chat_bubble_outline_rounded),
              for (final id in preview) _card(store, id),
              if (rest.isNotEmpty)
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      title: Text('其余 ${rest.length} 个'),
                      children: [for (final id in rest) _card(store, id)],
                    ),
                  ),
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
        const SectionTitle('笔记草稿', icon: Icons.edit_note_rounded),
        if (_drafts.isEmpty) const Text('今天没有要记的句子', style: TextStyle(color: muted)),
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
    final known = store.vocabSeen(id);
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (known ? pine : indigo).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              known ? Icons.visibility_rounded : Icons.visibility_off_outlined,
              color: known ? pine : indigo,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  known ? word.en : word.cn,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  known
                      ? '${word.cn} · ${posLabelZh(word.pos)}'
                      : posLabelZh(word.pos),
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _sceneStatus(LessonStore store) {
    if (store.sceneInFlight && store.scene == null) return '生成中';
    if (store.scene == null) return '未生成';
    return '已生成';
  }

  void _openPrimary(BuildContext context, AppModel model) {
    final label = model.store.homeActionLabel();
    if (label == '回看今天' && model.store.checkedIn) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const CoachThreadPage(readOnly: true),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CoachThreadPage(),
      ),
    );
  }

  void _openErrors(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PracticePage()),
    );
  }
}

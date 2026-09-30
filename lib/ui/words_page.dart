import 'package:flutter/material.dart';

import '../engine/lesson_store.dart';
import 'english_app.dart';
import 'theme.dart';

class WordsPage extends StatelessWidget {
  const WordsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final store = model.store;
    final plan = store.requiredTodayPlan;
    final todayIds = [
      ...plan.newWordIds,
      ...plan.reviewWordIds,
      ...plan.errorWordIds,
    ];
    final today = [for (final id in todayIds) store.word(id)].whereType<Lexeme>();
    final later = store.browsableWords.where((word) => !todayIds.contains(word.id));
    final remaining = store.untaughtInLevelCount();
    final levelLabel = normalizeLevel(store.level);
    return SoftScaffold(
      title: '词本',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          PrimaryCta(label: '添加生词', onPressed: () => _add(context)),
          const SizedBox(height: 8),
          const SectionTitle('今天的词', icon: Icons.wb_sunny_outlined),
          if (today.isEmpty)
            const EmptyHint(
              icon: Icons.auto_stories_outlined,
              title: '今天还没有词',
              subtitle: '完成计划或添加生词后会出现在这里。',
            )
          else
            for (final word in today) _row(context, word, highlight: true),
          const SizedBox(height: 8),
          SectionTitle('当前水平 · $levelLabel', icon: Icons.stairs_outlined),
          AppCard(
            child: Text(
              remaining > 0
                  ? '还有 $remaining 个未教词，每天从中随机抽。'
                  : '这一档的新词已经抽完了，可以在「我的」里改水平（明天生效）。',
              style: const TextStyle(color: muted, height: 1.4),
            ),
          ),
          const SizedBox(height: 8),
          const SectionTitle('以后会学的词', icon: Icons.schedule_outlined),
          if (later.isEmpty)
            const EmptyHint(
              icon: Icons.schedule_outlined,
              title: '还没有排进以后的词',
              subtitle: '自己加的生词会优先出现在这里。',
            )
          else
            for (final word in later) _row(context, word),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Lexeme word, {bool highlight = false}) {
    return AppCard(
      accent: highlight,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WordCardPage(id: word.id),
          ),
        );
      },
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  pine.withValues(alpha: 0.18),
                  indigo.withValues(alpha: 0.12),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              word.en.isNotEmpty ? word.en[0].toUpperCase() : '?',
              style: const TextStyle(
                color: pine,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  word.en,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${word.cn} · ${word.pos}',
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: muted),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext pageContext) async {
    final en = TextEditingController();
    final cn = TextEditingController();
    final pos = TextEditingController();
    final model = AppScope.of(pageContext);
    await showDialog<void>(
      context: pageContext,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('添加'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: en,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(hintText: '英文'),
              ),
              TextField(
                controller: cn,
                decoration: const InputDecoration(hintText: '中文'),
              ),
              TextField(
                controller: pos,
                decoration: const InputDecoration(hintText: '词性'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (en.text.trim().isEmpty ||
                    cn.text.trim().isEmpty ||
                    pos.text.trim().isEmpty) {
                  return;
                }
                final id = model.store.addUserWord(
                  en: en.text.trim(),
                  cn: cn.text.trim(),
                  pos: pos.text.trim(),
                );
                model.commit();
                Navigator.pop(dialogContext);
                Navigator.of(pageContext).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WordCardPage(id: id, fresh: true),
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    en.dispose();
    cn.dispose();
    pos.dispose();
  }
}

class WordCardPage extends StatelessWidget {
  const WordCardPage({super.key, required this.id, this.fresh = false});

  final String id;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final word = store.word(id);
    final next = word == null
        ? null
        : store.nextErrorReview(id) ?? store.successReviewOn(id);
    return SoftScaffold(
      title: '词卡',
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.maybePop(context),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: word == null
            ? const SizedBox.shrink()
            : AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      word.en,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(word.cn, style: const TextStyle(fontSize: 20)),
                    Text(word.pos, style: const TextStyle(color: muted)),
                    const SizedBox(height: 12),
                    Text(
                      next == null
                          ? '还没排进某一天'
                          : '下一次 ${store.formatDay(next)}',
                      style: const TextStyle(color: muted),
                    ),
                    if (fresh) ...[
                      const SizedBox(height: 12),
                      const Text('从明天开始练', style: TextStyle(color: pine)),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

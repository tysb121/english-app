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
    final plan = store.ensureTodayPlan();
    final todayIds = [
      ...plan.newWordIds,
      ...plan.reviewWordIds,
      ...plan.errorWordIds,
    ];
    final today = [for (final id in todayIds) store.word(id)].whereType<Lexeme>();
    final later = store.catalog.where((word) => !todayIds.contains(word.id));
    return Scaffold(
      appBar: AppBar(title: const Text('今日英语')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          FilledButton(
            onPressed: () => _add(context),
            child: const Text('添加'),
          ),
          const SizedBox(height: 16),
          const Text('今天的词'),
          for (final word in today) _row(context, word),
          const SizedBox(height: 16),
          const Text('以后会学的词'),
          for (final word in later) _row(context, word),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Lexeme word) {
    return ListTile(
      title: Text(word.en),
      subtitle: Text(word.cn),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WordCardPage(id: word.id),
          ),
        );
      },
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
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('关闭'),
        ),
        leadingWidth: 72,
        title: const Text('今日英语'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: word == null
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(word.en, style: const TextStyle(fontSize: 32, color: ink)),
                  const SizedBox(height: 8),
                  Text(word.cn, style: const TextStyle(fontSize: 20)),
                  Text(word.pos),
                  const SizedBox(height: 12),
                  Text(
                    next == null
                        ? '还没排进某一天'
                        : '下一次 ${store.formatDay(next)}',
                  ),
                  if (fresh) ...[
                    const SizedBox(height: 12),
                    const Text('从明天开始练'),
                  ],
                ],
              ),
      ),
    );
  }
}

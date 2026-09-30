import 'package:flutter/material.dart';

import 'english_app.dart';
import 'theme.dart';

class LevelPage extends StatelessWidget {
  const LevelPage({super.key});

  static const _options = [
    (
      '入门',
      'A1 · hello / good / day',
      Icons.emoji_emotions_outlined,
    ),
    (
      '基础',
      'A2 · although / appear / around',
      Icons.menu_book_outlined,
    ),
    (
      '进阶',
      'B1 · abandon / absorb / access',
      Icons.school_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    return SoftScaffold(
      title: '选择程度',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            '先选一个水平',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            '选择一个适合自己的起点。今日练习开始后，改水平会从明天起生效。',
            style: TextStyle(color: muted, height: 1.45),
          ),
          const SizedBox(height: 16),
          for (final option in _options)
            AppCard(
              onTap: () {
                model.store.level = option.$1;
                model.store.levelChosen = true;
                model.commit();
              },
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          pine.withValues(alpha: 0.18),
                          indigo.withValues(alpha: 0.14),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(option.$3, color: pine),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.$1,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          option.$2,
                          style: const TextStyle(color: muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: muted),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'english_app.dart';
import 'theme.dart';

class LevelPage extends StatelessWidget {
  const LevelPage({super.key});

  static const _options = [
    (
      '新手',
      "I'm running late. 要迟到了",
      Icons.emoji_emotions_outlined,
    ),
    (
      '简单工作对话',
      "Let's start the standup. 我们开始站会。",
      Icons.work_outline_rounded,
    ),
    (
      '更长的表达',
      "Let's take this offline. 会下再说。",
      Icons.record_voice_over_outlined,
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
            '决定从哪一档说法开始。今天的计划冻住后，改水平从明天生效。',
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

import 'package:flutter/material.dart';

import 'english_app.dart';
import 'theme.dart';

class LevelPage extends StatelessWidget {
  const LevelPage({super.key});

  static const _options = [
    ('新手', "I'm running late. 要迟到了"),
    ('简单工作对话', "Let's start the standup. 我们开始站会。"),
    ('更长的表达', "Let's take this offline. 会下再说。"),
  ];

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('今日英语')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const Text(
            '先选一个水平',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '决定从哪一档说法开始。今天的计划冻住后，改水平从明天生效。',
            style: TextStyle(color: Color(0xFF4E4A43)),
          ),
          const SizedBox(height: 20),
          for (final option in _options) ...[
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.white,
              ),
              onPressed: () {
                model.store.level = option.$1;
                model.store.levelChosen = true;
                model.commit();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.$1,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    option.$2,
                    style: const TextStyle(color: Color(0xFF4E4A43)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

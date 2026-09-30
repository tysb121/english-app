import 'package:flutter/material.dart';

import '../app/app_model.dart';
import '../engine/lesson_store.dart';
import 'english_app.dart';
import 'theme.dart';

/// Exhausted-level CEFR upgrade offer (confirm → tomorrow; no auto jump).
class UpgradeNudgeCard extends StatelessWidget {
  const UpgradeNudgeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final store = model.store;
    if (!store.shouldOfferLevelUpgrade) return const SizedBox.shrink();
    final next = store.nextProductLevel!;
    final current = normalizeLevel(store.level);
    return AppCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up_rounded, color: pine, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '本级新词已经练完了',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '「$current」未教新词已经全部练完。升到「$next」后从明天按新级抽词，今天计划不动。',
            style: const TextStyle(color: muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    store.acceptLevelUpgrade();
                    model.commit();
                  },
                  child: Text('升到$next'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  store.dismissUpgradeNudge();
                  model.commit();
                },
                child: const Text('暂不'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../engine/lesson_store.dart';
import 'english_app.dart';
import 'theme.dart';

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    store.ensureTodayPlan();
    final days = store.history;
    return Scaffold(
      appBar: AppBar(title: const Text('今日英语')),
      body: ListView(
        children: [
          for (final plan in days)
            ListTile(
              title: Text(store.formatDay(plan.date)),
              subtitle: Text(plan.scene?.scenarioCn ?? '还没有场景'),
              trailing: Text(store.planComplete(plan) ? '完成' : '未完成'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RecordDetailPage(day: plan.date),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class RecordDetailPage extends StatelessWidget {
  const RecordDetailPage({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    DayPlan? plan;
    for (final item in store.history) {
      if (item.date == day) plan = item;
    }
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('关闭'),
        ),
        leadingWidth: 72,
        title: const Text('今日英语'),
      ),
      body: plan == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(store.formatDay(plan.date)),
                const SizedBox(height: 8),
                Text(plan.scene?.scenarioCn ?? '还没有场景'),
                if (plan.scene != null)
                  Text(
                    plan.scene!.scenarioEn,
                    style: const TextStyle(color: ink),
                  ),
                const SizedBox(height: 16),
                const Text('新词'),
                for (final id in plan.newWordIds)
                  Text(store.word(id)?.en ?? id),
                const SizedBox(height: 16),
                const Text('笔记'),
                if (plan.notes.isEmpty) const Text('没有保存的笔记'),
                for (final note in plan.notes)
                  Text('${note.wrong} → ${note.corrected} → ${note.whyCn}'),
              ],
            ),
    );
  }
}

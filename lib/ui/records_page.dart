import 'package:flutter/material.dart';

import '../engine/lesson_store.dart';
import 'english_app.dart';
import 'theme.dart';

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final days = store.history;
    return SoftScaffold(
      title: '记录',
      body: days.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: EmptyHint(
                  icon: Icons.calendar_month_outlined,
                  title: '还没有打卡记录',
                  subtitle: '完成今天的认词、造句和短对话后，会显示在这里。',
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                for (final plan in days)
                  AppCard(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RecordDetailPage(day: plan.date),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: (store.planComplete(plan) ? pine : muted)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            store.planComplete(plan)
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked,
                            color: store.planComplete(plan) ? pine : muted,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                store.formatDay(plan.date),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                plan.scene?.scenarioCn ?? '还没有场景',
                                style: const TextStyle(color: muted, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          store.planComplete(plan) ? '完成' : '未完成',
                          style: TextStyle(
                            color: store.planComplete(plan) ? pine : muted,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
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
    return SoftScaffold(
      title: '当天详情',
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.maybePop(context),
      ),
      body: plan == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.formatDay(plan.date),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(plan.scene?.scenarioCn ?? '还没有场景'),
                      if (plan.scene != null)
                        Text(
                          plan.scene!.scenarioEn,
                          style: const TextStyle(color: muted),
                        ),
                    ],
                  ),
                ),
                const SectionTitle('新词', icon: Icons.auto_stories_outlined),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final id in plan.newWordIds)
                        Text(store.word(id)?.en ?? id),
                    ],
                  ),
                ),
                const SectionTitle('笔记', icon: Icons.edit_note_rounded),
                AppCard(
                  child: plan.notes.isEmpty
                      ? const Text('没有保存的笔记', style: TextStyle(color: muted))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final note in plan.notes)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  '${note.wrong} → ${note.corrected} → ${note.whyCn}',
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

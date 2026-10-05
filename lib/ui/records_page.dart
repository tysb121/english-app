import 'package:flutter/material.dart';

import '../engine/chat_message.dart';
import '../engine/gradebook.dart';
import '../engine/lesson_store.dart';
import 'english_app.dart';
import 'theme.dart';

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final items = model.classCoach.log.book.items;
    final classes = model.classCoach.log.classes.reversed.toList();
    return SoftScaffold(
      title: '记录',
      body: items.isEmpty && classes.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: EmptyHint(
                  icon: Icons.calendar_month_outlined,
                  title: '还没有上课记录',
                  subtitle: '上完一节，收课条会出现在这里。点开只看，不再请求老师。',
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                if (items.isNotEmpty) ...[
                  const SectionTitle('学习项', icon: Icons.menu_book_outlined),
                  for (final item in items)
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.promptCn,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(item.targetEn),
                          const SizedBox(height: 4),
                          Text(
                            itemStatusLabel(item.status),
                            style: const TextStyle(color: muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                ],
                if (classes.isNotEmpty) ...[
                  const SectionTitle('上课', icon: Icons.calendar_month_outlined),
                  for (final item in classes)
                    AppCard(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ClassRecordPage(classId: item.id),
                          ),
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _stamp(item.startedAt),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.closeNote.trim().isEmpty
                                ? '这一节还开着'
                                : item.closeNote,
                            style: const TextStyle(color: muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

String _stamp(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class ClassRecordPage extends StatelessWidget {
  const ClassRecordPage({super.key, required this.classId});

  final String classId;

  @override
  Widget build(BuildContext context) {
    final classes = AppScope.of(context).classCoach.log.classes;
    final match = classes.where((item) => item.id == classId);
    final item = match.isEmpty ? null : match.first;
    return SoftScaffold(
      title: '这一节',
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
      body: item == null
          ? const Center(child: Text('这节课不在了'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (item.closeNote.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      item.closeNote,
                      style: const TextStyle(color: muted),
                    ),
                  ),
                for (final message in item.messages)
                  Align(
                    alignment: message.role == ChatRole.user
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: speechBubbleMaxWidth(context),
                      ),
                      decoration: BoxDecoration(
                        color: message.role == ChatRole.user ? pine : mist,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        message.content,
                        style: TextStyle(
                          color: message.role == ChatRole.user
                              ? Colors.white
                              : ink,
                        ),
                      ),
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

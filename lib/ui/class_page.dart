import 'package:flutter/material.dart';

import '../app/class_coach.dart';
import '../engine/chat_message.dart';
import '../engine/gradebook.dart';
import 'answer_card.dart';
import 'english_app.dart';
import 'theme.dart';

class ClassPage extends StatefulWidget {
  const ClassPage({super.key});

  @override
  State<ClassPage> createState() => _ClassPageState();
}

class _ClassPageState extends State<ClassPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  var _greeted = false;
  String? _pinned;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _greeted) return;
      _greeted = true;
      AppScope.of(context).classCoach.ensureGreeting();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final coach = model.classCoach;
    final open = coach.log.openClass;
    final waiting = coach.pendingCard != null;
    final lastId = open == null || open.messages.isEmpty
        ? ''
        : open.messages.last.id;
    _pinLatest(
      '$lastId|${coach.draft}|${coach.pendingCard?.id}|${coach.error}',
    );
    return SoftScaffold(
      title: '上课',
      actions: [
        TextButton(
          onPressed: coach.busy ? null : () => coach.stopHere(),
          child: const Text('先到这'),
        ),
      ],
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                if (!coach.hasKey)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      '填写密钥后才能上课。到「我的」粘贴 DeepSeek 密钥。',
                      style: TextStyle(color: muted),
                    ),
                  ),
                if (open != null)
                  for (final message in open.messages)
                    _Bubble(
                      mine: message.role == ChatRole.user,
                      text: message.content,
                    ),
                if (coach.draft.trim().isNotEmpty)
                  _Bubble(mine: false, text: coach.draft),
                if (coach.status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      coach.status!,
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                  ),
                if (coach.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            coach.error!,
                            style: const TextStyle(color: wrongRed),
                          ),
                        ),
                        TextButton(
                          onPressed: coach.retry,
                          child: const Text('再发一次'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (coach.practiced != null)
            _PracticeStrip(item: coach.practiced!, coach: coach),
          if (waiting)
            AnswerCardSheet(
              card: coach.pendingCard!,
              onConfirm: (optionId, text) {
                coach.confirmCard(optionId: optionId, text: text);
              },
              onUnknown: coach.unknownCard,
            )
          else
            _Composer(
              controller: _input,
              busy: coach.busy,
              onSend: () {
                final text = _input.text;
                _input.clear();
                coach.sendText(text);
              },
            ),
        ],
      ),
    );
  }

  void _pinLatest(String token) {
    if (token == _pinned) return;
    _pinned = token;
    _jumpToEnd();
  }

  void _jumpToEnd([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scroll.hasClients) {
        if (attempt < 3) _jumpToEnd(attempt + 1);
        return;
      }
      final position = _scroll.position;
      if (!position.hasContentDimensions) return;
      final target = position.maxScrollExtent;
      if ((position.pixels - target).abs() < 1) return;
      position.jumpTo(target);
    });
  }
}

class _PracticeStrip extends StatelessWidget {
  const _PracticeStrip({required this.item, required this.coach});

  final StudyItem item;
  final ClassCoach coach;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        children: [
          _hideRow(
            shown: coach.hidePrompt ? '中文已遮住' : item.promptCn,
            hidden: coach.hidePrompt,
            label: coach.hidePrompt ? '显示中文' : '遮住中文',
            onPressed: coach.busy ? null : coach.toggleHidePrompt,
          ),
          _hideRow(
            shown: coach.hideAnswer ? '英文已遮住' : item.targetEn,
            hidden: coach.hideAnswer,
            label: coach.hideAnswer ? '显示英文' : '遮住英文',
            onPressed: coach.busy ? null : coach.toggleHideAnswer,
          ),
        ],
      ),
    );
  }

  Widget _hideRow({
    required String shown,
    required bool hidden,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            shown,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: hidden ? muted : ink, fontSize: 15),
          ),
        ),
        TextButton(onPressed: onPressed, child: Text(label)),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.mine, required this.text});

  final bool mine;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: speechBubbleMaxWidth(context)),
        decoration: BoxDecoration(
          color: mine ? pine : mist,
          borderRadius: BorderRadius.circular(16),
          border: mine ? null : Border.all(color: softBorder),
        ),
        child: Text(
          text,
          style: TextStyle(color: mine ? Colors.white : ink, height: 1.35),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: !busy,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(hintText: '跟老师说'),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : onSend,
                  child: const Text('发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

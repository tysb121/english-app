import 'package:flutter/material.dart';

import '../engine/chat_message.dart';
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
    return SoftScaffold(
      title: '上课',
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
                        TextButton(onPressed: coach.retry, child: const Text('再发一次')),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: coach.busy ? null : () => coach.stopHere(),
              child: const Text('先到这'),
            ),
          ),
          if (waiting)
            AnswerCardSheet(
              card: coach.pendingCard!,
              onConfirm: (optionId, text) {
                coach.confirmCard(optionId: optionId, text: text);
              },
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
        constraints: const BoxConstraints(maxWidth: 320),
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

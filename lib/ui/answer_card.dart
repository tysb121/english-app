import 'package:flutter/material.dart';

import '../engine/agent_tools.dart';
import 'theme.dart';

/// Bottom card for a choice, true/false, or fill-in question.
class AnswerCardSheet extends StatefulWidget {
  const AnswerCardSheet({
    super.key,
    required this.card,
    required this.onConfirm,
  });

  final AnswerCard card;
  final void Function(String? optionId, String text) onConfirm;

  @override
  State<AnswerCardSheet> createState() => _AnswerCardSheetState();
}

class _AnswerCardSheetState extends State<AnswerCardSheet> {
  String? _optionId;
  late final TextEditingController _blank = TextEditingController();

  @override
  void dispose() {
    _blank.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final canConfirm = card.kind == CardKind.blank
        ? _blank.text.trim().isNotEmpty
        : _optionId != null;
    return HalfSheet(
      child: Column(
        key: const Key('answer-card'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(card.prompt, style: const TextStyle(fontSize: 18, color: ink)),
          const SizedBox(height: 12),
          if (card.kind == CardKind.blank)
            TextField(
              key: const Key('answer-blank'),
              controller: _blank,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: card.placeholder ?? '写下答案',
              ),
            )
          else
            for (final option in card.options)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  key: Key('option-${option.id}'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _optionId == option.id
                        ? pine.withValues(alpha: 0.12)
                        : null,
                    side: BorderSide(
                      color: _optionId == option.id ? pine : softBorder,
                    ),
                  ),
                  onPressed: () => setState(() => _optionId = option.id),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(option.text),
                  ),
                ),
              ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('answer-confirm'),
            onPressed: canConfirm
                ? () => widget.onConfirm(_optionId, _blank.text)
                : null,
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }
}

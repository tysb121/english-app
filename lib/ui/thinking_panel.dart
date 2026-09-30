import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Compact collapsible chain-of-thought above the answer.
class ThinkingPanel extends StatelessWidget {
  const ThinkingPanel({
    super.key,
    required this.reasoning,
    this.streaming = false,
    this.initiallyExpanded,
  });

  final String reasoning;
  final bool streaming;
  final bool? initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final text = reasoning.trim();
    if (text.isEmpty && !streaming) return const SizedBox.shrink();
    final title = streaming ? '思考中…' : '思考过程';
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded ?? streaming,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF4E4A43),
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0EEE8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                text.isEmpty ? '…' : text,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF4E4A43),
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CoachAnswerBubble extends StatelessWidget {
  const CoachAnswerBubble({
    super.key,
    required this.content,
    this.reasoning = '',
    this.streaming = false,
    this.mine = false,
    this.usageTokens,
    this.elapsedMs,
    this.finishedAt,
  });

  final String content;
  final String reasoning;
  final bool streaming;
  final bool mine;
  final int? usageTokens;
  final int? elapsedMs;
  final DateTime? finishedAt;

  @override
  Widget build(BuildContext context) {
    final pass = content.startsWith('✓');
    final fail = content.startsWith('✗');
    final Color border;
    if (pass) {
      border = pine;
    } else if (fail) {
      border = wrongRed;
    } else {
      border = const Color(0xFFE3DDD2);
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.88,
        ),
        decoration: BoxDecoration(
          color: mine ? pine.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: pass || fail ? 1.4 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!mine)
              ThinkingPanel(
                reasoning: reasoning,
                streaming: streaming && content.trim().isEmpty,
              ),
            if (content.trim().isNotEmpty || !streaming)
              Text(
                content.trim().isEmpty && streaming ? '…' : content,
                style: const TextStyle(color: ink),
              )
            else if (streaming && reasoning.trim().isNotEmpty)
              const Text(
                '回答生成中…',
                style: TextStyle(fontSize: 13, color: Color(0xFF4E4A43)),
              ),
            if (!mine && !streaming && content.trim().isNotEmpty)
              _ReplyFooter(
                content: content,
                usageTokens: usageTokens,
                elapsedMs: elapsedMs,
                finishedAt: finishedAt,
              ),
          ],
        ),
      ),
    );
  }
}

class _ReplyFooter extends StatelessWidget {
  const _ReplyFooter({
    required this.content,
    this.usageTokens,
    this.elapsedMs,
    this.finishedAt,
  });

  final String content;
  final int? usageTokens;
  final int? elapsedMs;
  final DateTime? finishedAt;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (usageTokens != null) parts.add('用量 $usageTokens tok');
    if (elapsedMs != null) {
      final sec = (elapsedMs! / 1000).clamp(0.1, 9999.0);
      parts.add(sec >= 10 ? '${sec.round()}s' : '${sec.toStringAsFixed(1)}s');
    }
    if (finishedAt != null) {
      final t = finishedAt!.toLocal();
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      parts.add('$hh:$mm');
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '复制',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: content));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy_outlined, size: 18, color: Color(0xFF4E4A43)),
          ),
          if (parts.isNotEmpty)
            Expanded(
              child: Text(
                parts.join(' · '),
                style: const TextStyle(fontSize: 12, color: Color(0xFF4E4A43)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

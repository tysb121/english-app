import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

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
        childrenPadding: const EdgeInsets.only(bottom: 10),
        leading: Icon(
          streaming ? Icons.auto_awesome : Icons.psychology_alt_outlined,
          size: 18,
          color: indigo.withValues(alpha: 0.85),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: muted,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    indigo.withValues(alpha: 0.06),
                    pine.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: softBorder),
              ),
              child: Text(
                text.isEmpty ? '…' : text,
                style: const TextStyle(
                  fontSize: 13,
                  color: muted,
                  height: 1.4,
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

  static MarkdownStyleSheet _coachMdStyle(BuildContext context) {
    const base = TextStyle(color: ink, height: 1.45, fontSize: 15);
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      pPadding: EdgeInsets.zero,
      strong: base.copyWith(fontWeight: FontWeight.w700),
      em: base.copyWith(fontStyle: FontStyle.italic),
      code: base.copyWith(
        fontFamily: 'monospace',
        fontSize: 13.5,
        backgroundColor: indigo.withValues(alpha: 0.08),
      ),
      codeblockDecoration: BoxDecoration(
        color: indigo.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      blockquote: base.copyWith(color: muted),
      listBullet: base,
      listIndent: 20,
      h1: base.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
      h2: base.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      h3: base.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
      blockSpacing: 8,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pass = content.startsWith('✓');
    final fail = content.startsWith('✗');
    final Color border;
    final Color fill;
    if (mine) {
      border = pine.withValues(alpha: 0.28);
      fill = pine.withValues(alpha: 0.12);
    } else if (pass) {
      border = pine.withValues(alpha: 0.45);
      fill = pine.withValues(alpha: 0.06);
    } else if (fail) {
      border = wrongRed.withValues(alpha: 0.4);
      fill = wrongRed.withValues(alpha: 0.05);
    } else {
      border = softBorder;
      fill = mist;
    }

    final display = content.trim().isEmpty && streaming ? '…' : content;

    final bubble = Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.88,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 6),
            bottomRight: Radius.circular(mine ? 6 : 18),
          ),
          border: Border.all(color: border, width: pass || fail ? 1.3 : 1),
          boxShadow: [
            BoxShadow(
              color: indigo.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
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
              mine
                  ? Text(
                      display,
                      style: const TextStyle(color: ink, height: 1.4),
                    )
                  : MarkdownBody(
                      data: display,
                      selectable: false,
                      softLineBreak: true,
                      styleSheet: _coachMdStyle(context),
                    )
            else if (streaming && reasoning.trim().isNotEmpty)
              const Text(
                '回答生成中…',
                style: TextStyle(fontSize: 13, color: muted),
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

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 8),
            child: child,
          ),
        );
      },
      child: bubble,
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
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              foregroundColor: muted,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
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
            icon: const Icon(Icons.copy_outlined, size: 15),
            label: const Text('复制', style: TextStyle(fontSize: 12)),
          ),
          if (parts.isNotEmpty) ...[
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                parts.join(' · '),
                style: const TextStyle(fontSize: 11, color: muted),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

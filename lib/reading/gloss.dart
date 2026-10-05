import '../data/cefr_core.dart';
import '../engine/api_requests.dart';
import '../net/chat_reply.dart';

enum GlossStep { book, cache, needsKey, ask }

class GlossPlan {
  const GlossPlan(this.step, [this.glossCn]);

  final GlossStep step;
  final String? glossCn;
}

/// Book hit, then a cached sentence gloss, then a key check. Asking is the
/// only step that may call the model, and only with the word plus its sentence.
GlossPlan planGloss({
  CefrWord? hit,
  String? cached,
  required bool hasKey,
}) {
  final book = hit?.cn.trim();
  if (book != null && book.isNotEmpty) return GlossPlan(GlossStep.book, book);
  final known = cached?.trim();
  if (known != null && known.isNotEmpty) {
    return GlossPlan(GlossStep.cache, known);
  }
  if (!hasKey) return const GlossPlan(GlossStep.needsKey);
  return const GlossPlan(GlossStep.ask);
}

ApiCall glossRequest({
  required String apiKey,
  required String baseUrl,
  required String model,
  required String word,
  required String sentence,
}) {
  return deepSeekPlainChat(
    apiKey: apiKey,
    baseUrl: baseUrl,
    model: model,
    temperature: 0.2,
    maxTokens: 200,
    messages: [
      {
        'role': 'system',
        'content':
            '你在帮人读一本英文书。只解释所给的这一个词在这一句里的意思，用一两句简体中文。不要翻译别的句子，不要出题。',
      },
      {
        'role': 'user',
        'content': '词：$word\n句子：$sentence',
      },
    ],
  );
}

String? glossFromBody(String body) {
  final text = parseChatReply(body)?.content?.trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

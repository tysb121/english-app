import '../engine/api_requests.dart';
import 'chat_reply.dart';
import 'sse_chat.dart';

class Posted {
  final int status;
  final String body;

  const Posted(this.status, this.body);
}

abstract class Poster {
  Future<Posted> send(ApiCall call);
}

/// Optional live SSE. [IoPoster] implements this; tests can omit it.
abstract class StreamingPoster implements Poster {
  Stream<SseChatEvent> streamChat(ApiCall call);
}

/// Open a chat stream. Falls back to one-shot [Poster.send] when needed.
Stream<SseChatEvent> openChatStream(Poster poster, ApiCall call) {
  if (poster is StreamingPoster && call.body['stream'] == true) {
    return poster.streamChat(call);
  }
  return _fallbackStream(poster, call);
}

Stream<SseChatEvent> _fallbackStream(Poster poster, ApiCall call) async* {
  final posted = await poster.send(call);
  if (posted.status != 200) {
    yield SseChatEvent(
      httpStatus: posted.status,
      errorMessage: deepSeekStatusText(posted.status),
    );
    return;
  }
  final events = parseSseBody(posted.body);
  if (events.isEmpty) {
    final reply = parseChatReply(posted.body);
    if (reply != null && (reply.content ?? '').isNotEmpty) {
      yield SseChatEvent(
        contentDelta: reply.content,
        reasoningDelta: reply.reasoningContent,
        finishReason: reply.finishReason ?? 'stop',
      );
      return;
    }
    yield SseChatEvent(
      httpStatus: posted.status,
      errorMessage: '服务暂时不可用',
    );
    return;
  }
  for (final event in events) {
    yield event;
  }
}

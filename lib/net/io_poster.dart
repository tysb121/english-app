import 'dart:convert';
import 'dart:io';

import '../engine/api_requests.dart';
import 'chat_reply.dart';
import 'poster.dart';
import 'sse_chat.dart';

class IoPoster implements StreamingPoster {
  @override
  Future<Posted> send(ApiCall call) async {
    if (call.uri.scheme != 'https') return const Posted(0, 'https');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 60);
    try {
      final request = await client
          .postUrl(call.uri)
          .timeout(const Duration(seconds: 60));
      _headers(request, call);
      request.add(utf8.encode(jsonEncode(call.body)));
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 120));
      return Posted(response.statusCode, body);
    } on Exception {
      return const Posted(0, 'network');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Stream<SseChatEvent> streamChat(ApiCall call) async* {
    if (call.uri.scheme != 'https') {
      yield const SseChatEvent(httpStatus: 0, errorMessage: '地址只接受 https');
      return;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 60);
    try {
      final request = await client
          .postUrl(call.uri)
          .timeout(const Duration(seconds: 60));
      _headers(request, call);
      request.add(utf8.encode(jsonEncode(call.body)));
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode != 200) {
        yield SseChatEvent(
          httpStatus: response.statusCode,
          errorMessage: deepSeekStatusText(response.statusCode),
        );
        return;
      }
      final lines = response
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        final t = line.trimRight();
        if (!t.startsWith('data:')) continue;
        final payload = t.substring(5).trimLeft();
        final event = parseSseDataPayload(payload);
        if (event != null) yield event;
        if (payload.trim() == '[DONE]') break;
      }
    } on Exception {
      yield const SseChatEvent(httpStatus: 0, errorMessage: '服务暂时不可用');
    } finally {
      client.close(force: true);
    }
  }

  void _headers(HttpClientRequest request, ApiCall call) {
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );
    final authorization = call.headers['Authorization'];
    if (authorization != null) {
      request.headers.set(HttpHeaders.authorizationHeader, authorization);
    }
  }
}

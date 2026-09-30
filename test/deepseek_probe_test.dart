import 'dart:convert';

import 'package:english_app/app/app_model.dart';
import 'package:english_app/engine/api_requests.dart';
import 'package:english_app/net/chat_reply.dart';
import 'package:english_app/net/poster.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cefr_fixture.dart';

void main() {
  test('deepSeekProbe user content includes the word json', () {
    final call = deepSeekProbe(apiKey: 'k');
    expect(call.body['response_format'], {'type': 'json_object'});
    final messages = call.body['messages'] as List;
    final content = (messages.first as Map)['content'] as String;
    expect(content.toLowerCase(), contains('json'));
  });

  test('deepSeekStatusText distinguishes json prompt rule from bad model', () {
    expect(deepSeekStatusText(401), '密钥无效');
    expect(deepSeekStatusText(400), '地址或模型名不被接受');
    final body = jsonEncode({
      'error': {
        'message':
            "Prompt must contain the word 'json' in some form to use 'response_format' of type 'json_object'.",
      },
    });
    expect(deepSeekStatusText(400, body: body), '探测请求格式有误');
    expect(deepSeekBodyHint(body), '探测请求格式有误');
    expect(
      deepSeekErrorMessageLine(body),
      contains("must contain the word 'json'"),
    );
  });

  test('testConnection surfaces json-rule hint and server detail', () async {
    final store = fixtureStore(clock: () => DateTime(2026, 5, 5));
    final body = jsonEncode({
      'error': {
        'message':
            "Prompt must contain the word 'json' in some form to use 'response_format' of type 'json_object'.",
      },
    });
    final poster = _ScriptPoster([Posted(400, body)]);
    final model = AppModel(
      store: store,
      poster: poster,
      deepSeekKey: 'test-key',
    );
    final message = await model.testConnection();
    expect(message, startsWith('探测请求格式有误'));
    expect(message, contains('must contain the word'));
    expect(model.connectionOk, isFalse);
  });
}

class _ScriptPoster implements Poster {
  _ScriptPoster(this.responses);

  final List<Posted> responses;
  final List<ApiCall> calls = [];

  @override
  Future<Posted> send(ApiCall call) async {
    calls.add(call);
    return responses.removeAt(0);
  }
}

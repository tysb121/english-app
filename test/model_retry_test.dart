import 'dart:convert';

import 'package:english_app/app/app_model.dart';
import 'package:english_app/engine/api_requests.dart';
import 'package:english_app/engine/lesson_store.dart';
import 'package:english_app/net/poster.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an invalid scene is retried once and then kept', () async {
    final store = LessonStore(clock: () => DateTime(2026, 5, 2));
    store.ensureTodayPlan();
    final before = store.reviewSnapshot();
    final poster = ScriptPoster([
      Posted(200, _wrap('{', finish: 'stop')),
      Posted(200, _wrap(_scene)),
    ]);
    final model = AppModel(
      store: store,
      poster: poster,
      deepSeekKey: 'test-key',
    );
    final error = await model.fillScene();
    expect(error, isNull);
    expect(store.scene!.scenarioEn, 'Standup');
    expect(store.shouldRequestScene, isFalse);
    expect(store.reviewSnapshot(), before);
    expect(poster.calls, hasLength(2));
    expect(poster.calls.first.uri.host, 'api.deepseek.com');
    expect(poster.calls.first.uri.path, '/chat/completions');
    expect(poster.calls.first.body['max_tokens'], 1200);
    expect(poster.calls.first.body['temperature'], 0.4);
    expect(poster.calls.first.body['thinking'], {'type': 'disabled'});
    expect(poster.calls.first.body['reasoning_effort'], 'none');
    expect(poster.calls.first.body['stream'], isFalse);
    expect(poster.calls.first.body.containsKey('tools'), isFalse);
    expect(poster.calls.first.body['user_id'], store.installId);
    expect(store.progressJson().contains('Bearer'), isFalse);

    final again = await model.fillScene();
    expect(again, isNull);
    expect(poster.calls, hasLength(2));
    expect(store.scene!.scenarioEn, 'Standup');
  });

  test('two rejected grades do not move dates or check-in', () async {
    final store = LessonStore(clock: () => DateTime(2026, 5, 3));
    store.ensureTodayPlan();
    final before = store.reviewSnapshot();
    final poster = ScriptPoster([
      Posted(200, _wrap('{"pass":true}', finish: 'length')),
      Posted(401, '{"error":"bad"}'),
    ]);
    final model = AppModel(
      store: store,
      poster: poster,
      deepSeekKey: 'test-key',
    );
    final error = await model.gradeQuiz(0, 'hello');
    expect(error, '密钥无效');
    expect(store.quizSnapshot(), [null, null, null, null]);
    expect(store.reviewSnapshot(), before);
    expect(store.checkedIn, isFalse);
    expect(poster.calls, hasLength(2));
  });

  test('probe and translation do not grade the quiz', () async {
    final store = LessonStore(clock: () => DateTime(2026, 5, 4));
    store.ensureTodayPlan();
    store.applyModelResponse(
      task: 'grade_open',
      content: '{"pass":false,"errors":[{"excerpt":"x","fix":"y","why_cn":"z"}],"corrected_en":"No."}',
      finishReason: 'stop',
      quizIndex: 1,
    );
    final quiz = store.quizSnapshot();
    final poster = ScriptPoster([
      Posted(200, '{"ok":true}'),
      Posted(200, _wrap('你好')),
    ]);
    final model = AppModel(
      store: store,
      poster: poster,
      deepSeekKey: 'test-key',
      tokenHubKey: 'hub-key',
    );
    expect(await model.testConnection(), '已连通');
    expect(store.quizSnapshot(), quiz);
    final translated = await model.translate('hello', toChinese: true);
    expect(translated, isNull);
    expect(store.referencePreview, '你好');
    expect(store.quizSnapshot(), quiz);
    expect(poster.calls.last.uri.host, 'tokenhub.tencentmaas.com');
    expect(poster.calls.last.uri.path, '/v1/chat/completions');
    expect(poster.calls.last.body['model'], 'hy-mt2-plus');
    expect(poster.calls.last.body.containsKey('response_format'), isFalse);
  });
}

class ScriptPoster implements Poster {
  ScriptPoster(this.responses);

  final List<Posted> responses;
  final List<ApiCall> calls = [];

  @override
  Future<Posted> send(ApiCall call) async {
    calls.add(call);
    return responses.removeAt(0);
  }
}

String _wrap(String content, {String finish = 'stop'}) {
  return jsonEncode({
    'choices': [
      {
        'finish_reason': finish,
        'message': {'content': content},
      },
    ],
    'usage': {'total_tokens': 9},
  });
}

const _scene = '''
{
  "scenario_en": "Standup",
  "scenario_cn": "早会",
  "phrases": [{"en": "Let's start.", "cn": "我们开始。"}],
  "dialogue": [
    {"speaker": "A", "en": "What did you finish?", "cn": "你做完了什么？"},
    {"speaker": "B", "en": "I finished the standup.", "cn": "我开完了站会。"},
    {"speaker": "A", "en": "Any blocker?", "cn": "有阻碍吗？"},
    {"speaker": "B", "en": "No blocker.", "cn": "没有阻碍。"},
    {"speaker": "A", "en": "Please follow up.", "cn": "请跟进。"},
    {"speaker": "B", "en": "I will follow up.", "cn": "我会跟进。"}
  ],
  "grammar": {
    "point_cn": "说已经发生的事。",
    "examples": ["I finished the report.", "I sent the notes."]
  }
}
''';

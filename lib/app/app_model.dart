import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../engine/api_requests.dart';
import '../engine/chat_thread.dart';
import '../engine/lesson_store.dart';
import '../engine/prompts.dart';
import '../net/chat_reply.dart';
import '../net/poster.dart';
import 'secrets.dart';

class AppModel extends ChangeNotifier {
  AppModel({
    required this.store,
    required this.poster,
    this.chat,
    this.deepSeekKey = '',
    this.deepSeekBase = 'https://api.deepseek.com',
    this.deepSeekModel = 'deepseek-flash',
    this.tokenHubKey = '',
    this.tokenHubBase = 'https://tokenhub.tencentmaas.com/v1',
    this.tokenHubModel = 'hy-mt2-plus',
    this.unlocked = false,
    this.persistProgress,
    this.persistSecrets,
  });

  final LessonStore store;
  final Poster poster;
  final ChatThread? chat;
  String deepSeekKey;
  String deepSeekBase;
  String deepSeekModel;
  String tokenHubKey;
  String tokenHubBase;
  String tokenHubModel;
  bool unlocked;
  final void Function(String json)? persistProgress;
  final void Function(SavedSecrets secrets)? persistSecrets;

  bool connectionOk = false;
  String? connectionMessage;
  Future<String?>? _sceneTask;

  bool get hasDeepSeekKey => deepSeekKey.trim().isNotEmpty;
  bool get hasTokenHubKey => tokenHubKey.trim().isNotEmpty;

  void commit() {
    final save = persistProgress;
    if (save != null) {
      try {
        save(store.progressJson());
      } on Object {
        // A full disk should not roll back an answer already held in memory.
      }
    }
    notifyListeners();
  }

  /// UI-only refresh (e.g. stream tokens) without rewriting progress.
  void tick() => notifyListeners();

  void unlock() {
    if (!hasDeepSeekKey) return;
    unlocked = true;
    notifyListeners();
  }

  /// Enter the shell without a key; online steps stay blocked with a CTA.
  void browseWithoutKey() {
    unlocked = true;
    notifyListeners();
  }

  String? updateDeepSeek({
    required String key,
    required String base,
    required String modelName,
  }) {
    final nextBase = base.trim().isEmpty
        ? 'https://api.deepseek.com'
        : base.trim();
    if (!_https(nextBase)) return '地址只接受 https';
    deepSeekKey = key.trim();
    deepSeekBase = nextBase;
    deepSeekModel = modelName.trim().isEmpty
        ? 'deepseek-flash'
        : modelName.trim();
    _saveSecrets();
    notifyListeners();
    return null;
  }

  String? updateTokenHub({
    required String key,
    required String base,
    required String modelName,
  }) {
    final nextBase = base.trim().isEmpty
        ? 'https://tokenhub.tencentmaas.com/v1'
        : base.trim();
    if (!_https(nextBase)) return '地址只接受 https';
    tokenHubKey = key.trim();
    tokenHubBase = nextBase;
    tokenHubModel = modelName.trim().isEmpty ? 'hy-mt2-plus' : modelName.trim();
    _saveSecrets();
    notifyListeners();
    return null;
  }

  Future<String> testConnection() async {
    if (!hasDeepSeekKey) {
      connectionOk = false;
      connectionMessage = '密钥无效';
      notifyListeners();
      return connectionMessage!;
    }
    final call = deepSeekProbe(
      apiKey: deepSeekKey.trim(),
      baseUrl: deepSeekBase,
      model: deepSeekModel,
      userId: store.installId,
    );
    if (call.uri.scheme != 'https') {
      connectionMessage = '地址只接受 https';
      connectionOk = false;
      notifyListeners();
      return connectionMessage!;
    }
    try {
      final posted = await poster.send(call);
      if (posted.status == 200) {
        final decoded = jsonDecode(posted.body);
        if (decoded is Map) {
          connectionOk = true;
          connectionMessage = '已连通';
          notifyListeners();
          return connectionMessage!;
        }
      }
      connectionOk = false;
      connectionMessage = deepSeekStatusText(posted.status, body: posted.body);
      final detail = deepSeekErrorMessageLine(posted.body);
      if (detail != null && detail.isNotEmpty) {
        connectionMessage = '$connectionMessage · $detail';
      }
    } on Object {
      connectionOk = false;
      connectionMessage = '服务暂时不可用';
    }
    notifyListeners();
    return connectionMessage!;
  }

  Future<String?> fillScene() {
    if (!store.shouldRequestScene) return Future<String?>.value();
    final running = _sceneTask;
    if (running != null) return running;
    final task = _fillScene();
    _sceneTask = task;
    return task.whenComplete(() {
      if (identical(_sceneTask, task)) _sceneTask = null;
    });
  }

  Future<String?> gradeSentence(String wordId, String answer) {
    final word = store.word(wordId);
    final label = word == null ? wordId : '${word.en} / ${word.cn}';
    return _grade(
      prompt: store.sentencePrompt(wordId),
      requiredWords: '必须自然用上这个词：$label',
      answer: answer,
      sentenceWordId: wordId,
    );
  }

  Future<String?> gradeLine({
    required String prompt,
    required String requiredWords,
    required String answer,
  }) {
    return _grade(
      prompt: prompt,
      requiredWords: requiredWords,
      answer: answer,
    );
  }

  Future<String?> explain() async {
    store.lastExplainCn = null;
    store.lastExplainEn = null;
    final error = await runTask(
      task: 'explain',
      messages: explainMessages(store),
    );
    commit();
    return error;
  }

  Future<String?> translate(String text, {required bool toChinese}) async {
    if (!hasTokenHubKey) return '没填密钥';
    final call = tokenHubTranslation(
      apiKey: tokenHubKey.trim(),
      text: text,
      toChinese: toChinese,
      baseUrl: tokenHubBase,
      model: tokenHubModel,
    );
    if (call.uri.scheme != 'https') return '地址只接受 https';
    final first = await _translateOnce(call);
    if (first.accepted) {
      store.applyTranslation(first.text!);
      commit();
      return null;
    }
    if (!first.retry) return first.error;
    final second = await _translateOnce(call);
    if (second.accepted) {
      store.applyTranslation(second.text!);
      commit();
      return null;
    }
    return second.error ?? '请再试一次';
  }

  Future<String?> _fillScene() async {
    store.sceneInFlight = true;
    notifyListeners();
    try {
      return await runTask(task: 'fill_scene', messages: fillSceneMessages(store));
    } on Object {
      return '服务暂时不可用';
    } finally {
      store.sceneInFlight = false;
      commit();
    }
  }

  Future<String?> _grade({
    required String prompt,
    required String requiredWords,
    required String answer,
    String? sentenceWordId,
  }) async {
    store.lastGrade = null;
    final error = await runTask(
      task: 'grade_open',
      messages: gradeMessages(
        store: store,
        prompt: prompt,
        requiredWords: requiredWords,
        answer: answer,
      ),
      sentenceWordId: sentenceWordId,
    );
    commit();
    return error;
  }

  @visibleForTesting
  Future<String?> runTask({
    required String task,
    required List<Map<String, String>> messages,
    String? sentenceWordId,
  }) async {
    final first = await _once(task, messages, sentenceWordId);
    if (first.accepted) return null;
    if (!first.retry) return first.error;
    final retryMessages = [
      ...messages,
      {
        'role': 'user',
        'content':
            '上一次没有返回合法 JSON。原文如下：\n${_clip(first.raw)}\n请只重发合法 JSON。',
      },
    ];
    final second = await _once(task, retryMessages, sentenceWordId);
    if (second.accepted) return null;
    return second.error ?? '没有返回合法结果';
  }

  Future<_AttemptResult> _once(
    String task,
    List<Map<String, String>> messages,
    String? sentenceWordId,
  ) async {
    if (!hasDeepSeekKey) {
      return const _AttemptResult.fail('密钥无效');
    }
    final call = deepSeekChat(
      apiKey: deepSeekKey.trim(),
      task: task,
      messages: messages,
      baseUrl: deepSeekBase,
      model: deepSeekModel,
      userId: store.installId,
    );
    if (call.uri.scheme != 'https') {
      return const _AttemptResult.fail('地址只接受 https');
    }
    try {
      final posted = await poster.send(call);
      final reply = posted.status == 200 ? parseChatReply(posted.body) : null;
      var accepted = false;
      if (reply != null) {
        accepted = store.applyModelResponse(
          task: task,
          content: reply.content ?? '',
          finishReason: reply.finishReason,
          sentenceWordId: sentenceWordId,
        );
      }
      store.recordCall(
        task: task,
        ok: accepted,
        finishReason: reply?.finishReason,
        tokens: reply?.tokens,
      );
      if (accepted) {
        return _AttemptResult.ok(reply?.content);
      }
      final retry =
          posted.status == 200 ||
          posted.status == 500 ||
          posted.status == 503 ||
          posted.status == 0;
      if (!retry) {
        return _AttemptResult.fail(deepSeekStatusText(posted.status));
      }
      return _AttemptResult.fail(
        posted.status == 200 ? '没有返回合法结果' : '服务暂时不可用',
        raw: reply?.content ?? posted.body,
        retry: true,
      );
    } on Object {
      store.recordCall(task: task, ok: false);
      return const _AttemptResult.fail('服务暂时不可用', retry: true);
    }
  }

  Future<_TranslationResult> _translateOnce(ApiCall call) async {
    try {
      final posted = await poster.send(call);
      if (posted.status != 200) {
        final retry =
            posted.status == 500 || posted.status == 503 || posted.status == 0;
        final message = posted.status == 402
            ? '未开通该模型或余额不足'
            : deepSeekStatusText(posted.status);
        return _TranslationResult.fail(message, retry: retry);
      }
      final reply = parseChatReply(posted.body);
      final text = reply?.content;
      if (text == null || !plainTranslation(text)) {
        return const _TranslationResult.fail('请再试一次', retry: true);
      }
      return _TranslationResult.ok(text.trim());
    } on Object {
      return const _TranslationResult.fail('服务暂时不可用', retry: true);
    }
  }

  void _saveSecrets() {
    persistSecrets?.call(
      SavedSecrets(
        deepSeekKey: deepSeekKey,
        deepSeekBase: deepSeekBase,
        deepSeekModel: deepSeekModel,
        tokenHubKey: tokenHubKey,
        tokenHubBase: tokenHubBase,
        tokenHubModel: tokenHubModel,
      ),
    );
  }

  bool _https(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.isScheme('https') && uri.host.isNotEmpty;
  }

  String _clip(String? raw) {
    final text = raw ?? '';
    if (text.length <= 4000) return text;
    return text.substring(0, 4000);
  }
}

class _AttemptResult {
  final bool accepted;
  final bool retry;
  final String? error;
  final String? raw;

  const _AttemptResult.ok(this.raw)
    : accepted = true,
      retry = false,
      error = null;

  const _AttemptResult.fail(this.error, {this.raw, this.retry = false})
    : accepted = false;
}

class _TranslationResult {
  final bool accepted;
  final bool retry;
  final String? error;
  final String? text;

  const _TranslationResult.ok(this.text)
    : accepted = true,
      retry = false,
      error = null;

  const _TranslationResult.fail(this.error, {this.retry = false})
    : accepted = false,
      text = null;
}

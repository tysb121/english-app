import 'reasoning_effort.dart';

/// HTTP calls the phone makes. Builders only; tests never hit the network.
class ApiCall {
  final Uri uri;
  final Map<String, String> headers;
  final Map<String, Object?> body;

  const ApiCall({
    required this.uri,
    required this.headers,
    required this.body,
  });
}

const deepSeekChatPath = '/chat/completions';
const tokenHubChatPath = '/v1/chat/completions';
const tokenHubHost = 'tokenhub.tencentmaas.com';

ApiCall deepSeekChat({
  required String apiKey,
  required String task,
  required List<Map<String, String>> messages,
  String baseUrl = 'https://api.deepseek.com',
  String model = 'deepseek-flash',
  String? userId,
}) {
  final root = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  final maxTokens = switch (task) {
    'fill_scene' => 1200,
    'grade_open' => 400,
    'explain' => 500,
    _ => 400,
  };
  return ApiCall(
    uri: Uri.parse('$root$deepSeekChatPath'),
    headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    },
    body: {
      'model': model,
      'messages': messages,
      'stream': false,
      'temperature': task == 'fill_scene' ? 0.4 : 0,
      'max_tokens': maxTokens,
      'response_format': {'type': 'json_object'},
      'thinking': {'type': 'disabled'},
      'reasoning_effort': 'none',
      if (userId != null && userId.isNotEmpty) 'user_id': userId,
    },
  );
}

ApiCall deepSeekProbe({
  required String apiKey,
  String baseUrl = 'https://api.deepseek.com',
  String model = 'deepseek-flash',
  String? userId,
}) {
  final root = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  return ApiCall(
    uri: Uri.parse('$root$deepSeekChatPath'),
    headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    },
    body: {
      'model': model,
      'messages': [
        {'role': 'user', 'content': '只返回 {"ok":true}'},
      ],
      'stream': false,
      'temperature': 0,
      'max_tokens': 16,
      'response_format': {'type': 'json_object'},
      'thinking': {'type': 'disabled'},
      'reasoning_effort': 'none',
      if (userId != null && userId.isNotEmpty) 'user_id': userId,
    },
  );
}

ApiCall tokenHubTranslation({
  required String apiKey,
  required String text,
  required bool toChinese,
  String baseUrl = 'https://tokenhub.tencentmaas.com/v1',
  String model = 'hy-mt2-plus',
}) {
  final root = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  final target = toChinese ? '中文' : '英文';
  return ApiCall(
    uri: Uri.parse('$root/chat/completions'),
    headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    },
    body: {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': '将以下文本翻译为$target，注意只需要输出翻译后的结果，不要额外解释：$text',
        },
      ],
      'stream': false,
    },
  );
}

const coachSystemPrompt =
    '你是「今日英语」应用里的英语教练，只做一件事：帮用户练英语。\n'
    '身份边界：你不是通用助手、不是编程/写作/百科/生活顾问。与练英语无关的请求，用一两句中文礼貌拒绝，'
    '并立刻把话题带回今天的词、句子、对话或考核。\n'
    '教学方式：用简短中文带练，一次只推进一小步；用户要练的句子用英文。'
    '可以纠正语法和用法，给一句改写和一句原因。\n'
    '不要宣布打卡，不要安排复习日期，不要声称进度已经记下，不要调用工具，不要输出 JSON。';

const checkpointSystemPrompt =
    '你在为「今日英语」英语教练整理更早的对话。只整理与练英语有关的事实。'
    '只输出检查点正文，用简体中文，按下面的小节顺序，空节写「无」。\n'
    '\n'
    '## 正在练什么\n'
    '## 已经练过的词和句子\n'
    '## 停在哪里\n'
    '## 还没做完的事\n'
    '## 需要记住的约束\n'
    '\n'
    '合并已有检查点里仍然成立的事实，丢掉过时的。不要调用工具，不要写小节以外的话，不要输出 JSON。';

ApiCall deepSeekPlainChat({
  required String apiKey,
  required List<Map<String, String>> messages,
  String baseUrl = 'https://api.deepseek.com',
  String model = 'deepseek-flash',
  String? userId,
  double temperature = 0.4,
  int maxTokens = 800,
  bool stream = false,
  String reasoningEffort = 'off',
}) {
  final root = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  final thinking = deepSeekThinkingFields(reasoningEffort);
  final tokens = normalizeReasoningEffort(reasoningEffort) == 'off'
      ? maxTokens
      : maxTokens + 800;
  return ApiCall(
    uri: Uri.parse('$root$deepSeekChatPath'),
    headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    },
    body: {
      'model': model,
      'messages': messages,
      'stream': stream,
      // Temperature is ignored while thinking is enabled; kept for off mode.
      'temperature': temperature,
      'max_tokens': tokens,
      ...thinking,
      if (stream) 'stream_options': {'include_usage': true},
      if (userId != null && userId.isNotEmpty) 'user_id': userId,
    },
  );
}

ApiCall deepSeekSummarize({
  required String apiKey,
  required String source,
  String baseUrl = 'https://api.deepseek.com',
  String model = 'deepseek-flash',
  String? userId,
}) {
  return deepSeekPlainChat(
    apiKey: apiKey,
    baseUrl: baseUrl,
    model: model,
    userId: userId,
    temperature: 0,
    maxTokens: 800,
    messages: [
      {'role': 'system', 'content': checkpointSystemPrompt},
      {'role': 'user', 'content': source},
    ],
  );
}

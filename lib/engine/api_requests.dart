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

/// UI / progress values: off / low / medium / high.
/// DeepSeek Chat Completions uses thinking.type + reasoning_effort low|high|max.
/// Docs map medium → high; we keep medium in UI and map at request time.
const reasoningEfforts = ['off', 'low', 'medium', 'high'];

String normalizeReasoningEffort(String value) {
  switch (value.trim()) {
    case 'low':
      return 'low';
    case 'medium':
      return 'medium';
    case 'high':
    case 'max':
      return 'high';
    default:
      return 'off';
  }
}

/// Fields for Chat Completions body (OpenAI-compatible DeepSeek).
Map<String, Object?> deepSeekThinkingFields(String effort) {
  final normalized = normalizeReasoningEffort(effort);
  if (normalized == 'off') {
    return {
      'thinking': {'type': 'disabled'},
    };
  }
  final apiEffort = switch (normalized) {
    'low' => 'low',
    'medium' => 'high',
    _ => 'high',
  };
  return {
    'thinking': {'type': 'enabled'},
    'reasoning_effort': apiEffort,
  };
}

String reasoningEffortLabel(String effort) {
  return switch (normalizeReasoningEffort(effort)) {
    'low' => '低',
    'medium' => '中',
    'high' => '高',
    _ => '关闭',
  };
}

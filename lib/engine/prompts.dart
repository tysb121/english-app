import 'lesson_store.dart';

const coachSystem =
    '你是简短的英语教练。对话和例句用英文。讲解用中文。一次只指出至多两处问题，并给出改对后的整句。只输出要求的 JSON，不要 Markdown 围栏。';

List<Map<String, String>> fillSceneMessages(LessonStore store) {
  final words = store
      .scheduledNewWords()
      .map((id) {
        final word = store.word(id);
        if (word == null) return id;
        return '${word.en} / ${word.cn} / ${word.pos}';
      })
      .join('\n');
  return [
    _system(store),
    {
      'role': 'user',
      'content':
          '当天新词：\n$words\n学习目标：${store.goal}\n水平：${store.level}\n语气：${store.tone}\n本地场景提纲：空\n请只返回一个 JSON 对象，包含 scenario_en、scenario_cn、phrases（1 到 5 条，每条有 en 和 cn）、dialogue（6 到 10 句，speaker 只能是 A 或 B，B 是用户，每句有 en 和 cn）、grammar（含 point_cn 和正好 2 条 examples）。每个新词都要出现在对话英文里。不要返回复习日期或打卡结论。',
    },
  ];
}

List<Map<String, String>> gradeMessages({
  required LessonStore store,
  required String prompt,
  required String requiredWords,
  required String answer,
}) {
  return [
    _system(store),
    {
      'role': 'user',
      'content':
          '题目：$prompt\n参考或必用：$requiredWords\n用户原文：$answer\n只返回 JSON：{"pass":true,"errors":[{"excerpt":"","fix":"","why_cn":""}],"corrected_en":""}。errors 最多 2 条。不要返回日期、掌握度或打卡。',
    },
  ];
}

List<Map<String, String>> explainMessages(LessonStore store) {
  final scene = store.scene;
  final examples = scene?.grammarExamples.join(' | ') ?? '';
  return [
    _system(store),
    {
      'role': 'user',
      'content':
          '语法卡片：${scene?.grammarCn ?? ''}\n例句：$examples\n请用中文顺着这张卡片讲，只返回 JSON：{"answer_cn":"","example_en":""}',
    },
  ];
}

String gradeRequirement(LessonStore store, int index) {
  final words = store
      .scheduledNewWords()
      .map((id) => store.word(id)?.en ?? id)
      .join(', ');
  return switch (index) {
    0 => words,
    1 => '意思正确即可，不必和参考译文逐词相同',
    2 => '接上对方的意思',
    _ => '至少用上两个今天的新词：$words',
  };
}

Map<String, String> _system(LessonStore store) {
  return {'role': 'system', 'content': '$coachSystem 语气：${store.tone}。'};
}

/// Maps English part-of-speech tags (CEFR / ECDICT style) to short Chinese labels
/// for beginners. Prompt text sent to the model may keep English [pos].
String posLabelZh(String pos) {
  final key = pos.trim().toLowerCase();
  if (key.isEmpty) return '其它';
  return switch (key) {
    'noun' || 'n' => '名词',
    'verb' || 'v' || 'be-verb' || 'do-verb' || 'have-verb' => '动词',
    'adverb' || 'adv' => '副词',
    'adjective' || 'adj' || 'a' => '形容词',
    'preposition' || 'prep' || 'p' => '介词',
    'conjunction' || 'conj' || 'c' => '连词',
    'pronoun' || 'pron' || 'r' => '代词',
    'interjection' || 'int' || 'i' || 'excl' => '感叹词',
    'determiner' || 'det' || 'article' => '限定词',
    'number' || 'num' || 'cardinal' => '数词',
    'modal auxiliary' || 'modal' || 'auxiliary' || 'aux' => '助动词',
    'infinitive-to' || 'to' => '不定式标记',
    _ => pos.trim(),
  };
}

import 'package:english_app/engine/pos_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('posLabelZh maps common CEFR tags to Chinese', () {
    expect(posLabelZh('noun'), '名词');
    expect(posLabelZh('VERB'), '动词');
    expect(posLabelZh('adverb'), '副词');
    expect(posLabelZh('adjective'), '形容词');
    expect(posLabelZh('preposition'), '介词');
    expect(posLabelZh('conjunction'), '连词');
    expect(posLabelZh('pronoun'), '代词');
    expect(posLabelZh('interjection'), '感叹词');
    expect(posLabelZh('determiner'), '限定词');
    expect(posLabelZh('number'), '数词');
    expect(posLabelZh('be-verb'), '动词');
    expect(posLabelZh('modal auxiliary'), '助动词');
    expect(posLabelZh('infinitive-to'), '不定式标记');
  });

  test('posLabelZh keeps unknowns and uses 其它 for empty', () {
    expect(posLabelZh(''), '其它');
    expect(posLabelZh('   '), '其它');
    expect(posLabelZh('particle'), 'particle');
  });
}

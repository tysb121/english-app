import 'dart:math';

import 'package:english_app/data/cefr_core.dart';
import 'package:english_app/engine/lesson_store.dart';

/// Small CEFR-shaped book for unit/widget tests (not the full asset).
const List<CefrWord> cefrFixture = [
  CefrWord(
    id: 'cc_a1_hello_noun_ce4a5e',
    en: 'hello',
    cn: '喂；嘿',
    pos: 'noun',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a1_good_adjectiv_2bed5e',
    en: 'good',
    cn: '好的；优良的',
    pos: 'adjective',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a1_time_noun_53674f',
    en: 'time',
    cn: '时间；时侯',
    pos: 'noun',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a1_day_noun_7f65b3',
    en: 'day',
    cn: '天；日子',
    pos: 'noun',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a1_work_noun_bf4aae',
    en: 'work',
    cn: '工作；劳动',
    pos: 'noun',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a1_home_noun_b8d824',
    en: 'home',
    cn: '家；避难所',
    pos: 'noun',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a1_friend_noun_c6552e',
    en: 'friend',
    cn: '朋友；支持者',
    pos: 'noun',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a1_water_noun_e21e30',
    en: 'water',
    cn: '水；雨水',
    pos: 'noun',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a1_book_noun_5f36f6',
    en: 'book',
    cn: '书；书籍',
    pos: 'noun',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a1_school_noun_c83a68',
    en: 'school',
    cn: '学校；鱼群',
    pos: 'noun',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a1_apple_noun_595d42',
    en: 'apple',
    cn: '苹果；家伙',
    pos: 'noun',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a1_food_noun_458e40',
    en: 'food',
    cn: '食物；养料',
    pos: 'noun',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a1_name_noun_bc8cd5',
    en: 'name',
    cn: '名字；名称',
    pos: 'noun',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a1_yes_adverb_c01407',
    en: 'yes',
    cn: '是',
    pos: 'adverb',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a1_no_adverb_f6e7f9',
    en: 'no',
    cn: '不',
    pos: 'adverb',
    level: 'a1',
  ),
  CefrWord(
    id: 'cc_a2_although_conjunct_a8d8d0',
    en: 'although',
    cn: '虽然；尽管',
    pos: 'conjunction',
    level: 'a2',
  ),
  CefrWord(
    id: 'cc_a2_appear_verb_a794fd',
    en: 'appear',
    cn: '出现；显得',
    pos: 'verb',
    level: 'a2',
  ),
  CefrWord(
    id: 'cc_a2_around_adverb_31e28b',
    en: 'around',
    cn: '兜着圈子；在附近',
    pos: 'adverb',
    level: 'a2',
  ),
  CefrWord(
    id: 'cc_a2_attack_noun_3fd629',
    en: 'attack',
    cn: '攻击；抨击',
    pos: 'noun',
    level: 'a2',
  ),
  CefrWord(
    id: 'cc_a2_attempt_noun_97b6e3',
    en: 'attempt',
    cn: '尝试；企图',
    pos: 'noun',
    level: 'a2',
  ),
  CefrWord(
    id: 'cc_b1_abandon_verb_bb6626',
    en: 'abandon',
    cn: '放弃；抛弃',
    pos: 'verb',
    level: 'b1',
  ),
  CefrWord(
    id: 'cc_b1_absorb_verb_c75d47',
    en: 'absorb',
    cn: '吸收；使全神贯注',
    pos: 'verb',
    level: 'b1',
  ),
  CefrWord(
    id: 'cc_b1_abstract_adjectiv_39ffdd',
    en: 'abstract',
    cn: '抽象的；深奥的',
    pos: 'adjective',
    level: 'b1',
  ),
  CefrWord(
    id: 'cc_b1_academic_adjectiv_f800d3',
    en: 'academic',
    cn: '学院的；学术的',
    pos: 'adjective',
    level: 'b1',
  ),
  CefrWord(
    id: 'cc_b1_access_noun_f26d4d',
    en: 'access',
    cn: '通路；入口',
    pos: 'noun',
    level: 'b1',
  ),
];

/// [Random] that makes [List.shuffle] keep original order (always swaps with 0).
class StableRandom implements Random {
  /// Always pick the last index so [List.shuffle] is a no-op.
  @override
  int nextInt(int max) => max <= 0 ? 0 : max - 1;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}

LessonStore fixtureStore({
  DateTime Function()? clock,
  String level = '入门',
  bool levelChosen = false,
  Random? random,
  String? installId,
}) {
  return LessonStore(
    clock: clock,
    book: cefrFixture,
    random: random ?? StableRandom(),
    installId: installId,
  )
    ..level = level
    ..levelChosen = levelChosen;
}

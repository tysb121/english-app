/// A word the learner kept while reading. Not a study item and not a grade.
class LeftWord {
  const LeftWord({
    required this.word,
    required this.sentence,
    required this.glossCn,
    required this.at,
  });

  final String word;
  final String sentence;
  final String glossCn;
  final String at;
}

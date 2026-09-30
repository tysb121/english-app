import 'package:english_app/data/cefr_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cefr_core asset loads with A1/A2/B1 Chinese entries', () async {
    final book = await loadCefrCore();
    expect(book.bookId, 'cefr_core');
    expect(book.titleLevels['a1'], '入门');
    expect(book.titleLevels['a2'], '基础');
    expect(book.titleLevels['b1'], '进阶');
    expect(book.entries.length, greaterThanOrEqualTo(5000));
    expect(book.counts['a1'], greaterThan(1000));
    expect(book.counts['a2'], greaterThan(1000));
    expect(book.counts['b1'], greaterThan(2000));
    expect(book.byLevel('a1').length, book.counts['a1']);
    final sample = book.entries.first;
    expect(sample.id, isNotEmpty);
    expect(sample.en, isNotEmpty);
    expect(sample.cn, isNotEmpty);
    expect(sample.level, anyOf('a1', 'a2', 'b1'));
    expect(sample.bookId, 'cefr_core');
    // Spot-check a known lemma
    final good = book.entries.where((w) => w.en == 'good' && w.pos == 'adjective');
    expect(good, isNotEmpty);
    expect(good.first.cn, contains('好'));
  });

  test('ATTRIBUTION asset is present', () async {
    final text = await rootBundle.loadString('assets/wordbooks/ATTRIBUTION.md');
    expect(text, contains('CEFR-J'));
    expect(text, contains('ECDICT'));
  });
}

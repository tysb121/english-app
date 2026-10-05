import 'package:english_app/reading/book_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a period stays on the word it follows', () {
    final pieces = readerBlocks(
      'Leaves stuck to the wet shoes by the door.',
    ).single.pieces;
    final door = pieces.lastWhere((piece) => piece.word == 'door');
    expect(door.shown, 'door.');
    expect(door.word, 'door');
    expect(pieces.map((piece) => piece.shown), isNot(contains('.')));
  });

  test('quotes and commas stay on the neighboring word', () {
    final pieces = readerBlocks('"Hello," she said.').single.pieces;
    expect(
      pieces.firstWhere((piece) => piece.word == 'Hello').shown,
      '"Hello,"',
    );
    expect(pieces.firstWhere((piece) => piece.word == 'said').shown, 'said.');
    expect(pieces.firstWhere((piece) => piece.word == 'she').shown, 'she');
  });

  test('a hyphen stays with the word before it', () {
    final pieces = readerBlocks('A well-known lane.').single.pieces;
    expect(pieces.firstWhere((piece) => piece.word == 'well').shown, 'well-');
    expect(pieces.firstWhere((piece) => piece.word == 'known').shown, 'known');
    expect(pieces.firstWhere((piece) => piece.word == 'lane').shown, 'lane.');
  });
}

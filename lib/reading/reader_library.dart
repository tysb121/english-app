import '../app/coach_database.dart';
import '../data/cefr_core.dart';
import 'book_text.dart';
import 'left_word.dart';
import 'reader_book.dart';

export 'reader_book.dart';

/// Local books, sentence glosses, and words kept while reading.
class ReaderLibrary {
  ReaderLibrary(this._db);

  final CoachDatabase _db;

  Future<List<ReaderBookSummary>> listBooks() => _db.listReaderBooks();

  Future<ReaderBook?> book(String id) => _db.readerBook(id);

  Future<ReaderBook> openBytes({
    required String name,
    required List<int> bytes,
  }) async {
    final extracted = extractBook(fileName: name, bytes: bytes);
    final id = bookIdFor(bytes);
    final existing = await _db.readerBook(id);
    if (existing != null) {
      await _db.touchReaderBook(id);
      return existing;
    }
    return _db.insertReaderBook(
      id: id,
      title: extracted.title,
      fileName: name,
      text: extracted.text,
    );
  }

  Future<void> savePlace(String id, int place) => _db.saveReaderPlace(id, place);

  Future<CefrWord?> exactWord(String word) => _db.exactWord(word);

  Future<String?> cachedGloss({
    required String word,
    required String sentence,
  }) {
    return _db.cachedGloss(word: word, sentence: sentence);
  }

  Future<void> saveGloss({
    required String word,
    required String sentence,
    required String glossCn,
  }) {
    return _db.saveGloss(word: word, sentence: sentence, glossCn: glossCn);
  }

  Future<void> leaveWord({
    required String word,
    required String sentence,
    required String glossCn,
  }) {
    return _db.leaveWord(word: word, sentence: sentence, glossCn: glossCn);
  }

  Future<List<LeftWord>> leftWords({int limit = 20}) =>
      _db.leftWords(limit: limit);
}

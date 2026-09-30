import 'dart:convert';

import 'package:flutter/services.dart';

/// One lemma in the CEFR core wordbook (A1/A2/B1).
class CefrWord {
  final String id;
  final String en;
  final String cn;
  final String pos;
  final String level; // a1 | a2 | b1
  final String bookId;

  const CefrWord({
    required this.id,
    required this.en,
    required this.cn,
    required this.pos,
    required this.level,
    this.bookId = 'cefr_core',
  });

  factory CefrWord.fromJson(Map<String, dynamic> json) {
    return CefrWord(
      id: json['id'] as String,
      en: json['en'] as String,
      cn: json['cn'] as String,
      pos: (json['pos'] as String?) ?? '',
      level: json['level'] as String,
      bookId: (json['book_id'] as String?) ?? 'cefr_core',
    );
  }
}

class CefrCoreBook {
  final String bookId;
  final Map<String, String> titleLevels;
  final Map<String, int> counts;
  final List<CefrWord> entries;

  const CefrCoreBook({
    required this.bookId,
    required this.titleLevels,
    required this.counts,
    required this.entries,
  });

  List<CefrWord> byLevel(String level) {
    final key = level.toLowerCase();
    return [for (final w in entries) if (w.level == key) w];
  }
}

/// Loads [assets/wordbooks/cefr_core.json] for [LessonStore].
Future<CefrCoreBook> loadCefrCore({
  AssetBundle? bundle,
  String assetPath = 'assets/wordbooks/cefr_core.json',
}) async {
  final raw = await (bundle ?? rootBundle).loadString(assetPath);
  final map = jsonDecode(raw) as Map<String, dynamic>;
  final entriesJson = map['entries'] as List<dynamic>? ?? const [];
  final countsRaw = map['counts'] as Map<String, dynamic>? ?? const {};
  final titlesRaw = map['title_levels'] as Map<String, dynamic>? ?? const {};
  return CefrCoreBook(
    bookId: (map['book_id'] as String?) ?? 'cefr_core',
    titleLevels: {
      for (final e in titlesRaw.entries) e.key: e.value.toString(),
    },
    counts: {
      for (final e in countsRaw.entries) e.key: (e.value as num).toInt(),
    },
    entries: [
      for (final item in entriesJson)
        CefrWord.fromJson(item as Map<String, dynamic>),
    ],
  );
}

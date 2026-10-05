import 'dart:convert';

import 'package:archive/archive.dart';

/// Readable text extracted from a local book. [text] is what a place offset
/// points into. Offsets are not positions in the original file bytes.
class BookText {
  const BookText({required this.title, required this.text});

  final String title;
  final String text;
}

class BookOpenError implements Exception {
  const BookOpenError(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReaderPiece {
  const ReaderPiece({
    required this.shown,
    required this.wordStart,
    required this.wordEnd,
    this.word,
  });

  /// Letters of a tappable word. [shown] may also include the punctuation
  /// that sits against those letters, so a period does not wrap onto its own line.
  final String? word;
  final String shown;
  final int wordStart;
  final int wordEnd;

  bool get isWord => word != null;
}

class ReaderBlock {
  const ReaderBlock({required this.start, required this.pieces});

  final int start;
  final List<ReaderPiece> pieces;
}

class SentenceSlice {
  const SentenceSlice({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;
}

BookText extractBook({required String fileName, required List<int> bytes}) {
  final lower = fileName.trim().toLowerCase();
  if (lower.endsWith('.txt')) return _extractTxt(fileName, bytes);
  if (lower.endsWith('.epub')) return _extractEpub(fileName, bytes);
  throw const BookOpenError('只能打开 txt 或 epub');
}

String bookIdFor(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

int clampPlace(int offset, int length) {
  if (length <= 0 || offset <= 0) return 0;
  if (offset > length) return length;
  return offset;
}

int blockIndexForPlace(List<ReaderBlock> blocks, int place) {
  if (blocks.isEmpty) return 0;
  var index = 0;
  for (var i = 0; i < blocks.length; i++) {
    if (blocks[i].start <= place) {
      index = i;
    } else {
      break;
    }
  }
  return index;
}

List<ReaderBlock> readerBlocks(String text) {
  if (text.isEmpty) return const [];
  final blocks = <ReaderBlock>[];
  for (final match in RegExp(r'[^\n]+').allMatches(text)) {
    final line = match.group(0)!;
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final start = match.start + line.indexOf(trimmed);
    _appendChunks(blocks, text, start, start + trimmed.length);
  }
  return blocks;
}

SentenceSlice sentenceAround(String text, int wordStart, int wordEnd) {
  final safeStart = wordStart.clamp(0, text.length);
  final safeEnd = wordEnd.clamp(safeStart, text.length);
  var start = 0;
  for (var i = safeStart - 1; i >= 0; i--) {
    if (_isStop(text[i])) {
      start = i + 1;
      break;
    }
  }
  while (start < safeStart && _isSpace(text[start])) {
    start++;
  }
  var end = text.length;
  for (var i = safeEnd; i < text.length; i++) {
    if (_isStop(text[i])) {
      end = i + 1;
      break;
    }
  }
  return SentenceSlice(
    start: start,
    end: end,
    text: text.substring(start, end).trim(),
  );
}

void _appendChunks(List<ReaderBlock> blocks, String text, int start, int end) {
  const limit = 700;
  if (end - start <= limit) {
    blocks.add(
      ReaderBlock(
        start: start,
        pieces: _stickPunctuation(_piecesIn(text, start, end)),
      ),
    );
    return;
  }
  var chosen = start + limit;
  for (var i = chosen; i > start + 200; i--) {
    if (!_isStop(text[i])) continue;
    var next = i + 1;
    while (next < end && _isSpace(text[next])) {
      next++;
    }
    chosen = next;
    break;
  }
  if (chosen <= start || chosen >= end) chosen = start + limit;
  blocks.add(
    ReaderBlock(
      start: start,
      pieces: _stickPunctuation(_piecesIn(text, start, chosen)),
    ),
  );
  _appendChunks(blocks, text, chosen, end);
}

List<ReaderPiece> _piecesIn(String text, int start, int end) {
  final slice = text.substring(start, end);
  final pieces = <ReaderPiece>[];
  var cursor = 0;
  for (final match in RegExp(
    r"[A-Za-z]+(?:'[A-Za-z]+)?",
  ).allMatches(slice)) {
    if (match.start > cursor) {
      pieces.add(
        ReaderPiece(
          shown: slice.substring(cursor, match.start),
          wordStart: start + cursor,
          wordEnd: start + match.start,
        ),
      );
    }
    pieces.add(
      ReaderPiece(
        shown: match.group(0)!,
        word: match.group(0),
        wordStart: start + match.start,
        wordEnd: start + match.end,
      ),
    );
    cursor = match.end;
  }
  if (cursor < slice.length) {
    pieces.add(
      ReaderPiece(
        shown: slice.substring(cursor),
        wordStart: start + cursor,
        wordEnd: end,
      ),
    );
  }
  return pieces;
}

/// Pull punctuation onto the neighboring word so Wrap cannot leave "." alone.
List<ReaderPiece> _stickPunctuation(List<ReaderPiece> pieces) {
  final out = <ReaderPiece>[];
  final pending = StringBuffer();
  int? pendingStart;
  var pendingEnd = 0;

  void clearPending() {
    pending.clear();
    pendingStart = null;
  }

  for (final piece in pieces) {
    if (piece.isWord) {
      final lead = pending.toString();
      clearPending();
      out.add(
        ReaderPiece(
          shown: lead + piece.shown,
          word: piece.word,
          wordStart: piece.wordStart,
          wordEnd: piece.wordEnd,
        ),
      );
      continue;
    }
    final text = piece.shown;
    var index = 0;
    while (index < text.length) {
      if (_isSpace(text[index])) {
        final start = index;
        while (index < text.length && _isSpace(text[index])) {
          index++;
        }
        out.add(
          ReaderPiece(
            shown: text.substring(start, index),
            wordStart: piece.wordStart + start,
            wordEnd: piece.wordStart + index,
          ),
        );
        continue;
      }
      if (_isPunct(text[index])) {
        final start = index;
        while (index < text.length && _isPunct(text[index])) {
          index++;
        }
        final punct = text.substring(start, index);
        if (out.isNotEmpty && out.last.isWord && pending.isEmpty) {
          final last = out.removeLast();
          out.add(
            ReaderPiece(
              shown: last.shown + punct,
              word: last.word,
              wordStart: last.wordStart,
              wordEnd: last.wordEnd,
            ),
          );
        } else {
          pendingStart ??= piece.wordStart + start;
          pending.write(punct);
          pendingEnd = piece.wordStart + index;
        }
        continue;
      }
      final start = index;
      while (index < text.length &&
          !_isSpace(text[index]) &&
          !_isPunct(text[index])) {
        index++;
      }
      final token = text.substring(start, index);
      final lead = pending.toString();
      final leadStart = pendingStart;
      clearPending();
      out.add(
        ReaderPiece(
          shown: lead + token,
          wordStart: leadStart ?? piece.wordStart + start,
          wordEnd: piece.wordStart + index,
        ),
      );
    }
  }
  if (pending.isNotEmpty) {
    out.add(
      ReaderPiece(
        shown: pending.toString(),
        wordStart: pendingStart!,
        wordEnd: pendingEnd,
      ),
    );
  }
  return out;
}

bool _isPunct(String char) {
  if (_isSpace(char)) return false;
  final code = char.codeUnitAt(0);
  final letter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  final digit = code >= 48 && code <= 57;
  return !letter && !digit;
}

bool _isStop(String char) => char == '.' || char == '!' || char == '?';

bool _isSpace(String char) =>
    char == ' ' || char == '\n' || char == '\t' || char == '\r';

BookText _extractTxt(String fileName, List<int> bytes) {
  if (bytes.isEmpty) throw const BookOpenError('这本书是空的');
  var data = bytes;
  if (data.length >= 3 &&
      data[0] == 0xEF &&
      data[1] == 0xBB &&
      data[2] == 0xBF) {
    data = data.sublist(3);
  }
  final text = utf8
      .decode(data, allowMalformed: true)
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trim();
  if (text.isEmpty) throw const BookOpenError('这本书没有可读的文字');
  return BookText(title: _titleFromName(fileName), text: text);
}

BookText _extractEpub(String fileName, List<int> bytes) {
  if (bytes.isEmpty) throw const BookOpenError('这本书是空的');
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    throw const BookOpenError('这本书打不开');
  }
  final files = <String, ArchiveFile>{};
  for (final file in archive) {
    if (!file.isFile) continue;
    final key = file.name
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    files[key] = file;
  }
  final containerFile = _findFile(files, 'META-INF/container.xml');
  if (containerFile == null) throw const BookOpenError('这本书打不开');
  final container = _zipText(containerFile);
  final opfPath = RegExp(
    '''full-path\\s*=\\s*(['"])(.*?)\\1''',
    caseSensitive: false,
  ).firstMatch(container)?.group(2)?.trim();
  if (opfPath == null || opfPath.isEmpty) {
    throw const BookOpenError('这本书打不开');
  }
  final opfKey = opfPath
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'^/+'), '')
      .split('#')
      .first;
  final opfFile = _findFile(files, opfKey);
  if (opfFile == null) throw const BookOpenError('这本书打不开');
  final opf = _zipText(opfFile);
  final opfDir = opfKey.contains('/')
      ? opfKey.substring(0, opfKey.lastIndexOf('/'))
      : '';
  final manifest = <String, String>{};
  for (final tag in RegExp(
    r'<item\b[^>]*>',
    caseSensitive: false,
  ).allMatches(opf)) {
    final raw = tag.group(0)!;
    final id = _attr(raw, 'id');
    final href = _attr(raw, 'href');
    if (id != null && href != null && href.isNotEmpty) {
      manifest[id] = href;
    }
  }
  final hrefs = <String>[];
  for (final tag in RegExp(
    r'<itemref\b[^>]*>',
    caseSensitive: false,
  ).allMatches(opf)) {
    final id = _attr(tag.group(0)!, 'idref');
    final href = id == null ? null : manifest[id];
    if (href != null) hrefs.add(href);
  }
  if (hrefs.isEmpty) hrefs.addAll(manifest.values);
  final chapters = <String>[];
  for (final href in hrefs) {
    final file = _findFile(files, _joinZip(opfDir, href));
    if (file == null) continue;
    final chapter = htmlToText(_zipText(file));
    if (chapter.isNotEmpty) chapters.add(chapter);
  }
  final text = chapters.join('\n\n').trim();
  if (text.isEmpty) throw const BookOpenError('这本书没有可读的文字');
  return BookText(title: _epubTitle(opf, fileName), text: text);
}

String htmlToText(String html) {
  var source = html.replaceAll(
    RegExp(
      r'<(script|style)\b[^>]*>[\s\S]*?</\1>',
      caseSensitive: false,
    ),
    ' ',
  );
  source = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  source = source.replaceAll('\n', ' ');
  source = source.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  source = source.replaceAll(
    RegExp(
      r'</(p|div|h[1-6]|li|tr|blockquote|section|article)>',
      caseSensitive: false,
    ),
    '\n',
  );
  source = source.replaceAll(RegExp(r'<[^>]+>'), '');
  source = _decodeEntities(source);
  final lines = <String>[];
  for (final line in source.split('\n')) {
    final trimmed = line.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    if (trimmed.isNotEmpty) lines.add(trimmed);
  }
  return lines.join('\n\n');
}

String _epubTitle(String opf, String fileName) {
  final raw = RegExp(
    r'<dc:title\b[^>]*>([\s\S]*?)</dc:title>',
    caseSensitive: false,
  ).firstMatch(opf)?.group(1);
  final fallback = RegExp(
    r'<title\b[^>]*>([\s\S]*?)</title>',
    caseSensitive: false,
  ).firstMatch(opf)?.group(1);
  final picked = (raw ?? fallback ?? '').replaceAll(RegExp(r'<[^>]+>'), '');
  final title = _decodeEntities(picked).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (title.isEmpty) return _titleFromName(fileName);
  return title;
}

String _titleFromName(String fileName) {
  final base = fileName.split(RegExp(r'[/\\]')).last.trim();
  final dot = base.lastIndexOf('.');
  final stem = dot > 0 ? base.substring(0, dot) : base;
  final title = stem.trim();
  return title.isEmpty ? '未命名' : title;
}

String? _attr(String tag, String name) {
  return RegExp(
    '$name\\s*=\\s*([\'"])(.*?)\\1',
    caseSensitive: false,
  ).firstMatch(tag)?.group(2)?.trim();
}

String _joinZip(String dir, String href) {
  final clean = Uri.decodeFull(href.split('#').first.trim());
  if (clean.startsWith('/')) {
    return clean.replaceFirst(RegExp(r'^/+'), '');
  }
  final parts = <String>[
    ...dir.split('/').where((part) => part.isNotEmpty),
    ...clean.split('/'),
  ];
  final stack = <String>[];
  for (final part in parts) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (stack.isNotEmpty) stack.removeLast();
      continue;
    }
    stack.add(part);
  }
  return stack.join('/');
}

ArchiveFile? _findFile(Map<String, ArchiveFile> files, String path) {
  final direct = files[path];
  if (direct != null) return direct;
  final lower = path.toLowerCase();
  for (final entry in files.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  return null;
}

String _zipText(ArchiveFile file) {
  final bytes = file.readBytes();
  if (bytes == null || bytes.isEmpty) return '';
  return utf8.decode(bytes, allowMalformed: true);
}

String _decodeEntities(String input) {
  final numeric = input
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
        return _char(int.tryParse(match.group(1)!, radix: 16));
      })
      .replaceAllMapped(RegExp(r'&#([0-9]+);'), (match) {
        return _char(int.tryParse(match.group(1)!));
      });
  return numeric
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}

String _char(int? code) {
  if (code == null || code < 0 || code > 0x10FFFF) return '';
  return String.fromCharCode(code);
}

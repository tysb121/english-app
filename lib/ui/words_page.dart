import 'package:flutter/material.dart';

import '../data/cefr_core.dart';
import '../engine/pos_label.dart';
import '../reading/book_text.dart';
import '../reading/reader_book.dart';
import 'english_app.dart';
import 'reader_page.dart';
import 'theme.dart';

/// Lookup against the on-device wordbook. Searching writes no study item.
class WordsPage extends StatefulWidget {
  const WordsPage({super.key});

  @override
  State<WordsPage> createState() => _WordsPageState();
}

class _WordsPageState extends State<WordsPage> {
  final _query = TextEditingController();
  var _generation = 0;
  List<CefrWord> _hits = const [];
  List<ReaderBookSummary> _books = const [];
  String? _note;
  String? _bookNote;
  var _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadShelf());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _reloadShelf() async {
    final reader = AppScope.of(context).reader;
    if (reader == null) return;
    final books = await reader.listBooks();
    if (!mounted) return;
    setState(() => _books = books);
  }

  Future<void> _openPicked() async {
    if (_opening) return;
    final model = AppScope.of(context);
    final pick = model.pickLocalBook;
    final reader = model.reader;
    if (pick == null || reader == null) {
      setState(() => _bookNote = '阅读还没准备好');
      return;
    }
    setState(() {
      _opening = true;
      _bookNote = null;
    });
    try {
      final picked = await pick();
      if (!mounted) return;
      if (picked == null) {
        setState(() => _opening = false);
        return;
      }
      final book = await reader.openBytes(name: picked.name, bytes: picked.bytes);
      if (!mounted) return;
      setState(() => _opening = false);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ReaderPage(bookId: book.id)),
      );
      if (mounted) await _reloadShelf();
    } on BookOpenError catch (error) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _bookNote = error.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _bookNote = '这本书打不开';
      });
    }
  }

  Future<void> _openSaved(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReaderPage(bookId: id)),
    );
    if (mounted) await _reloadShelf();
  }

  Future<void> _lookup(String raw) async {
    final text = raw.trim();
    final generation = ++_generation;
    if (text.isEmpty) {
      setState(() {
        _hits = const [];
        _note = null;
      });
      return;
    }
    final search = AppScope.of(context).searchWords;
    if (search == null) {
      setState(() {
        _hits = const [];
        _note = '词书还没准备好';
      });
      return;
    }
    final hits = await search(query: text, limit: cefrLookupCap);
    if (!mounted || generation != _generation) return;
    setState(() {
      _hits = hits;
      _note = hits.isEmpty ? '词书里没有这一条' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim();
    return SoftScaffold(
      title: '词',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: TextField(
              controller: _query,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(hintText: '查英文或中文'),
              onChanged: _lookup,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                if (query.isEmpty) ...[
                  const SectionTitle('在读', icon: Icons.menu_book_outlined),
                  FilledButton.icon(
                    onPressed: _opening ? null : _openPicked,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('打开一本书'),
                  ),
                  if (_bookNote != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _bookNote!,
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                  for (final book in _books)
                    AppCard(
                      onTap: () => _openSaved(book.id),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            book.title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            book.place > 0 ? '接着读' : '从头读',
                            style: const TextStyle(color: muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  const EmptyHint(
                    icon: Icons.search,
                    title: '查本机词书',
                    subtitle: '输入英文或中文。查阅不记成绩。',
                  ),
                ] else if (_note != null)
                  EmptyHint(
                    icon: Icons.search_off,
                    title: _note!,
                    subtitle: '换一个词再查。',
                  )
                else
                  for (final word in _hits) _hit(word),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hit(CefrWord word) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            word.en,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(word.cn, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 2),
          Text(
            posLabelZh(word.pos),
            style: const TextStyle(color: muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

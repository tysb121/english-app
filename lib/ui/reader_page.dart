import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../reading/book_text.dart';
import '../reading/gloss.dart';
import 'english_app.dart';
import 'theme.dart';

/// Continuous reading. A place is a character offset into the extracted text.
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, required this.bookId});

  final String bookId;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _items = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  String _title = '在读';
  String _text = '';
  List<ReaderBlock> _blocks = const [];
  var _place = 0;
  var _armed = false;
  var _leaving = false;
  var _allowPop = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onPositions);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onPositions);
    super.dispose();
  }

  Future<void> _load() async {
    final library = AppScope.of(context).reader;
    if (library == null) {
      setState(() => _error = '阅读还没准备好');
      return;
    }
    final book = await library.book(widget.bookId);
    if (!mounted) return;
    if (book == null) {
      setState(() => _error = '这本书打不开');
      return;
    }
    final blocks = readerBlocks(book.text);
    setState(() {
      _title = book.title;
      _text = book.text;
      _blocks = blocks;
      _place = book.place;
      _error = null;
    });
    _reveal(blockIndexForPlace(blocks, book.place));
  }

  void _reveal(int index) {
    void attempt(int tries) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (index > 0 && _items.isAttached) {
          _items.jumpTo(index: index);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _armed = true;
          });
          return;
        }
        if (index == 0 || tries <= 0) {
          _armed = true;
          return;
        }
        attempt(tries - 1);
      });
    }

    attempt(4);
  }

  void _onPositions() {
    if (!_armed || _blocks.isEmpty) return;
    ItemPosition? top;
    for (final position in _positions.itemPositions.value) {
      if (position.itemTrailingEdge <= 0) continue;
      if (top == null || position.index < top.index) top = position;
    }
    if (top == null || top.index < 0 || top.index >= _blocks.length) return;
    _place = _blocks[top.index].start;
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    final library = AppScope.of(context).reader;
    if (library != null) {
      await library.savePlace(widget.bookId, _place);
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _openGloss(ReaderPiece piece) async {
    final word = piece.word;
    if (word == null || _text.isEmpty) return;
    final sentence = sentenceAround(_text, piece.wordStart, piece.wordEnd).text;
    if (sentence.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: mist,
      builder: (context) => GlossSheet(word: word, sentence: sentence),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _leave();
      },
      child: SoftScaffold(
        title: _title,
        leading: IconButton(
          tooltip: '返回',
          onPressed: _leave,
          icon: const Icon(Icons.arrow_back),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return EmptyHint(
        icon: Icons.menu_book_outlined,
        title: _error!,
        subtitle: '回到词页再打开一次。',
      );
    }
    if (_blocks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ScrollablePositionedList.builder(
      itemScrollController: _items,
      itemPositionsListener: _positions,
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 48),
      itemCount: _blocks.length,
      itemBuilder: (context, index) {
        final block = _blocks[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Wrap(
            spacing: 0,
            runSpacing: 2,
            children: [
              for (final piece in block.pieces) _piece(piece),
            ],
          ),
        );
      },
    );
  }

  Widget _piece(ReaderPiece piece) {
    final style = const TextStyle(fontSize: 19, height: 1.55, color: ink);
    final text = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(piece.shown, style: style),
    );
    if (!piece.isWord) return text;
    return Semantics(
      button: true,
      label: piece.word,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openGloss(piece),
        child: text,
      ),
    );
  }
}

class GlossSheet extends StatefulWidget {
  const GlossSheet({super.key, required this.word, required this.sentence});

  final String word;
  final String sentence;

  @override
  State<GlossSheet> createState() => _GlossSheetState();
}

class _GlossSheetState extends State<GlossSheet> {
  String? _gloss;
  String? _source;
  String? _note;
  var _left = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    final model = AppScope.of(context);
    final library = model.reader;
    if (library == null) {
      setState(() => _note = '词书还没准备好');
      return;
    }
    final hit = await library.exactWord(widget.word);
    final cached = await library.cachedGloss(
      word: widget.word,
      sentence: widget.sentence,
    );
    if (!mounted) return;
    final plan = planGloss(
      hit: hit,
      cached: cached,
      hasKey: model.hasDeepSeekKey,
    );
    switch (plan.step) {
      case GlossStep.book:
      case GlossStep.cache:
        setState(() {
          _gloss = plan.glossCn;
          _source = plan.step == GlossStep.book ? '本机词书' : '这一句';
          _note = null;
        });
        return;
      case GlossStep.needsKey:
        setState(() {
          _note = '填写密钥后才能查这个词。到「我的」粘贴 DeepSeek 密钥。';
        });
        return;
      case GlossStep.ask:
        setState(() => _note = '在看这一句');
        try {
          final posted = await model.poster.send(
            glossRequest(
              apiKey: model.deepSeekKey,
              baseUrl: model.deepSeekBase,
              model: model.deepSeekModel,
              word: widget.word,
              sentence: widget.sentence,
            ),
          );
          if (!mounted) return;
          final gloss = posted.status == 200 ? glossFromBody(posted.body) : null;
          if (gloss == null) {
            if (!mounted) return;
            setState(() => _note = '这一句暂时没有解释');
            return;
          }
          if (!mounted) return;
          setState(() {
            _gloss = gloss;
            _source = '这一句';
            _note = null;
          });
          await library.saveGloss(
            word: widget.word,
            sentence: widget.sentence,
            glossCn: gloss,
          );
        } on Object {
          if (!mounted || _gloss != null) return;
          setState(() => _note = '这一句暂时没有解释');
        }
    }
  }

  Future<void> _leave() async {
    final gloss = _gloss;
    if (gloss == null || _left || _busy) return;
    final library = AppScope.of(context).reader;
    if (library == null) return;
    setState(() => _busy = true);
    await library.leaveWord(
      word: widget.word,
      sentence: widget.sentence,
      glossCn: gloss,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _left = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gloss = _gloss;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.word,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            if (_source != null) ...[
              const SizedBox(height: 4),
              Text(_source!, style: const TextStyle(color: muted, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Text(
              gloss ?? _note ?? '在查这个词',
              style: const TextStyle(fontSize: 16, height: 1.45),
            ),
            if (gloss != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _left || _busy ? null : _leave,
                  child: Text(_left ? '已留下' : '留下这个词'),
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

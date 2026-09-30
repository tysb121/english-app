import 'package:flutter/material.dart';

import '../engine/lesson_store.dart';
import 'english_app.dart';
import 'theme.dart';

/// Shortcut sheet for today's due error words (coach thread also covers errors).
class PracticePage extends StatefulWidget {
  const PracticePage({super.key});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  final TextEditingController _answer = TextEditingController();
  VocabFeedback? _vocab;
  String? _errorGap;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    final store = model.store;
    if (_vocab == null) {
      final pending = store.pendingError;
      if (pending != null) {
        _vocab = pending;
        _errorGap = store.errorGapLabel(pending.wordId);
      }
    }
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('关闭'),
        ),
        leadingWidth: 72,
        title: const Text('错词'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 280),
            children: [_errorBody(store)],
          ),
          if (_sheet() case final sheet?) HalfSheet(child: sheet),
        ],
      ),
    );
  }

  Widget? _sheet() {
    if (_vocab == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _vocab!.correct ? '对了' : _vocab!.correctEn,
          style: TextStyle(
            color: _vocab!.correct ? pine : wrongRed,
            fontSize: 18,
          ),
        ),
        if (_errorGap != null) Text(_errorGap!),
        const SizedBox(height: 12),
        FilledButton(onPressed: _nextError, child: const Text('下一条')),
      ],
    );
  }

  Widget _errorBody(LessonStore store) {
    final id = store.currentErrorId;
    if (id == null) return const Text('今天的错词看完了');
    final word = store.word(id);
    final sentence = store.errorSentence(id);
    final pending = _vocab != null;
    if (sentence != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(sentence, style: const TextStyle(fontSize: 22, color: ink)),
          const SizedBox(height: 8),
          const Text('请重写整句'),
          if (!pending) ...[
            const SizedBox(height: 12),
            AnswerField(controller: _answer),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _submitError(store, id),
              child: const Text('提交'),
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(word?.cn ?? '', style: const TextStyle(fontSize: 36, color: ink)),
        Text(word?.pos ?? ''),
        if (!pending) ...[
          const SizedBox(height: 16),
          AnswerField(controller: _answer),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _submitError(store, id),
            child: const Text('提交'),
          ),
        ],
      ],
    );
  }

  void _submitError(LessonStore store, String id) {
    final feedback = store.submitErrorReview(id, _answer.text);
    final gap = store.errorGapLabel(id);
    AppScope.of(context).commit();
    setState(() {
      _vocab = feedback;
      _errorGap = gap;
    });
  }

  void _nextError() {
    final store = AppScope.of(context).store;
    store.advanceErrorCursor();
    AppScope.of(context).commit();
    _answer.clear();
    setState(() {
      _vocab = null;
      _errorGap = null;
    });
    if (store.currentErrorId == null && mounted) {
      Navigator.maybePop(context);
    }
  }
}

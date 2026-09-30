import 'package:flutter/material.dart';

import '../engine/lesson_store.dart';
import 'english_app.dart';
import 'theme.dart';

enum PracticeKind { vocab, dialogue, quiz, errors }

class PracticePage extends StatefulWidget {
  const PracticePage({super.key, required this.kind});

  final PracticeKind kind;

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  final TextEditingController _answer = TextEditingController();
  late PracticeKind _kind = widget.kind;
  bool _bootstrapped = false;
  bool _busy = false;
  bool _grammar = false;
  bool _showSummary = false;
  String? _failure;
  VocabFeedback? _vocab;
  GradeResult? _grade;
  int? _quizFocus;
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
    if (!_bootstrapped && _kind == PracticeKind.dialogue) {
      _bootstrapped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (model.store.shouldRequestScene) _writeScene(model);
      });
    }
    if (_kind == PracticeKind.quiz && _quizFocus == null && !_showSummary) {
      _quizFocus = store.openQuizIndex;
      if (_quizFocus == null) _showSummary = true;
    }
    if (_kind == PracticeKind.vocab && _vocab == null) {
      _vocab = store.pendingVocab;
    }
    if (_kind == PracticeKind.errors && _vocab == null) {
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
        title: Text(_title),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 280),
            children: [
              switch (_kind) {
                PracticeKind.vocab => _vocabBody(model),
                PracticeKind.dialogue => _dialogueBody(model),
                PracticeKind.quiz => _quizBody(model),
                PracticeKind.errors => _errorBody(model),
              },
            ],
          ),
          if (_sheet(model) case final sheet?) HalfSheet(child: sheet),
        ],
      ),
    );
  }

  String get _title {
    return switch (_kind) {
      PracticeKind.vocab => '认词',
      PracticeKind.dialogue => '对话',
      PracticeKind.quiz => '考核',
      PracticeKind.errors => '错词',
    };
  }

  Widget? _sheet(dynamic model) {
    if (_failure != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_failure!),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _retry,
            child: const Text('重试'),
          ),
        ],
      );
    }
    final grade = _grade;
    if (grade != null) {
      final finished = _kind == PracticeKind.quiz && _showSummary;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (grade.pass)
            const Text('对了', style: TextStyle(color: pine, fontSize: 18)),
          for (final item in grade.errors.take(2)) ...[
            Text(item.excerpt, style: const TextStyle(color: wrongRed)),
            Text(item.fix),
            Text(item.whyCn),
          ],
          Text(grade.correctedEn),
          const SizedBox(height: 12),
          if (_kind == PracticeKind.dialogue)
            FilledButton(onPressed: _nextLine, child: const Text('下一句')),
          if (_kind == PracticeKind.quiz && !finished)
            FilledButton(onPressed: _nextQuiz, child: const Text('下一题')),
          if (finished) _summary(model.store),
        ],
      );
    }
    if (_kind == PracticeKind.errors && _vocab != null) {
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
    if (_kind == PracticeKind.quiz && _showSummary) {
      return _summary(model.store);
    }
    if (_kind == PracticeKind.dialogue && model.store.dialogueDone && _grade == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('对话完成'),
          const SizedBox(height: 12),
          FilledButton(onPressed: _goQuiz, child: const Text('去考核')),
        ],
      );
    }
    return null;
  }

  Widget _summary(dynamic store) {
    final count = store.quizPassCount as int;
    final passed = count >= 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('通过了 $count 题'),
        const SizedBox(height: 12),
        if (!passed)
          FilledButton(
            onPressed: () {
              store.redoFailedQuiz();
              AppScope.of(context).commit();
              setState(() {
                _showSummary = false;
                _grade = null;
                _failure = null;
                _quizFocus = store.openQuizIndex as int?;
                _answer.clear();
              });
            },
            child: const Text('重做没过的'),
          ),
        TextButton(
          onPressed: () => Navigator.maybePop(context),
          child: Text(passed ? '回到今天' : '先回到今天'),
        ),
      ],
    );
  }

  Widget _vocabBody(dynamic model) {
    final store = model.store as LessonStore;
    final id = store.currentVocabId;
    if (id == null) {
      return const Text('今天的认词做完了');
    }
    final word = store.word(id)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(word.cn, style: const TextStyle(fontSize: 36, color: ink)),
        const SizedBox(height: 8),
        Text(word.pos),
        const SizedBox(height: 24),
        AnswerField(controller: _answer),
        const SizedBox(height: 16),
        if (_vocab == null)
          FilledButton(
            onPressed: _busy ? null : () => _submitVocab(store),
            child: const Text('提交'),
          )
        else ...[
          Text(
            _vocab!.correct ? '对了' : _vocab!.correctEn,
            style: TextStyle(
              color: _vocab!.correct ? pine : wrongRed,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _nextVocab(store),
            child: Text(_vocab!.correct ? '下一个' : '先记住，下一个'),
          ),
        ],
      ],
    );
  }

  Widget _dialogueBody(dynamic model) {
    final store = model.store as LessonStore;
    final scene = store.scene;
    if (scene == null) {
      if (_failure != null) return const SizedBox.shrink();
      return const Text('正在写今天的场景');
    }
    if (store.dialogueDone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(scene.scenarioCn, style: const TextStyle(fontSize: 28, color: ink)),
          Text(scene.scenarioEn),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _grammar = !_grammar),
              child: const Text('这个语法'),
            ),
          ),
          if (_grammar) _grammarCard(model, scene),
        ],
      );
    }
    final cursor = store.dialogueCursor;
    final lines = scene.dialogue;
    if (cursor < 0 || cursor >= lines.length) {
      return const SizedBox.shrink();
    }
    final line = lines[cursor];
    final start = cursor >= 2 ? cursor - 2 : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(scene.scenarioCn, style: const TextStyle(fontSize: 22, color: ink)),
        Text(scene.scenarioEn, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 12),
        for (var i = start; i < cursor; i++)
          Text(lines[i].en, style: const TextStyle(fontSize: 13, color: ink)),
        const SizedBox(height: 12),
        if (line.speaker == 'A') ...[
          if (model.hasTokenHubKey as bool)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : () => _translate(model, line.en),
                child: const Text('参考译文'),
              ),
            ),
          Text(line.en, style: const TextStyle(fontSize: 28, color: ink)),
          const SizedBox(height: 8),
          Text(line.cn),
          if (store.referencePreview != null) Text(store.referencePreview!),
          const SizedBox(height: 16),
          FilledButton(onPressed: _nextLine, child: const Text('下一句')),
        ] else ...[
          const Text('轮到你'),
          const SizedBox(height: 8),
          Text(line.cn, style: const TextStyle(fontSize: 28, color: ink)),
          const SizedBox(height: 16),
          AnswerField(controller: _answer),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : () => _sendLine(model, line),
            child: const Text('发送'),
          ),
        ],
      ],
    );
  }

  Widget _grammarCard(dynamic model, LessonScene scene) {
    final store = model.store as LessonStore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(scene.grammarCn),
        for (final example in scene.grammarExamples) Text(example),
        TextButton(
          onPressed: _busy ? null : () => _explain(model),
          child: const Text('再讲讲'),
        ),
        if (store.lastExplainCn != null) Text(store.lastExplainCn!),
        if (store.lastExplainEn != null) Text(store.lastExplainEn!),
      ],
    );
  }

  Widget _quizBody(dynamic model) {
    final store = model.store as LessonStore;
    if (_showSummary) return const Text('四题都有结果了');
    final index = _quizFocus;
    if (index == null) return const SizedBox.shrink();
    if (index == 2 && store.scene == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (store.sceneInFlight) const Text('正在写今天的场景'),
          FilledButton(
            onPressed: _busy ? null : () => _writeScene(model),
            child: const Text('先生成场景'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${index + 1} / 4'),
        const SizedBox(height: 12),
        Text(store.quizPrompt(index), style: const TextStyle(fontSize: 24, color: ink)),
        const SizedBox(height: 16),
        AnswerField(controller: _answer),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : () => _submitQuiz(model, index),
          child: const Text('提交'),
        ),
      ],
    );
  }

  Widget _errorBody(dynamic model) {
    final store = model.store as LessonStore;
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
              onPressed: _busy ? null : () => _submitError(store, id),
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
            onPressed: _busy ? null : () => _submitError(store, id),
            child: const Text('提交'),
          ),
        ],
      ],
    );
  }

  void _submitVocab(LessonStore store) {
    final feedback = store.submitVocab(_answer.text);
    AppScope.of(context).commit();
    setState(() => _vocab = feedback);
  }

  void _nextVocab(LessonStore store) {
    store.advanceVocab();
    AppScope.of(context).commit();
    _answer.clear();
    setState(() => _vocab = null);
    if (store.currentVocabId == null && mounted) {
      Navigator.maybePop(context);
    }
  }

  Future<void> _writeScene(dynamic model) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final error = await model.fillScene() as String?;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = error;
    });
  }

  Future<void> _sendLine(dynamic model, SceneLine line) async {
    final store = model.store as LessonStore;
    final words = store.scheduledNewWords().map((id) => store.word(id)?.en ?? id).join(', ');
    setState(() {
      _busy = true;
      _failure = null;
      _grade = null;
    });
    final error = await model.gradeLine(
      prompt: '用英文接话',
      requiredWords: '要表达的意思：${line.cn}。今天的词：$words',
      answer: _answer.text,
    ) as String?;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = error;
      _grade = error == null ? store.lastGrade : null;
    });
  }

  void _nextLine() {
    final model = AppScope.of(context);
    model.store.advanceDialogue();
    model.commit();
    _answer.clear();
    setState(() {
      _grade = null;
      _failure = null;
    });
  }

  void _goQuiz() {
    setState(() {
      _kind = PracticeKind.quiz;
      _grade = null;
      _failure = null;
      _showSummary = false;
      _quizFocus = null;
      _answer.clear();
    });
  }

  Future<void> _submitQuiz(dynamic model, int index) async {
    setState(() {
      _busy = true;
      _failure = null;
      _grade = null;
    });
    final error = await model.gradeQuiz(index, _answer.text) as String?;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = error;
      _grade = error == null ? (model.store as LessonStore).lastGrade : null;
    });
  }

  void _nextQuiz() {
    final store = AppScope.of(context).store;
    _answer.clear();
    setState(() {
      _grade = null;
      _failure = null;
      _quizFocus = store.openQuizIndex;
      _showSummary = _quizFocus == null;
    });
  }

  Future<void> _explain(dynamic model) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final error = await model.explain() as String?;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = error;
    });
  }

  Future<void> _translate(dynamic model, String text) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final error = await model.translate(text, toChinese: true) as String?;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = error;
    });
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

  void _retry() {
    final model = AppScope.of(context);
    if (_kind == PracticeKind.dialogue && model.store.scene == null) {
      _writeScene(model);
      return;
    }
    if (_kind == PracticeKind.quiz && _quizFocus != null) {
      _submitQuiz(model, _quizFocus!);
      return;
    }
    if (_kind == PracticeKind.dialogue) {
      final scene = model.store.scene;
      final cursor = model.store.dialogueCursor;
      if (scene != null && cursor < scene.dialogue.length) {
        _sendLine(model, scene.dialogue[cursor]);
      }
    }
  }
}

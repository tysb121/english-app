import 'package:english_app/app/app_model.dart';
import 'package:english_app/engine/api_requests.dart';
import 'package:english_app/engine/chat_message.dart';
import 'package:english_app/engine/chat_thread.dart';
import 'package:english_app/net/poster.dart';
import 'package:english_app/ui/coach_thread_page.dart';
import 'package:english_app/ui/english_app.dart';
import 'package:english_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cefr_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'home shows all today words; coach has opener without card wall',
    (tester) async {
      final view = tester.view;
      view.physicalSize = const Size(400, 900);
      view.devicePixelRatio = 1.0;
      addTearDown(view.resetPhysicalSize);
      addTearDown(view.resetDevicePixelRatio);

      final store = fixtureStore(
        clock: () => DateTime(2026, 1, 1),
        levelChosen: true,
      );
      store.ensureTodayPlan();
      final ids = store.requiredTodayPlan.newWordIds;
      expect(ids.length, greaterThanOrEqualTo(5));

      final model = AppModel(
        store: store,
        poster: _SilentPoster(),
        deepSeekKey: 'test-key',
        unlocked: true,
        chat: ChatThread(idFactory: () => 's1'),
      );
      await tester.pumpWidget(EnglishApp(model: model));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('上课'), findsOneWidget);
      expect(find.text('先到这'), findsOneWidget);
      expect(find.text('今日练习的词'), findsNothing);
      expect(find.textContaining('看过了'), findsNothing);
    },
  );

  testWidgets('coach markdown chat has no raw bold markers', (tester) async {
    final store = fixtureStore(
      clock: () => DateTime(2026, 1, 1),
      levelChosen: true,
    );
    store.ensureTodayPlan();
    final chat = ChatThread(idFactory: () => 's2');
    chat.messages.addAll([
      const ChatMessage(
        id: 'u1',
        role: ChatRole.user,
        content: 'I like chicken.',
      ),
      const ChatMessage(
        id: 'a1',
        role: ChatRole.assistant,
        content:
            'Soft fix: **I like chicken.**\n\n- Keep it short\n\nTry `hello`.',
      ),
    ]);
    final model = AppModel(
      store: store,
      poster: _SilentPoster(),
      deepSeekKey: 'test-key',
      unlocked: true,
      chat: chat,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppScope(model: model, child: const CoachThreadPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('I like chicken.'), findsWidgets);
    expect(find.textContaining('Keep it short'), findsOneWidget);
  });
}

class _SilentPoster implements Poster {
  @override
  Future<Posted> send(ApiCall call) async => const Posted(200, '');
}

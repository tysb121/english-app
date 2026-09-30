import 'package:flutter/material.dart';

import '../app/app_model.dart';
import 'level_page.dart';
import 'records_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'today_page.dart';
import 'words_page.dart';

class EnglishApp extends StatelessWidget {
  const EnglishApp({super.key, required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '今日英语',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) {
        return AppScope(model: model, child: child ?? const SizedBox.shrink());
      },
      home: const RootPage(),
    );
  }
}

class AppScope extends InheritedNotifier<AppModel> {
  const AppScope({required AppModel model, required super.child, super.key})
    : super(notifier: model);

  static AppModel of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing');
    return scope!.notifier!;
  }
}

class RootPage extends StatelessWidget {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppScope.of(context);
    if (!model.store.levelChosen) return const LevelPage();
    if (!model.unlocked) return const SettingsPage(gate: true);
    return const HomeShell();
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    const pages = [TodayPage(), WordsPage(), RecordsPage(), SettingsPage()];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.circle_outlined),
            label: '今天',
          ),
          NavigationDestination(icon: Icon(Icons.list_alt), label: '词'),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            label: '记录',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

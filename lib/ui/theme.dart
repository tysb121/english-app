import 'package:flutter/material.dart';

const Color paper = Color(0xFFF6F4EF);
const Color ink = Color(0xFF1B1B1B);
const Color pine = Color(0xFF0E6B45);
const Color wrongRed = Color(0xFF8E2F2F);

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: paper,
    colorScheme: const ColorScheme.light(
      primary: pine,
      onPrimary: Colors.white,
      surface: paper,
      onSurface: ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: pine,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: paper,
      indicatorColor: pine.withValues(alpha: 0.16),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return const TextStyle(color: ink, fontSize: 13);
      }),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(),
    ),
  );
}

class AnswerField extends StatelessWidget {
  const AnswerField({super.key, required this.controller, this.hint = '用英文回答'});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('answer'),
      controller: controller,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      keyboardType: TextInputType.text,
      textCapitalization: TextCapitalization.none,
      style: const TextStyle(color: ink, fontSize: 18),
      decoration: InputDecoration(hintText: hint),
    );
  }
}

class HalfSheet extends StatelessWidget {
  const HalfSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.white,
        elevation: 12,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: child,
          ),
        ),
      ),
    );
  }
}

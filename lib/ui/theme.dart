import 'package:flutter/material.dart';

/// Soft teal / indigo coach palette (pine kept as accent alias).
const Color paper = Color(0xFFF3F6FB);
const Color paperDeep = Color(0xFFE8EEF8);
const Color ink = Color(0xFF1A2332);
const Color muted = Color(0xFF5B6577);
const Color pine = Color(0xFF0F7A6E); // teal accent
const Color indigo = Color(0xFF3D5AFE);
const Color mist = Color(0xFFFFFFFF);
const Color wrongRed = Color(0xFFB42318);
const Color softBorder = Color(0xFFD7DEEA);

ThemeData buildTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: pine,
    primary: pine,
    secondary: indigo,
    brightness: Brightness.light,
    surface: paper,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: paper,
    colorScheme: base.copyWith(onSurface: ink, primary: pine, secondary: indigo),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: -0.4,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.35),
      bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.35),
      bodySmall: TextStyle(fontSize: 13, color: muted, height: 1.35),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
    ),
    cardTheme: CardThemeData(
      color: mist,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: softBorder),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: pine,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: const BorderSide(color: softBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: mist,
      selectedColor: pine.withValues(alpha: 0.16),
      side: const BorderSide(color: softBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(color: ink, fontWeight: FontWeight.w600),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: mist.withValues(alpha: 0.94),
      indicatorColor: pine.withValues(alpha: 0.14),
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? pine : muted,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? pine : muted, size: 24);
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: mist,
      hintStyle: const TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: softBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: softBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: pine, width: 1.4),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

class SoftScaffold extends StatelessWidget {
  const SoftScaffold({
    super.key,
    required this.body,
    this.title = '今日英语',
    this.leading,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
  });

  final Widget body;
  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7FAFF), paper, paperDeep],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: leading,
          title: Text(title),
          actions: actions,
        ),
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.accent = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: mist,
        borderRadius: radius,
        border: Border.all(
          color: accent ? pine.withValues(alpha: 0.35) : softBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: indigo.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(
                borderRadius: radius,
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: card,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: pine),
            const SizedBox(width: 8),
          ],
          Text(text, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.subtitle,
  }) : assert(detail != null || subtitle != null);

  final IconData icon;
  final String title;
  final String? detail;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Icon(icon, size: 36, color: pine.withValues(alpha: 0.85)),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            detail ?? subtitle ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted),
          ),
        ],
      ),
    );
  }
}

class ProgressChip extends StatelessWidget {
  const ProgressChip({
    super.key,
    required this.label,
    required this.done,
    required this.icon,
  });

  final String label;
  final bool done;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: done ? pine.withValues(alpha: 0.14) : mist,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: done ? pine.withValues(alpha: 0.35) : softBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Icon(
              done ? Icons.check_circle_rounded : icon,
              key: ValueKey(done),
              size: 16,
              color: done ? pine : muted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: done ? pine : ink,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class PrimaryCta extends StatefulWidget {
  const PrimaryCta({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<PrimaryCta> createState() => _PrimaryCtaState();
}

class _PrimaryCtaState extends State<PrimaryCta> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFF109E8D), pine, Color(0xFF0B5F6E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: pine.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SizedBox(
            height: 54,
            width: double.infinity,
            child: Center(
              child: Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
        color: mist,
        elevation: 16,
        shadowColor: indigo.withValues(alpha: 0.2),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
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

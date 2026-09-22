import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF4F46E5);
  static const Color primaryDark = Color(0xFF3730A3);
  static const Color accent = Color(0xFF06B6D4);
  static const Color income = Color(0xFF10B981);
  static const Color expense = Color(0xFFEF4444);
  static const Color transfer = Color(0xFF3B82F6);
  static const Color surface = Color(0xFFF8FAFC);
  static const Color card = Colors.white;
  static const Color surfaceDark = Color(0xFF0F172A);
  static const Color cardDark = Color(0xFF1E293B);

  static ThemeData get light => _build(
        brightness: Brightness.light,
        scheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
          primary: primary,
          secondary: accent,
          surface: surface,
        ),
        scaffold: surface,
        cardColor: card,
        inputFill: Colors.white,
        navBackground: card,
        border: Colors.grey.shade300,
        divider: Colors.grey.shade200,
        unselected: Colors.grey.shade600,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        scheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.dark,
          primary: const Color(0xFF818CF8),
          secondary: accent,
          surface: cardDark,
        ),
        scaffold: surfaceDark,
        cardColor: cardDark,
        inputFill: const Color(0xFF1E293B),
        navBackground: const Color(0xFF111827),
        border: const Color(0xFF334155),
        divider: const Color(0xFF1E293B),
        unselected: const Color(0xFF94A3B8),
      );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color scaffold,
    required Color cardColor,
    required Color inputFill,
    required Color navBackground,
    required Color border,
    required Color divider,
    required Color unselected,
  }) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: primary,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border.withValues(alpha: isDark ? 0.8 : 1)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: navBackground,
        indicatorColor: primary.withValues(alpha: isDark ? 0.28 : 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFA5B4FC) : primary,
            );
          }
          return TextStyle(fontSize: 12, color: unselected);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
              color: isDark ? const Color(0xFFA5B4FC) : primary,
              size: 24,
            );
          }
          return IconThemeData(color: unselected, size: 24);
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: divider),
    );
  }

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: primary.withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  static BoxDecoration balanceCardDecoration = BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [primary, primaryDark, Color(0xFF6366F1)],
    ),
    borderRadius: BorderRadius.circular(24),
    boxShadow: [
      BoxShadow(
        color: primary.withValues(alpha: 0.35),
        blurRadius: 20,
        offset: const Offset(0, 10),
      ),
    ],
  );
}

import 'package:flutter/material.dart';

class LeafyTheme {
  static const background = Color(0xfff7f9f6);
  static const surface = Color(0xffffffff);
  static const surfaceSoft = Color(0xffeef5ef);
  static const primary = Color(0xff356a4d);
  static const primaryDark = Color(0xff234c37);
  static const border = Color(0xffdde7df);
  static const muted = Color(0xff718078);
  static const text = Color(0xff203128);
  static const warning = Color(0xffa66b20);
  static const danger = Color(0xffa94747);

  static const darkBackground = Color(0xff101713);
  static const darkSurface = Color(0xff18211c);
  static const darkSurfaceSoft = Color(0xff223128);
  static const darkBorder = Color(0xff314238);
  static const darkText = Color(0xffe7efe9);
  static const darkMuted = Color(0xffa7b5ac);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      surface: surface,
    );

    return _build(
      scheme: scheme,
      scaffold: background,
      card: surface,
      soft: surfaceSoft,
      borderColor: border,
      foreground: text,
      mutedColor: muted,
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      surface: darkSurface,
    ).copyWith(
      primary: const Color(0xff86c79d),
      onPrimary: const Color(0xff0f2a19),
      surface: darkSurface,
      onSurface: darkText,
      outline: darkBorder,
      outlineVariant: const Color(0xff314238),
      surfaceContainerLowest: const Color(0xff101713),
      surfaceContainerLow: const Color(0xff151e19),
      surfaceContainer: const Color(0xff18211c),
      surfaceContainerHigh: const Color(0xff1d2922),
      surfaceContainerHighest: const Color(0xff223128),
      onSurfaceVariant: const Color(0xffa7b5ac),
      tertiary: const Color(0xffd9bd7d),
      tertiaryContainer: const Color(0xff403721),
      onTertiaryContainer: const Color(0xffffe6a8),
      errorContainer: const Color(0xff4a2b25),
      onErrorContainer: const Color(0xffffd9d0),
    );

    return _build(
      scheme: scheme,
      scaffold: darkBackground,
      card: darkSurface,
      soft: darkSurfaceSoft,
      borderColor: darkBorder,
      foreground: darkText,
      mutedColor: darkMuted,
    );
  }

  static ThemeData _build({
    required ColorScheme scheme,
    required Color scaffold,
    required Color card,
    required Color soft,
    required Color borderColor,
    required Color foreground,
    required Color mutedColor,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      dividerColor: borderColor,
      appBarTheme: AppBarThemeData(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scaffold,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: borderColor),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: card,
        labelStyle: TextStyle(color: mutedColor),
        hintStyle: TextStyle(color: mutedColor),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: scheme.primary,
            width: 1.4,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          foregroundColor: scheme.brightness == Brightness.dark
              ? foreground
              : primaryDark,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: soft,
        side: BorderSide(color: borderColor),
        labelStyle: TextStyle(color: foreground),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: soft,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: foreground),
        ),
        height: 72,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: borderColor,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.brightness == Brightness.dark
            ? const Color(0xffe7efe9)
            : text,
        contentTextStyle: TextStyle(
          color: scheme.brightness == Brightness.dark
              ? const Color(0xff172019)
              : Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

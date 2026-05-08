import 'package:flutter/material.dart';

/// PIG theme — matches PIGv4's Navy/Maroon/HotPink color scheme.
class PigTheme {
  static const Color navy = Color(0xFF000080);
  static const Color darkNavy = Color(0xFF1a1a2e);
  static const Color maroon = Color(0xFF800000);
  static const Color hotPink = Color(0xFFFF69B4);
  static const Color cyan = Color(0xFF00FFFF);
  static const Color goldenrod = Color(0xFFDAA520);
  static const Color lawnGreen = Color(0xFF7CFC00);
  static const Color bgPink = Color(0xFFFFEEEE);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkNavy,
      primaryColor: navy,
      colorScheme: const ColorScheme.dark(
        primary: hotPink,
        secondary: goldenrod,
        surface: darkNavy,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: hotPink,
        elevation: 2,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: navy,
        selectedItemColor: hotPink,
        unselectedItemColor: Colors.grey,
      ),
      cardTheme: CardThemeData(
        color: darkNavy.withAlpha(230),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: maroon, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkNavy,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: hotPink),
        ),
        hintStyle: const TextStyle(color: Colors.grey),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return hotPink;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: Colors.grey, width: 2),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: hotPink,
        thumbColor: hotPink,
        inactiveTrackColor: Colors.grey,
        overlayColor: Color(0x29FF69B4),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: maroon,
        foregroundColor: hotPink,
      ),
      iconTheme: const IconThemeData(color: hotPink),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white),
        bodySmall: TextStyle(color: Colors.grey),
        titleLarge: TextStyle(color: hotPink, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: hotPink),
        labelLarge: TextStyle(color: hotPink),
      ),
    );
  }
}

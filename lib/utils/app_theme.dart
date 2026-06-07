import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MashColors {
  static const primary = Color(0xFF8B0000);
  static const secondary = Color(0xFFFFD700);
  static const background = Color(0xFFFFF8E7);
  static const ink = Color(0xFF241A16);
  static const success = Color(0xFF198754);
}

ThemeData buildMashTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: MashColors.primary,
      primary: MashColors.primary,
      secondary: MashColors.secondary,
      surface: MashColors.background,
    ),
    scaffoldBackgroundColor: MashColors.background,
    useMaterial3: true,
  );
  return base.copyWith(
    textTheme: GoogleFonts.fredokaTextTheme(base.textTheme)
        .apply(bodyColor: MashColors.ink, displayColor: MashColors.ink)
        .copyWith(
          displayLarge: GoogleFonts.lilitaOne(fontSize: 54, color: MashColors.ink),
          displayMedium: GoogleFonts.lilitaOne(fontSize: 44, color: MashColors.ink),
          headlineLarge: GoogleFonts.lilitaOne(fontSize: 34, color: MashColors.ink),
          headlineMedium: GoogleFonts.lilitaOne(fontSize: 28, color: MashColors.ink),
          headlineSmall: GoogleFonts.lilitaOne(fontSize: 24, color: MashColors.ink),
          titleLarge: GoogleFonts.lilitaOne(fontSize: 22, color: MashColors.ink),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: MashColors.primary,
      foregroundColor: Colors.white,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shadowColor: MashColors.primary.withValues(alpha: .12),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE8DED1))),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MashColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: GoogleFonts.lilitaOne(fontSize: 17, letterSpacing: .4),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: Colors.white,
      indicatorColor: MashColors.secondary.withValues(alpha: .45),
      labelTextStyle: WidgetStateProperty.all(GoogleFonts.fredoka(fontSize: 11, fontWeight: FontWeight.w700)),
    ),
  );
}

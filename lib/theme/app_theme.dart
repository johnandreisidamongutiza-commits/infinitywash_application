import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryBlue = Color(0xFF0D3B66);
  static const Color lightBlue = Color(0xFFE3F2FD);
  static const Color accentBlue = Color(0xFF2196F3);
  static const Color softGray = Color(0xFFF5F7F9);
  static const Color textDark = Color(0xFF0D3B66);
  static const Color textLight = Color(0xFF707070);
  static const Color borderGray = Color(0xFFE0E0E0);
  static const Color errorRed = Color(0xFFE53935);
  static const Color teamMemberOrange = Color(0xFFFFF3E0);
  static const Color teamMemberIconOrange = Color(0xFFFF9800);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: accentBlue,
        surface: Colors.white,
        background: Colors.white,
      ),
      textTheme: GoogleFonts.lexendTextTheme().copyWith(
        displaySmall: GoogleFonts.lexend(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        headlineMedium: GoogleFonts.lexend(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        titleMedium: GoogleFonts.lexend(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textDark,
        ),
        bodyLarge: GoogleFonts.lexend(
          fontSize: 16,
          color: textDark,
        ),
        bodyMedium: GoogleFonts.lexend(
          fontSize: 14,
          color: textLight,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.lexend(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// Utility class for common styles that don't fit in ThemeData
class AppStyles {
  static BoxDecoration cardDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.5)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.03),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );

  static BoxDecoration selectedCardDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: AppTheme.accentBlue, width: 2),
    boxShadow: [
      BoxShadow(
        color: AppTheme.accentBlue.withValues(alpha: 0.1),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:infinitywash/models/order.dart';

class StatusStyle {
  final Color primary;
  final Color background;
  final Color border;

  const StatusStyle({
    required this.primary,
    required this.background,
    required this.border,
  });
}

class AppTheme {
  // ── 60% Canvas & Neutral Base ──────────────────────────────────────────
  static const Color softGray = Color(0xFFF5F7F9);
  static const Color borderGray = Color(0xFFE0E0E0);
  static const Color lightBlue = Color(0xFFE3F2FD);

  // ── 30% Brand Structure & Content ──────────────────────────────────────
  static const Color primaryBlue = Color(0xFF0D3B66);
  static const Color textDark = Color(0xFF0D3B66);
  static const Color textLight = Color(0xFF707070);

  // ── 10% Action & Semantic Accent ───────────────────────────────────────
  /// Action & focus blue (WCAG AAA/AA compliant, calibrated from 0xFF2196F3)
  static const Color actionBlue = Color(0xFF0284C7);
  static const Color accentBlue = Color(0xFF0284C7);
  static const Color errorRed = Color(0xFFE53935);
  static const Color teamMemberOrange = Color(0xFFFFF3E0);
  static const Color teamMemberIconOrange = Color(0xFFFF9800);

  // ── Option C: Unified Brand-Status Styling ─────────────────────────────
  // 1. All Active Orders: Signature Brand Blue Palette
  static const Color statusActive = Color(0xFF0284C7);
  static const Color statusActiveBg = Color(0xFFE0F2FE);
  static const Color statusActiveBorder = Color(0xFFBAE6FD);

  // 2. Completed / Archived Orders: Neutral Slate Palette
  static const Color statusCompleted = Color(0xFF64748B);
  static const Color statusCompletedBg = Color(0xFFF1F5F9);
  static const Color statusCompletedBorder = Color(0xFFE2E8F0);

  // 3. Rejected / Cancelled Orders: Muted Rose Alert Palette
  static const Color statusError = Color(0xFFE11D48);
  static const Color statusErrorBg = Color(0xFFFFE4E6);
  static const Color statusErrorBorder = Color(0xFFFECDD3);

  // Backward compatibility aliases
  static const Color statusRequest = statusActive;
  static const Color statusRequestBg = statusActiveBg;
  static const Color statusRequestBorder = statusActiveBorder;
  static const Color statusPending = statusActive;
  static const Color statusPendingBg = statusActiveBg;
  static const Color statusPendingBorder = statusActiveBorder;
  static const Color statusProcessing = statusActive;
  static const Color statusProcessingBg = statusActiveBg;
  static const Color statusProcessingBorder = statusActiveBorder;
  static const Color statusReady = statusActive;
  static const Color statusReadyBg = statusActiveBg;
  static const Color statusReadyBorder = statusActiveBorder;
  static const Color statusDelivery = statusActive;
  static const Color statusDeliveryBg = statusActiveBg;
  static const Color statusDeliveryBorder = statusActiveBorder;

  /// Returns the unified semantic style for a given [OrderStatus].
  /// All active in-progress orders share the signature brand blue palette.
  /// Completed orders use a calm slate gray.
  /// Cancelled/rejected orders use a muted rose tone.
  static StatusStyle statusStyleFor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
      case OrderStatus.pending_pickup:
      case OrderStatus.processing:
      case OrderStatus.ready:
      case OrderStatus.out_for_delivery:
        return const StatusStyle(
          primary: statusActive,
          background: statusActiveBg,
          border: statusActiveBorder,
        );
      case OrderStatus.completed:
        return const StatusStyle(
          primary: statusCompleted,
          background: statusCompletedBg,
          border: statusCompletedBorder,
        );
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return const StatusStyle(
          primary: statusError,
          background: statusErrorBg,
          border: statusErrorBorder,
        );
    }
  }

  /// Convenience getter for the primary color of a given [OrderStatus].
  static Color statusColor(OrderStatus status) => statusStyleFor(status).primary;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: primaryBlue,
        surface: Colors.white,
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
          backgroundColor: primaryBlue,
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
    border: Border.all(color: AppTheme.primaryBlue, width: 2),
    boxShadow: [
      BoxShadow(
        color: AppTheme.primaryBlue.withValues(alpha: 0.1),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

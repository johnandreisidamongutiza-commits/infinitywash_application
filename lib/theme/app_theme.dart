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

  // ── Semantic Status Colors (Calibrated HSL Palette) ─────────────────────
  // Pending Approval & Pickup (Warm Honey Amber)
  static const Color statusPending = Color(0xFFD97706);
  static const Color statusPendingBg = Color(0xFFFEF3C7);
  static const Color statusPendingBorder = Color(0xFFFDE68A);

  // Processing (Ocean Azure Blue)
  static const Color statusProcessing = Color(0xFF0284C7);
  static const Color statusProcessingBg = Color(0xFFE0F2FE);
  static const Color statusProcessingBorder = Color(0xFFBAE6FD);

  // Ready (Fresh Mint / Emerald)
  static const Color statusReady = Color(0xFF059669);
  static const Color statusReadyBg = Color(0xFFD1FAE5);
  static const Color statusReadyBorder = Color(0xFFA7F3D0);

  // Out for Delivery (Modern Indigo)
  static const Color statusDelivery = Color(0xFF4F46E5);
  static const Color statusDeliveryBg = Color(0xFFEEF2FF);
  static const Color statusDeliveryBorder = Color(0xFFC7D2FE);

  // Completed (Cool Slate)
  static const Color statusCompleted = Color(0xFF64748B);
  static const Color statusCompletedBg = Color(0xFFF1F5F9);
  static const Color statusCompletedBorder = Color(0xFFE2E8F0);

  // Rejected / Cancelled (Muted Rose Coral)
  static const Color statusError = Color(0xFFE11D48);
  static const Color statusErrorBg = Color(0xFFFFE4E6);
  static const Color statusErrorBorder = Color(0xFFFECDD3);

  /// Returns the harmonious semantic style for a given [OrderStatus].
  static StatusStyle statusStyleFor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending_approval:
      case OrderStatus.pending_pickup:
        return const StatusStyle(
          primary: statusPending,
          background: statusPendingBg,
          border: statusPendingBorder,
        );
      case OrderStatus.processing:
        return const StatusStyle(
          primary: statusProcessing,
          background: statusProcessingBg,
          border: statusProcessingBorder,
        );
      case OrderStatus.ready:
        return const StatusStyle(
          primary: statusReady,
          background: statusReadyBg,
          border: statusReadyBorder,
        );
      case OrderStatus.out_for_delivery:
        return const StatusStyle(
          primary: statusDelivery,
          background: statusDeliveryBg,
          border: statusDeliveryBorder,
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
        secondary: accentBlue,
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

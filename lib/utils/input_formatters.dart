import 'package:flutter/services.dart';

/// Shared [TextInputFormatter]s so number, phone, and card fields physically
/// reject invalid characters on every platform (keyboard input, paste,
/// autofill). Apply alongside [TextInputType] — the keyboard hint alone does
/// not prevent letters on web/desktop.
class InputFormatters {
  InputFormatters._();

  /// Digits only (0-9). For quantities, OTP-like counters, IDs.
  static List<TextInputFormatter> get digitsOnly => [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
      ];

  /// Positive decimal numbers with at most [maxDecimals] places and one dot.
  /// For weights (kg) and supply amounts. Max length caps the whole value.
  static List<TextInputFormatter> decimal({int maxDecimals = 2, int? maxLength}) {
    return [
      _DecimalFormatter(maxDecimals: maxDecimals),
      if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
    ];
  }

  /// Phone characters: digits, spaces, +, -, parentheses. Max length caps
  /// the whole formatted value (20 fits '+63 (917) 123-4567').
  static List<TextInputFormatter> phone({int maxLength = 20}) {
    return [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9\+\-\s\(\)]')),
      LengthLimitingTextInputFormatter(maxLength),
    ];
  }

  /// Email format: disallows whitespace and enforces max length (254).
  static List<TextInputFormatter> email({int maxLength = 254}) {
    return [
      FilteringTextInputFormatter.deny(RegExp(r'\s')),
      LengthLimitingTextInputFormatter(maxLength),
    ];
  }

  /// Letters and digits only (no spaces). For card codes and codes in general.
  static List<TextInputFormatter> get alphanumeric => [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
      ];

  /// Letters, digits, hyphens — uppercased as typed. For card UIDs.
  static List<TextInputFormatter> get uppercaseCardUid => [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
        UpperCaseTextFormatter(),
      ];

  /// Name characters: letters (including accented like ñ, Ñ), spaces, hyphens,
  /// apostrophes. Physically blocks numbers, emojis, and special symbols.
  static List<TextInputFormatter> name({int maxLength = 50}) {
    return [
      FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z\u00C0-\u017F' \-]")),
      LengthLimitingTextInputFormatter(maxLength),
    ];
  }

  /// Vehicle details: alphanumeric, spaces, and standard punctuation (- / . , ( ) ').
  static List<TextInputFormatter> vehicleDetails({int maxLength = 60}) {
    return [
      FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z0-9\u00C0-\u017F\s'\-/,.\(\)]")),
      LengthLimitingTextInputFormatter(maxLength),
    ];
  }

  /// Free text without control characters, capped at [maxLength].
  /// For names, notes, landmark — prevents pasting endless text.
  static List<TextInputFormatter> text({int? maxLength}) {
    return [
      if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
    ];
  }

  /// Single line of free text capped at [maxLength] (also strips newlines
  /// from pastes).
  static List<TextInputFormatter> singleLine({int? maxLength}) {
    return [
      FilteringTextInputFormatter.singleLineFormatter,
      if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
    ];
  }
}

/// Uppercases every edit as it is applied. Combined with an allow-list
/// formatter for card UIDs so the stored value matches the DB (uppercased).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    if (upper == newValue.text) return newValue;
    return newValue.copyWith(
      text: upper,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

/// Decimal-number formatter: allows digits and a single decimal point with
/// at most [maxDecimals] digits after it. Rejects a second dot, leading
/// garbage, and over-long fractions while keeping the caret stable.
class _DecimalFormatter extends TextInputFormatter {
  final int maxDecimals;

  _DecimalFormatter({required this.maxDecimals});

  static final RegExp _allowed = RegExp(r'^\d*\.?\d*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    // Strip characters that are not digits or a dot.
    if (!_allowed.hasMatch(text)) {
      final cleaned = text.replaceAll(RegExp(r'[^0-9\.]'), '');
      return _collapseDots(newValue, cleaned);
    }

    return _collapseDots(newValue, text);
  }

  TextEditingValue _collapseDots(TextEditingValue newValue, String text) {
    // Keep only the first dot.
    final firstDot = text.indexOf('.');
    String cleaned = text;
    if (firstDot != -1) {
      final rest = text.substring(firstDot + 1).replaceAll('.', '');
      cleaned = text.substring(0, firstDot + 1) + rest;
    }

    // Cap the number of decimal places.
    if (firstDot != -1) {
      final fraction = cleaned.substring(firstDot + 1);
      if (fraction.length > maxDecimals) {
        cleaned = cleaned.substring(0, firstDot + 1 + maxDecimals);
      }
    }

    if (cleaned == newValue.text) return newValue;
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
      composing: TextRange.empty,
    );
  }
}

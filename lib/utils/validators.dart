/// Shared input validation used by every form in the app.
///
/// Each validator returns `null` when the value is valid, otherwise a
/// user-ready error message (no raw exception text).
class Validators {
  Validators._();

  static final RegExp _emailRe = RegExp(r'^[\w\.\-\+]+@([\w\-]+\.)+[a-zA-Z]{2,}$');
  static final RegExp _phoneRe = RegExp(r'^[0-9\+\-\s\(\)]{7,20}$');

  /// Email: required + basic format (delegates to [emailField]).
  static String? email(String? value) => emailField(value);

  /// Email when the field is optional.
  static String? optionalEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    return emailField(v);
  }

  /// Password for sign-in (non-empty).
  static String? passwordRequired(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Please enter your password.';
    return null;
  }

  /// Password for registration / reset: minimum strength rules.
  static String? newPassword(String? value, {int minLength = 6}) {
    final v = value ?? '';
    if (v.isEmpty) return 'Please enter a password.';
    if (v.length < minLength) return 'Password must be at least $minLength characters.';
    if (!v.contains(RegExp(r'[A-Za-z]')) || !v.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain both letters and numbers.';
    }
    return null;
  }

  /// Confirm-password matching.
  static String? confirmPassword(String? value, String? original) {
    if ((value ?? '').isEmpty) return 'Please confirm your password.';
    if (value != original) return 'Passwords do not match.';
    return null;
  }

  /// Generic required field with a friendly field name.
  static String? required(String? value, String fieldName) {
    if ((value ?? '').trim().isEmpty) return 'Please enter $fieldName.';
    return null;
  }

  /// Philippine mobile number (accepts 09XXXXXXXXX, +639XXXXXXXXX, or 9XXXXXXXXX).
  static String? phone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter your mobile number.';

    // Check for disallowed characters (only digits, spaces, +, -, parentheses allowed)
    if (!_phoneRe.hasMatch(v)) {
      return 'Mobile number contains invalid characters.';
    }

    final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 'Please enter your mobile number.';

    // Enforce Philippine mobile structure
    if (digits.startsWith('09')) {
      if (digits.length < 11) {
        return 'Mobile number must have 11 digits (e.g. 0917 123 4567).';
      }
      if (digits.length > 11) {
        return 'Mobile number cannot exceed 11 digits.';
      }
      return null;
    } else if (digits.startsWith('639')) {
      if (digits.length < 12) {
        return 'Mobile number must have 12 digits (e.g. +63 917 123 4567).';
      }
      if (digits.length > 12) {
        return 'Mobile number is too long.';
      }
      return null;
    } else if (digits.startsWith('9')) {
      if (digits.length < 10) {
        return 'Mobile number must have 10 digits without leading 0.';
      }
      if (digits.length > 10) {
        return 'Mobile number cannot exceed 10 digits.';
      }
      return null;
    } else {
      return 'Please enter a valid mobile number starting with 09 (e.g. 0917 123 4567).';
    }
  }

  /// Optional Philippine mobile number.
  static String? optionalPhone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    return phone(v);
  }

  /// Numeric amount greater than zero (payments).
  static String? positiveAmount(String? value, {String fieldName = 'amount'}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter the $fieldName.';
    final parsed = double.tryParse(v.replaceAll(',', ''));
    if (parsed == null) return 'Please enter a valid number for the $fieldName.';
    if (parsed <= 0) return 'The $fieldName must be greater than zero.';
    return null;
  }

  /// Non-negative integer quantity (loads, supplies).
  static String? positiveInt(String? value, {String fieldName = 'quantity'}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter the $fieldName.';
    final parsed = int.tryParse(v);
    if (parsed == null || parsed <= 0) return 'Please enter a valid $fieldName (at least 1).';
    return null;
  }

  /// Name: letters, spaces, hyphens; 2+ chars.
  static String? name(String? value, String fieldName) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter $fieldName.';
    if (v.length < 2) return '$fieldName must be at least 2 characters.';
    if (!v.contains(RegExp(r"^[a-zA-Z\u00C0-\u017F' \-]+$"))) {
      return 'Please enter a valid $fieldName (letters only).';
    }
    return null;
  }

  /// Free-form address (2+ chars).
  static String? address(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter your address.';
    if (v.length < 5) return 'Please enter a complete address.';
    return null;
  }

  /// RFID card number: alphanumeric, 6-20 chars.
  static String? rfidCard(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please scan or enter a card number.';
    if (v.length < 6 || v.length > 20) return 'That card number does not look right. Please scan again.';
    return null;
  }

  /// Maximum length guard for any text field.
  static String? maxLength(String? value, int max, String fieldName) {
    if ((value ?? '').length > max) return '$fieldName must be at most $max characters.';
    return null;
  }

  // ── Length constants shared by formatters and field validators ────────────
  static const int nameMin = 2;
  static const int nameMax = 50;
  static const int emailMax = 254;
  static const int passwordMax = 72; // Supabase/bcrypt practical limit
  static const int addressMax = 120;
  static const int landmarkMax = 120;
  static const int notesMax = 500;
  static const int supplyNameMax = 50;
  static const int supplyUnitMax = 10;
  static const int cardUidMin = 6;
  static const int cardUidMax = 20;
  static const double weightMinKg = 0.1;
  static const double weightMaxKg = 100.0;
  static const double amountMax = 100000.0;
  static const int otpLength = 6;

  // ── Field validators: required + format + MIN and MAX character limits ────

  /// Name field: required, min 2 chars (rejects 1-character names),
  /// max 50, letters/spaces/hyphens/apostrophes only.
  static String? nameField(String? value, String fieldName) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter $fieldName.';
    if (v.length < nameMin) return '$fieldName must be at least $nameMin characters.';
    if (v.length > nameMax) return '$fieldName must be at most $nameMax characters.';
    if (!v.contains(RegExp(r"^[a-zA-Z\u00C0-\u017F' \-]+$"))) {
      return 'Please enter a valid $fieldName (letters only).';
    }
    return null;
  }

  /// Password field: required, 6–72 characters, letters and numbers.
  static String? passwordField(String? value, {int minLength = 6}) {
    final v = value ?? '';
    if (v.isEmpty) return 'Please enter a password.';
    if (v.length < minLength) return 'Password must be at least $minLength characters.';
    if (v.length > passwordMax) return 'Password must be at most $passwordMax characters.';
    if (!v.contains(RegExp(r'[A-Za-z]')) || !v.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain both letters and numbers.';
    }
    return null;
  }

  /// Email field: required, valid format, granular errors, max 254 characters.
  static String? emailField(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter your email address.';
    if (v.length > emailMax) return 'Email address is too long.';
    if (v.contains(' ')) return 'Email address cannot contain spaces.';

    final atIndex = v.indexOf('@');
    if (atIndex == -1) {
      return "Email address must contain an '@'.";
    }
    if (atIndex == 0) {
      return "Please enter a username before '@'.";
    }
    if (v.indexOf('@', atIndex + 1) != -1) {
      return "Email address can only contain one '@'.";
    }

    final localPart = v.substring(0, atIndex);
    final domainPart = v.substring(atIndex + 1);

    if (domainPart.isEmpty) {
      return "Please include a domain after '@' (e.g. gmail.com).";
    }

    if (localPart.contains('..') || domainPart.contains('..')) {
      return 'Email address cannot contain consecutive dots.';
    }

    if (localPart.startsWith('.') || localPart.endsWith('.')) {
      return 'Username cannot start or end with a dot.';
    }

    if (!domainPart.contains('.')) {
      return 'Domain must include an extension (e.g. .com, .ph).';
    }

    final domainParts = domainPart.split('.');
    if (domainParts.any((part) => part.isEmpty)) {
      return 'Please enter a valid domain (e.g. name@example.com).';
    }

    final tld = domainParts.last;
    if (tld.length < 2 || !RegExp(r'^[a-zA-Z]+$').hasMatch(tld)) {
      return 'Please enter a valid domain ending (e.g. .com, .ph).';
    }

    if (!_emailRe.hasMatch(v)) {
      return 'Please enter a valid email address (e.g. name@example.com).';
    }
    return null;
  }

  /// Weight in kg for laundry loads: 0.1–100 kg, decimals only.
  static String? weightKg(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter the weight.';
    final parsed = double.tryParse(v);
    if (parsed == null) return 'Weight must be a number (e.g. 5.0).';
    if (parsed < weightMinKg) {
      return 'Weight must be at least ${weightMinKg.toStringAsFixed(1)} kg.';
    }
    if (parsed > weightMaxKg) {
      return 'Weight cannot exceed ${weightMaxKg.toStringAsFixed(0)} kg per load.';
    }
    return null;
  }

  /// Supply amount in its unit: numeric, > 0, ≤ 100,000.
  static String? supplyAmount(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter the amount.';
    final parsed = double.tryParse(v);
    if (parsed == null) return 'Amount must be a number (e.g. 5.0).';
    if (parsed <= 0) return 'Amount must be greater than zero.';
    if (parsed > amountMax) {
      return 'Amount is too large (max ${amountMax.toStringAsFixed(0)}).';
    }
    return null;
  }

  /// Supply name: required, 2–50 characters.
  static String? supplyName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter the supply name.';
    if (v.length < 2) return 'Supply name must be at least 2 characters.';
    if (v.length > supplyNameMax) {
      return 'Supply name must be at most $supplyNameMax characters.';
    }
    return null;
  }

  /// Supply unit: required, max 10 characters (e.g. L, kg, pcs).
  static String? supplyUnit(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter the unit (e.g. L, kg, pcs).';
    if (v.length > supplyUnitMax) {
      return 'Unit must be at most $supplyUnitMax characters.';
    }
    return null;
  }

  /// Card UID: alphanumeric + hyphen, 6–20 characters.
  static String? cardUid(String? value) {
    final v = value?.trim().toUpperCase() ?? '';
    if (v.isEmpty) return 'Please scan or enter a card number.';
    if (v.length < cardUidMin || v.length > cardUidMax) {
      return 'Card number must be $cardUidMin–$cardUidMax characters.';
    }
    if (!v.contains(RegExp(r'^[A-Z0-9\-]+$'))) {
      return 'Card number may only contain letters, numbers, and hyphens.';
    }
    return null;
  }

  /// Fixed-length OTP code: exactly 6 alphanumeric characters.
  static String? otpCode(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter the verification code.';
    if (v.length != otpLength) return 'The code must be exactly $otpLength characters.';
    if (!v.contains(RegExp(r'^[A-Za-z0-9]+$'))) {
      return 'The code may only contain letters and numbers.';
    }
    return null;
  }

  /// Optional notes/comment: max [max] characters (empty is valid).
  static String? optionalNotes(String? value,
      {String fieldName = 'Notes', int max = notesMax}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.length > max) {
      return '$fieldName must be at most $max characters (currently ${v.length}).';
    }
    return null;
  }

  /// Landmark / meetup note: optional by default; when [requiredField] is
  /// true it must be 2–120 characters.
  static String? landmark(String? value, {bool requiredField = false}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      return requiredField ? 'Please enter a landmark or meetup note.' : null;
    }
    if (v.length < 2) return 'Landmark must be at least 2 characters.';
    if (v.length > landmarkMax) {
      return 'Landmark must be at most $landmarkMax characters.';
    }
    return null;
  }

  // ── Date validation helpers ────────────────────────────────────────────────
  // No free-text date entry exists in the app (all dates come from system
  // timestamps or native pickers); these guards validate picked/derived dates
  // before submission.

  /// Rejects a date in the future.
  static String? notInFuture(DateTime? date, {String fieldName = 'Date'}) {
    if (date == null) return 'Please choose $fieldName.';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final chosen = DateTime(date.year, date.month, date.day);
    if (chosen.isAfter(today)) return '$fieldName cannot be in the future.';
    return null;
  }

  /// Rejects a date older than [years] years ago.
  static String? withinPastYears(DateTime? date, int years,
      {String fieldName = 'Date'}) {
    if (date == null) return 'Please choose $fieldName.';
    final earliest = DateTime.now().subtract(Duration(days: 365 * years));
    if (date.isBefore(earliest)) {
      return '$fieldName cannot be earlier than $years years ago.';
    }
    return null;
  }
}

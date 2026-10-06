import 'package:flutter_test/flutter_test.dart';

import 'package:infinitywash/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('accepts a normal address', () {
      expect(Validators.email('juan@example.com'), isNull);
    });

    test('accepts plus-addressing', () {
      expect(Validators.email('user+tag@domain.co'), isNull);
    });

    test('rejects empty', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('   '), isNotNull);
    });

    test('rejects missing @', () {
      expect(Validators.email('juan.example.com'), isNotNull);
    });

    test('rejects missing domain', () {
      expect(Validators.email('juan@'), isNotNull);
    });

    test('rejects missing TLD', () {
      expect(Validators.email('juan@example'), isNotNull);
    });

    test('error message is user-friendly', () {
      final msg = Validators.email('not-an-email')!;
      expect(msg, contains('valid email'));
    });
  });

  group('Validators.newPassword', () {
    test('accepts a strong-enough password', () {
      expect(Validators.newPassword('wash123'), isNull);
    });

    test('rejects empty', () {
      expect(Validators.newPassword(''), isNotNull);
    });

    test('rejects too-short passwords', () {
      expect(Validators.newPassword('ab1'), isNotNull);
    });

    test('rejects letters-only', () {
      expect(Validators.newPassword('abcdefgh'), isNotNull);
    });

    test('rejects numbers-only', () {
      expect(Validators.newPassword('12345678'), isNotNull);
    });

    test('mentions the minimum length in the message', () {
      final msg = Validators.newPassword('ab1')!;
      expect(msg, contains('6'));
    });
  });

  group('Validators.confirmPassword', () {
    test('accepts matching passwords', () {
      expect(Validators.confirmPassword('wash123', 'wash123'), isNull);
    });

    test('rejects mismatched passwords', () {
      expect(Validators.confirmPassword('wash123', 'wash124'), isNotNull);
    });

    test('rejects empty confirmation', () {
      expect(Validators.confirmPassword('', 'wash123'), isNotNull);
    });
  });

  group('Validators.phone', () {
    test('accepts a standard PH mobile number', () {
      expect(Validators.phone('09171234567'), isNull);
    });

    test('accepts formatted numbers', () {
      expect(Validators.phone('0917 123 4567'), isNull);
      expect(Validators.phone('+63 917 123 4567'), isNull);
    });

    test('rejects empty', () {
      expect(Validators.phone(''), isNotNull);
    });

    test('rejects too-short numbers', () {
      expect(Validators.phone('0917'), isNotNull);
    });

    test('rejects letters', () {
      expect(Validators.phone('0917abc4567'), isNotNull);
    });
  });

  group('Validators.required', () {
    test('accepts non-empty text', () {
      expect(Validators.required('hello', 'name'), isNull);
    });

    test('rejects empty and whitespace-only text', () {
      expect(Validators.required('', 'name'), isNotNull);
      expect(Validators.required('   ', 'name'), isNotNull);
    });

    test('message names the field', () {
      expect(Validators.required('', 'first name'), contains('first name'));
    });
  });

  group('Validators.positiveAmount', () {
    test('accepts a positive number', () {
      expect(Validators.positiveAmount('170'), isNull);
      expect(Validators.positiveAmount('170.50'), isNull);
      expect(Validators.positiveAmount('1,700'), isNull); // commas stripped
    });

    test('rejects empty', () {
      expect(Validators.positiveAmount(''), isNotNull);
    });

    test('rejects non-numeric text', () {
      expect(Validators.positiveAmount('abc'), isNotNull);
    });

    test('rejects zero and negatives', () {
      expect(Validators.positiveAmount('0'), isNotNull);
      expect(Validators.positiveAmount('-5'), isNotNull);
    });
  });

  group('Validators.positiveInt', () {
    test('accepts a positive integer', () {
      expect(Validators.positiveInt('3'), isNull);
    });

    test('rejects zero', () {
      expect(Validators.positiveInt('0'), isNotNull);
    });

    test('rejects decimals', () {
      expect(Validators.positiveInt('2.5'), isNotNull);
    });

    test('rejects text', () {
      expect(Validators.positiveInt('three'), isNotNull);
    });
  });

  group('Validators.name', () {
    test('accepts letters with spaces and hyphens', () {
      expect(Validators.name('Maria', 'first name'), isNull);
      expect(Validators.name('Anne-Marie', 'first name'), isNull);
      expect(Validators.name("Dela Cruz O'Connor", 'last name'), isNull);
    });

    test('rejects empty', () {
      expect(Validators.name('', 'first name'), isNotNull);
    });

    test('rejects single character', () {
      expect(Validators.name('J', 'first name'), isNotNull);
    });

    test('rejects digits', () {
      expect(Validators.name('Juan123', 'first name'), isNotNull);
    });
  });

  group('Validators.rfidCard', () {
    test('accepts a plausible card number', () {
      expect(Validators.rfidCard('A1B2C3D4'), isNull);
    });

    test('rejects empty', () {
      expect(Validators.rfidCard(''), isNotNull);
    });

    test('rejects too-short numbers', () {
      expect(Validators.rfidCard('A1'), isNotNull);
    });
  });

  group('Validators.maxLength', () {
    test('accepts text within the limit', () {
      expect(Validators.maxLength('hi', 10, 'Note'), isNull);
    });

    test('rejects text over the limit', () {
      expect(Validators.maxLength('x' * 11, 10, 'Note'), isNotNull);
    });
  });

  group('Validators.nameField', () {
    test('accepts letters with spaces, hyphens, apostrophes', () {
      expect(Validators.nameField('Maria', 'First name'), isNull);
      expect(Validators.nameField('Anne-Marie', 'First name'), isNull);
      expect(Validators.nameField("Dela Cruz O'Connor", 'Last name'), isNull);
    });

    test('rejects empty', () {
      expect(Validators.nameField('', 'First name'), isNotNull);
      expect(Validators.nameField('   ', 'First name'), isNotNull);
    });

    test('rejects a single character', () {
      expect(Validators.nameField('J', 'First name'), isNotNull);
    });

    test('rejects digits and symbols', () {
      expect(Validators.nameField('Juan123', 'First name'), isNotNull);
      expect(Validators.nameField('Ju@n', 'First name'), isNotNull);
    });

    test('rejects over 50 characters', () {
      expect(
        Validators.nameField('A' * 51, 'First name'),
        isNotNull,
      );
    });

    test('accepts exactly 50 characters', () {
      expect(Validators.nameField('A' * 50, 'First name'), isNull);
    });

    test('message names the field', () {
      expect(
        Validators.nameField('J', 'First name')!,
        contains('First name'),
      );
    });
  });

  group('Validators.passwordField', () {
    test('accepts a valid password', () {
      expect(Validators.passwordField('wash123'), isNull);
    });

    test('rejects empty', () {
      expect(Validators.passwordField(''), isNotNull);
    });

    test('rejects too-short passwords', () {
      expect(Validators.passwordField('ab1'), isNotNull);
    });

    test('rejects letters-only and numbers-only', () {
      expect(Validators.passwordField('abcdefgh'), isNotNull);
      expect(Validators.passwordField('123456'), isNotNull);
    });

    test('rejects over 72 characters', () {
      expect(
        Validators.passwordField('a1' * 36 + 'a'), // 73 chars
        isNotNull,
      );
    });

    test('accepts exactly 72 characters', () {
      expect(Validators.passwordField('a1' * 36), isNull);
    });
  });

  group('Validators.emailField', () {
    test('accepts a normal address', () {
      expect(Validators.emailField('juan@example.com'), isNull);
    });

    test('rejects empty', () {
      expect(Validators.emailField(''), isNotNull);
      expect(Validators.emailField('   '), isNotNull);
    });

    test('rejects bad format', () {
      expect(Validators.emailField('juan@example'), isNotNull);
      expect(Validators.emailField('not-an-email'), isNotNull);
    });

    test('rejects over 254 characters', () {
      final longLocal = 'a' * 244;
      expect(Validators.emailField('$longLocal@example.com'), isNotNull);
    });
  });

  group('Validators.weightKg', () {
    test('accepts values within 0.1-100 kg', () {
      expect(Validators.weightKg('0.1'), isNull);
      expect(Validators.weightKg('5.5'), isNull);
      expect(Validators.weightKg('100'), isNull);
    });

    test('rejects empty and non-numeric text', () {
      expect(Validators.weightKg(''), isNotNull);
      expect(Validators.weightKg('abc'), isNotNull);
    });

    test('rejects zero and below the 0.1 minimum', () {
      expect(Validators.weightKg('0'), isNotNull);
      expect(Validators.weightKg('0.05'), isNotNull);
    });

    test('rejects over 100 kg', () {
      expect(Validators.weightKg('100.1'), isNotNull);
    });
  });

  group('Validators.supplyAmount', () {
    test('accepts a positive amount within the cap', () {
      expect(Validators.supplyAmount('5'), isNull);
      expect(Validators.supplyAmount('5.25'), isNull);
      expect(Validators.supplyAmount('100000'), isNull);
    });

    test('rejects empty and non-numeric text', () {
      expect(Validators.supplyAmount(''), isNotNull);
      expect(Validators.supplyAmount('abc'), isNotNull);
    });

    test('rejects zero and negatives', () {
      expect(Validators.supplyAmount('0'), isNotNull);
      expect(Validators.supplyAmount('-5'), isNotNull);
    });

    test('rejects over the 100000 cap', () {
      expect(Validators.supplyAmount('100001'), isNotNull);
    });
  });

  group('Validators.supplyName', () {
    test('accepts a 2-50 character name', () {
      expect(Validators.supplyName('Liquid Detergent'), isNull);
      expect(Validators.supplyName('A' * 50), isNull);
    });

    test('rejects empty and single character', () {
      expect(Validators.supplyName(''), isNotNull);
      expect(Validators.supplyName('A'), isNotNull);
    });

    test('rejects over 50 characters', () {
      expect(Validators.supplyName('A' * 51), isNotNull);
    });
  });

  group('Validators.supplyUnit', () {
    test('accepts short units', () {
      expect(Validators.supplyUnit('L'), isNull);
      expect(Validators.supplyUnit('kg'), isNull);
      expect(Validators.supplyUnit('pcs'), isNull);
    });

    test('rejects empty', () {
      expect(Validators.supplyUnit(''), isNotNull);
    });

    test('rejects over 10 characters', () {
      expect(Validators.supplyUnit('k' * 11), isNotNull);
    });
  });

  group('Validators.cardUid', () {
    test('accepts alphanumeric with hyphens', () {
      expect(Validators.cardUid('A1B2C3D4'), isNull);
      expect(Validators.cardUid('RFID-0001'), isNull);
    });

    test('uppercases before checking', () {
      expect(Validators.cardUid('a1b2c3'), isNull);
    });

    test('rejects empty', () {
      expect(Validators.cardUid(''), isNotNull);
    });

    test('rejects under 6 and over 20 characters', () {
      expect(Validators.cardUid('A1B2C'), isNotNull);
      expect(Validators.cardUid('A' * 21), isNotNull);
    });

    test('rejects spaces and symbols', () {
      expect(Validators.cardUid('A1B2 C3'), isNotNull);
      expect(Validators.cardUid('A1B2C3!'), isNotNull);
    });
  });

  group('Validators.otpCode', () {
    test('accepts exactly 6 alphanumeric characters', () {
      expect(Validators.otpCode('ABC123'), isNull);
      expect(Validators.otpCode('000000'), isNull);
    });

    test('rejects empty', () {
      expect(Validators.otpCode(''), isNotNull);
    });

    test('rejects the wrong length', () {
      expect(Validators.otpCode('AB12'), isNotNull);
      expect(Validators.otpCode('ABC1234'), isNotNull);
    });

    test('rejects symbols', () {
      expect(Validators.otpCode('ABC12!'), isNotNull);
    });
  });

  group('Validators.optionalNotes', () {
    test('accepts empty', () {
      expect(Validators.optionalNotes(''), isNull);
      expect(Validators.optionalNotes(null), isNull);
    });

    test('accepts text within the default 500 limit', () {
      expect(Validators.optionalNotes('n' * 500), isNull);
    });

    test('rejects text over the limit', () {
      expect(Validators.optionalNotes('n' * 501), isNotNull);
    });

    test('honors a custom limit', () {
      expect(Validators.optionalNotes('n' * 21, max: 20), isNotNull);
      expect(Validators.optionalNotes('n' * 20, max: 20), isNull);
    });
  });

  group('Validators.landmark', () {
    test('empty is valid when optional', () {
      expect(Validators.landmark(''), isNull);
      expect(Validators.landmark(null), isNull);
    });

    test('empty is an error when required', () {
      expect(Validators.landmark('', requiredField: true), isNotNull);
    });

    test('rejects a single character', () {
      expect(Validators.landmark('N'), isNotNull);
    });

    test('accepts up to 120 characters and rejects beyond', () {
      expect(Validators.landmark('N' * 120), isNull);
      expect(Validators.landmark('N' * 121), isNotNull);
    });
  });

  group('Validators.notInFuture', () {
    test('null date is an error', () {
      expect(Validators.notInFuture(null), isNotNull);
    });

    test('today and past dates are valid', () {
      final now = DateTime.now();
      expect(Validators.notInFuture(now), isNull);
      expect(
        Validators.notInFuture(now.subtract(const Duration(days: 1))),
        isNull,
      );
    });

    test('tomorrow is rejected', () {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      expect(Validators.notInFuture(tomorrow), isNotNull);
    });
  });

  group('Validators.withinPastYears', () {
    test('null date is an error', () {
      expect(Validators.withinPastYears(null, 2), isNotNull);
    });

    test('recent dates are valid', () {
      expect(Validators.withinPastYears(DateTime.now(), 2), isNull);
    });

    test('dates older than the window are rejected', () {
      final threeYearsAgo =
          DateTime.now().subtract(const Duration(days: 365 * 3));
      expect(Validators.withinPastYears(threeYearsAgo, 2), isNotNull);
    });
  });
}

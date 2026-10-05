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
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinitywash/utils/input_formatters.dart';

/// Chains [formatters] the way EditableText does: each formatter receives
/// the original [oldText] as the "old" value and the accumulated result as
/// the "new" value.
TextEditingValue runFormatters(
  List<TextInputFormatter> formatters,
  String oldText,
  String newText,
) {
  var value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: newText.length),
  );
  final old = TextEditingValue(text: oldText);
  for (final formatter in formatters) {
    value = formatter.formatEditUpdate(old, value);
  }
  return value;
}

String formatted(
  List<TextInputFormatter> formatters,
  String oldText,
  String newText,
) {
  return runFormatters(formatters, oldText, newText).text;
}

void main() {
  group('InputFormatters.digitsOnly', () {
    test('keeps digits', () {
      expect(formatted(InputFormatters.digitsOnly, '', '0123456789'),
          '0123456789');
    });

    test('strips letters, symbols, spaces (including pastes)', () {
      expect(formatted(InputFormatters.digitsOnly, '', 'a1b2c3!@# '), '123');
    });
  });

  group('InputFormatters.decimal', () {
    test('keeps a plain decimal number', () {
      expect(formatted(InputFormatters.decimal(), '', '12.34'), '12.34');
    });

    test('strips non-numeric characters', () {
      expect(formatted(InputFormatters.decimal(), '', '5k.g0'), '5.0');
    });

    test('collapses a second dot into decimals', () {
      expect(formatted(InputFormatters.decimal(), '', '1.2.3'), '1.23');
    });

    test('caps the fraction at maxDecimals', () {
      expect(formatted(InputFormatters.decimal(maxDecimals: 2), '', '12.345'),
          '12.34');
      expect(formatted(InputFormatters.decimal(maxDecimals: 1), '', '12.34'),
          '12.3');
    });

    test('allows more decimals when maxDecimals is raised', () {
      expect(formatted(InputFormatters.decimal(maxDecimals: 3), '', '1.234'),
          '1.234');
    });

    test('honors maxLength via the length-limiting formatter', () {
      expect(
        formatted(InputFormatters.decimal(maxLength: 4), '', '12345'),
        '1234',
      );
    });

    test('leaves an already-valid value untouched', () {
      final result = runFormatters(InputFormatters.decimal(), '5.5', '5.5');
      expect(result.text, '5.5');
    });
  });

  group('InputFormatters.phone', () {
    test('keeps digits, spaces, +, -, parentheses', () {
      expect(formatted(InputFormatters.phone(), '', '+63 917 123-4567'),
          '+63 917 123-4567');
      expect(formatted(InputFormatters.phone(), '', '(0917) 123'), '(0917) 123');
    });

    test('strips letters', () {
      expect(formatted(InputFormatters.phone(), '', '0917abc4567'),
          '09174567');
    });

    test('caps the length at maxLength', () {
      expect(
        formatted(InputFormatters.phone(maxLength: 5), '', '09171234567'),
        '09171',
      );
    });
  });

  group('InputFormatters.alphanumeric', () {
    test('keeps letters and digits only', () {
      expect(formatted(InputFormatters.alphanumeric, '', 'A1-B2 C3'),
          'A1B2C3');
    });
  });

  group('InputFormatters.uppercaseCardUid', () {
    test('uppercases letters as typed', () {
      expect(formatted(InputFormatters.uppercaseCardUid, '', 'rfid-0001'),
          'RFID-0001');
    });

    test('keeps digits and hyphens, strips other symbols and spaces', () {
      expect(formatted(InputFormatters.uppercaseCardUid, '', 'a1b2 c3!'),
          'A1B2C3');
    });
  });

  group('InputFormatters.text', () {
    test('passes free text through', () {
      expect(formatted(InputFormatters.text(), '', 'Hello, world! 123'),
          'Hello, world! 123');
    });

    test('caps at maxLength', () {
      expect(formatted(InputFormatters.text(maxLength: 5), '', '1234567890'),
          '12345');
    });
  });

  group('InputFormatters.singleLine', () {
    test('strips newlines from pasted text', () {
      expect(formatted(InputFormatters.singleLine(), '', 'line1\nline2'),
          'line1line2');
    });

    test('caps at maxLength', () {
      expect(
        formatted(InputFormatters.singleLine(maxLength: 4), '', 'a\nb'),
        'ab',
      );
    });
  });

  group('UpperCaseTextFormatter', () {
    test('uppercases the text and keeps the caret', () {
      final formatter = UpperCaseTextFormatter();
      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(
          text: 'abc',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      expect(result.text, 'ABC');
      expect(result.selection.baseOffset, 3);
    });
  });
}

// Tests for the legal consent configuration layer.
//
// These tests guard the pieces that silently break the consent flow if
// they drift:
//   * a typo'd asset path would make the document unopenable and the
//     registration acceptance hash impossible to compute;
//   * a key renamed in the manifest without migrating the data would
//     orphan previously recorded acceptances (legalDocumentByKey throws
//     on unknown keys, which the profile screen relies on);
//   * the required set in Dart must match the server-side list in
//     handle_new_auth_user() - verified here against the literal list,
//     with a comment pointing at the SQL.
//
// Supabase is never contacted: setUpAll initializes a HERMETIC instance
// (test/supabase_test_setup.dart) purely so LegalService's field can
// construct SupabaseService.client without asserting. No query runs -
// these remain pure config and asset checks.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinitywash/config/legal_documents.dart';
import 'package:infinitywash/services/legal_service.dart';

import 'supabase_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeTestSupabase();
  });

  tearDownAll(() async {
    await disposeTestSupabase();
  });

  group('LegalDocument registry', () {
    test('has at least one document', () {
      expect(kLegalDocuments, isNotEmpty);
    });

    test('document keys are unique', () {
      final keys = kLegalDocuments.map((d) => d.key).toSet();
      expect(keys.length, kLegalDocuments.length,
          reason: 'duplicate keys would collide in legal_acceptances '
              'and make legalDocumentByKey ambiguous');
    });

    test('every document has a non-empty version and title', () {
      for (final doc in kLegalDocuments) {
        expect(doc.version, isNotEmpty,
            reason: '${doc.key} needs a version - acceptance rows are '
                'keyed on it');
        expect(doc.title, isNotEmpty);
      }
    });

    test('versions match the MAJOR.MINOR pattern', () {
      final pattern = RegExp(r'^\d+\.\d+$');
      for (final doc in kLegalDocuments) {
        expect(pattern.hasMatch(doc.version), isTrue,
            reason: '${doc.key} version "${doc.version}" should be '
                'MAJOR.MINOR so it reads clearly in the audit trail');
      }
    });

    test('required set matches the literal required key list', () {
      final requiredKeys =
          kLegalDocuments.where((d) => d.required).map((d) => d.key).toSet();
      expect(requiredKeys, kRequiredLegalDocumentKeys.toSet());

      // Server-side twin lives in handle_new_auth_user():
      //   supabase/migrations/20261005_legal_acceptances.sql
      //   v_required text[] := ARRAY['terms_of_service', 'privacy_policy'];
      // Both must be updated together.
      expect(kRequiredLegalDocumentKeys,
          containsAll(<String>['terms_of_service', 'privacy_policy']));
    });

    test('asset paths are unique', () {
      final paths = kLegalDocuments.map((d) => d.assetPath).toSet();
      expect(paths.length, kLegalDocuments.length);
    });

    test('effective dates are not in the future', () {
      // A document dated ahead of the build would claim consent for
      // terms the user could not yet have read.
      for (final doc in kLegalDocuments) {
        expect(doc.effectiveDateTime.isAfter(DateTime.now()), isFalse,
            reason: '${doc.key} effective date is in the future');
      }
    });

    test('effective dates parse as ISO-8601', () {
      for (final doc in kLegalDocuments) {
        expect(
          () => doc.effectiveDateTime,
          returnsNormally,
          reason: '${doc.key} effectiveDate must stay a valid ISO date '
              'string (YYYY-MM-DD)',
        );
      }
    });
  });

  group('legalDocumentByKey', () {
    test('returns the matching document', () {
      final doc = legalDocumentByKey('terms_of_service');
      expect(doc.key, 'terms_of_service');
      expect(doc.title, 'Terms of Service');
    });

    test('is case sensitive', () {
      expect(() => legalDocumentByKey('Terms_of_Service'),
          throwsStateError);
    });

    test('throws StateError for an unknown key', () {
      expect(() => legalDocumentByKey('does_not_exist'), throwsStateError);
    });
  });

  group('requiredLegalDocuments', () {
    test('returns exactly the required documents', () {
      final out = requiredLegalDocuments();
      expect(out, everyElement(predicate<LegalDocument>((d) => d.required)));
      expect(out.length, kRequiredLegalDocumentKeys.length);
    });

    test('returns an unmodifiable view', () {
      expect(() => requiredLegalDocuments().add(kLegalDocuments.first),
          throwsUnsupportedError);
    });
  });

  group('LegalService.sha256HexOf', () {
    test('matches the RFC 8449 known vector for "abc"', () {
      expect(
        LegalService.sha256HexOf('abc'),
        equals(
            'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'),
      );
    });

    test('produces 64 lowercase hex characters', () {
      final hex = LegalService.sha256HexOf('Infinity Wash');
      expect(hex, hasLength(64));
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(hex), isTrue);
    });

    test('is deterministic and sensitive to input', () {
      final a = LegalService.sha256HexOf('Version 1.0');
      final b = LegalService.sha256HexOf('Version 1.0');
      final c = LegalService.sha256HexOf('Version 1.1');
      expect(a, equals(b));
      expect(a, isNot(equals(c)),
          reason: 'a wording change must produce a different hash, or the '
              'document_hash column could not prove which text was shown');
    });
  });

  group('bundled legal assets', () {
    for (final doc in kLegalDocuments) {
      test('${doc.assetPath} exists and is non-empty', () async {
        final text = await rootBundle.loadString(doc.assetPath);
        expect(text, isNotEmpty,
            reason: 'an empty document would let a user "agree" to nothing');
      });

      test('${doc.key} text is a Markdown document with a heading',
          () async {
        final text = await rootBundle.loadString(doc.assetPath);
        expect(text.startsWith('# '), isTrue,
            reason: 'the reader renders Markdown; a missing heading usually '
                'means the wrong file was bundled');
      });

      test('${doc.key} states its own version in the text', () async {
        final text = await rootBundle.loadString(doc.assetPath);
        expect(text.contains('Version ${doc.version}'), isTrue,
            reason: 'the user must be able to see which version they read, '
                'not only rely on the UI chip');
      });

      test('${doc.assetPath} loads and hashes consistently', () async {
        final loaded = await LegalService().load(doc);
        expect(loaded.text, isNotEmpty);
        expect(loaded.sha256Hex, hasLength(64));
        // Second call must come from the memoised cache and be identical.
        final again = await LegalService().load(doc);
        expect(again.sha256Hex, equals(loaded.sha256Hex));
      });
    }
  });
}

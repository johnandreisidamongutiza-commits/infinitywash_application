import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/legal_documents.dart';
import 'supabase_service.dart';

/// A legal document with its text loaded and fingerprinted.
class LoadedLegalDocument {
  final LegalDocument document;

  /// The exact text shown to the user.
  final String text;

  /// sha256 hex of [text]. Stored in
  /// `legal_acceptances.document_hash` so a recorded acceptance
  /// can be tied back to the precise wording the user saw.
  final String sha256Hex;

  const LoadedLegalDocument({
    required this.document,
    required this.text,
    required this.sha256Hex,
  });
}

/// One row from `legal_acceptances`, as shown in the profile screen.
class LegalAcceptanceRecord {
  final String documentKey;
  final String documentVersion;
  final String documentHash;
  final String? appVersion;
  final String source;
  final DateTime acceptedAt;

  const LegalAcceptanceRecord({
    required this.documentKey,
    required this.documentVersion,
    required this.documentHash,
    required this.appVersion,
    required this.source,
    required this.acceptedAt,
  });

  String get documentTitle {
    try {
      return legalDocumentByKey(documentKey).title;
    } on StateError {
      return documentKey;
    }
  }

  factory LegalAcceptanceRecord.fromJson(Map<String, dynamic> json) {
    return LegalAcceptanceRecord(
      documentKey: json['document_key'] as String,
      documentVersion: json['document_version'] as String,
      documentHash: (json['document_hash'] ?? '') as String,
      appVersion: json['app_version'] as String?,
      source: (json['source'] ?? 'unknown') as String,
      acceptedAt: DateTime.parse(json['accepted_at'] as String),
    );
  }
}

/// Loads the bundled legal documents, records acceptances and checks
/// whether the signed-in user is up to date.
///
/// Consent is recorded server-side during registration by
/// `handle_new_auth_user()`; this service handles the in-app paths:
/// the re-consent banner and the profile's "Terms & Privacy" screen.
class LegalService {
  final SupabaseClient _client = SupabaseService.client;

  static const String _table = 'legal_acceptances';

  /// Asset text never changes while the app runs, so it is safe to
  /// cache per process. Keyed by asset path.
  static final Map<String, LoadedLegalDocument> _loadedByPath = {};

  PackageInfo? _cachedPackageInfo;

  // ------------------------------------------------------------------
  // Loading
  // ------------------------------------------------------------------

  /// Loads [doc]'s bundled text and computes its sha256.
  Future<LoadedLegalDocument> load(LegalDocument doc) async {
    final cached = _loadedByPath[doc.assetPath];
    if (cached != null) return cached;

    try {
      final text = await rootBundle.loadString(doc.assetPath);
      final loaded = LoadedLegalDocument(
        document: doc,
        text: text,
        sha256Hex: sha256HexOf(text),
      );
      _loadedByPath[doc.assetPath] = loaded;
      return loaded;
    } catch (e) {
      print('❌ LegalService: failed to load ${doc.assetPath}: $e');
      rethrow;
    }
  }

  /// Loads every document in one call, in manifest order.
  Future<List<LoadedLegalDocument>> loadAll() async {
    final out = <LoadedLegalDocument>[];
    for (final doc in kLegalDocuments) {
      out.add(await load(doc));
    }
    return out;
  }

  // ------------------------------------------------------------------
  // Reading acceptances
  // ------------------------------------------------------------------

  /// Newest accepted version per document key for [userId].
  ///
  /// Returns an empty map when the user has accepted nothing yet.
  Future<Map<String, String>> acceptedVersions(String userId) async {
    try {
      final rows = await _client
          .from(_table)
          .select('document_key, document_version, accepted_at')
          .eq('user_id', userId)
          .order('accepted_at', ascending: false);

      final out = <String, String>{};
      for (final row in rows as List) {
        final map = row as Map<String, dynamic>;
        // Rows come newest-first, so the first sighting of a key is
        // its newest version.
        out.putIfAbsent(
          map['document_key'] as String,
          () => map['document_version'] as String,
        );
      }
      return out;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205') {
        print('⚠️ LegalService: table $_table does not exist in Supabase (PGRST205).');
        return {};
      }
      print('❌ LegalService: failed to read acceptances for $userId: $e');
      rethrow;
    } catch (e) {
      print('❌ LegalService: failed to read acceptances for $userId: $e');
      rethrow;
    }
  }

  /// Full acceptance history for [userId], newest first.
  Future<List<LegalAcceptanceRecord>> acceptanceHistory(String userId) async {
    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('user_id', userId)
          .order('accepted_at', ascending: false);

      return (rows as List)
          .map(
            (row) => LegalAcceptanceRecord.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205') {
        print('⚠️ LegalService: table $_table does not exist in Supabase (PGRST205).');
        return [];
      }
      print('❌ LegalService: failed to read acceptance history: $e');
      rethrow;
    } catch (e) {
      print('❌ LegalService: failed to read acceptance history: $e');
      rethrow;
    }
  }

  /// True when [userId] has accepted every required document at the
  /// version currently bundled in this build.
  Future<bool> hasAcceptedCurrentVersions(String userId) async {
    try {
      final accepted = await acceptedVersions(userId);
      for (final doc in requiredLegalDocuments()) {
        if (accepted[doc.key] != doc.version) return false;
      }
      return true;
    } catch (e) {
      // Fail safe: if we cannot verify, treat the user as needing to
      // re-accept. The banner is dismissible, so this degrades to a
      // bounded nag rather than a silent compliance gap.
      print('⚠️ LegalService: could not verify acceptance, prompting: $e');
      return false;
    }
  }

  // ------------------------------------------------------------------
  // Recording acceptances
  // ------------------------------------------------------------------

  /// Records that the signed-in user accepted [doc].
  ///
  /// [source] is `in_app_prompt` (or another non-registration source).
  /// Re-accepting the same version is a no-op thanks to the table's
  /// UNIQUE constraint, so this is safe to call repeatedly.
  Future<void> accept(
    LegalDocument doc, {
    String source = 'in_app_prompt',
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('LegalService.accept called while signed out');
    }

    final loaded = await load(doc);

    try {
      await _client.from(_table).upsert(
        {
          'user_id': user.id,
          'document_key': doc.key,
          'document_version': doc.version,
          'document_hash': loaded.sha256Hex,
          'app_version': await _appVersion(),
          'source': source,
        },
        onConflict: 'user_id,document_key,document_version',
        ignoreDuplicates: true,
      );
      print('✅ LegalService: recorded ${doc.key} v${doc.version}');
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205') {
        print(
          '❌ LegalService: table public.legal_acceptances not found in Supabase (PGRST205). '
          'Please run supabase/migrations/20261005_legal_acceptances.sql in your Supabase SQL Editor.',
        );
        throw Exception(
          'Database setup required: Please run migration 20261005_legal_acceptances.sql in your Supabase SQL Editor.',
        );
      }
      print('❌ LegalService: failed to record acceptance: $e');
      rethrow;
    } catch (e) {
      print('❌ LegalService: failed to record acceptance: $e');
      rethrow;
    }
  }

  // ------------------------------------------------------------------
  // Registration metadata
  // ------------------------------------------------------------------

  /// Builds the `legal_acceptances` array for auth metadata.
  ///
  /// Pass the result to [AuthService.registerCustomer]; the
  /// `handle_new_auth_user()` trigger reads it, enforces that every
  /// required document is present and writes the acceptance rows.
  Future<List<Map<String, String>>> registrationAcceptances() async {
    final out = <Map<String, String>>[];
    for (final doc in requiredLegalDocuments()) {
      final loaded = await load(doc);
      out.add({
        'key': doc.key,
        'version': doc.version,
        'hash': loaded.sha256Hex,
      });
    }
    return out;
  }

  /// The running app's version, stamped onto acceptance rows so we can
  /// prove which build showed the user the document text. Returns null
  /// where the platform plugin is unavailable (tests, some shells).
  Future<String?> appVersion() => _appVersion();

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  /// sha256 hex digest of the given text.
  static String sha256HexOf(String text) => sha256.convert(utf8.encode(text)).toString();

  /// The running app's version (e.g. "1.0.0+1"), or null when the
  /// platform plugin is unavailable.
  Future<String?> _appVersion() async {
    if (_cachedPackageInfo != null) return _cachedPackageInfo!.version;
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedPackageInfo = info;
      return info.version;
    } catch (e) {
      // Tests and some desktop shells have no platform channel.
      print('⚠️ LegalService: package info unavailable, app_version omitted: $e');
      return null;
    }
  }
}

/// Registry of the legal documents the app shows to users.
///
/// This file is the single source of truth for WHICH text is bundled
/// (via [assetPath]), WHAT version it is, and WHETHER a user must
/// accept it to register.
///
/// Workflow for changing a document:
///
///  1. Edit the Markdown file under `assets/legal/`.
///  2. Bump [version] here (e.g. '1.0' -> '1.1') and update
///     [effectiveDate].
///  3. If the document is required, mirror the new required set in
///     `handle_new_auth_user()` (supabase/migrations) - that is the
///     server-side enforcement of the same rule.
///
/// Bumping the version is what makes already-registered users see the
/// re-consent banner exactly once (see LegalConsentBanner).
library;

/// One bundled legal document.
class LegalDocument {
  /// Stable identifier stored in `legal_acceptances.document_key`
  /// and in auth metadata. Never rename a key once released - that
  /// would orphan previously recorded acceptances.
  final String key;

  /// Human-readable title shown in the app UI.
  final String title;

  /// Version accepted by the user. Stored in
  /// `legal_acceptances.document_version`.
  final String version;

  /// ISO-8601 date (YYYY-MM-DD) this version takes effect. Kept as a
  /// string so every [LegalDocument] stays a compile-time constant.
  final String effectiveDate;

  /// Bundled Markdown asset containing the full text.
  final String assetPath;

  /// Whether a user must accept this document to register.
  /// Must match `v_required` in `handle_new_auth_user()`.
  final bool required;

  const LegalDocument({
    required this.key,
    required this.title,
    required this.version,
    required this.effectiveDate,
    required this.assetPath,
    required this.required,
  });

  /// Parsed [effectiveDate], for "not in the future" sanity checks.
  DateTime get effectiveDateTime => DateTime.parse(effectiveDate);
}

/// All documents shipped with this build.
const List<LegalDocument> kLegalDocuments = [
  LegalDocument(
    key: 'terms_of_service',
    title: 'Terms of Service',
    version: '1.0',
    effectiveDate: '2026-10-05',
    assetPath: 'assets/legal/terms_of_service.md',
    required: true,
  ),
  LegalDocument(
    key: 'privacy_policy',
    title: 'Privacy Policy',
    version: '1.0',
    effectiveDate: '2026-10-05',
    assetPath: 'assets/legal/privacy_policy.md',
    required: true,
  ),
];

/// Keys the server (`handle_new_auth_user()`) requires at registration.
/// Kept as a literal list for clarity - do not compute it at runtime.
const List<String> kRequiredLegalDocumentKeys = [
  'terms_of_service',
  'privacy_policy',
];

/// Looks up a document by its stable key.
///
/// Throws [StateError] for an unknown key - callers should never
/// silently swallow that, because an unknown key means a document
/// was renamed or removed without migrating the data.
LegalDocument legalDocumentByKey(String key) {
  for (final doc in kLegalDocuments) {
    if (doc.key == key) return doc;
  }
  throw StateError('Unknown legal document key: "$key"');
}

/// Returns the required documents, in manifest order.
List<LegalDocument> requiredLegalDocuments() =>
    kLegalDocuments.where((d) => d.required).toList(growable: false);

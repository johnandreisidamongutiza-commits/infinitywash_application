import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/legal_documents.dart';
import '../screens/shared/legal_document_screen.dart';
import '../services/legal_service.dart';
import '../services/secure_storage_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// Soft, non-blocking prompt for existing users who have not accepted
/// the current version of the required legal documents.
///
/// Never blocks the app. Dismissing is remembered **per document
/// version**, so bumping a version in `legal_documents.dart` makes
/// the banner reappear exactly once for that version.
class LegalConsentBanner extends StatefulWidget {
  /// Called once the user is fully up to date, so the parent can
  /// refresh its layout.
  final VoidCallback? onUpToDate;

  const LegalConsentBanner({super.key, this.onUpToDate});

  /// Version-scoped dismissal key: changes whenever any required
  /// document version changes, which is what re-shows the banner.
  static String get _dismissKey {
    final versionStamp = requiredLegalDocuments()
        .map((d) => '${d.key}-${d.version}')
        .join('__');
    return 'legal_banner_dismissed_$versionStamp';
  }

  @override
  State<LegalConsentBanner> createState() => _LegalConsentBannerState();
}

class _LegalConsentBannerState extends State<LegalConsentBanner> {
  final LegalService _legalService = LegalService();
  final FlutterSecureStorage _storage = SecureStorageService.instance.storage;

  /// Tri-state: null while checking, then whether the prompt applies.
  bool? _applies;
  List<LegalDocument> _pending = [];

  bool _working = false;

  @override
  void initState() {
    super.initState();
    _evaluate();
  }

  Future<void> _evaluate() async {
    if (!mounted) return;
    setState(() => _applies = null);

    final user = SupabaseService.currentUser;
    if (user == null) {
      // The banner only makes sense for a signed-in customer.
      if (!mounted) return;
      setState(() => _applies = false);
      return;
    }

    // Respect a dismissal recorded for this exact version set.
    if (await _storage.read(key: LegalConsentBanner._dismissKey) == 'true') {
      if (!mounted) return;
      setState(() => _applies = false);
      return;
    }

    try {
      final accepted = await _legalService.acceptedVersions(user.id);
      final pending = requiredLegalDocuments()
          .where((d) => accepted[d.key] != d.version)
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _pending = pending;
        _applies = pending.isNotEmpty;
      });
    } catch (e) {
      // Fail safe: if we cannot verify, keep prompting. The banner is
      // dismissible, so this stays a bounded nag rather than a silent
      // compliance gap.
      print('⚠️ LegalConsentBanner: could not verify acceptance: $e');
      if (!mounted) return;
      setState(() {
        _pending = requiredLegalDocuments();
        _applies = true;
      });
    }
  }

  Future<void> _dismiss() async {
    try {
      await _storage.write(key: LegalConsentBanner._dismissKey, value: 'true');
    } catch (e) {
      print('⚠️ LegalConsentBanner: could not persist dismissal: $e');
    }
    if (mounted) setState(() => _applies = false);
  }

  Future<void> _reviewAndAccept() async {
    if (_working) return;
    setState(() => _working = true);

    try {
      // Walk the outstanding documents one at a time. Cancelling any
      // of them keeps the banner up so nothing is silently skipped.
      for (final doc in _pending) {
        final accepted = await LegalDocumentScreen.show(
          context,
          doc,
          requireAcceptance: true,
        );
        if (!accepted) return;
      }
      widget.onUpToDate?.call();
    } finally {
      if (mounted) {
        setState(() => _working = false);
        await _evaluate();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final applies = _applies;
    if (applies == null || !applies) return const SizedBox.shrink();

    final titles = _pending.map((d) => d.title).join(' and the ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.lightBlue,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentBlue.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.gavel_outlined,
                  color: AppTheme.primaryBlue, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Please review our updated Terms',
                      style: AppTheme.lightTheme.textTheme.titleSmall
                          ?.copyWith(
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'We have published a new version of the $titles. '
                      'You can keep using the app while you take a look.',
                      style: AppTheme.lightTheme.textTheme.bodySmall
                          ?.copyWith(color: AppTheme.textDark),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _dismiss,
                child: const Text(
                  'Later',
                  style: TextStyle(color: AppTheme.textLight),
                ),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: _working ? null : _reviewAndAccept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: _working
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Review & Accept'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

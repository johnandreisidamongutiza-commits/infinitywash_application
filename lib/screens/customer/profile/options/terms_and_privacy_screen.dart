import 'package:flutter/material.dart';

import '../../../../config/legal_documents.dart';
import '../../../../services/legal_service.dart';
import '../../../../services/supabase_service.dart';
import '../../../../theme/app_theme.dart';
import '../../../shared/legal_document_screen.dart';

/// Lets the customer re-read the current Terms of Service and Privacy
/// Policy and see exactly which versions they have accepted and when.
///
/// Read-only by design: consent is captured at registration and via
/// the in-app prompt, never implicitly from this screen.
class CustomerTermsAndPrivacyScreen extends StatefulWidget {
  const CustomerTermsAndPrivacyScreen({super.key});

  @override
  State<CustomerTermsAndPrivacyScreen> createState() =>
      _CustomerTermsAndPrivacyScreenState();
}

class _CustomerTermsAndPrivacyScreenState
    extends State<CustomerTermsAndPrivacyScreen> {
  final LegalService _legalService = LegalService();

  List<LegalAcceptanceRecord>? _history;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() => _error = 'You are signed out.');
      return;
    }

    try {
      final history = await _legalService.acceptanceHistory(user.id);
      if (!mounted) return;
      setState(() => _history = history);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load your acceptance history: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Terms & Privacy',
          style: AppTheme.lightTheme.textTheme.titleMedium
              ?.copyWith(color: AppTheme.textDark),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            Text(
              'Documents',
              style: AppTheme.lightTheme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Tap a document to read the full text.',
              style: AppTheme.lightTheme.textTheme.bodySmall
                  ?.copyWith(color: AppTheme.textLight),
            ),
            const SizedBox(height: 12),
            for (final doc in kLegalDocuments) ...[
              _buildDocumentCard(doc),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 24),
            Text(
              'Your acceptances',
              style: AppTheme.lightTheme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Each time you accept a version, we record the version, the '
              'exact text it contained, and when you accepted it.',
              style: AppTheme.lightTheme.textTheme.bodySmall
                  ?.copyWith(color: AppTheme.textLight),
            ),
            const SizedBox(height: 12),
            _buildHistorySection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentCard(LegalDocument doc) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => LegalDocumentScreen.show(context, doc),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.softGray,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderGray),
        ),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, color: AppTheme.accentBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title,
                    style: AppTheme.lightTheme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Version ${doc.version} · '
                    'Effective ${_formatDate(doc.effectiveDateTime)}',
                    style: AppTheme.lightTheme.textTheme.bodySmall
                        ?.copyWith(color: AppTheme.textLight),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textLight),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySection() {
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _boxDecoration(),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.errorRed),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _error!,
                style: AppTheme.lightTheme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    final history = _history;
    if (history == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (history.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _boxDecoration(),
        child: Text(
          'You have not accepted a version yet. Existing customers are '
          'prompted from the home screen; new sign-ups accept at '
          'registration.',
          style: AppTheme.lightTheme.textTheme.bodySmall
              ?.copyWith(color: AppTheme.textLight),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        children: [
          for (var i = 0; i < history.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, color: AppTheme.borderGray),
            _buildHistoryRow(history[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryRow(LegalAcceptanceRecord record) {
    final isCurrent =
        record.documentVersion == legalDocumentByKey(record.documentKey).version;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            isCurrent ? Icons.verified_outlined : Icons.history,
            color: isCurrent ? Colors.green : AppTheme.textLight,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record.documentTitle} · v${record.documentVersion}',
                  style: AppTheme.lightTheme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'Accepted ${_formatDateTime(record.acceptedAt)} · '
                  '${_describeSource(record.source)}'
                  '${record.appVersion == null ? '' : ' · app ${record.appVersion}'}',
                  style: AppTheme.lightTheme.textTheme.bodySmall
                      ?.copyWith(color: AppTheme.textLight),
                ),
              ],
            ),
          ),
          if (isCurrent)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Current',
                style: AppTheme.lightTheme.textTheme.bodySmall?.copyWith(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  BoxDecoration _boxDecoration() => BoxDecoration(
        color: AppTheme.softGray,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
      );

  String _describeSource(String source) {
    switch (source) {
      case 'registration':
        return 'at registration';
      case 'in_app_prompt':
        return 'from the app';
      default:
        return source;
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatDateTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${_formatDate(d)} $hh:$mm';
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../config/legal_documents.dart';
import '../../services/legal_service.dart';
import '../../theme/app_theme.dart';

/// Full-screen reader for one legal document.
///
/// When [requireAcceptance] is true (registration and the re-consent
/// banner), a sticky footer holds the agree button and it stays
/// disabled until the user has scrolled to the bottom of the text -
/// evidence that the document was actually reviewed, not just opened.
///
/// Push it directly (no [showLegalDocument]) for read-only access
/// from the profile screen.
class LegalDocumentScreen extends StatefulWidget {
  final LegalDocument document;

  /// Whether to show the "I Agree" footer and gate it on scrolling.
  final bool requireAcceptance;

  /// Value stored in `legal_acceptances.source` when agreeing.
  final String acceptSource;

  const LegalDocumentScreen({
    super.key,
    required this.document,
    this.requireAcceptance = false,
    this.acceptSource = 'in_app_prompt',
  });

  /// Shows the reader and returns whether the user agreed.
  ///
  /// With [requireAcceptance] true the only way to dismiss is to
  /// scroll through and agree, or to cancel explicitly.
  static Future<bool> show(
    BuildContext context,
    LegalDocument document, {
    bool requireAcceptance = false,
    String acceptSource = 'in_app_prompt',
  }) async {
    final accepted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LegalDocumentScreen(
          document: document,
          requireAcceptance: requireAcceptance,
          acceptSource: acceptSource,
        ),
      ),
    );
    return accepted ?? false;
  }

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  final _scrollController = ScrollController();
  final _legalService = LegalService();

  LoadedLegalDocument? _loaded;
  String? _error;

  bool _reachedEnd = false;
  bool _agreeing = false;

  /// How close to the bottom counts as "read the whole thing".
  /// A small tolerance avoids fighting pixel rounding and iOS
  /// bouncing at the end of the list.
  static const double _endTolerance = 48;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadDocument();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDocument() async {
    try {
      final loaded = await _legalService.load(widget.document);
      if (mounted) setState(() => _loaded = loaded);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not load this document. Please try again.');
      }
    }
  }

  void _onScroll() {
    if (!widget.requireAcceptance || _reachedEnd) return;
    if (!_scrollController.hasClients) return;

    final max = _scrollController.position.maxScrollExtent;
    // Short content that fits on one screen: nothing to scroll to.
    if (max <= 0 || _scrollController.offset >= max - _endTolerance) {
      setState(() => _reachedEnd = true);
    }
  }

  Future<void> _agree() async {
    if (_agreeing) return;
    setState(() => _agreeing = true);
    try {
      await _legalService.accept(widget.document, source: widget.acceptSource);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _agreeing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not record your acceptance: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          doc.title,
          style: AppTheme.lightTheme.textTheme.titleMedium
              ?.copyWith(color: AppTheme.textDark),
        ),
        // With the scroll gate, back is still allowed - registration
        // simply cannot proceed without agreeing.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textDark),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.lightBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Version ${doc.version}',
                      style: AppTheme.lightTheme.textTheme.bodySmall
                          ?.copyWith(
                        color: AppTheme.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Effective ${_formatDate(doc.effectiveDateTime)}',
                    style: AppTheme.lightTheme.textTheme.bodySmall
                        ?.copyWith(color: AppTheme.textLight),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
            if (widget.requireAcceptance) _buildAgreeFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppTheme.errorRed, size: 40),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTheme.lightTheme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _error = null;
                  });
                  _loadDocument();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_loaded == null) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Markdown(
      controller: _scrollController,
      data: _loaded!.text,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      styleSheet: MarkdownStyleSheet.fromTheme(
        Theme.of(context),
      ).copyWith(
        h1: AppTheme.lightTheme.textTheme.headlineMedium
            ?.copyWith(color: AppTheme.textDark),
        h2: AppTheme.lightTheme.textTheme.titleLarge
            ?.copyWith(color: AppTheme.textDark),
        p: AppTheme.lightTheme.textTheme.bodyMedium
            ?.copyWith(color: AppTheme.textDark, height: 1.5),
      ),
    );
  }

  Widget _buildAgreeFooter() {
    final ready = _loaded != null && _reachedEnd && !_agreeing;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppTheme.borderGray.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_reachedEnd)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.swipe_up, size: 16, color: AppTheme.textLight),
                  const SizedBox(width: 6),
                  Text(
                    'Scroll to the end to continue',
                    style: AppTheme.lightTheme.textTheme.bodySmall
                        ?.copyWith(color: AppTheme.textLight),
                  ),
                ],
              ),
            ),
          ElevatedButton(
            onPressed: ready ? _agree : null,
            child: _agreeing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_reachedEnd
                    ? 'I Agree'
                    : 'Read the full ${widget.document.title} to continue'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

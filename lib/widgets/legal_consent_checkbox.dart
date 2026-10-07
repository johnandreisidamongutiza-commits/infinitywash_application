import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../config/legal_documents.dart';
import '../screens/shared/legal_document_screen.dart';
import '../theme/app_theme.dart';

/// "I confirm I am at least 13 years old and I have read and agree to
/// the Terms of Service and the Privacy Policy", with each document
/// name tappable.
///
/// The documents open read-only here: a user cannot record consent
/// before the account exists, so the checkbox itself is the consent
/// gesture and `handle_new_auth_user()` writes the acceptance rows
/// server-side at registration.
class LegalConsentCheckbox extends StatefulWidget {
  /// Current checked state, owned by the parent form.
  final bool value;

  /// Called when the checkbox is toggled.
  final ValueChanged<bool> onChanged;

  const LegalConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<LegalConsentCheckbox> createState() => _LegalConsentCheckboxState();
}

class _LegalConsentCheckboxState extends State<LegalConsentCheckbox> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  TapGestureRecognizer _recognizerFor(BuildContext context, LegalDocument doc) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () {
        // Read-only: registration records consent via the trigger.
        LegalDocumentScreen.show(context, doc, requireAcceptance: false);
      };
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    // Required documents render as tappable links, in manifest order.
    final required = requiredLegalDocuments();

    final baseStyle = AppTheme.lightTheme.textTheme.bodyMedium
            ?.copyWith(color: AppTheme.textDark) ??
        const TextStyle();
    final linkStyle = baseStyle.copyWith(
      color: AppTheme.accentBlue,
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.underline,
    );

    // Rebuild recognizers each pass; dispose() clears the previous set.
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final spans = <InlineSpan>[
      const TextSpan(
          text: 'I confirm I am at least 13 years old and I have read and '
              'agree to the '),
    ];

    for (var i = 0; i < required.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ' and the '));
      spans.add(
        TextSpan(
          text: required[i].title,
          style: linkStyle,
          recognizer: _recognizerFor(context, required[i]),
        ),
      );
    }

    spans.add(const TextSpan(text: '.'));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: widget.value,
          onChanged: (v) => widget.onChanged(v ?? false),
          activeColor: AppTheme.accentBlue,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text.rich(
              TextSpan(style: baseStyle, children: spans),
            ),
          ),
        ),
      ],
    );
  }
}

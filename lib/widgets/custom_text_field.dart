import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

class CustomTextField extends StatefulWidget {
  final String label;
  final String hint;
  final IconData prefixIcon;
  final bool isPassword;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;

  /// Hard character cap rendered with a live counter. Enforced by
  /// [MaxLengthEnforcement.enforced] so pasted text is truncated, too.
  final int? maxLength;

  /// Input formatters (e.g. [InputFormatters.digitsOnly]) that physically
  /// reject disallowed characters on every platform.
  final List<TextInputFormatter>? inputFormatters;

  /// Capitalization behavior (words for names, sentences for notes).
  final TextCapitalization textCapitalization;

  /// Whether the OS autocorrect/suggestion bar is enabled.
  final bool autocorrect;

  /// Action button on the soft keyboard (done, next, search…).
  final TextInputAction? textInputAction;

  /// Invoked when the field is submitted (keyboard action pressed).
  final ValueChanged<String>? onSubmitted;

  /// Whether the field participates in form validation/submit focus order.
  final bool enabled;

  const CustomTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.prefixIcon,
    this.isPassword = false,
    this.controller,
    this.onChanged,
    this.keyboardType,
    this.validator,
    this.maxLength,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
    this.textInputAction,
    this.onSubmitted,
    this.enabled = true,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTheme.lightTheme.textTheme.titleMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: widget.controller,
          obscureText: widget.isPassword ? _obscureText : false,
          keyboardType: widget.keyboardType,
          onChanged: widget.onChanged,
          validator: widget.validator,
          // Validators run on every edit so inline errors clear as the user
          // types instead of only on submit.
          autovalidateMode: AutovalidateMode.onUserInteraction,
          maxLength: widget.maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          inputFormatters: widget.inputFormatters,
          textCapitalization: widget.textCapitalization,
          autocorrect: widget.autocorrect,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onSubmitted,
          enabled: widget.enabled,
          buildCounter: widget.maxLength == null
              ? null
              : (context,
                  {required currentLength,
                  required isFocused,
                  required maxLength}) {
                  // Quiet character counter; red when the cap is reached.
                  return Padding(
                    padding: const EdgeInsets.only(right: 4, bottom: 4),
                    child: Text(
                      '$currentLength/$maxLength',
                      style: TextStyle(
                        fontSize: 11,
                        color: currentLength >= (maxLength ?? 0)
                            ? AppTheme.errorRed
                            : AppTheme.textLight,
                      ),
                    ),
                  );
                },
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: AppTheme.lightTheme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.textLight.withValues(alpha: 0.5),
            ),
            prefixIcon: Icon(widget.prefixIcon, color: AppTheme.textDark.withValues(alpha: 0.5)),
            suffixIcon: widget.isPassword
                ? IconButton(
                    icon: Icon(
                      _obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: AppTheme.textDark.withValues(alpha: 0.5),
                    ),
                    onPressed: () => setState(() => _obscureText = !_obscureText),
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            errorStyle: const TextStyle(fontSize: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.borderGray),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.borderGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.accentBlue, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

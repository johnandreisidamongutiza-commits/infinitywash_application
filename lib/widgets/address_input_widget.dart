import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Shared 3-part address input used by both customer registration and
/// the staff walk-in order creation flow.
///
/// Parts:
///   1. House / Unit / Street — free-text
///   2. Barangay              — Santa Cruz dropdown (or custom if "Other")
///   3. Landmark / Meetup Note — optional free-text
///
/// The caller owns the controllers and [selectedBarangay] so that the
/// parent can read values and rebuild its own state.
class AddressInputWidget extends StatelessWidget {
  const AddressInputWidget({
    super.key,
    required this.houseStreetController,
    required this.customBarangayController,
    required this.landmarkController,
    required this.selectedBarangay,
    required this.onBarangayChanged,
    this.showLandmark = true,
    this.houseStreetRequired = true,
    this.barangayRequired = true,
    this.houseStreetHint = 'e.g. Blk 5 Lot 12, Sunflower St.',
    this.landmarkHint = 'e.g. Near church, blue gate',
    this.helperText,
    this.fillColor = Colors.white,
    this.borderRadius = 16.0,
    this.iconColor,
  });

  final TextEditingController houseStreetController;
  final TextEditingController customBarangayController;
  final TextEditingController landmarkController;
  final String? selectedBarangay;
  final ValueChanged<String?> onBarangayChanged;
  final bool showLandmark;
  final bool houseStreetRequired;
  final bool barangayRequired;
  final String houseStreetHint;
  final String landmarkHint;

  /// Optional helper text shown below the barangay dropdown.
  final String? helperText;

  /// Input background fill color (defaults to white to match CustomTextField).
  final Color fillColor;

  /// Border radius of the fields (defaults to 16 to match CustomTextField).
  final double borderRadius;

  /// Custom icon color (defaults to AppTheme.textDark at 50% opacity).
  final Color? iconColor;

  /// All barangays in Santa Cruz, Laguna.
  static const List<String> santaCruzBarangays = [
    'Alipit',
    'Bagumbayan',
    'Bubukal',
    'Calios',
    'Duhat',
    'Gatid',
    'Jasaan',
    'Labuin',
    'Malinao',
    'Oogong',
    'Pagsawitan',
    'Palasan',
    'Patimbao',
    'Poblacion I',
    'Poblacion II',
    'Poblacion III',
    'Poblacion IV',
    'Poblacion V',
    'San Angel',
    'San Jose',
    'San Juan',
    'Santa Cruz',
    'Santisimo Rosario',
    'Santo Angel Central',
    'Santo Angel Norte',
    'Santo Angel Sur',
    'Other / Outside Sta. Cruz',
  ];

  /// Build the full composed address string from the 3 parts.
  /// Call this from the parent's state to get the value to save/submit.
  static String buildFullAddress({
    required String houseStreet,
    required String? selectedBarangay,
    required String customBarangay,
  }) {
    final brgy = selectedBarangay == 'Other / Outside Sta. Cruz'
        ? customBarangay.trim()
        : (selectedBarangay ?? customBarangay.trim());

    final parts = <String>[];
    if (houseStreet.isNotEmpty) parts.add(houseStreet);
    if (brgy.isNotEmpty) {
      if (!brgy.toLowerCase().contains('brgy') &&
          !brgy.toLowerCase().contains('barangay')) {
        parts.add('Brgy. $brgy');
      } else {
        parts.add(brgy);
      }
    }
    if (selectedBarangay != 'Other / Outside Sta. Cruz' && parts.isNotEmpty) {
      parts.add('Santa Cruz, Laguna');
    }
    return parts.join(', ');
  }

  /// Parse an existing address string and populate the controllers.
  /// Useful when loading saved customer data into the form.
  static void parseAndPopulate({
    required String address,
    required TextEditingController houseStreetController,
    required void Function(String?) setBarangay,
    TextEditingController? customBarangayController,
  }) {
    String? matchedBarangay;
    for (final b in santaCruzBarangays) {
      if (b == 'Other / Outside Sta. Cruz') continue;
      final regex = RegExp('\\b${RegExp.escape(b)}\\b', caseSensitive: false);
      if (regex.hasMatch(address)) {
        matchedBarangay = b;
        break;
      }
    }

    if (matchedBarangay != null) {
      setBarangay(matchedBarangay);
      final lower = address.toLowerCase();
      final idx = lower.indexOf(matchedBarangay.toLowerCase());
      if (idx > 0) {
        var prefix = address.substring(0, idx).trim();
        prefix = prefix
            .replaceAll(
                RegExp(r',?\s*(brgy\.?|barangay)\s*$', caseSensitive: false),
                '')
            .trim();
        if (prefix.endsWith(',')) {
          prefix = prefix.substring(0, prefix.length - 1).trim();
        }
        houseStreetController.text = prefix.isNotEmpty ? prefix : address;
      } else {
        houseStreetController.text = address;
      }
    } else {
      if (customBarangayController != null && address.contains(',')) {
        final commaIdx = address.lastIndexOf(',');
        final possibleBrgy = address.substring(commaIdx + 1).trim();
        final streetPart = address.substring(0, commaIdx).trim();
        setBarangay('Other / Outside Sta. Cruz');
        customBarangayController.text = possibleBrgy;
        houseStreetController.text = streetPart;
      } else {
        houseStreetController.text = address;
      }
    }
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
    required Color effectiveIconColor,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.lexend(
        fontSize: 14,
        color: AppTheme.textLight.withValues(alpha: 0.5),
      ),
      errorStyle: GoogleFonts.lexend(
        fontSize: 12,
        color: AppTheme.errorRed,
      ),
      prefixIcon: Icon(prefixIcon, color: effectiveIconColor),
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: AppTheme.borderGray),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: AppTheme.borderGray),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: AppTheme.accentBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: AppTheme.errorRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: AppTheme.errorRed, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor =
        iconColor ?? AppTheme.textDark.withValues(alpha: 0.5);
    final textStyle = GoogleFonts.lexend(
      fontSize: 14,
      color: AppTheme.textDark,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Part 1: House / Street ──────────────────────────────────
        _SectionLabel(
          label: 'House No. / Street',
          isRequired: houseStreetRequired,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: houseStreetController,
          textCapitalization: TextCapitalization.words,
          style: textStyle,
          decoration: _buildInputDecoration(
            hintText: houseStreetHint,
            prefixIcon: Icons.home_outlined,
            effectiveIconColor: effectiveIconColor,
          ),
          validator: houseStreetRequired
              ? (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter your house/street address'
                  : null
              : null,
        ),

        const SizedBox(height: 20),

        // ── Part 2: Barangay ────────────────────────────────────────
        _SectionLabel(
          label: 'Barangay',
          isRequired: barangayRequired,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: selectedBarangay,
          isExpanded: true,
          style: textStyle,
          icon: Icon(Icons.keyboard_arrow_down, color: effectiveIconColor),
          hint: Text(
            'Select your barangay',
            style: GoogleFonts.lexend(
              fontSize: 14,
              color: AppTheme.textLight.withValues(alpha: 0.5),
            ),
          ),
          decoration: _buildInputDecoration(
            hintText: '',
            prefixIcon: Icons.location_city_outlined,
            effectiveIconColor: effectiveIconColor,
          ),
          items: santaCruzBarangays
              .map(
                (b) => DropdownMenuItem(
                  value: b,
                  child: Text(
                    b,
                    style: textStyle,
                  ),
                ),
              )
              .toList(),
          onChanged: onBarangayChanged,
          validator: barangayRequired
              ? (v) => v == null ? 'Please select your barangay' : null
              : null,
        ),

        // Optional helper text below dropdown
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              helperText!,
              style: GoogleFonts.lexend(
                fontSize: 12,
                color: AppTheme.textLight,
              ),
            ),
          ),
        ],

        // Custom barangay field — shown only when "Other" is selected
        if (selectedBarangay == 'Other / Outside Sta. Cruz') ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: customBarangayController,
            textCapitalization: TextCapitalization.words,
            style: textStyle,
            decoration: _buildInputDecoration(
              hintText: 'e.g. Pila, Laguna or other area',
              prefixIcon: Icons.edit_location_alt_outlined,
              effectiveIconColor: effectiveIconColor,
            ),
            validator: barangayRequired
                ? (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter your barangay / area'
                    : null
                : null,
          ),
        ],

        // ── Part 3: Landmark / Meetup Note ─────────────────────────
        if (showLandmark) ...[
          const SizedBox(height: 20),
          const _SectionLabel(
            label: 'Landmark / Meetup Note',
            isRequired: false,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: landmarkController,
            textCapitalization: TextCapitalization.sentences,
            style: textStyle,
            decoration: _buildInputDecoration(
              hintText: landmarkHint,
              prefixIcon: Icons.assistant_navigation,
              effectiveIconColor: effectiveIconColor,
            ),
          ),
        ],
      ],
    );
  }
}

/// Label with standard Lexend typography matching CustomTextField.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.isRequired = false});

  final String label;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        text: label,
        style: GoogleFonts.lexend(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textDark,
        ),
        children: isRequired
            ? [
                TextSpan(
                  text: ' *',
                  style: GoogleFonts.lexend(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.errorRed,
                  ),
                ),
              ]
            : null,
      ),
    );
  }
}

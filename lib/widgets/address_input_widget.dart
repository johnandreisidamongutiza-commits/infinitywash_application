import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../utils/input_formatters.dart';
import '../utils/validators.dart';

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

  /// Strip redundant barangay, town, and province from the house/street string
  static String cleanHouseStreet(String rawHouseStreet, String? barangay) {
    var cleaned = rawHouseStreet.trim();
    if (cleaned.isEmpty) return '';

    // If a barangay is identified, strip any instances of it
    if (barangay != null &&
        barangay.trim().isNotEmpty &&
        barangay != 'Other / Outside Sta. Cruz') {
      final brgyClean = RegExp.escape(barangay.trim());
      cleaned = cleaned.replaceAll(
        RegExp(r',?\s*(brgy\.?|barangay)?\s*' + brgyClean + r'\b',
            caseSensitive: false),
        '',
      );
    }

    // Strip municipality/city variations (Santa Cruz, Sta Cruz, Sta. Cruz, statucruz, etc.)
    cleaned = cleaned.replaceAll(
      RegExp(r',?\s*(santa\s*cruz|sta\.?\s*cruz|statucruz)\b',
          caseSensitive: false),
      '',
    );

    // Strip province & country
    cleaned = cleaned.replaceAll(
      RegExp(r',?\s*(laguna|philippines|calabarzon)\b', caseSensitive: false),
      '',
    );

    // Clean up leftover leading/trailing commas, periods, hyphens, and multiple commas
    cleaned = cleaned.replaceAll(RegExp(r'[,;]+'), ',');
    cleaned = cleaned.replaceAll(RegExp(r',\s*,'), ',');
    cleaned = cleaned.trim();
    while (cleaned.startsWith(',') || cleaned.startsWith('-')) {
      cleaned = cleaned.substring(1).trim();
    }
    while (cleaned.endsWith(',') || cleaned.endsWith('-')) {
      cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    }

    return cleaned.trim();
  }

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

    // Clean houseStreet to strip any redundant barangay, city, or province mentions
    final cleanedStreet = cleanHouseStreet(houseStreet, brgy);

    final parts = <String>[];
    if (cleanedStreet.isNotEmpty) {
      parts.add(cleanedStreet);
    }
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
  /// Useful when loading saved customer data into the form or parsing map pin addresses.
  static void parseAndPopulate({
    required String address,
    required TextEditingController houseStreetController,
    required void Function(String?) setBarangay,
    TextEditingController? customBarangayController,
  }) {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      houseStreetController.text = '';
      return;
    }

    String? matchedBarangay;
    for (final b in santaCruzBarangays) {
      if (b == 'Other / Outside Sta. Cruz') continue;
      final regex = RegExp('\\b${RegExp.escape(b)}\\b', caseSensitive: false);
      if (regex.hasMatch(trimmed)) {
        matchedBarangay = b;
        break;
      }
    }

    if (matchedBarangay != null) {
      setBarangay(matchedBarangay);
      final lower = trimmed.toLowerCase();
      final idx = lower.indexOf(matchedBarangay.toLowerCase());
      if (idx > 0) {
        var prefix = trimmed.substring(0, idx).trim();
        prefix = prefix
            .replaceAll(
                RegExp(r',?\s*(brgy\.?|barangay)\s*$', caseSensitive: false),
                '')
            .trim();
        if (prefix.endsWith(',')) {
          prefix = prefix.substring(0, prefix.length - 1).trim();
        }
        prefix = cleanHouseStreet(prefix, matchedBarangay);
        houseStreetController.text = prefix;
      } else {
        // Address starts with the barangay (e.g. "Bubukal, Santa Cruz, Laguna")
        // There is no separate street/house prefix in this string.
        houseStreetController.text = '';
      }
    } else {
      if (customBarangayController != null && trimmed.contains(',')) {
        final commaIdx = trimmed.lastIndexOf(',');
        final possibleBrgy = trimmed.substring(commaIdx + 1).trim();
        final streetPart = trimmed.substring(0, commaIdx).trim();
        setBarangay('Other / Outside Sta. Cruz');
        customBarangayController.text = possibleBrgy;
        houseStreetController.text = cleanHouseStreet(streetPart, possibleBrgy);
      } else {
        houseStreetController.text = cleanHouseStreet(trimmed, null);
      }
    }
  }

  /// Formats and deduplicates any raw address string for display (e.g., in rider or staff views).
  /// Resolves redundant strings such as:
  /// "bubukal statucruz laguna, brgy. bubukal sta cruz, laguna" -> "Brgy. Bubukal, Santa Cruz, Laguna"
  static String formatDisplayAddress(String? address) {
    if (address == null || address.trim().isEmpty) {
      return 'No address provided';
    }

    final trimmed = address.trim();

    // Check if any Santa Cruz barangay is in the address
    String? foundBarangay;
    for (final b in santaCruzBarangays) {
      if (b == 'Other / Outside Sta. Cruz') continue;
      final regex = RegExp('\\b${RegExp.escape(b)}\\b', caseSensitive: false);
      if (regex.hasMatch(trimmed)) {
        foundBarangay = b;
        break;
      }
    }

    if (foundBarangay != null) {
      final segments = trimmed
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final nonRedundantSegments = <String>[];
      bool addedBarangay = false;
      bool addedTown = false;

      for (final seg in segments) {
        final lower = seg.toLowerCase();

        final isBrgyOnly = lower == foundBarangay.toLowerCase() ||
            lower == 'brgy. ${foundBarangay.toLowerCase()}' ||
            lower == 'brgy ${foundBarangay.toLowerCase()}' ||
            lower == 'barangay ${foundBarangay.toLowerCase()}';

        final isTownOrProvinceOnly = lower == 'santa cruz' ||
            lower == 'sta. cruz' ||
            lower == 'sta cruz' ||
            lower == 'statucruz' ||
            lower == 'laguna' ||
            lower == 'santa cruz laguna' ||
            lower == 'sta cruz laguna' ||
            lower == 'sta. cruz laguna' ||
            lower == 'philippines';

        final isCompositeRedundant = (lower.contains(foundBarangay.toLowerCase()) &&
            (lower.contains('sta') ||
                lower.contains('cruz') ||
                lower.contains('laguna')));

        if (isBrgyOnly || isCompositeRedundant) {
          if (!addedBarangay) {
            nonRedundantSegments.add('Brgy. $foundBarangay');
            addedBarangay = true;
          }
        } else if (isTownOrProvinceOnly) {
          if (!addedTown) {
            nonRedundantSegments.add('Santa Cruz, Laguna');
            addedTown = true;
          }
        } else {
          final cleanedSeg = cleanHouseStreet(seg, foundBarangay);
          if (cleanedSeg.isNotEmpty) {
            nonRedundantSegments.add(cleanedSeg);
          }
        }
      }

      if (!addedBarangay) {
        nonRedundantSegments.add('Brgy. $foundBarangay');
      }
      if (!addedTown) {
        nonRedundantSegments.add('Santa Cruz, Laguna');
      }

      final uniqueSegments = <String>[];
      for (final s in nonRedundantSegments) {
        if (!uniqueSegments.any((u) => u.toLowerCase() == s.toLowerCase())) {
          uniqueSegments.add(s);
        }
      }

      return uniqueSegments.join(', ');
    }

    return trimmed;
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
          inputFormatters:
              InputFormatters.text(maxLength: Validators.addressMax),
          decoration: _buildInputDecoration(
            hintText: houseStreetHint,
            prefixIcon: Icons.home_outlined,
            effectiveIconColor: effectiveIconColor,
          ),
          validator: (v) {
            final value = v?.trim() ?? '';
            if (value.isEmpty) {
              return houseStreetRequired
                  ? 'Please enter your house/street address'
                  : null;
            }
            if (value.length < 2) {
              return 'Address must be at least 2 characters.';
            }
            if (value.length > Validators.addressMax) {
              return 'Address must be at most ${Validators.addressMax} characters.';
            }
            return null;
          },
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
            inputFormatters:
                InputFormatters.text(maxLength: Validators.addressMax),
            decoration: _buildInputDecoration(
              hintText: 'e.g. Pila, Laguna or other area',
              prefixIcon: Icons.edit_location_alt_outlined,
              effectiveIconColor: effectiveIconColor,
            ),
            validator: barangayRequired
                ? (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) {
                      return 'Please enter your barangay / area';
                    }
                    if (value.length < 2) {
                      return 'Barangay / area must be at least 2 characters.';
                    }
                    return null;
                  }
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
            inputFormatters:
                InputFormatters.text(maxLength: Validators.landmarkMax),
            decoration: _buildInputDecoration(
              hintText: landmarkHint,
              prefixIcon: Icons.assistant_navigation,
              effectiveIconColor: effectiveIconColor,
            ),
            validator: Validators.landmark,
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

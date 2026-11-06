import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/legal_documents.dart';
import '../../theme/app_theme.dart';
import '../../utils/input_formatters.dart';
import '../../utils/validators.dart';
import '../../widgets/address_input_widget.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/legal_consent_checkbox.dart';
import '../../services/auth_service.dart';
import '../../services/legal_service.dart';
import '../../utils/save_account_prompt.dart';
import 'customer_main_screen.dart';

class GoogleProfileCompletionScreen extends StatefulWidget {
  const GoogleProfileCompletionScreen({super.key});

  @override
  State<GoogleProfileCompletionScreen> createState() => _GoogleProfileCompletionScreenState();
}

class _GoogleProfileCompletionScreenState extends State<GoogleProfileCompletionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _legalService = LegalService();
  final _phone = TextEditingController();
  final _street = TextEditingController();
  final _customBarangay = TextEditingController();
  final _landmark = TextEditingController();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  String? _barangay;
  bool _accepted = false;
  bool _saveAccount = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final metadata = Supabase.instance.client.auth.currentUser?.userMetadata ?? {};
    final fullName = (metadata['full_name'] ?? metadata['name'] ?? '').toString().trim().split(RegExp(r'\s+'));
    _firstName = TextEditingController(text: (metadata['first_name'] ?? (fullName.isNotEmpty ? fullName.first : '')).toString());
    _lastName = TextEditingController(text: (metadata['last_name'] ?? (fullName.length > 1 ? fullName.skip(1).join(' ') : '')).toString());
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _street.dispose();
    _customBarangay.dispose();
    _landmark.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (_formKey.currentState?.validate() != true) return;
    if (!_accepted) {
      _message('Please read and accept the Terms of Service and Privacy Policy.');
      return;
    }
    setState(() => _saving = true);
    try {
      final address = AddressInputWidget.buildFullAddress(
        houseStreet: _street.text.trim(),
        selectedBarangay: _barangay,
        customBarangay: _customBarangay.text.trim(),
      );
      await _authService.completeCustomerProfile(
        firstName: Validators.cleanName(_firstName.text),
        lastName: Validators.cleanName(_lastName.text),
        phone: Validators.normalizePhone(_phone.text.trim()),
        address: address,
        landmark: _landmark.text.trim(),
      );
      for (final document in requiredLegalDocuments()) {
        await _legalService.accept(document, source: 'registration');
      }
      if (_saveAccount) {
        await _authService.rememberCurrentSession();
      }
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const CustomerMainScreen()),
        (_) => false,
      );
    } catch (error) {
      if (mounted) _message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Complete your profile')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('One more step', style: AppTheme.lightTheme.textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  const Text('Add the contact and delivery details needed to place an order.'),
                  const SizedBox(height: 24),
                  CustomTextField(label: 'First Name', hint: 'Juan', prefixIcon: Icons.person_outline, controller: _firstName, inputFormatters: InputFormatters.name(), validator: (v) => Validators.nameField(v, 'First name'), maxLength: Validators.nameMax, textCapitalization: TextCapitalization.words),
                  const SizedBox(height: 16),
                  CustomTextField(label: 'Last Name', hint: 'Dela Cruz', prefixIcon: Icons.person_outline, controller: _lastName, inputFormatters: InputFormatters.name(), validator: (v) => Validators.nameField(v, 'Last name'), maxLength: Validators.nameMax, textCapitalization: TextCapitalization.words),
                  const SizedBox(height: 16),
                  CustomTextField(label: 'Mobile Number', hint: '09XX-XXX-XXXX', prefixIcon: Icons.phone_android_outlined, controller: _phone, keyboardType: TextInputType.phone, inputFormatters: InputFormatters.phone(), validator: Validators.phone),
                  const SizedBox(height: 16),
                  AddressInputWidget(houseStreetController: _street, customBarangayController: _customBarangay, landmarkController: _landmark, selectedBarangay: _barangay, onBarangayChanged: (value) => setState(() => _barangay = value), helperText: 'Santa Cruz, Laguna only. Select "Other" if outside.', landmarkHint: 'e.g. Near church, blue gate'),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.softGray,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LegalConsentCheckbox(
                          value: _accepted,
                          onChanged: (value) => setState(() => _accepted = value),
                        ),
                        const SizedBox(height: 12),
                        Divider(
                          height: 1,
                          color: AppTheme.borderGray.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => setState(() => _saveAccount = !_saveAccount),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 4, horizontal: 2),
                            child: Row(
                              children: [
                                SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: Checkbox(
                                    value: _saveAccount,
                                    onChanged: (v) => setState(
                                        () => _saveAccount = v ?? false),
                                    activeColor: AppTheme.accentBlue,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Save account on this device for quick sign-in',
                                    style: GoogleFonts.lexend(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.textDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _saving ? null : _complete, child: _saving ? const CircularProgressIndicator() : const Text('Save and continue'))),
                ],
              ),
            ),
          ),
        ),
      );
}

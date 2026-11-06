import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../services/profile_service.dart';
import '../../../../theme/app_theme.dart';
import '../../../../utils/app_error.dart';
import '../../../../utils/input_formatters.dart';
import '../../../../utils/validators.dart';
import '../../../../widgets/custom_text_field.dart';
import '../../../../widgets/editable_profile_avatar.dart';

class RiderAccountDetailsScreen extends StatefulWidget {
  const RiderAccountDetailsScreen({super.key});

  @override
  State<RiderAccountDetailsScreen> createState() =>
      _RiderAccountDetailsScreenState();
}

class _RiderAccountDetailsScreenState extends State<RiderAccountDetailsScreen> {
  final _personalFormKey = GlobalKey<FormState>();
  final _profileService = ProfileService();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _vehicleController = TextEditingController();

  String? _avatarUrl;
  String? _profileId;
  bool _hasChanges = false;
  bool _isLoading = true;

  // Edit states
  bool _isEditingPersonal = false;
  bool _isSavingPersonal = false;

  // Baseline values
  String _initialFirstName = '';
  String _initialLastName = '';
  String _initialPhone = '';
  String _initialEmail = '';
  String _initialVehicle = '';

  bool get _hasPersonalChanges {
    return _firstNameController.text.trim() != _initialFirstName ||
        _lastNameController.text.trim() != _initialLastName ||
        _phoneController.text.trim() != _initialPhone ||
        _vehicleController.text.trim() != _initialVehicle;
  }

  bool get _hasUnsavedChanges => _isEditingPersonal && _hasPersonalChanges;

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _firstNameController.addListener(_onFieldChanged);
    _lastNameController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _vehicleController.addListener(_onFieldChanged);
    _loadProfile();
  }

  @override
  void dispose() {
    _firstNameController.removeListener(_onFieldChanged);
    _lastNameController.removeListener(_onFieldChanged);
    _phoneController.removeListener(_onFieldChanged);
    _vehicleController.removeListener(_onFieldChanged);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _vehicleController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getProfile();
      _profileId = profile['id'] as String?;
      final employee = await _profileService.getEmployee(profile['id']);

      if (!mounted) return;

      _firstNameController.text = profile['first_name'] ?? '';
      _lastNameController.text = profile['last_name'] ?? '';
      _phoneController.text = profile['phone'] ?? employee['phone'] ?? '';
      _emailController.text = profile['email'] ?? employee['email'] ?? '';
      _vehicleController.text = employee['vehicle_details'] ?? '';
      _avatarUrl = profile['avatar_url'] as String?;

      _initialFirstName = _firstNameController.text.trim();
      _initialLastName = _lastNameController.text.trim();
      _initialPhone = _phoneController.text.trim();
      _initialEmail = _emailController.text.trim();
      _initialVehicle = _vehicleController.text.trim();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not load account details. ${mapErrorToMessage(error)}',
            style: GoogleFonts.lexend(color: Colors.white),
          ),
          backgroundColor: AppTheme.errorRed,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CARD ACTIONS: PERSONAL INFO
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _savePersonalInfo() async {
    if (!_hasPersonalChanges) {
      setState(() => _isEditingPersonal = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No changes made to personal information.',
                  style: GoogleFonts.lexend(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.primaryBlue,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    if (_personalFormKey.currentState?.validate() != true) return;

    final firstName = Validators.cleanName(_firstNameController.text);
    final lastName = Validators.cleanName(_lastNameController.text);
    if (firstName.isEmpty || lastName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter both your first and last name',
            style: GoogleFonts.lexend(color: Colors.white),
          ),
          backgroundColor: AppTheme.errorRed,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    _firstNameController.text = firstName;
    _lastNameController.text = lastName;

    setState(() => _isSavingPersonal = true);

    try {
      final normalizedPhone =
          Validators.normalizePhone(_phoneController.text.trim());
      _phoneController.text = normalizedPhone;

      await _profileService.updateProfile(
        firstName: firstName,
        lastName: lastName,
        phone: normalizedPhone,
        email: _emailController.text.trim().toLowerCase(),
      );

      final vehicleDetails =
          Validators.cleanVehicleDetails(_vehicleController.text);
      _vehicleController.text = vehicleDetails;

      if (_profileId != null) {
        final riderName = '$firstName $lastName'.trim();
        await _profileService.updateEmployee(
          profileId: _profileId!,
          name: riderName,
          phone: normalizedPhone,
          vehicleDetails: vehicleDetails,
        );
      }

      _initialFirstName = firstName;
      _initialLastName = lastName;
      _initialPhone = normalizedPhone;
      _initialEmail = _emailController.text.trim().toLowerCase();
      _initialVehicle = vehicleDetails;
      _hasChanges = true;

      if (!mounted) return;
      setState(() => _isEditingPersonal = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Personal information updated successfully!',
                  style: GoogleFonts.lexend(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapErrorToMessage(error),
            style: GoogleFonts.lexend(color: Colors.white),
          ),
          backgroundColor: AppTheme.errorRed,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingPersonal = false);
      }
    }
  }

  void _cancelPersonalEdit() {
    _personalFormKey.currentState?.reset();
    _firstNameController.text = _initialFirstName;
    _lastNameController.text = _initialLastName;
    _phoneController.text = _initialPhone;
    _emailController.text = _initialEmail;
    _vehicleController.text = _initialVehicle;
    setState(() => _isEditingPersonal = false);
  }

  Future<bool> _showDiscardChangesDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Discard Changes?',
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          'You have unsaved changes in one of your sections. Are you sure you want to discard them and exit?',
          style: GoogleFonts.lexend(fontSize: 14, color: AppTheme.textDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Keep Editing',
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.w600,
                color: AppTheme.accentBlue,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorRed),
            child: Text(
              'Discard',
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.bold,
                color: AppTheme.errorRed,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _showDiscardChangesDialog();
        if (shouldPop && context.mounted) {
          Navigator.pop(context, _hasChanges);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: Text(
            'Account Details',
            style: GoogleFonts.lexend(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: AppTheme.textDark,
            ),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textDark,
              size: 20,
            ),
            onPressed: () async {
              if (_hasUnsavedChanges) {
                final shouldPop = await _showDiscardChangesDialog();
                if (shouldPop && context.mounted) {
                  Navigator.pop(context, _hasChanges);
                }
              } else {
                Navigator.pop(context, _hasChanges);
              }
            },
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.accentBlue,
                  strokeWidth: 2.5,
                ),
              )
            : SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderCard(),
                    const SizedBox(height: 20),
                    _buildSectionHeader(
                      icon: Icons.person_outline_rounded,
                      title: 'Personal Information',
                      action: _isEditingPersonal
                          ? null
                          : _buildEditButton(
                              onPressed: () =>
                                  setState(() => _isEditingPersonal = true),
                            ),
                    ),
                    const SizedBox(height: 8),
                    _buildPersonalInfoCard(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI HELPERS & COMPONENTS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEditButton({required VoidCallback onPressed}) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.edit_outlined, size: 15, color: AppTheme.accentBlue),
      label: Text(
        'Edit',
        style: GoogleFonts.lexend(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.accentBlue,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: AppTheme.accentBlue.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    String placeholder = 'Not set',
  }) {
    final hasValue = value.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.accentBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppTheme.accentBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textLight,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hasValue ? value : placeholder,
                style: GoogleFonts.lexend(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: hasValue
                      ? AppTheme.textDark
                      : AppTheme.textLight.withValues(alpha: 0.7),
                  fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCardActionButtons({
    required VoidCallback onCancel,
    required VoidCallback onSave,
    required bool isSaving,
    bool canSave = true,
    String saveLabel = 'Save',
  }) {
    const buttonHeight = 46.0;
    final borderRadius = BorderRadius.circular(12);

    return SizedBox(
      height: buttonHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: isSaving ? null : onCancel,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.softGray,
                foregroundColor: AppTheme.textDark,
                elevation: 0,
                shadowColor: Colors.transparent,
                side: BorderSide(
                  color: AppTheme.borderGray.withValues(alpha: 0.8),
                  width: 1,
                ),
                shape: RoundedRectangleBorder(borderRadius: borderRadius),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppTheme.textDark,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Cancel',
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: (isSaving || !canSave) ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                disabledBackgroundColor: Colors.grey.shade300,
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.grey.shade600,
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: borderRadius),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: canSave ? Colors.white : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          saveLabel,
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: canSave ? Colors.white : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final fullName =
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
            .trim();
    final displayName =
        fullName.isNotEmpty ? fullName : 'Delivery Rider';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          EditableProfileAvatar(
            avatarUrl: _avatarUrl,
            name: displayName,
            role: 'Rider',
            radius: 30,
            onAvatarChanged: (newUrl) {
              setState(() {
                _avatarUrl = newUrl;
                _hasChanges = true;
              });
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: GoogleFonts.lexend(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.two_wheeler_rounded,
                        size: 13,
                        color: AppTheme.accentBlue,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Verified Rider',
                          style: GoogleFonts.lexend(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accentBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.accentBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.lexend(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _buildPersonalInfoCard() {
    if (!_isEditingPersonal) {
      final fullName =
          '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
              .trim();

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(
              icon: Icons.person_outline_rounded,
              label: 'Full Name',
              value: fullName,
              placeholder: 'No name set',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(
                height: 1,
                color: AppTheme.borderGray.withValues(alpha: 0.4),
              ),
            ),
            _buildInfoRow(
              icon: Icons.phone_android_outlined,
              label: 'Mobile Number',
              value: _phoneController.text.trim(),
              placeholder: 'No phone number set',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(
                height: 1,
                color: AppTheme.borderGray.withValues(alpha: 0.4),
              ),
            ),
            _buildInfoRow(
              icon: Icons.email_outlined,
              label: 'Email Address',
              value: _emailController.text.trim(),
              placeholder: 'No email address set',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(
                height: 1,
                color: AppTheme.borderGray.withValues(alpha: 0.4),
              ),
            ),
            _buildInfoRow(
              icon: Icons.two_wheeler_outlined,
              label: 'Vehicle Details',
              value: _vehicleController.text.trim(),
              placeholder: 'No vehicle details specified',
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.accentBlue.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentBlue.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: _personalFormKey,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: CustomTextField(
                    label: 'First Name',
                    hint: 'First name',
                    prefixIcon: Icons.badge_outlined,
                    controller: _firstNameController,
                    inputFormatters: InputFormatters.name(),
                    validator: (v) => Validators.nameField(v, 'First name'),
                    maxLength: Validators.nameMax,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: CustomTextField(
                    label: 'Last Name',
                    hint: 'Last name',
                    prefixIcon: Icons.badge_outlined,
                    controller: _lastNameController,
                    inputFormatters: InputFormatters.name(),
                    validator: (v) => Validators.nameField(v, 'Last name'),
                    maxLength: Validators.nameMax,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Mobile Number',
              hint: '09XX-XXX-XXXX',
              prefixIcon: Icons.phone_android_outlined,
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: InputFormatters.phone(),
              validator: Validators.phone,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Email Address',
              hint: 'Email address',
              prefixIcon: Icons.email_outlined,
              controller: _emailController,
              enabled: false,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Vehicle Details',
              hint: 'e.g. Honda Wave 110 - ABC 1234',
              prefixIcon: Icons.two_wheeler_outlined,
              controller: _vehicleController,
              validator: Validators.vehicleDetails,
              inputFormatters: InputFormatters.vehicleDetails(),
              maxLength: Validators.vehicleDetailsMax,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            _buildCardActionButtons(
              onCancel: _cancelPersonalEdit,
              onSave: _savePersonalInfo,
              isSaving: _isSavingPersonal,
              canSave: _hasPersonalChanges,
            ),
          ],
        ),
      ),
    );
  }
}

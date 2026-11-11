import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../theme/app_theme.dart';
import '../../../../services/sound_service.dart';
import '../../../../widgets/top_notification.dart';

/// Staff notification preferences.
///
/// Styled to match the customer-facing option screens (soft gray canvas, white
/// cards, lexend typography) instead of the bare default widgets it used to
/// render.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _newOrder = true;
  bool _paymentAlerts = true;
  bool _soundAlerts = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final sound = await SoundService.instance.isSoundEnabled();
    if (mounted) {
      setState(() {
        _soundAlerts = sound;
        _isLoading = false;
      });
    }
  }

  Future<void> _testSound() async {
    await SoundService.instance.playNotificationSound(force: true);
    if (mounted) {
      showTopNotification(
        context,
        message: 'Playing default notification chime',
        icon: Icons.volume_up_rounded,
        backgroundColor: AppTheme.accentBlue,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softGray,
      appBar: AppBar(
        title: Text(
          'Notification Settings',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppTheme.textDark,
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.textDark,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 20),
                  _buildSwitchTile(
                    icon: Icons.volume_up_outlined,
                    title: 'Audible Sound Alert',
                    subtitle: 'Play an alert sound when a new service request arrives.',
                    value: _soundAlerts,
                    onChanged: (val) async {
                      setState(() => _soundAlerts = val);
                      await SoundService.instance.setSoundEnabled(val);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildTestSoundCard(),
                  const SizedBox(height: 12),
                  _buildSwitchTile(
                    icon: Icons.assignment_outlined,
                    title: 'New Order Requests',
                    subtitle: 'Receive alerts when a new laundry order request is submitted.',
                    value: _newOrder,
                    onChanged: (val) => setState(() => _newOrder = val),
                  ),
                  const SizedBox(height: 12),
                  _buildSwitchTile(
                    icon: Icons.payments_outlined,
                    title: 'Payment Alerts',
                    subtitle: 'Receive notifications for successful payments.',
                    value: _paymentAlerts,
                    onChanged: (val) => setState(() => _paymentAlerts = val),
                  ),
                  const SizedBox(height: 20),
                  _buildDeviceNote(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI COMPONENTS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTestSoundCard() {
    return InkWell(
      onTap: _testSound,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.accentBlue.withValues(alpha: 0.25),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.lightBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 20,
                color: AppTheme.accentBlue,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Test Notification Chime',
                style: GoogleFonts.lexend(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentBlue,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.accentBlue,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppStyles.cardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.lightBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.notifications_active_outlined,
              color: AppTheme.accentBlue,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stay in the Loop',
                  style: GoogleFonts.lexend(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose which updates reach you while you are on duty. '
                  'Your changes apply right away.',
                  style: GoogleFonts.lexend(
                    fontSize: 13,
                    color: AppTheme.textLight,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      // Tapping anywhere on the card toggles it; the switch handles its own
      // taps, so the two never fire together.
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: AppStyles.cardDecoration,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: value ? AppTheme.lightBlue : AppTheme.softGray,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 20,
                color: value ? AppTheme.accentBlue : AppTheme.textLight,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.lexend(
                      fontSize: 12,
                      color: AppTheme.textLight,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: AppTheme.accentBlue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceNote() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: AppTheme.textLight.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Delivery also depends on your device notification settings.',
            style: GoogleFonts.lexend(
              fontSize: 12,
              color: AppTheme.textLight,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/payment_service.dart';
import '../../theme/app_theme.dart';

/// Shared GCash payment flow for staff and customer screens.
///
/// Step 1: Shows the GCash QR image uploaded by the admin website
///         (falls back to account name/number when not configured).
/// Step 2: Capture or upload the payment receipt for the order.
///
/// Pops with the selected receipt [File], or null if cancelled.
/// The caller is responsible for recording the payment via
/// [PaymentService.submitGcashPayment].
class GcashQrPaymentScreen extends StatefulWidget {
  final String title;
  final String orderLabel;
  final double amount;
  final String? customerName;

  const GcashQrPaymentScreen({
    super.key,
    this.title = 'GCash Payment',
    required this.orderLabel,
    required this.amount,
    this.customerName,
  });

  @override
  State<GcashQrPaymentScreen> createState() => _GcashQrPaymentScreenState();
}

class _GcashQrPaymentScreenState extends State<GcashQrPaymentScreen> {
  final PaymentService _paymentService = PaymentService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoadingQr = true;
  GcashSettings _settings = GcashSettings.empty;
  File? _receiptFile;
  bool _isPickingImage = false;
  int _step = 1; // 1 = show QR, 2 = capture/upload receipt

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _paymentService.fetchGcashSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _isLoadingQr = false;
    });
  }

  Future<void> _pickImage({required ImageSource source}) async {
    if (_isPickingImage) return;
    setState(() => _isPickingImage = true);
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked != null) {
        setState(() => _receiptFile = File(picked.path));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not get the receipt photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  void _showReceiptSourceSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppTheme.accentBlue),
              title: const Text('Take Photo'),
              subtitle: const Text('Photograph the GCash receipt screen'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(source: ImageSource.camera);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppTheme.accentBlue),
              title: const Text('Upload from Gallery'),
              subtitle: const Text('Choose the GCash receipt screenshot'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(source: ImageSource.gallery);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: _step == 1 ? _buildQrStep() : _buildReceiptStep(),
    );
  }

  // ---------------------------------------------------------------------
  // Step 1: Show the admin-uploaded GCash QR
  // ---------------------------------------------------------------------
  Widget _buildQrStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAmountCard(),
          const SizedBox(height: 24),
          Text('Scan & Pay with GCash',
              style: AppTheme.lightTheme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _buildQrCard(),
          const SizedBox(height: 20),
          _buildGcashInstructions(),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _step = 2),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Next',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007DFE),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildAmountCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF007DFE),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF007DFE).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (widget.customerName != null &&
                  widget.customerName!.trim().isNotEmpty)
                Expanded(
                  child: Text(
                    widget.customerName!,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.orderLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Amount to Pay',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            '₱${widget.amount.toStringAsFixed(2)}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildQrCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGray),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _isLoadingQr
          ? const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            )
          : _settings.qrImageUrl != null
              ? Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        _settings.qrImageUrl!,
                        height: 240,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const SizedBox(
                            height: 240,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) =>
                            _buildQrUnavailable(
                                'QR image could not be loaded.'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Scan this QR using your GCash app',
                      style: TextStyle(fontSize: 12, color: AppTheme.textLight),
                    ),
                  ],
                )
              : _buildQrUnavailable(
                  'GCash QR is not configured yet. Pay using the account details below.'),
    );
  }

  Widget _buildQrUnavailable(String message) {
    return Column(
      children: [
        Container(
          height: 140,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code_2,
                  size: 48, color: Colors.orange.withValues(alpha: 0.7)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 12, color: AppTheme.textDark),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGcashInstructions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF007DFE).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF007DFE).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF007DFE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.account_balance_wallet,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'GCash Account Details',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF005AB5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Account Name:',
                  style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              Flexible(
                child: Text(
                  _settings.accountName ?? 'INFINITYWASH HUB',
                  textAlign: TextAlign.right,
                  style:
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('GCash Mobile Number:',
                  style: TextStyle(fontSize: 12, color: AppTheme.textLight)),
              Flexible(
                child: Text(
                  _settings.accountNumber ?? '0917-555-WASH (9274)',
                  textAlign: TextAlign.right,
                  style:
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Step 2: Capture or upload the payment receipt
  // ---------------------------------------------------------------------
  Widget _buildReceiptStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment Receipt',
              style: AppTheme.lightTheme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Take a photo or upload the GCash receipt for this payment. '
            'Our admin team will verify it against the GCash transaction history.',
            style: TextStyle(fontSize: 12, color: AppTheme.textLight),
          ),
          const SizedBox(height: 20),
          _buildReceiptPreview(),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _isPickingImage ? null : _showReceiptSourceSelector,
                  icon: _receiptFile == null
                      ? const Icon(Icons.add_a_photo, size: 18)
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(
                    _receiptFile == null
                        ? (_isPickingImage ? 'Opening camera...' : 'Capture / Upload')
                        : 'Change Receipt',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentBlue,
                    side: const BorderSide(color: AppTheme.accentBlue, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _receiptFile == null ? null : _saveReceipt,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Save Receipt',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => setState(() => _step = 1),
              child: const Text('Back to QR Code',
                  style: TextStyle(color: AppTheme.textLight)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildReceiptPreview() {
    if (_receiptFile == null) {
      return Container(
        height: 220,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.softGray,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppTheme.borderGray,
              style: BorderStyle.solid,
              width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long,
                size: 48, color: AppTheme.textLight.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            const Text(
              'No receipt added yet',
              style: TextStyle(fontSize: 13, color: AppTheme.textLight),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap "Capture / Upload" below',
              style: TextStyle(fontSize: 11, color: AppTheme.textLight),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: Image.file(
                _receiptFile!,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 16),
              const SizedBox(width: 6),
              const Text(
                'Receipt ready to upload',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.green),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _saveReceipt() {
    if (_receiptFile == null) return;
    Navigator.pop(context, _receiptFile);
  }
}

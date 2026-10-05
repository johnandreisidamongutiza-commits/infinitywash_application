import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  /// Height reserved for the QR image. Tall enough for a full GCash
  /// screenshot; the viewer below lets the user zoom in and out.
  static const double _qrImageHeight = 340;

  /// Minimum/maximum zoom applied to the QR image.
  static const double _minQrZoom = 1.0;
  static const double _maxQrZoom = 4.0;

  final TransformationController _qrTransformController =
      TransformationController();
  double _qrZoom = 1.0;

  bool _isLoadingQr = true;
  GcashSettings _settings = GcashSettings.empty;

  /// The QR is either a remote URL or, when the admin stored it inline,
  /// a base64 data URI. Image.network cannot load a data URI, so those
  /// are decoded once here and rendered with Image.memory.
  String? _qrImageUrl;
  Uint8List? _qrImageBytes;

  File? _receiptFile;
  bool _isPickingImage = false;
  int _step = 1; // 1 = show QR, 2 = capture/upload receipt

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _qrTransformController.dispose();
    super.dispose();
  }

  /// Zoom the QR image in or out. Clamped between [_minQrZoom] and [_maxQrZoom].
  void _zoomQr(double factor) {
    final next = (_qrZoom * factor).clamp(_minQrZoom, _maxQrZoom);
    _qrTransformController.value =
        Matrix4.identity()..scaleByDouble(next, next, next, 1);
    setState(() => _qrZoom = next);
  }

  /// Back to the "fit to screen" view.
  void _resetQrZoom() {
    _qrTransformController.value = Matrix4.identity();
    setState(() => _qrZoom = 1.0);
  }

  Future<void> _loadSettings() async {
    final settings = await _paymentService.fetchGcashSettings();
    if (!mounted) return;

    String? url;
    Uint8List? bytes;
    final raw = settings.qrImageUrl;
    if (raw != null) {
      final source = _resolveQrSource(raw);
      url = source.url;
      bytes = source.bytes;
    }

    setState(() {
      _settings = settings;
      _qrImageUrl = url;
      _qrImageBytes = bytes;
      _isLoadingQr = false;
    });
  }

  /// Splits a stored QR value into a network URL or decoded image bytes.
  static ({String? url, Uint8List? bytes}) _resolveQrSource(String raw) {
    if (!raw.startsWith('data:')) {
      return (url: raw, bytes: null);
    }

    final separator = raw.indexOf(',');
    if (separator == -1) {
      print('⚠️ Malformed GCash QR data URI (no comma separator)');
      return (url: null, bytes: null);
    }

    final meta = raw.substring(0, separator);
    final payload = raw.substring(separator + 1);
    try {
      if (meta.contains(';base64')) {
        return (url: null, bytes: base64Decode(payload));
      }
      return (url: Uri.dataFromString(raw).toString(), bytes: null);
    } catch (e) {
      print('❌ Could not decode the GCash QR data URI: $e');
      return (url: null, bytes: null);
    }
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
          content: Text('Could not take the receipt photo. Please try again.'),
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
              height: _qrImageHeight,
              child: Center(child: CircularProgressIndicator()),
            )
          : (_qrImageUrl != null || _qrImageBytes != null)
              ? Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildQrImage(),
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

  /// Renders the QR from decoded bytes (data URI) or from a remote URL.
  /// The admin may store a full GCash screenshot instead of a cropped QR,
  /// so the image is given room and can be pinched to zoom.
  Widget _buildQrImage() {
    final Widget image;
    final bytes = _qrImageBytes;

    if (bytes != null) {
      image = Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _buildQrUnavailable(
            'The stored GCash QR image could not be decoded.'),
      );
    } else {
      image = Image.network(
        _qrImageUrl!,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            height: _qrImageHeight,
            child: Center(child: CircularProgressIndicator()),
          );
        },
        errorBuilder: (context, error, stackTrace) => _buildQrUnavailable(
            'QR image could not be loaded. Please contact the admin to re-upload it.'),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InteractiveViewer(
          transformationController: _qrTransformController,
          minScale: _minQrZoom,
          maxScale: _maxQrZoom,
          // Panning only makes sense once zoomed in; below that the
          // page keeps its normal scroll behaviour.
          panEnabled: _qrZoom > 1,
          child: SizedBox(
            height: _qrImageHeight,
            width: double.infinity,
            child: image,
          ),
        ),
        const SizedBox(height: 10),
        _buildZoomControls(),
      ],
    );
  }

  /// Zoom out / reset / zoom in buttons plus a percentage readout.
  Widget _buildZoomControls() {
    final percent = (_qrZoom * 100).round();

    Widget button({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      return IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        color: AppTheme.accentBlue,
        disabledColor: AppTheme.textLight.withValues(alpha: 0.4),
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: AppTheme.softGray,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        button(
          icon: Icons.zoom_out,
          tooltip: 'Zoom out',
          onPressed: _qrZoom > _minQrZoom ? () => _zoomQr(1 / 1.4) : null,
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.softGray,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$percent%',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
        ),
        const SizedBox(width: 8),
        button(
          icon: Icons.zoom_in,
          tooltip: 'Zoom in',
          onPressed: _qrZoom < _maxQrZoom ? () => _zoomQr(1.4) : null,
        ),
        const SizedBox(width: 8),
        button(
          icon: Icons.fit_screen_outlined,
          tooltip: 'Reset zoom',
          onPressed: _qrZoom == _minQrZoom ? null : _resetQrZoom,
        ),
      ],
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

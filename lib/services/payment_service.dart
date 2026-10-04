import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'order_service.dart';

/// GCash configuration managed from the admin website, stored in the
/// singleton `gcash_settings` row (id = 1).
class GcashSettings {
  /// Public URL of the uploaded GCash QR image.
  final String? qrImageUrl;

  /// Account name shown to the payer (e.g. INFINITYWASH HUB).
  final String? accountName;

  /// GCash mobile number shown to the payer.
  final String? accountNumber;

  const GcashSettings({
    this.qrImageUrl,
    this.accountName,
    this.accountNumber,
  });

  /// Used when the row is missing or unreadable — screens fall back to
  /// the default account instructions.
  static const GcashSettings empty = GcashSettings();
}

/// GCash payment flow used by staff and customer screens.
///
/// Flow contract (matches the admin website's OCR pipeline):
///  * The admin uploads the GCash QR image and account details, which
///    the app reads from the `gcash_settings` table (singleton row).
///  * The app shows that QR, the user pays, then captures/uploads
///    the GCash receipt image.
///  * The receipt is stored in the 'payment-receipts' bucket and a
///    payments row is created with status 'pending' — that is the
///    "for review" state the admin website's OCR verification uses
///    (it extracts the reference number, matches it against the
///    daily transaction history, then marks it VERIFIED or rejects).
///  * The order itself is marked payment_status='paid' immediately
///    so the app reflects the payment right away.
class PaymentService {
  final SupabaseClient _client = Supabase.instance.client;
  final OrderService _orderService = OrderService();

  static const int _settingsRowId = 1;
  static const String _receiptBucket = 'payment-receipts';

  /// Reads the admin-managed GCash configuration from `gcash_settings`
  /// (singleton row, id = 1): the uploaded QR image URL plus the account
  /// name and number shown on the payment screens.
  /// Returns [GcashSettings.empty] when the row is missing or unreadable,
  /// so callers fall back to the default account instructions.
  Future<GcashSettings> fetchGcashSettings() async {
    try {
      final row = await _client
          .from('gcash_settings')
          .select('qr_image_url, account_name, account_number')
          .eq('id', _settingsRowId)
          .maybeSingle();

      if (row == null) {
        print('⚠️ gcash_settings row (id=1) not found');
        return GcashSettings.empty;
      }

      String? clean(dynamic value) {
        final trimmed = (value as String?)?.trim();
        return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
      }

      return GcashSettings(
        qrImageUrl: clean(row['qr_image_url']),
        accountName: clean(row['account_name']),
        accountNumber: clean(row['account_number']),
      );
    } catch (e) {
      print('❌ Could not load GCash settings from gcash_settings: $e');
      return GcashSettings.empty;
    }
  }

  /// Uploads the receipt, records the GCash payment with status
  /// 'pending' (for review on the admin website) and marks the order
  /// as paid. Returns the generated transaction number.
  Future<String> submitGcashPayment({
    required String orderId,
    required double amount,
    required File receiptFile,
    String? assignedStaffId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    // Step 1: Upload the receipt first — if this fails, no payment
    // row is written so nothing is left half-saved.
    final receiptUrl =
        await uploadReceipt(orderId: orderId, receiptFile: receiptFile);

    // Step 2: Transaction number (same generator as cash payments)
    final transactionNumber = await _orderService.generateTransactionNumber();

    // Step 3: Insert the payment with status 'pending' = for review
    final paymentData = <String, dynamic>{
      'transaction_number': transactionNumber,
      'order_id': orderId,
      'amount': amount,
      'payment_method': 'gcash',
      'status': 'pending',
      'receipt_url': receiptUrl,
      'paid_at': now,
      'created_at': now,
    };
    if (assignedStaffId != null) {
      paymentData['processed_by'] = assignedStaffId;
    }
    await _client.from('payments').insert(paymentData);

    // Step 4: Mark the order paid immediately (app-side "PAID")
    await _client.from('orders').update({
      'payment_status': 'paid',
      'payment_method': 'gcash',
      'paid_at': now,
      'updated_at': now,
    }).eq('id', orderId);

    print('✅ GCash payment recorded: $transactionNumber '
        '(order $orderId marked paid, pending admin verification)');
    return transactionNumber;
  }

  /// Upload a receipt image to the 'payment-receipts' bucket and
  /// return its public URL.
  Future<String> uploadReceipt({
    required String orderId,
    required File receiptFile,
  }) async {
    final bytes = await receiptFile.readAsBytes();
    final isPng = receiptFile.path.toLowerCase().endsWith('.png');
    final path =
        '$orderId/${DateTime.now().millisecondsSinceEpoch}.${isPng ? 'png' : 'jpg'}';

    await _client.storage.from(_receiptBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: isPng ? 'image/png' : 'image/jpeg',
            upsert: false,
          ),
        );

    final publicUrl = _client.storage.from(_receiptBucket).getPublicUrl(path);
    print('✅ Receipt uploaded: $path');
    return publicUrl;
  }
}

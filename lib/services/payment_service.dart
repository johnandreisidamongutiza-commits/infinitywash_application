import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../utils/app_error.dart';
import 'order_service.dart';
import 'photo_file_service.dart';

/// GCash configuration managed from the admin website, stored in the
/// singleton `gcash_settings` row (id = 1).
class GcashSettings {
  /// Public URL of the uploaded GCash QR image.
  final String? qrImageUrl;

  /// Account name shown to the payer (e.g. INFINITYWASH HUB).
  final String? accountName;

  /// GCash mobile number shown to the payer.
  final String? accountNumber;

  const GcashSettings({this.qrImageUrl, this.accountName, this.accountNumber});

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

  Future<String?> getLatestReceiptRejectionReason(String orderId) async {
    final row = await _client
        .from('gcash_receipt_submissions')
        .select('rejection_reason')
        .eq('order_id', orderId)
        .eq('status', 'rejected')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    final reason = (row['rejection_reason'] as String?)?.trim();
    return reason == null || reason.isEmpty
        ? 'Please contact support for more information.'
        : reason;
  }

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

  /// Generates a standard RFC 4122 v4 UUID string.
  static String _generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Uploads the receipt, records the GCash payment with status
  /// 'pending' (for review on the admin website), creates a submission in
  /// `gcash_receipt_submissions`, and marks the order as paid.
  /// Returns the generated transaction number.
  Future<String> submitGcashPayment({
    required String orderId,
    required double amount,
    required File receiptFile,
    String? assignedStaffId,
    String source = 'mobile_app',
  }) async {
    final receiptText = await _readReceiptText(receiptFile);
    final referenceNumber = _extractReferenceNumber(receiptText);
    final receiptDateTime = _extractReceiptDateTime(receiptText);
    if (referenceNumber == null || receiptDateTime == null) {
      throw const AppError(
        'This image must show a GCash reference number and transaction date/time. Please choose a clear receipt.',
        type: AppErrorType.validation,
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();

    // Step 1: Upload the receipt first — if this fails, no payment
    // row is written so nothing is left half-saved.
    final receiptUrl = await uploadReceipt(
      orderId: orderId,
      receiptFile: receiptFile,
    );

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

    String? paymentId;
    try {
      final paymentResponse = await _client
          .from('payments')
          .insert(paymentData)
          .select('id')
          .maybeSingle();
      paymentId = paymentResponse?['id'] as String?;
    } catch (_) {
      // Fallback in case select is restricted by RLS
      await _client.from('payments').insert(paymentData);
    }

    // Step 4: Record in gcash_receipt_submissions for admin OCR queue
    try {
      int? imageSizeBytes;
      try {
        imageSizeBytes = await receiptFile.length();
      } catch (_) {}

      // Fetch order_number to link on the submission row
      String? orderNumber;
      try {
        final orderRow = await _client
            .from('orders')
            .select('order_number')
            .eq('id', orderId)
            .maybeSingle();
        orderNumber = orderRow?['order_number'] as String?;
      } catch (_) {}

      // Fetch profile id of the current logged-in user
      String? submittedByProfileId;
      final currentAuthUser = _client.auth.currentUser;
      if (currentAuthUser != null) {
        try {
          final profileRow = await _client
              .from('profiles')
              .select('id')
              .eq('supabase_user_id', currentAuthUser.id)
              .maybeSingle();
          submittedByProfileId = profileRow?['id'] as String?;
        } catch (_) {}
      }

      final submissionId = _generateUuidV4();
      final submissionData = <String, dynamic>{
        'id': submissionId,
        'order_id': orderId,
        'order_number': orderNumber,
        'receipt_image_url': receiptUrl,
        'image_size_bytes': imageSizeBytes,
        'ocr_raw_text': receiptText,
        'ocr_reference_number': referenceNumber,
        'ocr_receipt_datetime': receiptDateTime,
        'ocr_amount': null,
        'ocr_success': true,
        'ocr_error': null,
        'match_status': 'no_match',
        'match_detail': null,
        'status': 'pending_review',
        'source': source,
        'submitted_by': submittedByProfileId,
        'payment_id': paymentId,
        'created_at': now,
      };

      await _client.from('gcash_receipt_submissions').insert(submissionData);
      print('✅ Receipt linked to gcash_receipt_submissions: $submissionId');
    } catch (e) {
      print('⚠️ Warning: Failed to insert into gcash_receipt_submissions: $e');
    }

    // Step 5: Mark the order paid immediately (app-side "PAID")
    await _client
        .from('orders')
        .update({
          'payment_status': 'paid',
          'payment_method': 'gcash',
          'paid_at': now,
          'updated_at': now,
        })
        .eq('id', orderId);

    print(
      '✅ GCash payment recorded: $transactionNumber '
      '(order $orderId marked paid, pending admin verification)',
    );
    await PhotoFileService.deleteTemporary(receiptFile);
    return transactionNumber;
  }

  Future<String> _readReceiptText(File image) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      return (await recognizer.processImage(InputImage.fromFile(image))).text
          .trim();
    } finally {
      await recognizer.close();
    }
  }

  String? _extractReferenceNumber(String text) {
    final lines = text.split(RegExp(r'[\r\n]+'));
    final labelPattern = RegExp(
      r'\b(?:reference|ref\.?)\s*(?:no\.?|number|#)?\s*[:#.-]?\s*(.*)$',
      caseSensitive: false,
    );
    final digitsPattern = RegExp(r'^\s*([0-9][0-9\s-]{7,30})');

    for (var i = 0; i < lines.length; i++) {
      final label = labelPattern.firstMatch(lines[i]);
      if (label == null) continue;
      var value = label.group(1) ?? '';
      if (value.trim().isEmpty && i + 1 < lines.length) value = lines[i + 1];
      final digits = digitsPattern
          .firstMatch(value)
          ?.group(1)
          ?.replaceAll(RegExp(r'\D'), '');
      if (digits != null && digits.length >= 8 && digits.length <= 24)
        return digits;
    }
    return null;
  }

  String? _extractReceiptDateTime(String text) {
    final date = RegExp(
      r'\b(?:\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}[/-]\d{1,2}[/-]\d{1,2}|(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2},?\s+\d{2,4})\b',
      caseSensitive: false,
    ).firstMatch(text);
    final time = RegExp(
      r'\b(?:0?[1-9]|1[0-2])[:. ]?[0-5]\d\s*(?:A\.?M\.?|P\.?M\.?)\b|\b(?:[01]?\d|2[0-3])[:.][0-5]\d\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (date == null || time == null) return null;
    return '${date.group(0)} ${time.group(0)}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Upload a receipt image to the 'payment-receipts' bucket and
  /// return its public URL. Throws a friendly [AppError] on failure.
  Future<String> uploadReceipt({
    required String orderId,
    required File receiptFile,
  }) async {
    if (await receiptFile.length() > PhotoFileService.maxBytes) {
      throw const AppError(
        'The receipt photo must be 10 MB or smaller. Please choose another photo.',
        type: AppErrorType.storage,
      );
    }
    Uint8List bytes;
    try {
      bytes = await receiptFile.readAsBytes();
    } catch (_) {
      throw const AppError(
        'The receipt photo could not be read. Please retake the photo and try again.',
        type: AppErrorType.storage,
      );
    }

    final isPng = receiptFile.path.toLowerCase().endsWith('.png');
    final path =
        '$orderId/${DateTime.now().millisecondsSinceEpoch}.${isPng ? 'png' : 'jpg'}';

    try {
      await _client.storage
          .from(_receiptBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: isPng ? 'image/png' : 'image/jpeg',
              upsert: false,
            ),
          );
    } on StorageException catch (e) {
      throw mapError(e, stackTrace: StackTrace.current);
    } catch (e) {
      throw AppError(
        'The receipt could not be uploaded. Please check your connection and try again.',
        type: AppErrorType.storage,
        originalError: e,
        stackTrace: StackTrace.current,
      );
    }

    final publicUrl = _client.storage.from(_receiptBucket).getPublicUrl(path);
    print('✅ Receipt uploaded: $path');
    return publicUrl;
  }
}

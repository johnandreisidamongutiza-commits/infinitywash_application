import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../utils/app_error.dart';
import 'supabase_service.dart';
import 'loyalty_service.dart';
import 'service_catalog_service.dart';

/// What [OrderService.completeOrder] should do given an order's current
/// status. See [CompleteOrderGuards.decideAction].
enum CompleteOrderAction { notFound, skip, completeAndAward }

/// Pure decision points for [OrderService.completeOrder], extracted for unit
/// testing without a Supabase backend.
@visibleForTesting
abstract final class CompleteOrderGuards {
  /// Decides what [OrderService.completeOrder] should do given the order's
  /// current DB status:
  /// - `notFound`        → order row missing, completeOrder throws.
  /// - `skip`            → already completed; idempotent no-op (no re-update,
  ///   no duplicate loyalty award).
  /// - `completeAndAward`→ transition to 'completed' + award loyalty points.
  static CompleteOrderAction decideAction(String? currentStatus) {
    if (currentStatus == null) return CompleteOrderAction.notFound;
    if (currentStatus == 'completed') return CompleteOrderAction.skip;
    return CompleteOrderAction.completeAndAward;
  }

  /// Loads-to-points mapping used for the award (minimum of 1 point).
  static int loyaltyPointsFor(int? loadsCount) => loadsCount == null || loadsCount < 1 ? 1 : loadsCount;
}

/// Holds accurate order counts for Today's Queue in staff dashboard.
class TodayQueueCounts {
  final int requests;
  final int processing;
  final int outForDelivery;
  final int completedToday;

  const TodayQueueCounts({
    this.requests = 0,
    this.processing = 0,
    this.outForDelivery = 0,
    this.completedToday = 0,
  });
}

class OrderService {
  final SupabaseClient _client = SupabaseService.client;
  final LoyaltyService _loyaltyService = LoyaltyService();
  final ServiceCatalogService _catalogService = ServiceCatalogService();

  /// Generate next sequential order number for today (ORD-YYMMDD-001, up to 999/day)
  Future<String> generateOrderNumber() async {
    try {
      final now = DateTime.now();
      final yy = (now.year % 100).toString().padLeft(2, '0');
      final mm = now.month.toString().padLeft(2, '0');
      final dd = now.day.toString().padLeft(2, '0');
      final dateStr = '$yy$mm$dd';
      
      // Query for orders created today with this date prefix
      final prefix = 'ORD-$dateStr-';
      
      final response = await _client
          .from('orders')
          .select('order_number')
          .like('order_number', '$prefix%')
          .order('order_number', ascending: false)
          .limit(1);

      if (response.isEmpty) {
        // No orders today, start with 001
        return '${prefix}001';
      }

      // Extract the sequence number from the last order
      final lastOrderNumber = response.first['order_number'] as String;
      final sequencePart = lastOrderNumber.replaceAll(prefix, '');
      final lastSequence = int.tryParse(sequencePart) ?? 0;

      // Increment and format with leading zeros.
      // NOTE: still race-prone if two staff create orders at the exact same
      // moment — callers must catch the unique-violation on insert and retry
      // with the next sequence (see createOrder's collision retry).
      final nextSequence = lastSequence + 1;
      return '$prefix${nextSequence.toString().padLeft(3, '0')}';
    } catch (e) {
      print('Error generating order number: $e');
      // Fallback to timestamp-based if query fails
      final now = DateTime.now();
      final yy = (now.year % 100).toString().padLeft(2, '0');
      final mm = now.month.toString().padLeft(2, '0');
      final dd = now.day.toString().padLeft(2, '0');
      final dateStr = '$yy$mm$dd';
      return 'ORD-$dateStr-${(now.millisecondsSinceEpoch % 1000).toString().padLeft(3, '0')}';
    }
  }

  /// Generate transaction number for payments (PAY-YYYYMMDD-00001)
  Future<String> generateTransactionNumber() async {
    try {
      final now = DateTime.now();
      final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final prefix = 'PAY-$dateStr-';
      
      final response = await _client
          .from('payments')
          .select('transaction_number')
          .like('transaction_number', '$prefix%')
          .order('transaction_number', ascending: false)
          .limit(1);

      if (response.isEmpty) {
        return '${prefix}00001';
      }

      final lastTxnNumber = response.first['transaction_number'] as String;
      final sequencePart = lastTxnNumber.replaceAll(prefix, '');
      final lastSequence = int.tryParse(sequencePart) ?? 0;
      final nextSequence = lastSequence + 1;
      
      return '$prefix${nextSequence.toString().padLeft(5, '0')}';
    } catch (e) {
      print('Error generating transaction number: $e');
      final now = DateTime.now();
      final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      return 'PAY-$dateStr-${now.millisecondsSinceEpoch.toString().substring(8)}';
    }
  }

  /// Create a complete order with loads, addons, and optional payment
  /// Returns the created order ID
  Future<String> createOrder({
    required String customerId,
    required String orderNumber,
    required String serviceId,
    required String serviceName,
    required List<OrderLoad> loads,
    required double subtotal,
    required double totalAmount,
    String? assignedStaffId,
    bool pickupRequested = false,
    bool deliveryRequested = false,
    String? deliveryAddress,
    String? deliveryLandmark,
    String? customerNotes,
    String? staffNotes,
    String? rfidTag,
    List<Map<String, dynamic>> addons = const [],
    bool isPaid = false,
    String? paymentMethod,
  }) async {
    try {
      // Validations
      if (customerId.isEmpty) {
        throw const AppError(
          'A customer must be selected before creating the order.',
          type: AppErrorType.validation,
        );
      }
      if (orderNumber.isEmpty) {
        throw const AppError(
          'Order number could not be generated. Please try again.',
          type: AppErrorType.validation,
        );
      }
      // Allow empty loads for rider pickup orders (will be added after pickup)
      if (loads.isEmpty && !pickupRequested) {
        throw const AppError(
          'Add at least one load before creating the order.',
          type: AppErrorType.validation,
        );
      }
      if (subtotal < 0 || totalAmount < 0) {
        throw const AppError(
          'Order amounts cannot be negative. Please review the prices.',
          type: AppErrorType.validation,
        );
      }
      if (deliveryRequested && (deliveryAddress == null || deliveryAddress.isEmpty)) {
        throw const AppError(
          'A delivery address is required for delivery orders.',
          type: AppErrorType.validation,
        );
      }

      final now = DateTime.now().toUtc().toIso8601String();

      // Calculate totals
      final totalWeight = loads.fold(0.0, (sum, load) => sum + load.weight);
      final loadsCount = loads.length;

      // Determine initial status based on pickup/delivery requirements
      String initialStatus;
      String? receivedAtTime;
      String? processingAtTime;

      if (pickupRequested) {
        // If pickup is requested, order starts as pending_pickup
        initialStatus = 'pending_pickup';
        receivedAtTime = null; // Not received yet
        processingAtTime = null; // Not processing yet
      } else {
        // Walk-in drop-off orders start as processing immediately
        initialStatus = 'processing';
        receivedAtTime = now;
        processingAtTime = now;
      }

      print('📦 Creating order: $orderNumber');
      print('   Customer: $customerId');
      print('   Loads: $loadsCount (${totalWeight}kg)');
      print('   Total: ₱$totalAmount');
      print('   Pickup requested: $pickupRequested');
      print('   Delivery requested: $deliveryRequested');
      print('   Initial status: $initialStatus');

      // Step 1: Insert order
      final orderData = {
        'order_number': orderNumber,
        'customer_id': customerId,
        'source': 'walk_in',
        'service_id': serviceId,
        'service_name': serviceName,
        'weight_kg': totalWeight,
        'loads_count': loadsCount,
        'customer_notes': customerNotes,
        'staff_notes': staffNotes,
        'pickup_requested': pickupRequested,
        'delivery_requested': deliveryRequested,
        'pickup_address': pickupRequested ? deliveryAddress : null, // Use same address for pickup
        'delivery_address': deliveryAddress,
        'landmark': deliveryLandmark,
        'subtotal': subtotal,
        'delivery_fee': 0.0, // Always free delivery
        'total_amount': totalAmount,
        'payment_status': isPaid ? 'paid' : 'pending',
        'status': initialStatus, // Use computed status
        'received_at': receivedAtTime,
        'processing_at': processingAtTime,
        'created_at': now,
        'updated_at': now,
      };

      // Only add assigned_staff_id if we have a valid staff ID
      if (assignedStaffId != null) {
        orderData['assigned_staff_id'] = assignedStaffId;
      }

      // Insert the order, retrying with the next sequence if another
      // concurrent order took the same order_number (unique constraint).
      Object? orderResponse;
      var attempt = 0;
      var workingOrderNumber = orderNumber;
      const maxAttempts = 5;
      while (true) {
        try {
          orderData['order_number'] = workingOrderNumber;
          orderResponse = await _client
              .from('orders')
              .insert(orderData)
              .select('id')
              .single();
          break;
        } catch (e) {
          final isUniqueViolation = e.toString().contains('duplicate key') ||
              e.toString().contains('orders_order_number_key');
          attempt++;
          if (!isUniqueViolation || attempt >= maxAttempts) rethrow;

          // Bump the trailing sequence and retry.
          final match = RegExp(r'(\d+)$').firstMatch(workingOrderNumber);
          final nextSeq = (int.tryParse(match?.group(1) ?? '0') ?? 0) + 1;
          workingOrderNumber =
              workingOrderNumber.replaceRange(match!.start, workingOrderNumber.length, nextSeq.toString().padLeft(3, '0'));
          print('⚠️ Order number collision, retrying as $workingOrderNumber (attempt $attempt)');
        }
      }

      final orderId = (orderResponse as Map<String, dynamic>)['id'] as String;
      print('✅ Order created: $orderId');

      // Step 2: Insert order loads
      final loadsData = loads.map((load) {
        final loadJson = load.toJson();
        loadJson['order_id'] = orderId;
        loadJson['created_at'] = now;
        loadJson['updated_at'] = now;
        return loadJson;
      }).toList();

      await _client.from('order_loads').insert(loadsData);
      print('✅ Created ${loads.length} loads');

      // Step 3: Insert order addons (if any)
      if (addons.isNotEmpty) {
        print('🔄 Processing ${addons.length} add-ons...');
        final addonsData = <Map<String, dynamic>>[];

        // Resolve all addon codes in ONE cached catalog call
        // (replaces one DB query per addon).
        final addonCodes = addons
            .map((addon) => addon['addon_code'] as String)
            .toList();
        final resolvedAddons =
            await _catalogService.resolveAddonsByCode(addonCodes);

        for (final addon in addons) {
          final addonCode = addon['addon_code'] as String;
          final serviceAddon = resolvedAddons[addonCode];

          if (serviceAddon == null) {
            print('⚠️ Add-on not found: $addonCode');
            continue;
          }

          // Safely handle null price
          final priceValue = serviceAddon['price'];
          if (priceValue == null) {
            print('⚠️ Add-on has null price: $addonCode, skipping');
            continue;
          }

          final quantity = (addon['quantity'] ?? 1) as num;
          final unitPrice = (priceValue as num).toDouble();

          addonsData.add({
            'order_id': orderId,
            'addon_id': serviceAddon['id'],
            'addon_name': serviceAddon['addon_name'],
            'quantity': quantity,
            'unit_price': unitPrice,
            'line_total': quantity.toDouble() * unitPrice,
            'created_at': now,
          });
        }

        if (addonsData.isNotEmpty) {
          await _client.from('order_addons').insert(addonsData);
          print('✅ Created ${addonsData.length} addons');
        }
      }

      // Step 4: Create payment record (if paid immediately)
      if (isPaid && paymentMethod != null) {
        final transactionNumber = await generateTransactionNumber();
        
        final paymentData = {
          'transaction_number': transactionNumber,
          'order_id': orderId,
          'amount': totalAmount,
          'payment_method': paymentMethod.toLowerCase(),
          'status': 'paid',
          'paid_at': now,
          'created_at': now,
        };

        // Only add processed_by if we have a valid staff ID
        if (assignedStaffId != null) {
          paymentData['processed_by'] = assignedStaffId;
          print('✅ Payment processed by staff: $assignedStaffId');
        } else {
          print('⚠️ No staff ID available, creating payment without processed_by');
        }

        print('📦 Payment data being inserted: $paymentData');
        await _client.from('payments').insert(paymentData);
        print('✅ Payment recorded: $transactionNumber ($paymentMethod)');
      }

      print('🎉 Order creation complete: $orderNumber');

      // Create dispatch jobs if pickup/delivery requested
      if (pickupRequested || deliveryRequested) {
        await _createDispatchJobsForOrder(
          orderId: orderId,
          pickupRequested: pickupRequested,
          deliveryRequested: deliveryRequested,
          address: deliveryAddress ?? '',
          landmark: deliveryLandmark,
        );
      }

      return orderId;
    } catch (e) {
      print('❌ Error creating order: $e');
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  /// Create dispatch jobs for walk-in orders
  Future<void> _createDispatchJobsForOrder({
    required String orderId,
    required bool pickupRequested,
    required bool deliveryRequested,
    required String address,
    String? landmark,
  }) async {
    try {
      if (!pickupRequested && !deliveryRequested) {
        return; // No dispatch needed
      }

      if (address.isEmpty) {
        print('⚠️ Cannot create dispatch job: No address provided');
        return;
      }

      print('🔄 Creating dispatch jobs for walk-in order: $orderId');

      // Fetch order with customer info to get customer name & coordinates
      final orderResponse = await _client
          .from('orders')
          .select('''
            *,
            customers!inner(first_name, last_name)
          ''')
          .eq('id', orderId)
          .single();

      // Extract customer name
      final customerData = orderResponse['customers'] as Map<String, dynamic>?;
      final firstName = customerData?['first_name'] as String? ?? '';
      final lastName = customerData?['last_name'] as String? ?? '';
      final customerName = lastName.isNotEmpty 
          ? '$firstName $lastName'.trim()
          : firstName.isNotEmpty 
              ? firstName 
              : 'Unknown Customer';

      // Use order/customer pinned coordinates. No fake fallback — jobs
      // without a pin are created with null coordinates and riders see the
      // address with a "no pin" notice instead of a wrong map point.
      final pinLat = (orderResponse['delivery_latitude'] as num?)?.toDouble() ??
          (orderResponse['pickup_latitude'] as num?)?.toDouble() ??
          (customerData?['pin_latitude'] as num?)?.toDouble();
      final pinLng = (orderResponse['delivery_longitude'] as num?)?.toDouble() ??
          (orderResponse['pickup_longitude'] as num?)?.toDouble() ??
          (customerData?['pin_longitude'] as num?)?.toDouble();

      if (pinLat != null && pinLng != null) {
        print('✅ Using pinned coordinates: ($pinLat, $pinLng)');
      } else {
        print('⚠️ No pin for order $orderId — creating job without coordinates');
      }

      // Create unassigned dispatch jobs
      final supabaseService = SupabaseService();

      if (pickupRequested) {
        await supabaseService.createDispatchJob(
          orderId: orderId,
          riderId: null, // NULL for unassigned
          jobType: 'pickup',
          latitude: pinLat,
          longitude: pinLng,
          address: address,
          landmark: landmark,
          customerName: customerName, // Pass customer name
          notes: 'Pickup laundry from customer',
        );
        print('✅ Created pickup dispatch job');
      }

      // Note: Delivery job will be created when order status changes to 'ready'
      // This ensures riders only see delivery jobs when laundry is actually ready
    } catch (e) {
      print('❌ Error creating dispatch jobs: $e');
      // Don't rethrow - order creation should succeed even if dispatch fails
    }
  }

  /// Weigh, categorize, and check in an accepted app request that already exists.
  Future<void> checkInExistingOrder({
    required String orderId,
    required List<OrderLoad> loads,
    required double subtotal,
    required double totalAmount,
    String? loyaltyCardUid,   // Optional — customer may present their loyalty card
    List<Map<String, dynamic>> addons = const [],
    String? staffNotes,
    String? assignedStaffId,
  }) async {
    try {
      if (loads.isEmpty) {
        throw const AppError(
          'Add at least one load before checking in.',
          type: AppErrorType.validation,
        );
      }

      final existingLoads = await _client
          .from('order_loads')
          .select('id')
          .eq('order_id', orderId);

      if (existingLoads.isNotEmpty) {
        throw const AppError(
          'This order has already been checked in.',
          type: AppErrorType.validation,
        );
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final totalWeight = loads.fold(0.0, (sum, load) => sum + load.weight);

      final loadsData = loads.map((load) {
        final loadJson = load.toJson();
        loadJson['order_id'] = orderId;
        loadJson['created_at'] = now;
        loadJson['updated_at'] = now;
        return loadJson;
      }).toList();

      await _client.from('order_loads').insert(loadsData);

      if (addons.isNotEmpty) {
        print('🔄 Processing ${addons.length} add-ons...');
        final addonsData = <Map<String, dynamic>>[];

        // Resolve all addon codes in ONE cached catalog call
        // (replaces one DB query per addon).
        final addonCodes = addons
            .map((addon) => addon['addon_code'] as String)
            .toList();
        final resolvedAddons =
            await _catalogService.resolveAddonsByCode(addonCodes);

        for (final addon in addons) {
          final addonCode = addon['addon_code'] as String;
          final serviceAddon = resolvedAddons[addonCode];

          if (serviceAddon == null) {
            print('⚠️ Add-on not found: $addonCode');
            continue;
          }

          // Safely handle null price
          final priceValue = serviceAddon['price'];
          if (priceValue == null) {
            print('⚠️ Add-on has null price: $addonCode, skipping');
            continue;
          }

          final quantity = (addon['quantity'] ?? 1) as num;
          final unitPrice = (priceValue as num).toDouble();

          addonsData.add({
            'order_id': orderId,
            'addon_id': serviceAddon['id'],
            'addon_name': serviceAddon['addon_name'],
            'quantity': quantity,
            'unit_price': unitPrice,
            'line_total': quantity.toDouble() * unitPrice,
            'created_at': now,
          });
        }

        if (addonsData.isNotEmpty) {
          await _client.from('order_addons').insert(addonsData);
          print('✅ Created ${addonsData.length} addons');
        }
      }

      final updates = <String, dynamic>{
        'weight_kg': totalWeight,
        'loads_count': loads.length,
        'subtotal': subtotal,
        'total_amount': totalAmount,
        'status': 'processing',
        'received_at': now,
        'processing_at': now,
        'updated_at': now,
      };

      if (staffNotes != null && staffNotes.trim().isNotEmpty) {
        updates['staff_notes'] = staffNotes.trim();
      }
      if (assignedStaffId != null) {
        updates['assigned_staff_id'] = assignedStaffId;
      }

      await _client.from('orders').update(updates).eq('id', orderId);
      print('✅ Checked in order $orderId with ${loads.length} loads${loyaltyCardUid != null ? ' and Loyalty Card $loyaltyCardUid' : ''}');
    } catch (e) {
      print('❌ Error checking in order: $e');
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  /// Get accurate queue counts for the staff dashboard Today's Queue.
  Future<TodayQueueCounts> getTodayQueueCounts() async {
    try {
      final now = DateTime.now();
      final todayMidnightLocal = DateTime(now.year, now.month, now.day);
      final todayMidnightUtcString =
          todayMidnightLocal.toUtc().toIso8601String();

      final results = await Future.wait([
        // 0: Requests awaiting review (status: pending_approval)
        _client
            .from('orders')
            .select('id')
            .eq('status', 'pending_approval'),
        // 1: Processing orders (in-shop pipeline: pending_pickup, processing, ready)
        _client
            .from('orders')
            .select('id')
            .inFilter('status', ['pending_pickup', 'processing', 'ready']),
        // 2: Out for delivery orders
        _client
            .from('orders')
            .select('id')
            .eq('status', 'out_for_delivery'),
        // 3: Completed orders today
        _client
            .from('orders')
            .select('id, completed_at, updated_at')
            .eq('status', 'completed')
            .or('completed_at.gte.$todayMidnightUtcString,updated_at.gte.$todayMidnightUtcString'),
      ]);

      final requestsCount = (results[0] as List).length;
      final processingCount = (results[1] as List).length;
      final outForDeliveryCount = (results[2] as List).length;

      final completedRows = results[3] as List;
      final completedTodayCount = completedRows.where((row) {
        final completedAtStr = row['completed_at'] as String?;
        final updatedAtStr = row['updated_at'] as String?;
        final dateStr = completedAtStr ?? updatedAtStr;
        if (dateStr == null) return false;
        final date = DateTime.tryParse(dateStr)?.toLocal();
        if (date == null) return false;
        return date.isAfter(todayMidnightLocal) ||
            date.isAtSameMomentAs(todayMidnightLocal);
      }).length;

      print(
          '📊 TodayQueueCounts: requests=$requestsCount, processing=$processingCount, outForDelivery=$outForDeliveryCount, completedToday=$completedTodayCount');

      return TodayQueueCounts(
        requests: requestsCount,
        processing: processingCount,
        outForDelivery: outForDeliveryCount,
        completedToday: completedTodayCount,
      );
    } catch (e) {
      print('❌ Error fetching today queue counts: $e');
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  /// Fetch orders with optional status filter and pagination offset.
  /// Use [offset] + [limit] to implement cursor-style pagination:
  ///   page 0 → offset=0, page 1 → offset=limit, etc.
  Future<List<LaundryOrder>> fetchOrders({
    List<String>? statuses,
    String? assignedStaffId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      print('📊 fetchOrders called: statuses=$statuses, limit=$limit, offset=$offset');
      
      // Build base query with customer information and RFID tags
      // Use explicit column selection to avoid id collision between orders and order_loads
      var query = _client
          .from('orders')
          .select('''
            id,
            order_number,
            customer_id,
            source,
            service_id,
            service_name,
            weight_kg,
            loads_count,
            customer_notes,
            staff_notes,
            assigned_staff_id,
            assigned_rider_id,
            pickup_requested,
            delivery_requested,
            pickup_address,
            delivery_address,
            landmark,
            subtotal,
            delivery_fee,
            total_amount,
            payment_status,
            status,
            received_at,
            processing_at,
            ready_at,
            out_for_delivery_at,
            completed_at,
            created_at,
            updated_at,
            laundry_photo_urls,
            customer_description,
            estimated_loads,
            rejection_reason,
            reviewed_at,
            reviewed_by,
            expires_at,
            order_loads(*),
            customers(first_name, last_name, customer_code, phone, address, landmark)
          ''');

      // Apply status filter if provided
      if (statuses != null && statuses.isNotEmpty) {
        query = query.inFilter('status', statuses);
      }

      // Apply staff filter if provided
      if (assignedStaffId != null) {
        query = query.eq('assigned_staff_id', assignedStaffId);
      }

      // Apply ordering and range (for pagination), then execute.
      // range(from, to) is inclusive on both ends.
      print('📊 Executing query with range($offset, ${offset + limit - 1})');
      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      print('📊 Query returned ${response.length} orders');

      // Convert to LaundryOrder objects
      final orders = <LaundryOrder>[];
      
      for (var orderData in response) {
        // Parse loads
        final loadsData = orderData['order_loads'] as List?;
        final loads = loadsData?.map((loadJson) {
          return OrderLoad.fromJson(loadJson as Map<String, dynamic>);
        }).toList() ?? [];

        // Create order (will load from database fields)
        final order = LaundryOrder.fromJson(orderData);
        
        // Extract customer information from joined data
        final customerData = orderData['customers'] as Map<String, dynamic>?;
        final firstName = customerData?['first_name'] as String? ?? '';
        final lastName = customerData?['last_name'] as String? ?? '';
        final customerName = lastName.isNotEmpty ? '$firstName $lastName' : firstName.isNotEmpty ? firstName : 'Unknown';
        final customerPhone = customerData?['phone'] as String?;
        
        // Since fromJson doesn't handle loads (they come from join), we need to create new order with loads
        final orderWithLoads = LaundryOrder(
          id: order.id,
          orderNumber: orderData['order_number'] as String?, // Add order number
          customerName: customerName.isNotEmpty && customerName != 'Unknown' ? customerName : order.customerName, // Prefer customer name from joined data
          customerPhone: customerPhone?.isNotEmpty == true ? customerPhone : order.customerPhone, // Prefer customer phone from joined data
          deliveryAddress: order.deliveryAddress ?? (customerData?['address'] as String?),
          deliveryLandmark: order.deliveryLandmark ?? (customerData?['landmark'] as String?),
          channel: order.channel,
          collectionMethod: order.collectionMethod,
          returnMethod: order.returnMethod,
          status: order.status,
          paymentStatus: order.paymentStatus,
          loads: loads,
          instructions: order.instructions,
          rfidTag: null, // Loyalty cards are permanent per-customer, not per-order
          createdAt: order.createdAt,
          processingAt: order.processingAt, // Include processing timestamp
          paymentMethod: order.paymentMethod,
          paidAt: order.paidAt,
          laundryPhotoUrls: order.laundryPhotoUrls,
          customerDescription: order.customerDescription,
          estimatedLoads: order.estimatedLoads,
          rejectionReason: order.rejectionReason,
          staffMessage: order.staffMessage ?? (orderData['staff_notes'] as String?),
          reviewedAt: order.reviewedAt,
          reviewedBy: order.reviewedBy,
          expiresAt: order.expiresAt,
          underReviewBy: null,
          totalAmount: order.totalAmount ?? (orderData['total_amount'] as num?)?.toDouble(),
        );

        orders.add(orderWithLoads);
      }

      print('✅ Fetched ${orders.length} orders');
      return orders;
    } catch (e) {
      print('❌ Error fetching orders: $e');
      rethrow;
    }
  }

  /// Record a payment for an order and update order payment_status to 'paid'
  Future<String> recordPayment({
    required String orderId,
    required double amount,
    required String paymentMethod,
    String? assignedStaffId,
  }) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final transactionNumber = await generateTransactionNumber();

      final paymentData = {
        'transaction_number': transactionNumber,
        'order_id': orderId,
        'amount': amount,
        'payment_method': paymentMethod.toLowerCase(),
        'status': 'paid',
        'paid_at': now,
        'created_at': now,
      };

      if (assignedStaffId != null) {
        paymentData['processed_by'] = assignedStaffId;
      }

      print('📦 Recording payment: $paymentData');
      await _client.from('payments').insert(paymentData);

      // Update orders table — mirror payment_method and paid_at so both the
      // payments row and the orders row stay in sync (the GCash flow in
      // PaymentService already does this).
      await _client.from('orders').update({
        'payment_status': 'paid',
        'payment_method': paymentMethod.toLowerCase(),
        'paid_at': now,
        'updated_at': now,
      }).eq('id', orderId);

      print('✅ Payment successfully recorded for order $orderId: $transactionNumber ($paymentMethod)');
      return transactionNumber;
    } catch (e) {
      print('❌ Error recording payment: $e');
      rethrow;
    }
  }

  /// Update order status
  Future<void> updateOrderStatus(String orderId, String status) async {
    try {
      final updates = {
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Add timestamp fields based on status
      switch (status) {
        case 'processing':
          updates['processing_at'] = DateTime.now().toUtc().toIso8601String();
          break;
        case 'ready':
          print('🔍 DEBUG: Order status changing to READY, will create delivery job...');
          updates['ready_at'] = DateTime.now().toUtc().toIso8601String();
          // Create delivery dispatch job when order is ready
          await _createDeliveryJobIfNeeded(orderId);
          break;
        case 'out_for_delivery':
          updates['out_for_delivery_at'] = DateTime.now().toUtc().toIso8601String();
          break;
        case 'completed':
          // Delegate to the shared, idempotent completion path (row update +
          // loyalty award). Return early — completeOrder already wrote the row.
          await completeOrder(orderId);
          return;
        case 'cancelled':
          break;
      }

      await _client
          .from('orders')
          .update(updates)
          .eq('id', orderId);

      print('✅ Updated order $orderId status to: $status');
    } catch (e) {
      print('❌ Error updating order status: $e');
      rethrow;
    }
  }

  /// Complete an order (status='completed' + loyalty points) from ANY path.
  ///
  /// Previously loyalty points were only awarded when staff completed the
  /// order via [updateOrderStatus]; rider-completed deliveries went through
  /// SupabaseService.syncOrderStatus() and silently skipped the award. Both
  /// paths now funnel through this method so points are never lost.
  ///
  /// Idempotent: safe to call twice for the same order — the award only runs
  /// when the order actually transitions into 'completed'.
  Future<void> completeOrder(String orderId) async {
    final now = DateTime.now().toUtc().toIso8601String();

    // Only proceed if the order is not already completed (idempotency guard).
    final current = await _client
        .from('orders')
        .select('status')
        .eq('id', orderId)
        .maybeSingle();
    switch (CompleteOrderGuards.decideAction(current?['status'] as String?)) {
      case CompleteOrderAction.notFound:
        throw AppError(
          'We could not find that order. It may have been removed.',
          type: AppErrorType.notFound,
        );
      case CompleteOrderAction.skip:
        print('ℹ️ Order $orderId already completed — skipping duplicate completion');
        return;
      case CompleteOrderAction.completeAndAward:
        break;
    }

    await _client.from('orders').update({
      'status': 'completed',
      'completed_at': now,
      'updated_at': now,
    }).eq('id', orderId);

    print('✅ Order $orderId completed');

    // Award loyalty points if linked to a loyalty card. Failures are logged
    // but do not fail the completion (matches previous behavior).
    await _awardLoyaltyPointsForOrder(orderId);
  }

  /// Create delivery dispatch job when order becomes ready
  Future<void> _createDeliveryJobIfNeeded(String orderId) async {
    try {
      print('🔍 DEBUG: _createDeliveryJobIfNeeded called for order: $orderId');
      
      // Fetch order to check if delivery is requested
      print('🔍 DEBUG: Fetching order data...');
      final orderResponse = await _client
          .from('orders')
          .select('''
            *,
            customers!inner(first_name, last_name, address, landmark)
          ''')
          .eq('id', orderId)
          .single();

      print('🔍 DEBUG: Order fetched successfully');
      print('🔍 DEBUG: Order data: ${orderResponse.toString()}');

      final deliveryRequested = orderResponse['delivery_requested'] as bool? ?? false;
      print('🔍 DEBUG: delivery_requested = $deliveryRequested');
      
      if (!deliveryRequested) {
        print('ℹ️ Delivery not requested for order $orderId, skipping delivery job creation');
        return;
      }

      print('🔍 DEBUG: Checking for existing delivery job...');
      // Check if delivery job already exists (avoid duplicates)
      final existingJob = await _client
          .from('dispatch_jobs')
          .select('id')
          .eq('order_id', orderId)
          .eq('job_type', 'delivery')
          .maybeSingle();

      print('🔍 DEBUG: Existing job query result: ${existingJob?.toString() ?? "null (no existing job)"}');

      if (existingJob != null) {
        print('ℹ️ Delivery job already exists for order $orderId');
        return;
      }

      print('🔍 DEBUG: Extracting address data...');
      // Get address
      final deliveryAddress = orderResponse['delivery_address'] as String?;
      final pickupAddress = orderResponse['pickup_address'] as String?;
      final customerData = orderResponse['customers'] as Map<String, dynamic>?;
      final customerAddress = customerData?['address'] as String?;
      final landmark = orderResponse['landmark'] as String? ?? customerData?['landmark'] as String?;
      
      print('🔍 DEBUG: deliveryAddress = $deliveryAddress');
      print('🔍 DEBUG: pickupAddress = $pickupAddress');
      print('🔍 DEBUG: customerAddress = $customerAddress');
      print('🔍 DEBUG: landmark = $landmark');
      
      final finalAddress = deliveryAddress ?? pickupAddress ?? customerAddress ?? '';
      print('🔍 DEBUG: finalAddress = "$finalAddress"');
      
      if (finalAddress.isEmpty) {
        print('⚠️ Cannot create delivery job: No address for order $orderId');
        return;
      }

      print('🔍 DEBUG: Extracting customer name...');
      // Extract customer name
      final firstName = customerData?['first_name'] as String? ?? '';
      final lastName = customerData?['last_name'] as String? ?? '';
      final customerName = lastName.isNotEmpty 
          ? '$firstName $lastName'.trim()
          : firstName.isNotEmpty 
              ? firstName 
              : 'Unknown Customer';
      
      print('🔍 DEBUG: customerName = "$customerName"');

      // Use order/customer pinned coordinates. No fake fallback — riders see
      // the address with a "no pin" notice instead of a wrong map point.
      final pinLat = (orderResponse['delivery_latitude'] as num?)?.toDouble() ??
          (orderResponse['pickup_latitude'] as num?)?.toDouble() ??
          (customerData?['pin_latitude'] as num?)?.toDouble();
      final pinLng = (orderResponse['delivery_longitude'] as num?)?.toDouble() ??
          (orderResponse['pickup_longitude'] as num?)?.toDouble() ??
          (customerData?['pin_longitude'] as num?)?.toDouble();

      if (pinLat != null && pinLng != null) {
        print('✅ Using pinned coordinates: ($pinLat, $pinLng)');
      } else {
        print('⚠️ No pin for order $orderId — creating delivery job without coordinates');
      }

      print('🔍 DEBUG: About to call createDispatchJob...');
      // Create delivery dispatch job
      final supabaseService = SupabaseService();
      await supabaseService.createDispatchJob(
        orderId: orderId,
        riderId: null, // NULL for unassigned
        jobType: 'delivery',
        latitude: pinLat,
        longitude: pinLng,
        address: finalAddress,
        landmark: landmark,
        customerName: customerName,
        notes: 'Deliver clean laundry to customer',
      );

      print('✅ Created delivery dispatch job for ready order $orderId');
    } catch (e) {
      print('❌ Error creating delivery job: $e');
      print('❌ Error stack trace: ${StackTrace.current}');
      // Don't rethrow - order status update should succeed even if dispatch creation fails
    }
  }

  /// Award loyalty points for completed order if a card or customer profile is linked
  Future<void> _awardLoyaltyPointsForOrder(String orderId) async {
    try {
      final orderRow = await _client
          .from('orders')
          .select('customer_id, loads_count, order_number')
          .eq('id', orderId)
          .maybeSingle();

      if (orderRow == null) return;

      final loadsCount = CompleteOrderGuards.loyaltyPointsFor((orderRow['loads_count'] as num?)?.toInt());
      final orderNumber = orderRow['order_number'] as String?;
      final customerId = orderRow['customer_id'] as String?;

      // Check if customer has linked loyalty card
      if (customerId != null) {
        final card = await _loyaltyService.getLinkedCard(customerId);
        if (card != null) {
          await _loyaltyService.awardPoints(
            cardId: card.cardId,
            customerId: card.customerId,
            orderId: orderId,
            loadsCompleted: loadsCount,
            orderNumber: orderNumber,
          );
          print('⭐ Awarded $loadsCount points to loyalty card ${card.uid} for order $orderNumber');
        } else {
          print('ℹ️ No loyalty card linked for customer on order $orderNumber');
        }
      } else {
        print('ℹ️ No customer ID found for order $orderNumber');
      }
    } catch (e) {
      print('⚠️ Failed to award loyalty points for order $orderId: $e');
    }
  }

  /// Staff manually completes pickup when rider forgets
  /// This updates the dispatch job status and syncs order status to 'processing'
  Future<void> staffCompletePickup({
    required String orderId,
    required String staffId,
    String? notes,
  }) async {
    try {
      print('🔧 Staff completing pickup for order: $orderId');
      
      // Find the active pickup dispatch job for this order
      final dispatchJobResponse = await _client
          .from('dispatch_jobs')
          .select('id, status')
          .eq('order_id', orderId)
          .eq('job_type', 'pickup')
          .neq('status', 'pickup_done') // Find incomplete pickup jobs
          .maybeSingle();

      if (dispatchJobResponse == null) {
        throw const AppError(
          'No active pickup job was found for this order. Refresh the list and try again.',
          type: AppErrorType.notFound,
        );
      }

      final jobId = dispatchJobResponse['id'] as String;
      final now = DateTime.now().toUtc().toIso8601String();

      // Update dispatch job to pickup_done
      await _client.from('dispatch_jobs').update({
        'status': 'pickup_done',
        'completed_at': now,
        'updated_at': now,
      }).eq('id', jobId);

      print('✅ Updated dispatch job $jobId to pickup_done');

      // Update order status to processing and add staff note
      final updates = {
        'status': 'processing',
        'received_at': now,
        'processing_at': now,
        'updated_at': now,
      };

      // Append staff note about manual completion
      if (notes != null && notes.trim().isNotEmpty) {
        updates['staff_notes'] = notes.trim();
      } else {
        updates['staff_notes'] = 'Pickup manually completed by staff (rider did not mark complete)';
      }

      await _client.from('orders').update(updates).eq('id', orderId);

      print('✅ Order status updated to processing by staff $staffId');
    } catch (e) {
      print('❌ Error staff completing pickup: $e');
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  /// Staff manually completes delivery when rider forgets
  /// This updates the dispatch job status and syncs order status to 'completed'
  Future<void> staffCompleteDelivery({
    required String orderId,
    required String staffId,
    String? notes,
  }) async {
    try {
      print('🔧 Staff completing delivery for order: $orderId');
      
      // Find the active delivery dispatch job for this order
      final dispatchJobResponse = await _client
          .from('dispatch_jobs')
          .select('id, status')
          .eq('order_id', orderId)
          .eq('job_type', 'delivery')
          .neq('status', 'delivery_done') // Find incomplete delivery jobs
          .maybeSingle();

      if (dispatchJobResponse == null) {
        throw const AppError(
          'No active delivery job was found for this order. Refresh the list and try again.',
          type: AppErrorType.notFound,
        );
      }

      final jobId = dispatchJobResponse['id'] as String;
      final now = DateTime.now().toUtc().toIso8601String();

      // Update dispatch job to delivery_done
      await _client.from('dispatch_jobs').update({
        'status': 'delivery_done',
        'completed_at': now,
        'updated_at': now,
      }).eq('id', jobId);

      print('✅ Updated dispatch job $jobId to delivery_done');

      // Update order status to completed and add staff note
      final updates = {
        'status': 'completed',
        'completed_at': now,
        'updated_at': now,
      };

      // Append staff note about manual completion
      if (notes != null && notes.trim().isNotEmpty) {
        updates['staff_notes'] = notes.trim();
      } else {
        updates['staff_notes'] = 'Delivery manually completed by staff (rider did not mark complete)';
      }

      await _client.from('orders').update(updates).eq('id', orderId);

      print('✅ Order status updated to completed by staff $staffId');
    } catch (e) {
      print('❌ Error staff completing delivery: $e');
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  /// Get order by ID with loads
  Future<LaundryOrder?> getOrderById(String orderId) async {
    try {
      final response = await _client
          .from('orders')
          .select('''
            *,
            order_loads(*),
            customers(first_name, last_name, customer_code, phone, address, landmark)
          ''')
          .eq('id', orderId)
          .maybeSingle();

      if (response == null) return null;

      // Parse loads
      final loadsData = response['order_loads'] as List?;
      final loads = loadsData?.map((loadJson) {
        return OrderLoad.fromJson(loadJson as Map<String, dynamic>);
      }).toList() ?? [];

      final order = LaundryOrder.fromJson(response);

      // Extract customer information from joined data
      final customerData = response['customers'] as Map<String, dynamic>?;
      final firstName = customerData?['first_name'] as String? ?? '';
      final lastName = customerData?['last_name'] as String? ?? '';
      final customerName = lastName.isNotEmpty ? '$firstName $lastName' : firstName.isNotEmpty ? firstName : 'Unknown';
      final customerPhone = customerData?['phone'] as String?;

      // Return order with loads
      return LaundryOrder(
        id: order.id,
        orderNumber: response['order_number'] as String?, // Include order number from database
        customerName: customerName.isNotEmpty && customerName != 'Unknown' ? customerName : order.customerName, // Prefer customer name from joined data
        customerPhone: customerPhone?.isNotEmpty == true ? customerPhone : order.customerPhone, // Prefer customer phone from joined data
        deliveryAddress: order.deliveryAddress ?? (customerData?['address'] as String?),
        deliveryLandmark: order.deliveryLandmark ?? (customerData?['landmark'] as String?),
        channel: order.channel,
        collectionMethod: order.collectionMethod,
        returnMethod: order.returnMethod,
        status: order.status,
        paymentStatus: order.paymentStatus,
        loads: loads,
        instructions: order.instructions,
        rfidTag: null, // Loyalty cards are permanent per-customer, not per-order
        createdAt: order.createdAt,
        processingAt: order.processingAt, // Include processing timestamp
        paymentMethod: order.paymentMethod,
        paidAt: order.paidAt,
        laundryPhotoUrls: order.laundryPhotoUrls,
        customerDescription: order.customerDescription,
        estimatedLoads: order.estimatedLoads,
        rejectionReason: order.rejectionReason,
        staffMessage: order.staffMessage ?? (response['staff_notes'] as String?),
        reviewedAt: order.reviewedAt,
        reviewedBy: order.reviewedBy,
        expiresAt: order.expiresAt,
        underReviewBy: null,
        totalAmount: order.totalAmount ?? (response['total_amount'] as num?)?.toDouble(),
      );
    } catch (e) {
      print('❌ Error getting order: $e');
      return null;
    }
  }
}

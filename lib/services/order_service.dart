import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import 'supabase_service.dart';
import 'rfid_service.dart';

class OrderService {
  final SupabaseClient _client = SupabaseService.client;
  final RfidService _rfidService = RfidService();

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

      // Increment and format with leading zeros
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
      // Validation for RFID tag
      if (rfidTag != null) {
        final isRfidAvailable = await _rfidService.isRfidTagAvailable(rfidTag);
        if (!isRfidAvailable) {
          throw Exception('RFID tag "$rfidTag" is not available');
        }
      }

      // Other validations
      if (customerId.isEmpty) {
        throw Exception('Customer ID is required');
      }
      if (orderNumber.isEmpty) {
        throw Exception('Order number is required');
      }
      if (loads.isEmpty) {
        throw Exception('At least one load is required');
      }
      if (subtotal < 0 || totalAmount < 0) {
        throw Exception('Invalid order amounts');
      }
      if (deliveryRequested && (deliveryAddress == null || deliveryAddress.isEmpty)) {
        throw Exception('Delivery address is required for delivery orders');
      }

      final now = DateTime.now().toIso8601String();

      // Calculate totals
      final totalWeight = loads.fold(0.0, (sum, load) => sum + load.weight);
      final loadsCount = loads.length;

      print('📦 Creating order: $orderNumber');
      print('   Customer: $customerId');
      print('   Loads: $loadsCount (${totalWeight}kg)');
      print('   Total: ₱$totalAmount');

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
        'pickup_address': null, // Walk-in orders don't need pickup address
        'delivery_address': deliveryAddress,
        'landmark': deliveryLandmark,
        'subtotal': subtotal,
        'delivery_fee': 0.0, // Always free delivery
        'total_amount': totalAmount,
        'payment_status': isPaid ? 'paid' : 'pending',
        'status': 'processing',
        'received_at': now,
        'processing_at': now,
        'created_at': now,
        'updated_at': now,
      };

      // Only add assigned_staff_id if we have a valid staff ID
      if (assignedStaffId != null) {
        orderData['assigned_staff_id'] = assignedStaffId;
      }

      final orderResponse = await _client
          .from('orders')
          .insert(orderData)
          .select('id')
          .single();

      final orderId = orderResponse['id'] as String;
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
        final addonsData = addons.map((addon) {
          return {
            'order_id': orderId,
            'addon_id': addon['addon_id'],
            'addon_name': addon['addon_name'],
            'quantity': addon['quantity'] ?? 1,
            'unit_price': addon['unit_price'],
            'line_total': addon['line_total'],
            'created_at': now,
          };
        }).toList();

        await _client.from('order_addons').insert(addonsData);
        print('✅ Created ${addons.length} addons');
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

      // Step 5: Assign RFID tag (if provided)
      if (rfidTag != null) {
        await _rfidService.assignRfidTagToOrder(orderId, rfidTag);
        print('✅ RFID tag assigned: $rfidTag');
      }

      print('🎉 Order creation complete: $orderNumber');
      return orderId;
    } catch (e) {
      print('❌ Error creating order: $e');
      if (e.toString().contains('violates')) {
        throw Exception('Database constraint error: ${e.toString()}');
      }
      rethrow;
    }
  }

  /// Weigh, categorize, and tag an accepted app request that already exists.
  Future<void> checkInExistingOrder({
    required String orderId,
    required List<OrderLoad> loads,
    required double subtotal,
    required double totalAmount,
    required String rfidTag,
    List<Map<String, dynamic>> addons = const [],
    String? staffNotes,
    String? assignedStaffId,
  }) async {
    try {
      if (loads.isEmpty) {
        throw Exception('At least one load is required');
      }
      if (rfidTag.isEmpty) {
        throw Exception('RFID tag is required');
      }

      final isRfidAvailable = await _rfidService.isRfidTagAvailable(rfidTag);
      if (!isRfidAvailable) {
        throw Exception('RFID tag "$rfidTag" is not available');
      }

      final existingLoads = await _client
          .from('order_loads')
          .select('id')
          .eq('order_id', orderId);

      if (existingLoads.isNotEmpty) {
        throw Exception('This order has already been checked in');
      }

      final now = DateTime.now().toIso8601String();
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
        final addonsData = addons.map((addon) {
          return {
            'order_id': orderId,
            'addon_id': addon['addon_id'],
            'addon_name': addon['addon_name'],
            'quantity': addon['quantity'] ?? 1,
            'unit_price': addon['unit_price'],
            'line_total': addon['line_total'],
            'created_at': now,
          };
        }).toList();
        await _client.from('order_addons').insert(addonsData);
      }

      await _rfidService.assignRfidTagToOrder(orderId, rfidTag);

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
      print('✅ Checked in order $orderId with ${loads.length} loads and RFID $rfidTag');
    } catch (e) {
      print('❌ Error checking in order: $e');
      rethrow;
    }
  }

  /// Fetch orders with optional status filter
  Future<List<LaundryOrder>> fetchOrders({
    List<String>? statuses,
    String? assignedStaffId,
    int limit = 50,
  }) async {
    try {
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
            customers!inner(first_name, last_name, customer_code, phone, address, landmark),
            rfid_tags(tag_code)
          ''');

      // Apply status filter if provided
      if (statuses != null && statuses.isNotEmpty) {
        query = query.inFilter('status', statuses);
      }

      // Apply staff filter if provided
      if (assignedStaffId != null) {
        query = query.eq('assigned_staff_id', assignedStaffId);
      }

      // Apply ordering and limit, then execute
      final response = await query
          .order('created_at', ascending: false)
          .limit(limit);

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
        
        // Extract RFID tag information from joined data
        final rfidTagData = orderData['rfid_tags'] as List?;
        final rfidTag = rfidTagData?.isNotEmpty == true 
            ? (rfidTagData!.first as Map<String, dynamic>)['tag_code'] as String?
            : null;
        
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
          rfidTag: rfidTag, // Use RFID tag from rfid_tags table
          createdAt: order.createdAt,
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

  /// Update order status
  Future<void> updateOrderStatus(String orderId, String status) async {
    try {
      final updates = {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Add timestamp fields based on status
      switch (status) {
        case 'processing':
          updates['processing_at'] = DateTime.now().toIso8601String();
          break;
        case 'ready':
          updates['ready_at'] = DateTime.now().toIso8601String();
          break;
        case 'out_for_delivery':
          updates['out_for_delivery_at'] = DateTime.now().toIso8601String();
          break;
        case 'completed':
          updates['completed_at'] = DateTime.now().toIso8601String();
          // Release RFID tag when order is completed
          await _rfidService.releaseRfidTag(orderId);
          break;
        case 'cancelled':
          // Release RFID tag when order is cancelled
          await _rfidService.releaseRfidTag(orderId);
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

  /// Get order by ID with loads
  Future<LaundryOrder?> getOrderById(String orderId) async {
    try {
      final response = await _client
          .from('orders')
          .select('''
            *,
            order_loads(*),
            rfid_tags(tag_code)
          ''')
          .eq('id', orderId)
          .maybeSingle();

      if (response == null) return null;

      // Parse loads
      final loadsData = response['order_loads'] as List?;
      final loads = loadsData?.map((loadJson) {
        return OrderLoad.fromJson(loadJson as Map<String, dynamic>);
      }).toList() ?? [];

      // Extract RFID tag information
      final rfidTagData = response['rfid_tags'] as List?;
      final rfidTag = rfidTagData?.isNotEmpty == true 
          ? (rfidTagData!.first as Map<String, dynamic>)['tag_code'] as String?
          : null;

      final order = LaundryOrder.fromJson(response);

      // Return order with loads
      return LaundryOrder(
        id: order.id,
        customerName: response['customer_name'] as String? ?? 'Unknown',
        customerPhone: order.customerPhone,
        deliveryAddress: order.deliveryAddress,
        deliveryLandmark: order.deliveryLandmark,
        channel: order.channel,
        collectionMethod: order.collectionMethod,
        returnMethod: order.returnMethod,
        status: order.status,
        paymentStatus: order.paymentStatus,
        loads: loads,
        instructions: order.instructions,
        rfidTag: rfidTag, // Use RFID tag from rfid_tags table
        createdAt: order.createdAt,
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
      );
    } catch (e) {
      print('❌ Error getting order: $e');
      return null;
    }
  }
}

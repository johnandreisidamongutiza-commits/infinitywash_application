import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dispatch_job.dart';
import '../models/order.dart';
import 'supabase_service.dart';

/// Adapter to convert DispatchJob to LaundryOrder
/// 
/// This adapter fetches the related order data from the database
/// and converts a DispatchJob into a LaundryOrder format that
/// existing UI components can understand.
class DispatchJobAdapter {
  final SupabaseClient _client = SupabaseService.client;
  
  // Cache to avoid redundant database queries
  final Map<String, LaundryOrder> _orderCache = {};
  
  // Track completion times for completed jobs
  final Map<String, DateTime> _completionTimes = {};

  /// Convert a single DispatchJob to LaundryOrder
  Future<LaundryOrder?> toLaundryOrder(DispatchJob job) async {
    // Check cache first
    if (_orderCache.containsKey(job.orderId)) {
      return _orderCache[job.orderId];
    }

    try {
      print('🔄 Converting DispatchJob ${job.id} to LaundryOrder...');
      
      // Store completion time if job is completed
      if (job.isCompleted && job.completedAt != null) {
        _completionTimes[job.orderId] = job.completedAt!;
      }
      
      // Fetch the related order data
      final response = await _client
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
          ''')
          .eq('id', job.orderId)
          .single();

      // Parse the order using existing logic
      final order = _parseOrderFromResponse(response);
      
      // Cache it
      _orderCache[job.orderId] = order;
      
      print('✅ Converted DispatchJob ${job.id} to LaundryOrder ${order.id}');
      return order;
    } catch (e) {
      print('❌ Error converting DispatchJob to LaundryOrder: $e');
      return null;
    }
  }

  /// Convert multiple DispatchJobs to LaundryOrders
  /// Returns only successfully converted orders (filters out nulls)
  Future<List<LaundryOrder>> toLaundryOrders(List<DispatchJob> jobs) async {
    final orders = <LaundryOrder>[];
    
    for (final job in jobs) {
      final order = await toLaundryOrder(job);
      if (order != null) {
        orders.add(order);
      }
    }
    
    print('✅ Converted ${orders.length} of ${jobs.length} DispatchJobs to LaundryOrders');
    return orders;
  }

  /// Clear the cache (useful for refreshing data)
  void clearCache() {
    _orderCache.clear();
    _completionTimes.clear();
    print('🗑️ DispatchJobAdapter cache cleared');
  }
  
  /// Get completion time for an order (if available)
  DateTime? getCompletionTime(String orderId) {
    return _completionTimes[orderId];
  }

  /// Parse a single order from Supabase response
  LaundryOrder _parseOrderFromResponse(Map<String, dynamic> orderData) {
    // Parse loads
    final loadsData = orderData['order_loads'] as List?;
    final loads = loadsData?.map((loadJson) {
      return OrderLoad.fromJson(loadJson as Map<String, dynamic>);
    }).toList() ?? [];

    // Extract customer information
    final customerData = orderData['customers'] as Map<String, dynamic>?;
    final firstName = customerData?['first_name'] as String? ?? '';
    final lastName = customerData?['last_name'] as String? ?? '';
    final customerName = lastName.isNotEmpty 
        ? '$firstName $lastName' 
        : firstName.isNotEmpty 
            ? firstName 
            : 'Unknown Customer';
    final customerPhone = customerData?['phone'] as String?;

    // Determine collection and return methods based on flags
    final pickupRequested = orderData['pickup_requested'] as bool? ?? false;
    final deliveryRequested = orderData['delivery_requested'] as bool? ?? false;
    
    final collectionMethod = pickupRequested 
        ? CollectionMethod.riderPickup 
        : CollectionMethod.dropOff;
    
    final returnMethod = deliveryRequested 
        ? ReturnMethod.delivery 
        : ReturnMethod.shopPickup;

    // Determine order channel
    final source = orderData['source'] as String?;
    final channel = source == 'walk_in' 
        ? OrderChannel.walkIn 
        : OrderChannel.online;

    // Parse status
    final statusStr = orderData['status'] as String? ?? 'pending_approval';
    final status = _mapDatabaseStatus(statusStr);

    // Parse payment status
    final paymentStatusStr = orderData['payment_status'] as String? ?? 'pending';
    final paymentStatus = paymentStatusStr == 'paid' 
        ? PaymentStatus.paid 
        : PaymentStatus.unpaid;

    // Get addresses - prioritize order-specific addresses, fallback to customer default
    final pickupAddress = orderData['pickup_address'] as String?;
    final deliveryAddress = orderData['delivery_address'] as String?;
    final landmarkFromOrder = orderData['landmark'] as String?;
    final landmarkFromCustomer = customerData?['landmark'] as String?;
    final landmark = landmarkFromOrder ?? landmarkFromCustomer;
    
    // Use appropriate address based on pickup/delivery flags
    final customerAddress = customerData?['address'] as String?;
    final finalPickupAddress = pickupAddress ?? (pickupRequested ? customerAddress : null);
    final finalDeliveryAddress = deliveryAddress ?? (deliveryRequested ? customerAddress : null);

    // Create order object
    return LaundryOrder(
      id: orderData['id'] as String,
      orderNumber: orderData['order_number'] as String?,
      customerName: customerName,
      customerPhone: customerPhone,
      deliveryAddress: finalDeliveryAddress ?? finalPickupAddress, // Use either address
      deliveryLandmark: landmark,
      channel: channel,
      collectionMethod: collectionMethod,
      returnMethod: returnMethod,
      status: status,
      paymentStatus: paymentStatus,
      loads: loads,
      instructions: orderData['customer_notes'] as String?,
      staffMessage: orderData['staff_notes'] as String?,
      createdAt: DateTime.parse(orderData['created_at'] as String),
      totalAmount: (orderData['total_amount'] as num?)?.toDouble(),
      laundryPhotoUrls: (orderData['laundry_photo_urls'] as List?)
          ?.map((e) => e as String)
          .toList(),
      customerDescription: orderData['customer_description'] as String?,
      estimatedLoads: orderData['estimated_loads'] as int?,
      rejectionReason: orderData['rejection_reason'] as String?,
      reviewedAt: orderData['reviewed_at'] != null 
          ? DateTime.parse(orderData['reviewed_at'] as String) 
          : null,
      reviewedBy: orderData['reviewed_by'] as String?,
      expiresAt: orderData['expires_at'] != null 
          ? DateTime.parse(orderData['expires_at'] as String) 
          : null,
    );
  }

  /// Map database status string to OrderStatus enum
  OrderStatus _mapDatabaseStatus(String status) {
    switch (status) {
      case 'pending_approval':
        return OrderStatus.pending_approval;
      case 'pending_pickup':
        return OrderStatus.pending_pickup;
      case 'processing':
        return OrderStatus.processing;
      case 'ready':
        return OrderStatus.ready;
      case 'out_for_delivery':
        return OrderStatus.out_for_delivery;
      case 'completed':
        return OrderStatus.completed;
      case 'cancelled':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.pending_approval;
    }
  }
}

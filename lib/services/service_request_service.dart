import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../utils/app_error.dart';
import '../services/supabase_service.dart';
import '../services/customer_service.dart';
import '../services/service_catalog_service.dart';
import '../services/loyalty_service.dart';

class ServiceRequestService {
  final SupabaseClient _client = SupabaseService.client;
  final CustomerService _customerService = CustomerService();
  final ServiceCatalogService _catalogService = ServiceCatalogService();
  final LoyaltyService _loyaltyService = LoyaltyService();

  /// Submit a new service request from authenticated customer
  /// Uses currently logged-in user's customer record instead of creating new one
  Future<String> submitAuthenticatedServiceRequest({
    required String pickupAddress,
    String? landmark,
    required CollectionMethod collectionMethod,
    required ReturnMethod returnMethod,
    String? paymentPreference,
    List<String>? photoUrls,
    String? customerDescription,
    String? instructions,
    List<Map<String, dynamic>> addons = const [],
  }) async {
    try {
      print('🔄 Starting authenticated service request submission...');
      print('💰 Payment preference: $paymentPreference'); // Debug log

      // Step 1: Get authenticated customer ID
      final customerId = await _customerService.getCurrentAuthenticatedCustomerId();
      print('✅ Using authenticated customer: $customerId');

      // Step 2: Check if customer has linked loyalty card (for logging only)
      print('🔄 Checking for linked loyalty card...');
      final linkedCard = await _loyaltyService.getLinkedCard(customerId);
      if (linkedCard != null) {
        print('✅ Found linked card: ${linkedCard.uid} (${linkedCard.currentPoints} pts)');
      }

      // Step 3: Get service information
      print('🔄 Loading service catalog...');
      final service = await _catalogService.getFullService();
      final serviceId = service['id'] as String;
      final serviceName = service['service_name'] as String;
      final basePrice = (service['base_price'] as num).toDouble();

      // Step 4: Generate order number
      final orderNumber = await _generateServiceRequestNumber();
      print('✅ Generated request number: $orderNumber');

      // Step 5: Set expiry time (24 hours from now)
      final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 24));

      // Step 6: Create service request in orders table
      final response = await _client.from('orders').insert({
        'order_number': orderNumber,
        'customer_id': customerId,
        'source': 'mobile_app',
        'service_id': serviceId,
        'service_name': serviceName,
        'weight_kg': null,
        'loads_count': 1,
        'customer_notes': instructions?.isNotEmpty == true ? instructions : null,
        'staff_notes': null,
        'assigned_staff_id': null,
        'assigned_rider_id': null,
        'pickup_requested': collectionMethod == CollectionMethod.riderPickup,
        'delivery_requested': returnMethod == ReturnMethod.delivery,
        'pickup_address': collectionMethod == CollectionMethod.riderPickup ? pickupAddress : null,
        'delivery_address': returnMethod == ReturnMethod.delivery ? pickupAddress : null,
        'landmark': landmark?.isNotEmpty == true ? landmark : null,
        'subtotal': basePrice,
        'delivery_fee': 0,
        'total_amount': basePrice,
        'payment_status': 'pending',
        'payment_preference': paymentPreference, // ← ADD THIS: Customer's preferred payment method
        'status': 'pending_approval',
        
        // Service request specific fields
        'laundry_photo_urls': photoUrls ?? [],
        'customer_description': customerDescription?.isNotEmpty == true ? customerDescription : null,
        'estimated_loads': null,
        'rejection_reason': null,
        'expires_at': expiresAt.toIso8601String(),
        'reviewed_at': null,
        'reviewed_by': null,
      }).select('id').single();

      final orderId = response['id'] as String;
      print('✅ Service request created: $orderId');

      // Insert add-ons if any
      if (addons.isNotEmpty) {
        print('🔄 Processing ${addons.length} add-ons...');
        final now = DateTime.now().toIso8601String();
        final addonsData = <Map<String, dynamic>>[];
        
        for (final addon in addons) {
          final addonCode = addon['addon_code'] as String;
          
          // Fetch the actual addon UUID from service_addons table
          final serviceAddon = await _client
              .from('service_addons')
              .select('id, addon_name, price')
              .eq('addon_code', addonCode)
              .eq('status', 'active')
              .maybeSingle();
          
          if (serviceAddon == null) {
            print('⚠️ Add-on not found: $addonCode');
            continue;
          }
          
          addonsData.add({
            'order_id': orderId,
            'addon_id': serviceAddon['id'],
            'addon_name': serviceAddon['addon_name'],
            'quantity': addon['quantity'] ?? 1,
            'unit_price': serviceAddon['price'],
            'line_total': (addon['quantity'] ?? 1) * (serviceAddon['price'] as num).toDouble(),
            'created_at': now,
          });
        }
        
        if (addonsData.isNotEmpty) {
          await _client.from('order_addons').insert(addonsData);
          print('✅ Created ${addonsData.length} add-ons for service request');
        }
      }

      return orderId;
    } catch (e) {
      print('❌ Error submitting authenticated service request: $e');
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  /// Submit a new service request from customer (legacy method for non-authenticated flow)
  Future<String> submitServiceRequest({
    required String customerName,
    required String customerPhone,
    required String pickupAddress,
    String? landmark,
    required CollectionMethod collectionMethod,
    required ReturnMethod returnMethod,
    String? paymentPreference,
    List<String>? photoUrls,
    String? customerDescription,
    String? instructions,
  }) async {
    try {
      print('🔄 Starting service request submission...');

      // Step 1: Create or find customer
      print('🔄 Creating/finding customer...');
      
      // Split customer name
      final nameParts = customerName.trim().split(' ');
      final firstName = nameParts.first;
      final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : null;
      
      final customerId = await _customerService.createCustomer(
        firstName: firstName,
        lastName: lastName,
        phone: customerPhone.isNotEmpty ? customerPhone : null,
        email: null, // Not collected in mobile app flow
        address: pickupAddress.isNotEmpty ? pickupAddress : null,
        landmark: landmark?.isNotEmpty == true ? landmark : null,
        customerType: 'mobile_app', // Mobile app customer
      );
      
      print('✅ Customer created/found: $customerId');

      // Step 2: Get service information
      print('🔄 Loading service catalog...');
      final service = await _catalogService.getFullService();
      final serviceId = service['id'] as String;
      final serviceName = service['service_name'] as String;
      final basePrice = (service['base_price'] as num).toDouble();

      // Step 3: Generate order number
      final orderNumber = await _generateServiceRequestNumber();
      print('✅ Generated request number: $orderNumber');

      // Step 4: Set expiry time (24 hours from now)
      final expiresAt = DateTime.now().add(const Duration(hours: 24));

      // Step 5: Create service request in orders table
      final response = await _client.from('orders').insert({
        'order_number': orderNumber,
        'customer_id': customerId,
        'source': 'mobile_app', // Mobile app source
        'service_id': serviceId,
        'service_name': serviceName,
        'weight_kg': null, // Will be determined by staff
        'loads_count': 1, // Default, staff will update
        'customer_notes': instructions?.isNotEmpty == true ? instructions : null,
        'staff_notes': null, // Staff will add notes during review
        'assigned_staff_id': null, // Not assigned yet
        'assigned_rider_id': null, // Not assigned yet
        'pickup_requested': collectionMethod == CollectionMethod.riderPickup,
        'delivery_requested': returnMethod == ReturnMethod.delivery,
        'pickup_address': collectionMethod == CollectionMethod.riderPickup ? pickupAddress : null,
        'delivery_address': returnMethod == ReturnMethod.delivery ? pickupAddress : null, // Same address for pickup/delivery in mobile app
        'landmark': landmark?.isNotEmpty == true ? landmark : null,
        'subtotal': basePrice, // Base price, will be updated after staff review
        'delivery_fee': 0, // Free delivery
        'total_amount': basePrice, // Will be updated after staff review
        'payment_status': 'pending', // Payment pending until staff approval
        'payment_preference': paymentPreference, // Customer's preferred payment method
        'status': 'pending_approval', // Waiting for staff review
        
        // Service request specific fields
        'laundry_photo_urls': photoUrls ?? [],
        'customer_description': customerDescription?.isNotEmpty == true ? customerDescription : null,
        'estimated_loads': null, // Staff will estimate from photos
        'rejection_reason': null,
        'expires_at': expiresAt.toIso8601String(),
        'reviewed_at': null,
        'reviewed_by': null,
      }).select('id').single();

      final orderId = response['id'] as String;
      print('✅ Service request created: $orderId');

      return orderId;
    } catch (e) {
      print('❌ Error submitting service request: $e');
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  /// Get service requests for a specific customer by customer ID (authenticated)
  Future<List<LaundryOrder>> getOrdersByCustomerId(String customerId) async {
    try {
      print('🔄 Fetching orders for customer ID: $customerId');

      final response = await _client
          .from('orders')
          .select('''
            *,
            customers!inner(first_name, last_name, phone, address, landmark),
            order_loads(*)
          ''')
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);

      final List<LaundryOrder> orders = [];
      for (final orderData in response) {
        try {
          final customer = orderData['customers'];
          final customerName = _buildCustomerName(
            customer['first_name'] as String?,
            customer['last_name'] as String?,
          );

          // Parse order loads
          final loadsData = orderData['order_loads'] as List?;
          final loads = loadsData?.map((loadJson) {
            return OrderLoad.fromJson(loadJson as Map<String, dynamic>);
          }).toList() ?? [];

          final order = LaundryOrder(
            id: orderData['id'] as String,
            orderNumber: orderData['order_number'] as String?,
            customerName: customerName,
            customerPhone: customer['phone'] as String?,
            deliveryAddress: orderData['delivery_address'] as String?,
            deliveryLandmark: orderData['landmark'] as String?,
            channel: OrderChannel.online,
            collectionMethod: (orderData['pickup_requested'] as bool) ? CollectionMethod.riderPickup : CollectionMethod.dropOff,
            returnMethod: (orderData['delivery_requested'] as bool) ? ReturnMethod.delivery : ReturnMethod.shopPickup,
            status: _mapDatabaseStatus(orderData['status'] as String),
            paymentStatus: _mapPaymentStatus(orderData['payment_status'] as String),
            loads: loads, // ← Now includes actual loads from database
            instructions: orderData['customer_notes'] as String?,
            rfidTag: null,
            createdAt: _parseLocalDateTime(orderData['created_at'])!,
            paymentMethod: null,
            paymentPreference: orderData['payment_preference'] as String?,
            paidAt: null,
            
            // Service request specific fields
            laundryPhotoUrls: List<String>.from(orderData['laundry_photo_urls'] ?? []),
            customerDescription: orderData['customer_description'] as String?,
            estimatedLoads: orderData['estimated_loads'] as int?,
            rejectionReason: orderData['rejection_reason'] as String?,
            staffMessage: null,
            reviewedAt: _parseLocalDateTime(orderData['reviewed_at']),
            reviewedBy: orderData['reviewed_by'] as String?,
            expiresAt: _parseLocalDateTime(orderData['expires_at']),
            underReviewBy: null,
            totalAmount: (orderData['total_amount'] as num?)?.toDouble(), // ← Add total_amount from database
          );

          orders.add(order);
        } catch (e) {
          print('⚠️ Error parsing order ${orderData['id']}: $e');
          continue;
        }
      }

      print('✅ Found ${orders.length} orders for customer');
      return orders;
    } catch (e) {
      print('❌ Error fetching customer orders: $e');
      rethrow;
    }
  }

  /// Get service requests for a specific customer by phone (deprecated - use getOrdersByCustomerId instead)
  @Deprecated('Use getOrdersByCustomerId instead for better security')
  Future<List<LaundryOrder>> getCustomerServiceRequests(String customerPhone) async {
    try {
      print('🔄 Fetching service requests for customer: $customerPhone');

      final response = await _client
          .from('orders')
          .select('''
            *,
            customers!inner(first_name, last_name, phone, address, landmark)
          ''')
          .eq('source', 'mobile_app')
          .eq('customers.phone', customerPhone)
          .order('created_at', ascending: false);

      final List<LaundryOrder> orders = [];
      for (final orderData in response) {
        try {
          final customer = orderData['customers'];
          final customerName = _buildCustomerName(
            customer['first_name'] as String?,
            customer['last_name'] as String?,
          );

          final order = LaundryOrder(
            id: orderData['id'] as String,
            orderNumber: orderData['order_number'] as String?,
            customerName: customerName,
            customerPhone: customer['phone'] as String?,
            deliveryAddress: orderData['delivery_address'] as String?,
            deliveryLandmark: orderData['landmark'] as String?,
            channel: OrderChannel.online, // Mobile app = online
            collectionMethod: (orderData['pickup_requested'] as bool) ? CollectionMethod.riderPickup : CollectionMethod.dropOff,
            returnMethod: (orderData['delivery_requested'] as bool) ? ReturnMethod.delivery : ReturnMethod.shopPickup,
            status: _mapDatabaseStatus(orderData['status'] as String),
            paymentStatus: _mapPaymentStatus(orderData['payment_status'] as String),
            loads: [], // Service requests don't have loads until approved
            instructions: orderData['customer_notes'] as String?,
            rfidTag: null, // RFID assigned after approval
            createdAt: _parseLocalDateTime(orderData['created_at'])!,
            paymentMethod: null, // Payment method set after approval
            paidAt: null,
            
            // Service request specific fields
            laundryPhotoUrls: List<String>.from(orderData['laundry_photo_urls'] ?? []),
            customerDescription: orderData['customer_description'] as String?,
            estimatedLoads: orderData['estimated_loads'] as int?,
            rejectionReason: orderData['rejection_reason'] as String?,
            staffMessage: null, // Staff message not implemented yet
            reviewedAt: _parseLocalDateTime(orderData['reviewed_at']),
            reviewedBy: orderData['reviewed_by'] as String?,
            expiresAt: _parseLocalDateTime(orderData['expires_at']),
            underReviewBy: null, // Under review feature not implemented yet
          );

          orders.add(order);
        } catch (e) {
          print('⚠️ Error parsing order ${orderData['id']}: $e');
          continue;
        }
      }

      print('✅ Found ${orders.length} service requests for customer');
      return orders;
    } catch (e) {
      print('❌ Error fetching customer service requests: $e');
      rethrow;
    }
  }

  /// Generate unique service request number (REQ-YYMMDD-001, up to 999/day)
  Future<String> _generateServiceRequestNumber() async {
    final now = DateTime.now();
    final yy = (now.year % 100).toString().padLeft(2, '0');
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final datePrefix = 'REQ-$yy$mm$dd';
    
    // Find the highest number for today
    final response = await _client
        .from('orders')
        .select('order_number')
        .like('order_number', '$datePrefix%')
        .order('order_number', ascending: false)
        .limit(1);

    int nextNumber = 1;
    if (response.isNotEmpty) {
      final lastOrderNumber = response.first['order_number'] as String;
      final lastNumberStr = lastOrderNumber.split('-').last;
      final lastNumber = int.tryParse(lastNumberStr) ?? 0;
      nextNumber = lastNumber + 1;
    }

    return '$datePrefix-${nextNumber.toString().padLeft(3, '0')}';
  }

  DateTime? _parseLocalDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.parse(value.toString()).toLocal();
  }

  /// Build customer full name from first and last name
  String _buildCustomerName(String? firstName, String? lastName) {
    if (firstName == null && lastName == null) return 'Unknown Customer';
    if (lastName == null || lastName.isEmpty) return firstName ?? 'Unknown Customer';
    if (firstName == null || firstName.isEmpty) return lastName;
    return '$firstName $lastName';
  }

  /// Map database status to OrderStatus enum
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
      case 'rejected':
        return OrderStatus.rejected;
      default:
        return OrderStatus.pending_approval;
    }
  }

  /// Map database payment status to PaymentStatus enum
  PaymentStatus _mapPaymentStatus(String status) {
    switch (status) {
      case 'paid':
        return PaymentStatus.paid;
      case 'pending':
      case 'failed':
      case 'refunded':
      default:
        return PaymentStatus.unpaid;
    }
  }

  /// Cancel an order by updating its status to cancelled
  Future<void> cancelOrder(String orderId) async {
    try {
      print('🔄 Cancelling order: $orderId');
      
      await _client
          .from('orders')
          .update({
            'status': 'cancelled',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);
      
      print('✅ Order cancelled successfully');
    } catch (e) {
      print('❌ Error cancelling order: $e');
      rethrow;
    }
  }

  /// Check if service request has expired (24 hours)
  bool isServiceRequestExpired(DateTime? expiresAt) {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt);
  }

  /// Get pending service requests for staff (non-expired only)
  Future<List<LaundryOrder>> getPendingServiceRequests() async {
    try {
      print('🔄 Fetching pending service requests for staff...');

      // Auto-reject requests that were never reviewed within 24 hours.
      await _autoRejectExpiredRequests();

      final now = DateTime.now().toIso8601String();
      
      final response = await _client
          .from('orders')
          .select('''
            *,
            customers!inner(first_name, last_name, phone, address, landmark)
          ''')
          .eq('source', 'mobile_app')
          .eq('status', 'pending_approval')
          .or('expires_at.is.null,expires_at.gt.$now') // Include non-expired requests
          .order('created_at', ascending: true); // Oldest first

      final List<LaundryOrder> requests = [];
      for (final orderData in response) {
        try {
          final customer = orderData['customers'];
          final customerName = _buildCustomerName(
            customer['first_name'] as String?,
            customer['last_name'] as String?,
          );

          final request = LaundryOrder(
            id: orderData['id'] as String,
            orderNumber: orderData['order_number'] as String?,
            customerName: customerName,
            customerPhone: customer['phone'] as String?,
            deliveryAddress: orderData['delivery_address'] as String?,
            deliveryLandmark: orderData['landmark'] as String?,
            channel: OrderChannel.online,
            collectionMethod: (orderData['pickup_requested'] as bool) ? CollectionMethod.riderPickup : CollectionMethod.dropOff,
            returnMethod: (orderData['delivery_requested'] as bool) ? ReturnMethod.delivery : ReturnMethod.shopPickup,
            status: OrderStatus.pending_approval,
            paymentStatus: PaymentStatus.unpaid,
            loads: [],
            instructions: orderData['customer_notes'] as String?,
            rfidTag: null,
            createdAt: _parseLocalDateTime(orderData['created_at'])!,
            paymentMethod: null,
            paidAt: null,
            
            // Service request fields
            laundryPhotoUrls: List<String>.from(orderData['laundry_photo_urls'] ?? []),
            customerDescription: orderData['customer_description'] as String?,
            estimatedLoads: orderData['estimated_loads'] as int?,
            rejectionReason: orderData['rejection_reason'] as String?,
            staffMessage: null,
            reviewedAt: _parseLocalDateTime(orderData['reviewed_at']),
            reviewedBy: orderData['reviewed_by'] as String?,
            expiresAt: _parseLocalDateTime(orderData['expires_at']),
            underReviewBy: isReviewLockValid(orderData)
                ? orderData['under_review_by'] as String?
                : null,
          );

          requests.add(request);
        } catch (e) {
          print('⚠️ Error parsing service request ${orderData['id']}: $e');
          continue;
        }
      }

      print('✅ Found ${requests.length} pending service requests');
      return requests;
    } catch (e) {
      print('❌ Error fetching pending service requests: $e');
      rethrow;
    }
  }

  /// Create dispatch jobs for approved order
  Future<void> _createDispatchJobsForApprovedOrder({
    required String orderId,
  }) async {
    try {
      print('🔍 DEBUG: _createDispatchJobsForApprovedOrder called for order: $orderId');
      print('🔄 Creating dispatch jobs for order: $orderId');

      // Fetch full order details
      print('🔍 DEBUG: Fetching order data...');
      final orderResponse = await _client
          .from('orders')
          .select('''
            *,
            customers(first_name, last_name, phone, address, landmark, pin_latitude, pin_longitude)
          ''')
          .eq('id', orderId)
          .single();

      print('🔍 DEBUG: Order fetched successfully');
      print('🔍 DEBUG: Order data: ${orderResponse.toString()}');

      final pickupRequested = orderResponse['pickup_requested'] as bool? ?? false;
      final deliveryRequested = orderResponse['delivery_requested'] as bool? ?? false;
      
      print('🔍 DEBUG: pickupRequested = $pickupRequested');
      print('🔍 DEBUG: deliveryRequested = $deliveryRequested');
      
      // Skip if no pickup/delivery needed
      if (!pickupRequested && !deliveryRequested) {
        print('ℹ️ No dispatch jobs needed for order $orderId');
        return;
      }

      print('🔍 DEBUG: Extracting address data...');
      // Get address from order
      final pickupAddress = orderResponse['pickup_address'] as String?;
      final deliveryAddress = orderResponse['delivery_address'] as String?;
      final orderLandmark = orderResponse['landmark'] as String?;
      final customerData = orderResponse['customers'] as Map<String, dynamic>?;
      final customerAddress = customerData?['address'] as String?;
      final customerLandmark = customerData?['landmark'] as String?;
      
      // Prefer order-specific landmark, fallback to customer's default landmark
      final landmark = orderLandmark ?? customerLandmark;
      
      print('🔍 DEBUG: pickupAddress = $pickupAddress');
      print('🔍 DEBUG: deliveryAddress = $deliveryAddress');
      print('🔍 DEBUG: customerAddress = $customerAddress');
      print('🔍 DEBUG: landmark = $landmark');
      
      // Extract customer name
      final firstName = customerData?['first_name'] as String? ?? '';
      final lastName = customerData?['last_name'] as String? ?? '';
      final customerName = lastName.isNotEmpty 
          ? '$firstName $lastName'.trim()
          : firstName.isNotEmpty 
              ? firstName 
              : 'Unknown Customer';
      
      print('🔍 DEBUG: customerName = "$customerName"');
      
      final finalAddress = pickupAddress ?? deliveryAddress ?? customerAddress ?? '';
      print('🔍 DEBUG: finalAddress = "$finalAddress"');
      
      if (finalAddress.isEmpty) {
        print('⚠️ Cannot create dispatch job: No address for order $orderId');
        return;
      }

      // Use customer's pinned coordinates. No fake fallback — riders see the
      // address with a "no pin" notice instead of being routed somewhere wrong.
      final pinLat = (customerData?['pin_latitude'] as num?)?.toDouble();
      final pinLng = (customerData?['pin_longitude'] as num?)?.toDouble();

      if (pinLat != null && pinLng != null) {
        print('✅ Using pinned coordinates: ($pinLat, $pinLng)');
      } else {
        print('⚠️ No pin for order $orderId — creating job without coordinates');
      }

      // Create dispatch jobs using SupabaseService
      final supabaseService = SupabaseService();
      
      if (pickupRequested) {
        print('🔍 DEBUG: About to create pickup dispatch job...');
        // Create pickup job - NULL rider_id means unassigned (all riders see it)
        await supabaseService.createDispatchJob(
          orderId: orderId,
          riderId: null, // NULL for unassigned
          jobType: 'pickup',
          latitude: pinLat,
          longitude: pinLng,
          address: finalAddress,
          landmark: landmark,
          customerName: customerName, // Pass customer name
          notes: 'Pickup laundry from customer',
        );
        print('✅ Created pickup dispatch job for order $orderId');
      }

      // Note: Delivery job will be created when order status changes to 'ready'
      // This ensures riders only see delivery jobs when laundry is actually ready
    } catch (e, stackTrace) {
      print('❌ Error creating dispatch jobs: $e');
      print('❌ Error stack trace: $stackTrace');
      print('❌ Error type: ${e.runtimeType}');
      if (e is PostgrestException) {
        print('❌ Postgrest error code: ${e.code}');
        print('❌ Postgrest error message: ${e.message}');
        print('❌ Postgrest error details: ${e.details}');
      }
      // Don't rethrow - order approval should succeed even if dispatch creation fails
    }
  }

  /// Approve service request by staff
  /// Get current user's employee ID if exists in the employees table
  Future<String?> _getCurrentEmployeeId() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return null;

      final profile = await _client
          .from('profiles')
          .select('id')
          .eq('supabase_user_id', user.id)
          .maybeSingle();

      if (profile == null) return null;

      final employee = await _client
          .from('employees')
          .select('id')
          .eq('profile_id', profile['id'])
          .maybeSingle();

      return employee?['id'] as String?;
    } catch (e) {
      print('⚠️ Could not resolve employee ID for reviewed_by: $e');
      return null;
    }
  }

  /// Transitions status to 'processing' upon staff approval
  Future<void> approveServiceRequest({
    required String orderId,
    required bool isRiderPickup,
    int? estimatedLoads,
  }) async {
    try {
      final newStatus = isRiderPickup ? 'pending_pickup' : 'processing';
      print('🔄 Approving service request $orderId -> $newStatus');

      // Get current user's employee record ID for reviewed_by (foreign key to employees.id)
      final employeeId = await _getCurrentEmployeeId();

      final updates = <String, dynamic>{
        'status': newStatus,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        // Release the review lock once a decision is recorded.
        'under_review_by': null,
        'under_review_at': null,
      };

      // Only set reviewed_by if an employee record exists in employees table
      if (employeeId != null) {
        updates['reviewed_by'] = employeeId;
      }

      if (estimatedLoads != null) {
        updates['estimated_loads'] = estimatedLoads;
      }

      await _client
          .from('orders')
          .update(updates)
          .eq('id', orderId);

      print('✅ Service request $orderId approved successfully as $newStatus');

      // Create dispatch jobs after successful approval
      print('🔍 DEBUG: About to create dispatch jobs after approval...');
      await _createDispatchJobsForApprovedOrder(orderId: orderId);
      print('🔍 DEBUG: Dispatch job creation completed (or failed silently)');
    } catch (e) {
      print('❌ Error approving service request: $e');
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  /// Reject service request by staff
  /// Transitions status to 'rejected' with reason
  Future<void> rejectServiceRequest({
    required String orderId,
    required String reason,
  }) async {
    try {
      print('🔄 Rejecting service request $orderId (Reason: $reason)');

      // Get current user's employee record ID for reviewed_by (foreign key to employees.id)
      final employeeId = await _getCurrentEmployeeId();

      final updates = <String, dynamic>{
        'status': 'rejected',
        'rejection_reason': reason,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        // Release the review lock when a decision is made.
        'under_review_by': null,
        'under_review_at': null,
      };

      // Only set reviewed_by if an employee record exists in employees table
      if (employeeId != null) {
        updates['reviewed_by'] = employeeId;
      }

      await _client
          .from('orders')
          .update(updates)
          .eq('id', orderId);

      print('✅ Service request $orderId rejected successfully');
    } catch (e) {
      print('❌ Error rejecting service request: $e');
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  // =========================================================================
  // REVIEW LOCK (under_review_by)
  // =========================================================================

  static const Duration reviewLockTimeout = Duration(minutes: 30);

  /// True if the raw row has a review lock that is still valid (held by
  /// someone and less than [reviewLockTimeout] old). Used when parsing rows.
  static bool isReviewLockValid(Map<String, dynamic> row) {
    return isReviewLockValidAt(row, DateTime.now());
  }

  /// Time-injectable core of [isReviewLockValid].
  @visibleForTesting
  static bool isReviewLockValidAt(Map<String, dynamic> row, DateTime now) {
    final holder = row['under_review_by'] as String?;
    if (holder == null || holder.isEmpty) return false;
    final at = row['under_review_at'];
    if (at == null) return false;
    final DateTime? when;
    try {
      when = at is DateTime ? at : DateTime.parse(at.toString());
    } catch (_) {
      return false;
    }
    return now.difference(when.toLocal()) < reviewLockTimeout;
  }

  /// Current user identifier for review locks (employee id when available,
  /// otherwise the auth user id) plus a display name for the UI.
  Future<(String, String)> _getCurrentReviewerIdentity() async {
    final user = _client.auth.currentUser;
    if (user == null) return ('', 'Unknown');

    try {
      final profile = await _client
          .from('profiles')
          .select('id, first_name, last_name')
          .eq('supabase_user_id', user.id)
          .maybeSingle();

      final name = [
        profile?['first_name'] as String?,
        profile?['last_name'] as String?,
      ].where((p) => p != null && p.isNotEmpty).join(' ');

      final employee = await _client
          .from('employees')
          .select('id')
          .eq('profile_id', profile?['id'] as Object? ?? '')
          .maybeSingle();

      final id = (employee?['id'] as String?) ?? user.id;
      return (id, name.isEmpty ? 'Staff' : name);
    } catch (e) {
      print('⚠️ Could not resolve reviewer identity: $e');
      return (user.id, 'Staff');
    }
  }

  /// Claim a request for review. Returns false if another staff member
  /// currently holds a valid lock on it.
  Future<bool> claimForReview(String orderId) async {
    try {
      final (myId, _) = await _getCurrentReviewerIdentity();
      if (myId.isEmpty) return false;

      // Read the current lock state first.
      final row = await _client
          .from('orders')
          .select('under_review_by, under_review_at')
          .eq('id', orderId)
          .maybeSingle();
      if (row == null) return false;

      if (isReviewLockValid(row)) {
        // Valid lock: only the holder (or re-claim by same person) succeeds.
        return row['under_review_by'] == myId;
      }

      // No valid lock — take it.
      await _client.from('orders').update({
        'under_review_by': myId,
        'under_review_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId);
      return true;
    } catch (e) {
      // If the columns don't exist yet (migration not applied), don't block
      // the review flow — just proceed without locking.
      print('⚠️ Review lock unavailable: $e');
      return true;
    }
  }

  /// Release the review lock (on exit without deciding).
  Future<void> releaseReviewLock(String orderId) async {
    try {
      final (myId, _) = await _getCurrentReviewerIdentity();
      await _client.from('orders').update({
        'under_review_by': null,
        'under_review_at': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', orderId).eq('under_review_by', myId);
    } catch (e) {
      print('⚠️ Could not release review lock: $e');
    }
  }

  /// Auto-reject pending requests past their 24-hour expiry. Runs on every
  /// staff list refresh so expired requests never linger as "pending".
  Future<void> _autoRejectExpiredRequests() async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _client
          .from('orders')
          .update({
            'status': 'rejected',
            'rejection_reason': 'expired_no_response',
            'reviewed_at': now,
            'updated_at': now,
          })
          .eq('status', 'pending_approval')
          .eq('source', 'mobile_app')
          .not('expires_at', 'is', null)
          .lt('expires_at', now);
    } catch (e) {
      print('⚠️ Could not auto-reject expired requests: $e');
    }
  }
}
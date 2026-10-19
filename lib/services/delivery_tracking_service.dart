import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/dispatch_job.dart';
import '../models/order.dart';
import 'supabase_service.dart';

/// Bundles all real-time and static information for an active customer delivery or pickup.
class ActiveDelivery {
  final LaundryOrder order;
  final DispatchJob? job;
  final String? riderName;
  final String? riderPhone;
  final String? vehicleDetails;
  final String? riderUserId;
  final LatLng? destinationLocation;
  final String destinationAddress;
  final bool isPickup;

  const ActiveDelivery({
    required this.order,
    this.job,
    this.riderName,
    this.riderPhone,
    this.vehicleDetails,
    this.riderUserId,
    this.destinationLocation,
    required this.destinationAddress,
    required this.isPickup,
  });

  /// True when a rider has accepted/been assigned to the job.
  bool get hasAssignedRider => (job?.riderId != null) || (riderName != null && riderName!.isNotEmpty);

  /// True when the rider is currently traveling with or to the laundry.
  bool get isInProgress => job?.status == 'in_progress' || order.status == OrderStatus.out_for_delivery;

  /// True when the dispatch job is finalized.
  bool get isCompleted => job?.status == 'done' || job?.status == 'pickup_done' || job?.status == 'delivery_done';
}

/// Result from a single delivery polling cycle — contains both job status and rider GPS.
class DeliveryPollResult {
  final DispatchJob? job;
  final LatLng? riderLocation;

  const DeliveryPollResult({this.job, this.riderLocation});
}

/// Service handling customer delivery and pickup tracking data, live coordinates, and status streams.
class DeliveryTrackingService {
  final SupabaseClient _client = SupabaseService.client;

  /// Fetches active delivery or pickup jobs for a specific authenticated customer.
  Future<List<ActiveDelivery>> getActiveDeliveries(String customerId) async {
    try {
      // 1. Fetch relevant active orders for this customer
      final ordersResponse = await _client
          .from('orders')
          .select('''
            *,
            customers (
              first_name,
              last_name,
              phone,
              address,
              landmark,
              pin_latitude,
              pin_longitude
            ),
            order_loads (*)
          ''')
          .eq('customer_id', customerId)
          .inFilter('status', [
            'pending_pickup',
            'out_for_delivery',
            'processing',
            'ready',
          ])
          .order('created_at', ascending: false);

      final List<ActiveDelivery> activeDeliveries = [];

      for (final rawOrder in (ordersResponse as List)) {
        final orderMap = rawOrder as Map<String, dynamic>;
        final orderId = orderMap['id'] as String;

        // Parse LaundryOrder
        final parsedOrder = _parseLaundryOrder(orderMap);

        final isPickup = parsedOrder.collectionMethod == CollectionMethod.riderPickup &&
            parsedOrder.status == OrderStatus.pending_pickup;
        final isDelivery = parsedOrder.returnMethod == ReturnMethod.delivery &&
            (parsedOrder.status == OrderStatus.out_for_delivery || parsedOrder.status == OrderStatus.ready);

        // 2. Fetch associated dispatch_jobs for this order (if any)
        final jobResponse = await _client
            .from('dispatch_jobs')
            .select()
            .eq('order_id', orderId)
            .neq('status', 'cancelled')
            .order('created_at', ascending: false)
            .limit(1);

        DispatchJob? job;
        if (jobResponse.isNotEmpty) {
          job = DispatchJob.fromJson(jobResponse.first);
        }

        // If neither the order status nor an active dispatch job indicates delivery/pickup, skip
        final hasActiveJob = job != null && (job.status == 'pending' || job.status == 'assigned' || job.status == 'in_progress');
        if (!isPickup && !isDelivery && !hasActiveJob) {
          continue;
        }

        // 3. Resolve rider details if a rider is assigned
        String? riderName;
        String? riderPhone;
        String? vehicleDetails;
        String? riderUserId;

        final riderEmployeeId = job?.riderId;
        if (riderEmployeeId != null && riderEmployeeId.isNotEmpty) {
          try {
            final empResponse = await _client
                .from('employees')
                .select('''
                  id,
                  vehicle_details,
                  profiles (
                    first_name,
                    last_name,
                    phone,
                    supabase_user_id
                  )
                ''')
                .eq('id', riderEmployeeId)
                .maybeSingle();

            if (empResponse != null) {
              vehicleDetails = empResponse['vehicle_details'] as String?;
              final profile = empResponse['profiles'] as Map<String, dynamic>?;
              if (profile != null) {
                final fName = profile['first_name'] as String? ?? '';
                final lName = profile['last_name'] as String? ?? '';
                riderName = '$fName $lName'.trim();
                riderPhone = profile['phone'] as String?;
                riderUserId = profile['supabase_user_id'] as String?;
              }
            }
          } catch (e) {
            debugPrint('⚠️ Could not resolve rider details: $e');
          }
        }

        // 4. Resolve destination coordinates
        LatLng? destLocation;
        if (job?.latitude != null && job?.longitude != null) {
          destLocation = LatLng(job!.latitude!, job.longitude!);
        } else {
          final cust = orderMap['customers'] as Map<String, dynamic>?;
          final lat = (cust?['pin_latitude'] as num?)?.toDouble();
          final lng = (cust?['pin_longitude'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            destLocation = LatLng(lat, lng);
          }
        }

        // Destination address string
        final destAddress = parsedOrder.deliveryAddress?.trim().isNotEmpty == true
            ? parsedOrder.deliveryAddress!
            : (job?.address?.trim().isNotEmpty == true
                ? job!.address!
                : 'Customer Delivery Address');

        activeDeliveries.add(ActiveDelivery(
          order: parsedOrder,
          job: job,
          riderName: riderName,
          riderPhone: riderPhone,
          vehicleDetails: vehicleDetails,
          riderUserId: riderUserId,
          destinationLocation: destLocation,
          destinationAddress: destAddress,
          isPickup: job?.jobType == 'pickup' || isPickup,
        ));
      }

      return activeDeliveries;
    } catch (e) {
      debugPrint('❌ Error fetching active deliveries: $e');
      rethrow;
    }
  }

  /// Fetches delivery details for a single specific order by its order ID.
  Future<ActiveDelivery?> getDeliveryByOrderId(String orderId) async {
    try {
      final orderResponse = await _client
          .from('orders')
          .select('''
            *,
            customers (
              first_name,
              last_name,
              phone,
              address,
              landmark,
              pin_latitude,
              pin_longitude
            ),
            order_loads (*)
          ''')
          .eq('id', orderId)
          .maybeSingle();

      if (orderResponse == null) return null;

      final parsedOrder = _parseLaundryOrder(orderResponse);
      final isPickup = parsedOrder.collectionMethod == CollectionMethod.riderPickup &&
          parsedOrder.status == OrderStatus.pending_pickup;

      // Associated dispatch job
      final jobResponse = await _client
          .from('dispatch_jobs')
          .select()
          .eq('order_id', orderId)
          .neq('status', 'cancelled')
          .order('created_at', ascending: false)
          .limit(1);

      DispatchJob? job;
      if (jobResponse.isNotEmpty) {
        job = DispatchJob.fromJson(jobResponse.first);
      }

      // Rider details
      String? riderName;
      String? riderPhone;
      String? vehicleDetails;
      String? riderUserId;

      final riderEmployeeId = job?.riderId;
      if (riderEmployeeId != null && riderEmployeeId.isNotEmpty) {
        try {
          final empResponse = await _client
              .from('employees')
              .select('''
                id,
                vehicle_details,
                profiles (
                  first_name,
                  last_name,
                  phone,
                  supabase_user_id
                )
              ''')
              .eq('id', riderEmployeeId)
              .maybeSingle();

          if (empResponse != null) {
            vehicleDetails = empResponse['vehicle_details'] as String?;
            final profile = empResponse['profiles'] as Map<String, dynamic>?;
            if (profile != null) {
              final fName = profile['first_name'] as String? ?? '';
              final lName = profile['last_name'] as String? ?? '';
              riderName = '$fName $lName'.trim();
              riderPhone = profile['phone'] as String?;
              riderUserId = profile['supabase_user_id'] as String?;
            }
          }
        } catch (e) {
          debugPrint('⚠️ Could not resolve rider details: $e');
        }
      }

      // Destination coordinates
      LatLng? destLocation;
      if (job?.latitude != null && job?.longitude != null) {
        destLocation = LatLng(job!.latitude!, job.longitude!);
      } else {
        final cust = orderResponse['customers'] as Map<String, dynamic>?;
        final lat = (cust?['pin_latitude'] as num?)?.toDouble();
        final lng = (cust?['pin_longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          destLocation = LatLng(lat, lng);
        }
      }

      final destAddress = parsedOrder.deliveryAddress?.trim().isNotEmpty == true
          ? parsedOrder.deliveryAddress!
          : (job?.address?.trim().isNotEmpty == true
              ? job!.address!
              : 'Customer Delivery Address');

      return ActiveDelivery(
        order: parsedOrder,
        job: job,
        riderName: riderName,
        riderPhone: riderPhone,
        vehicleDetails: vehicleDetails,
        riderUserId: riderUserId,
        destinationLocation: destLocation,
        destinationAddress: destAddress,
        isPickup: job?.jobType == 'pickup' || isPickup,
      );
    } catch (e) {
      debugPrint('❌ Error fetching delivery for order $orderId: $e');
      return null;
    }
  }

  /// Combined result from a single polling cycle — rider location + job status.
  /// This halves API requests by fetching both in one timer tick.
  Stream<DeliveryPollResult> pollDeliveryUpdates({
    required String jobId,
    String? riderId,
    Duration interval = const Duration(seconds: 60),
  }) {
    final controller = StreamController<DeliveryPollResult>();
    Timer? pollTimer;

    Future<void> poll() async {
      if (controller.isClosed) return;
      try {
        // 1. Fetch job status (always needed)
        DispatchJob? job;
        final jobResponse = await _client
            .from('dispatch_jobs')
            .select()
            .eq('id', jobId)
            .maybeSingle();
        if (jobResponse != null) {
          job = DispatchJob.fromJson(jobResponse);
        }

        // 2. Fetch rider location (only if rider is assigned and job is active)
        LatLng? riderLocation;
        final effectiveRiderId = job?.riderId ?? riderId;
        if (effectiveRiderId != null && effectiveRiderId.isNotEmpty) {
          final isActive = job == null || (job.status != 'done' && job.status != 'cancelled' &&
              job.status != 'pickup_done' && job.status != 'delivery_done');
          if (isActive) {
            riderLocation = await getLatestRiderLocation(
              riderId: effectiveRiderId,
              dispatchJobId: jobId,
            );
          }
        }

        if (!controller.isClosed) {
          controller.add(DeliveryPollResult(job: job, riderLocation: riderLocation));
        }

        // Auto-stop polling if the job is completed
        if (job != null && (job.status == 'done' || job.status == 'pickup_done' ||
            job.status == 'delivery_done' || job.status == 'cancelled')) {
          debugPrint('ℹ️ Delivery job $jobId is completed/cancelled — stopping poll.');
          pollTimer?.cancel();
        }
      } catch (e) {
        debugPrint('⚠️ Poll error for delivery updates: $e');
      }
    }

    // Immediately fetch, then poll at interval
    poll();
    pollTimer = Timer.periodic(interval, (_) => poll());

    controller.onCancel = () {
      pollTimer?.cancel();
      controller.close();
    };

    return controller.stream;
  }

  /// Fetch the latest one-time coordinate for a rider or job.
  Future<LatLng?> getLatestRiderLocation({required String riderId, String? dispatchJobId}) async {
    try {
      // rider_locations table is keyed by rider_id (one row per rider)
      var query = _client.from('rider_locations').select();

      if (riderId.isNotEmpty) {
        query = query.eq('rider_id', riderId);
      } else if (dispatchJobId != null && dispatchJobId.isNotEmpty) {
        query = query.eq('dispatch_job_id', dispatchJobId);
      } else {
        return null;
      }

      final response = await query.maybeSingle();
      if (response != null) {
        final lat = response['latitude'] as num?;
        final lng = response['longitude'] as num?;
        if (lat != null && lng != null) {
          return LatLng(lat.toDouble(), lng.toDouble());
        }
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ Error getting latest rider location: $e');
      return null;
    }
  }

  /// Helper to convert database order map into [LaundryOrder].
  LaundryOrder _parseLaundryOrder(Map<String, dynamic> json) {
    // Map loads
    final loadsJson = json['order_loads'] as List<dynamic>? ?? [];
    final loads = loadsJson.map((l) => OrderLoad.fromJson(l as Map<String, dynamic>)).toList();

    // Map order status
    final statusStr = json['status'] as String? ?? 'pending_approval';
    final status = switch (statusStr) {
      'pending_approval' => OrderStatus.pending_approval,
      'rejected' => OrderStatus.rejected,
      'cancelled' => OrderStatus.cancelled,
      'pending_pickup' => OrderStatus.pending_pickup,
      'processing' => OrderStatus.processing,
      'ready' => OrderStatus.ready,
      'out_for_delivery' => OrderStatus.out_for_delivery,
      'completed' => OrderStatus.completed,
      _ => OrderStatus.pending_approval,
    };

    final collectionMethod = json['collection_method'] == 'rider_pickup' || json['pickup_requested'] == true
        ? CollectionMethod.riderPickup
        : CollectionMethod.dropOff;

    final returnMethod = json['return_method'] == 'delivery' || json['delivery_requested'] == true
        ? ReturnMethod.delivery
        : ReturnMethod.shopPickup;

    final customer = json['customers'] as Map<String, dynamic>?;
    final fName = customer?['first_name'] as String? ?? '';
    final lName = customer?['last_name'] as String? ?? '';
    final customerName = '$fName $lName'.trim().isNotEmpty ? '$fName $lName'.trim() : 'Customer';

    return LaundryOrder(
      id: json['id'] as String,
      orderNumber: json['order_number'] as String?,
      customerName: customerName,
      customerPhone: customer?['phone'] as String?,
      deliveryAddress: json['delivery_address'] as String? ?? json['pickup_address'] as String?,
      deliveryLandmark: json['landmark'] as String?,
      channel: json['source'] == 'walk_in' ? OrderChannel.walkIn : OrderChannel.online,
      collectionMethod: collectionMethod,
      returnMethod: returnMethod,
      status: status,
      paymentStatus: json['payment_status'] == 'paid' ? PaymentStatus.paid : PaymentStatus.unpaid,
      loads: loads,
      instructions: json['customer_notes'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      totalAmount: (json['total_amount'] as num?)?.toDouble(),
      paymentPreference: json['payment_preference'] as String?,
    );
  }
}

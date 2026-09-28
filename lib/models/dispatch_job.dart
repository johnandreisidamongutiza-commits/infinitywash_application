import 'package:latlong2/latlong.dart';

/// Dispatch Job Model
/// 
/// Represents a pickup or delivery job assigned to a rider.
/// Maps to the dispatch_jobs table in Supabase.
class DispatchJob {
  final String id;
  final String orderId;
  final String? riderId;
  final String? jobNumber;
  final String jobType; // 'pickup' or 'delivery'
  final String status; // 'pending', 'assigned', 'in_progress', 'done', 'cancelled'
  final String? address;
  final String? landmark;
  final double? latitude;
  final double? longitude;
  final DateTime? scheduledAt;
  final DateTime? assignedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? proofUrl;
  final String? notes;
  final DateTime createdAt;

  DispatchJob({
    required this.id,
    required this.orderId,
    this.riderId,
    this.jobNumber,
    required this.jobType,
    required this.status,
    this.address,
    this.landmark,
    this.latitude,
    this.longitude,
    this.scheduledAt,
    this.assignedAt,
    this.startedAt,
    this.completedAt,
    this.proofUrl,
    this.notes,
    required this.createdAt,
  });

  /// Get location as LatLng (returns null if coordinates not set)
  LatLng? get location {
    if (latitude != null && longitude != null) {
      return LatLng(latitude!, longitude!);
    }
    return null;
  }

  /// Check if job has valid coordinates
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Check if job is active (in progress)
  bool get isActive => status == 'in_progress';

  /// Check if job is completed
  bool get isCompleted => status == 'done';

  /// Check if job is pending assignment or start
  bool get isPending => status == 'pending' || status == 'assigned';

  /// Get user-friendly status text
  String get statusText {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'assigned':
        return 'Assigned';
      case 'in_progress':
        return 'In Progress';
      case 'done':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  /// Get user-friendly job type text
  String get jobTypeText {
    return jobType == 'pickup' ? 'Pickup' : 'Delivery';
  }

  /// Create from Supabase JSON
  factory DispatchJob.fromJson(Map<String, dynamic> json) {
    return DispatchJob(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      riderId: json['rider_id'] as String?,
      jobNumber: json['job_number'] as String?,
      jobType: json['job_type'] as String,
      status: json['status'] as String,
      address: json['address'] as String?,
      landmark: json['landmark'] as String?,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      scheduledAt: json['scheduled_at'] != null
          ? DateTime.parse(json['scheduled_at'] as String).toLocal()
          : null,
      assignedAt: json['assigned_at'] != null
          ? DateTime.parse(json['assigned_at'] as String).toLocal()
          : null,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String).toLocal()
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String).toLocal()
          : null,
      proofUrl: json['proof_url'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  /// Convert to Supabase JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'rider_id': riderId,
      'job_number': jobNumber,
      'job_type': jobType,
      'status': status,
      'address': address,
      'landmark': landmark,
      'latitude': latitude,
      'longitude': longitude,
      'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
      'assigned_at': assignedAt?.toUtc().toIso8601String(),
      'started_at': startedAt?.toUtc().toIso8601String(),
      'completed_at': completedAt?.toUtc().toIso8601String(),
      'proof_url': proofUrl,
      'notes': notes,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  /// Create a copy with modified fields
  DispatchJob copyWith({
    String? id,
    String? orderId,
    String? riderId,
    String? jobNumber,
    String? jobType,
    String? status,
    String? address,
    String? landmark,
    double? latitude,
    double? longitude,
    DateTime? scheduledAt,
    DateTime? assignedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    String? proofUrl,
    String? notes,
    DateTime? createdAt,
  }) {
    return DispatchJob(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      riderId: riderId ?? this.riderId,
      jobNumber: jobNumber ?? this.jobNumber,
      jobType: jobType ?? this.jobType,
      status: status ?? this.status,
      address: address ?? this.address,
      landmark: landmark ?? this.landmark,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      assignedAt: assignedAt ?? this.assignedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      proofUrl: proofUrl ?? this.proofUrl,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'DispatchJob(id: $id, type: $jobType, status: $status, address: $address)';
  }
}

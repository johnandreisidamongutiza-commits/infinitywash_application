import 'package:supabase_flutter/supabase_flutter.dart';

class ArrivalProof {
  final String jobType;
  final String signedUrl;
  final DateTime? createdAt;

  const ArrivalProof({
    required this.jobType,
    required this.signedUrl,
    this.createdAt,
  });
}

class ArrivalProofService {
  final SupabaseClient _client = Supabase.instance.client;

  static const String _bucket = 'dispatch-proofs';

  Future<List<ArrivalProof>> getProofsForCustomerOrder(String orderId) async {
    final response = await _client.rpc(
      'get_customer_arrival_proofs',
      params: {'p_order_id': orderId},
    );
    if (response is! List) return const [];

    final proofs = <ArrivalProof>[];
    for (final item in response) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final storedPath = row['proof_path'] as String?;
      if (storedPath == null || !storedPath.startsWith('$_bucket/')) continue;

      final objectPath = storedPath.substring(_bucket.length + 1);
      final signedUrl = await _client.storage
          .from(_bucket)
          .createSignedUrl(objectPath, 60 * 60);
      final createdAtValue = row['created_at'] as String?;
      proofs.add(ArrivalProof(
        jobType: row['job_type'] as String? ?? 'delivery',
        signedUrl: signedUrl,
        createdAt: createdAtValue == null ? null : DateTime.tryParse(createdAtValue),
      ));
    }
    return proofs;
  }
}

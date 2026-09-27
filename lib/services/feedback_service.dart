import '../services/supabase_service.dart';

/// Service for managing customer feedback
class FeedbackService {
  final _supabaseClient = SupabaseService.client;

  /// Submit feedback for an order
  Future<void> submitFeedback({
    required String orderId,
    required String customerId,
    required int rating,
    String? comment,
  }) async {
    try {
      await _supabaseClient.from('feedback').insert({
        'order_id': orderId,
        'customer_id': customerId,
        'rating': rating,
        'comment': comment,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      print('✅ Feedback submitted successfully');
    } catch (e) {
      print('❌ Error submitting feedback: $e');
      rethrow;
    }
  }

  /// Get feedback for an order
  Future<Map<String, dynamic>?> getFeedbackForOrder(String orderId) async {
    try {
      final response = await _supabaseClient
          .from('feedback')
          .select()
          .eq('order_id', orderId)
          .maybeSingle();
      
      return response as Map<String, dynamic>?;
    } catch (e) {
      print('❌ Error getting feedback: $e');
      rethrow;
    }
  }

  /// Check if feedback exists for an order
  Future<bool> hasFeedback(String orderId) async {
    final feedback = await getFeedbackForOrder(orderId);
    return feedback != null;
  }
}

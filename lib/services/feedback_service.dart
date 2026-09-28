import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class FeedbackService {
  final SupabaseClient _client = SupabaseService.client;

  /// Check if feedback already exists for an order
  Future<Map<String, dynamic>?> getFeedbackForOrder(String orderId) async {
    try {
      print('🔍 Checking feedback for order: $orderId');
      
      final response = await _client
          .from('feedback')
          .select()
          .eq('order_id', orderId)
          .maybeSingle();

      if (response != null) {
        print('✅ Feedback found for order $orderId');
        return response;
      } else {
        print('📭 No feedback found for order $orderId');
        return null;
      }
    } catch (e) {
      print('❌ Error fetching feedback: $e');
      rethrow;
    }
  }

  /// Submit feedback for an order (one-time only)
  Future<void> submitFeedback({
    required String orderId,
    required String customerId, // Made required again
    required String customerName,
    required int rating,
    String? comment,
  }) async {
    try {
      // Validate rating
      if (rating < 1 || rating > 5) {
        throw Exception('Rating must be between 1 and 5');
      }

      print('📝 Submitting feedback for order $orderId: $rating stars');

      // Check if feedback already exists
      final existingFeedback = await getFeedbackForOrder(orderId);
      if (existingFeedback != null) {
        throw Exception('Feedback already submitted for this order');
      }

      // Build feedback data
      final feedbackData = <String, dynamic>{
        'order_id': orderId,
        'customer_id': customerId,
        'customer_name': customerName,
        'rating': rating,
        'created_at': DateTime.now().toIso8601String(),
      };

      // Only add comment if not null or empty
      if (comment != null && comment.trim().isNotEmpty) {
        feedbackData['comment'] = comment.trim();
      }

      // Insert feedback
      await _client.from('feedback').insert(feedbackData);

      print('✅ Feedback submitted successfully');
    } catch (e) {
      print('❌ Error submitting feedback: $e');
      rethrow;
    }
  }

  /// Get all feedback with order details (for admin/analytics)
  Future<List<Map<String, dynamic>>> getAllFeedback({
    int limit = 50,
  }) async {
    try {
      final response = await _client
          .from('feedback')
          .select('''
            *,
            orders(order_number, created_at, status)
          ''')
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching all feedback: $e');
      rethrow;
    }
  }

  /// Get average rating for the service
  Future<double> getAverageRating() async {
    try {
      final response = await _client
          .from('feedback')
          .select('rating');

      if (response.isEmpty) return 0.0;

      final ratings = response.map((f) => f['rating'] as int).toList();
      final sum = ratings.reduce((a, b) => a + b);
      final average = sum / ratings.length;

      print('⭐ Average rating: ${average.toStringAsFixed(2)}');
      return average;
    } catch (e) {
      print('❌ Error calculating average rating: $e');
      return 0.0;
    }
  }

  /// Check if feedback exists for an order
  Future<bool> hasFeedback(String orderId) async {
    final feedback = await getFeedbackForOrder(orderId);
    return feedback != null;
  }
}

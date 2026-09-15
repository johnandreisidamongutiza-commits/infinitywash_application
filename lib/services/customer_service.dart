import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class CustomerService {
  final SupabaseClient _client = SupabaseService.client;

  /// Generate next sequential customer code (CUST-00001, CUST-00002, etc.)
  Future<String> generateCustomerCode() async {
    try {
      // Query for the maximum customer_code to find the last number
      final response = await _client
          .from('customers')
          .select('customer_code')
          .order('customer_code', ascending: false)
          .limit(1);

      if (response.isEmpty) {
        // No customers yet, start with CUST-00001
        return 'CUST-00001';
      }

      // Extract the number from the last customer code
      final lastCode = response.first['customer_code'] as String;
      final numberPart = lastCode.replaceAll('CUST-', '');
      final lastNumber = int.tryParse(numberPart) ?? 0;

      // Increment and format with leading zeros
      final nextNumber = lastNumber + 1;
      return 'CUST-${nextNumber.toString().padLeft(5, '0')}';
    } catch (e) {
      print('Error generating customer code: $e');
      // Fallback to timestamp-based code if query fails
      return 'CUST-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    }
  }

  /// Create a new walk-in customer record
  /// Returns the customer UUID for linking to orders
  Future<String> createCustomer({
    required String firstName,
    String? lastName,
    String? phone,
    String? email,
    String? address,
    String? landmark,
  }) async {
    try {
      // Validate required fields
      if (firstName.trim().isEmpty) {
        throw Exception('Customer first name is required');
      }

      // Generate unique customer code
      final customerCode = await generateCustomerCode();

      final now = DateTime.now().toIso8601String();

      // Insert customer record
      final response = await _client
          .from('customers')
          .insert({
            'customer_code': customerCode,
            'first_name': firstName.trim(),
            'last_name': lastName?.trim(),
            'phone': phone?.trim(),
            'email': email?.trim(),
            'address': address?.trim(),
            'landmark': landmark?.trim(),
            'customer_type': 'walk_in',
            'profile_id': null, // Walk-in customers don't have app profiles
            'status': 'active',
            'joined_at': now,
            'created_at': now,
            'updated_at': now,
          })
          .select('id')
          .single();

      final customerId = response['id'] as String;
      final fullName = lastName != null && lastName.trim().isNotEmpty 
          ? '${firstName.trim()} ${lastName.trim()}'
          : firstName.trim();
      print('✅ Created customer: $customerCode ($customerId) - $fullName');
      return customerId;
    } on PostgrestException catch (e) {
      print('❌ Database error creating customer: ${e.message}');
      throw Exception('Database error: ${e.message}');
    } catch (e) {
      print('❌ Error creating customer: $e');
      rethrow;
    }
  }

  /// Find customer by phone number (for future reuse logic)
  Future<Map<String, dynamic>?> findCustomerByPhone(String phone) async {
    try {
      final response = await _client
          .from('customers')
          .select()
          .eq('phone', phone)
          .eq('status', 'active')
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error finding customer by phone: $e');
      return null;
    }
  }

  /// Get customer by ID
  Future<Map<String, dynamic>?> getCustomerById(String customerId) async {
    try {
      final response = await _client
          .from('customers')
          .select()
          .eq('id', customerId)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error getting customer: $e');
      return null;
    }
  }

  /// Update customer information
  Future<void> updateCustomer({
    required String customerId,
    String? fullName,
    String? phone,
    String? email,
    String? address,
    String? landmark,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (fullName != null) updates['full_name'] = fullName;
      if (phone != null) updates['phone'] = phone;
      if (email != null) updates['email'] = email;
      if (address != null) updates['address'] = address;
      if (landmark != null) updates['landmark'] = landmark;

      await _client
          .from('customers')
          .update(updates)
          .eq('id', customerId);

      print('✅ Updated customer: $customerId');
    } catch (e) {
      print('❌ Error updating customer: $e');
      rethrow;
    }
  }

  /// Search customers by name or phone (for future autocomplete)
  Future<List<Map<String, dynamic>>> searchCustomers(String query) async {
    try {
      final response = await _client
          .from('customers')
          .select()
          .or('full_name.ilike.%$query%,phone.ilike.%$query%')
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(10);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error searching customers: $e');
      return [];
    }
  }
}

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

  /// Create a new customer record
  /// Returns the customer UUID for linking to orders
  Future<String> createCustomer({
    required String firstName,
    String? lastName,
    String? phone,
    String? email,
    String? address,
    String? landmark,
    String customerType = 'walk_in', // Default to walk-in, can be 'mobile_app'
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
            'customer_type': customerType,
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

  /// Get customer ID for currently authenticated user
  /// Returns customer UUID if found, throws exception if not authenticated or no customer record
  Future<String> getCurrentAuthenticatedCustomerId() async {
    try {
      // Get current authenticated user
      final user = SupabaseService.currentUser;
      if (user == null) {
        throw Exception('User not authenticated. Please log in to continue.');
      }

      print('🔄 Looking up customer for authenticated user: ${user.id}');

      // Look up user's profile
      final profileResponse = await _client
          .from('profiles')
          .select('id')
          .eq('supabase_user_id', user.id)
          .maybeSingle();

      if (profileResponse == null) {
        throw Exception('User profile not found. Please complete registration.');
      }

      final profileId = profileResponse['id'] as String;
      print('✅ Found profile: $profileId');

      // Look up customer record linked to profile
      final customerResponse = await _client
          .from('customers')
          .select('id')
          .eq('profile_id', profileId)
          .eq('status', 'active')
          .maybeSingle();

      if (customerResponse == null) {
        throw Exception('Customer record not found. Please complete customer registration.');
      }

      final customerId = customerResponse['id'] as String;
      print('✅ Found customer: $customerId');

      return customerId;
    } catch (e) {
      print('❌ Error getting authenticated customer ID: $e');
      rethrow;
    }
  }

  /// Get customer profile for currently authenticated user
  /// Returns full customer data including profile information
  Future<Map<String, dynamic>?> getCurrentAuthenticatedCustomer() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return null;

      // Query customer with profile join
      final response = await _client
          .from('customers')
          .select('''
            *,
            profiles!inner(
              supabase_user_id,
              first_name,
              last_name,
              phone,
              email
            )
          ''')
          .eq('profiles.supabase_user_id', user.id)
          .eq('status', 'active')
          .maybeSingle();

      return response;
    } catch (e) {
      print('❌ Error getting authenticated customer profile: $e');
      return null;
    }
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_error.dart';
import 'supabase_service.dart';

class CustomerService {
  final SupabaseClient _client = SupabaseService.client;

  /// Generate next sequential customer code (CUST-00001, CUST-00002, etc.)
  /// Uses database sequence to prevent race conditions and duplicate key errors
  Future<String> generateCustomerCode() async {
    try {
      // Call database RPC function that uses a sequence
      // This guarantees unique codes even with concurrent requests
      final result = await _client.rpc('get_next_customer_code');
      
      if (result != null) {
        print('✅ Generated customer code via sequence: $result');
        return result as String;
      }
      
      // If RPC returns null, fall back to old method
      print('⚠️ Sequence RPC returned null, using fallback method');
      return await _generateCustomerCodeFallback();
    } catch (e) {
      // If RPC fails (function doesn't exist yet, permissions issue, etc.)
      // fall back to the old query-based method
      print('⚠️ Sequence RPC failed: $e, using fallback method');
      return await _generateCustomerCodeFallback();
    }
  }

  /// Fallback method for generating customer codes (legacy approach)
  /// Used when database sequence is not available
  /// WARNING: This method has race conditions and may cause duplicate key errors
  Future<String> _generateCustomerCodeFallback() async {
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
      print('❌ Fallback customer code generation failed: $e');
      // Last resort: timestamp-based code
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
    double? pinLatitude,
    double? pinLongitude,
    String customerType = 'walk_in', // Default to walk-in, can be 'mobile_app'
  }) async {
    try {
      // Validate required fields
      if (firstName.trim().isEmpty) {
        throw Exception('Customer first name is required');
      }

      // Normalize phone number before saving
      String? normalizedPhone;
      if (phone != null && phone.trim().isNotEmpty) {
        normalizedPhone = normalizePhone(phone.trim());
      }

      // Generate unique customer code
      final customerCode = await generateCustomerCode();

      final now = DateTime.now().toIso8601String();

      // Insert customer record
      final insertData = <String, dynamic>{
        'customer_code': customerCode,
        'first_name': firstName.trim(),
        'last_name': lastName?.trim(),
        'phone': normalizedPhone,
        'email': email?.trim(),
        'address': address?.trim(),
        'landmark': landmark?.trim(),
        if (pinLatitude != null) 'pin_latitude': pinLatitude,
        if (pinLongitude != null) 'pin_longitude': pinLongitude,
        'customer_type': customerType,
        'profile_id': null, // Walk-in customers don't have app profiles
        'status': 'active',
        'joined_at': now,
        'created_at': now,
        'updated_at': now,
      };

      Map<String, dynamic> response;
      try {
        response = await _client
            .from('customers')
            .insert(insertData)
            .select('id')
            .single();
      } on PostgrestException catch (e) {
        // If pin_latitude/pin_longitude columns do not exist in the database, retry without them
        if ((e.message.contains('pin_latitude') || e.code == '42703') &&
            (insertData.containsKey('pin_latitude') || insertData.containsKey('pin_longitude'))) {
          insertData.remove('pin_latitude');
          insertData.remove('pin_longitude');
          response = await _client
              .from('customers')
              .insert(insertData)
              .select('id')
              .single();
        } else {
          rethrow;
        }
      }

      final customerId = response['id'] as String;
      final fullName = lastName != null && lastName.trim().isNotEmpty 
          ? '${firstName.trim()} ${lastName.trim()}'
          : firstName.trim();
      print('✅ Created customer: $customerCode ($customerId) - $fullName');
      return customerId;
    } on PostgrestException catch (e) {
      print('❌ Database error creating customer: ${e.message}');
      throw mapError(e, stackTrace: StackTrace.current);
    } catch (e) {
      print('❌ Error creating customer: $e');
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
    }
  }

  /// Create or get existing customer for a profile (idempotent)
  /// This method is safe to call multiple times - it will only create once
  /// Returns the customer UUID
  Future<String> createOrGetCustomerForProfile({
    required String profileId,
    required String firstName,
    String? lastName,
    String? phone,
    String? email,
    String? address,
    String? landmark,
    double? pinLatitude,
    double? pinLongitude,
    String customerType = 'mobile_app',
  }) async {
    try {
      // Check if customer already exists for this profile
      final existing = await findCustomerByProfileId(profileId);
      if (existing != null) {
        final customerId = existing['id'] as String;
        print('✅ Customer already exists for profile $profileId: $customerId');
        
        // Optionally update customer info if provided data is different
        final needsUpdate = 
            (address != null && address.isNotEmpty && existing['address'] != address) ||
            (landmark != null && landmark.isNotEmpty && existing['landmark'] != landmark) ||
            (phone != null && phone.isNotEmpty && normalizePhone(existing['phone'] ?? '') != normalizePhone(phone)) ||
            (email != null && email.isNotEmpty && existing['email'] != email) ||
            (pinLatitude != null && existing['pin_latitude'] != pinLatitude) ||
            (pinLongitude != null && existing['pin_longitude'] != pinLongitude);
        
        if (needsUpdate) {
          print('ℹ️ Updating customer info for $customerId');
          
          // Normalize phone if updating
          String? normalizedPhone;
          if (phone != null && phone.trim().isNotEmpty) {
            normalizedPhone = normalizePhone(phone.trim());
          }
          
          await _client.from('customers').update({
            if (firstName.trim().isNotEmpty) 'first_name': firstName.trim(),
            if (lastName != null && lastName.trim().isNotEmpty) 'last_name': lastName.trim(),
            if (normalizedPhone != null) 'phone': normalizedPhone,
            if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
            if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
            if (landmark != null && landmark.trim().isNotEmpty) 'landmark': landmark.trim(),
            if (pinLatitude != null) 'pin_latitude': pinLatitude,
            if (pinLongitude != null) 'pin_longitude': pinLongitude,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', customerId);
        }
        
        return customerId;
      }

      // Customer doesn't exist, create new one
      print('🔄 Creating new customer for profile $profileId');
      
      // Validate required fields
      if (firstName.trim().isEmpty) {
        throw const AppError(
          'Please enter the customer\'s first name.',
          type: AppErrorType.validation,
        );
      }

      // Generate unique customer code
      final customerCode = await generateCustomerCode();
      final now = DateTime.now().toIso8601String();

      // Normalize phone before saving
      String? normalizedPhone;
      if (phone != null && phone.trim().isNotEmpty) {
        normalizedPhone = normalizePhone(phone.trim());
      }

      // Insert customer record with profile_id
      final response = await _client
          .from('customers')
          .insert({
            'customer_code': customerCode,
            'profile_id': profileId,
            'first_name': firstName.trim(),
            'last_name': lastName?.trim(),
            'phone': normalizedPhone,
            'email': email?.trim(),
            'address': address?.trim(),
            'landmark': landmark?.trim(),
            'pin_latitude': pinLatitude,
            'pin_longitude': pinLongitude,
            'customer_type': customerType,
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
      // If we get a duplicate key error, it means another process created the customer
      // Try to fetch it one more time
      if (e.message.contains('duplicate') || e.code == '23505') {
        print('⚠️ Duplicate detected, fetching existing customer...');
        final existing = await findCustomerByProfileId(profileId);
        if (existing != null) {
          print('✅ Found existing customer after duplicate: ${existing['id']}');
          return existing['id'] as String;
        }
      }
      
      print('❌ Database error creating customer: ${e.message}');
      throw mapError(e, stackTrace: StackTrace.current);
    } catch (e) {
      print('❌ Error creating customer: $e');
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
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

  /// Find customer by profile ID
  /// Used to check if a customer record already exists for a given profile
  Future<Map<String, dynamic>?> findCustomerByProfileId(String profileId) async {
    try {
      final response = await _client
          .from('customers')
          .select()
          .eq('profile_id', profileId)
          .eq('status', 'active')
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error finding customer by profile ID: $e');
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
    double? pinLatitude,
    double? pinLongitude,
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
      if (pinLatitude != null) updates['pin_latitude'] = pinLatitude;
      if (pinLongitude != null) updates['pin_longitude'] = pinLongitude;

      try {
        await _client
            .from('customers')
            .update(updates)
            .eq('id', customerId);
      } on PostgrestException catch (e) {
        if ((e.message.contains('pin_latitude') || e.code == '42703') &&
            (updates.containsKey('pin_latitude') || updates.containsKey('pin_longitude'))) {
          updates.remove('pin_latitude');
          updates.remove('pin_longitude');
          await _client
              .from('customers')
              .update(updates)
              .eq('id', customerId);
        } else {
          rethrow;
        }
      }

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

  /// Normalize phone number by removing all non-digit characters
  /// Example: "0912-345-6789" -> "09123456789"
  String normalizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^\d]'), '');
  }

  /// Search customers by name and/or phone with order history
  /// Returns customers sorted by most recent order date
  /// Normalizes phone numbers for flexible matching
  Future<List<Map<String, dynamic>>> searchCustomersWithHistory({
    String? name,
    String? firstName,
    String? lastName,
    String? phone,
  }) async {
    try {
      final fName = firstName?.trim() ?? '';
      final lName = lastName?.trim() ?? '';
      final rawName = name?.trim() ?? '';
      final rawPhone = phone?.trim() ?? '';

      // Build search conditions
      if (fName.isEmpty && lName.isEmpty && rawName.isEmpty && rawPhone.isEmpty) {
        return [];
      }

      // Normalize phone for database comparison
      String? normalizedPhone;
      if (rawPhone.isNotEmpty) {
        normalizedPhone = normalizePhone(rawPhone);
      }

      // Query customers with their most recent order
      var query = _client
          .from('customers')
          .select('''
            id,
            customer_code,
            first_name,
            last_name,
            phone,
            email,
            address,
            landmark,
            customer_type,
            joined_at,
            orders!customer_id (
              id,
              created_at,
              delivery_requested,
              customer_notes
            )
          ''')
          .eq('status', 'active');

      if (fName.isNotEmpty && lName.isNotEmpty) {
        query = query.ilike('first_name', '%$fName%').ilike('last_name', '%$lName%');
      } else if (fName.isNotEmpty) {
        query = query.or('first_name.ilike.%$fName%,last_name.ilike.%$fName%');
      } else if (lName.isNotEmpty) {
        query = query.or('first_name.ilike.%$lName%,last_name.ilike.%$lName%');
      } else if (rawName.isNotEmpty) {
        final parts = rawName.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
        if (parts.length >= 2) {
          query = query.ilike('first_name', '%${parts.first}%').ilike('last_name', '%${parts.sublist(1).join(' ')}%');
        } else {
          query = query.or('first_name.ilike.%$rawName%,last_name.ilike.%$rawName%');
        }
      }

      if (normalizedPhone != null && normalizedPhone.isNotEmpty) {
        query = query.ilike('phone', '%$normalizedPhone%');
      }

      final response = await query.limit(10);
      
      // Process results to include most recent order date for sorting
      final customers = List<Map<String, dynamic>>.from(response as List);
      
      for (var customer in customers) {
        // Extract most recent order
        final orders = customer['orders'] as List?;
        if (orders != null && orders.isNotEmpty) {
          // Sort orders by created_at descending
          orders.sort((a, b) {
            final aDate = DateTime.parse(a['created_at'] as String);
            final bDate = DateTime.parse(b['created_at'] as String);
            return bDate.compareTo(aDate);
          });
          
          customer['last_order'] = orders.first;
          customer['last_order_date'] = orders.first['created_at'];
        } else {
          customer['last_order'] = null;
          customer['last_order_date'] = null;
        }
      }

      // Sort by most recent order date (customers with recent orders first)
      customers.sort((a, b) {
        final aDate = a['last_order_date'] as String?;
        final bDate = b['last_order_date'] as String?;
        
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1; // No orders go last
        if (bDate == null) return -1; // No orders go last
        
        return DateTime.parse(bDate).compareTo(DateTime.parse(aDate));
      });

      print('✅ Found ${customers.length} customers matching query');
      return customers;
    } catch (e) {
      print('❌ Error searching customers with history: $e');
      return [];
    }
  }

  /// Get customer ID for currently authenticated user
  /// Returns customer UUID if found, throws [AppError] if not authenticated or no customer record
  Future<String> getCurrentAuthenticatedCustomerId() async {
    try {
      // Get current authenticated user
      final user = SupabaseService.currentUser;
      if (user == null) {
        throw const AppError(
          'You are signed out. Please log in to continue.',
          type: AppErrorType.auth,
        );
      }

      print('🔄 Looking up customer for authenticated user: ${user.id}');

      // Look up user's profile
      final profileResponse = await _client
          .from('profiles')
          .select('id')
          .eq('supabase_user_id', user.id)
          .maybeSingle();

      if (profileResponse == null) {
        throw const AppError(
          'Your profile could not be found. Please complete registration or contact support.',
          type: AppErrorType.notFound,
        );
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
        throw const AppError(
          'Your customer record could not be found. Please contact support so we can restore it.',
          type: AppErrorType.notFound,
        );
      }

      final customerId = customerResponse['id'] as String;
      print('✅ Found customer: $customerId');

      return customerId;
    } catch (e) {
      print('❌ Error getting authenticated customer ID: $e');
      if (e is AppError) rethrow;
      throw mapError(e, stackTrace: StackTrace.current);
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
      print('Error getting authenticated customer profile: $e');
      return null;
    }
  }

  /// Automatically sync any unclaimed walk-in orders matching this customer's phone.
  /// Reassigns past counter orders to this customer profile with zero manual steps.
  Future<int> syncWalkInOrders() async {
    try {
      final customerId = await getCurrentAuthenticatedCustomerId();
      final result = await _client.rpc(
        'sync_customer_walkin_orders',
        params: {'p_customer_id': customerId},
      );
      return (result as num?)?.toInt() ?? 0;
    } catch (_) {
      // Non-blocking fallback
      return 0;
    }
  }
}


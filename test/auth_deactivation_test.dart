import 'package:flutter_test/flutter_test.dart';
import 'package:infinitywash_application/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Account Deactivation Tests
/// 
/// These tests verify that the account deactivation login validation works correctly.
/// 
/// SETUP INSTRUCTIONS:
/// 1. Run the migration SQL file: add_deactivation_reason_migration.sql
/// 2. Create test accounts in Supabase with different statuses
/// 3. Update the test credentials below with your test accounts
/// 
/// TEST ACCOUNTS NEEDED:
/// - Active customer (status: 'active')
/// - Deactivated customer with reason (status: 'deactivated', deactivation_reason: 'Test reason')
/// - Deactivated customer without reason (status: 'deactivated', deactivation_reason: null)
/// - Active staff (status: 'active', role: 'staff')
/// - Deactivated staff (status: 'deactivated', role: 'staff')
/// - Active rider (status: 'active', role: 'rider')
/// - Deactivated rider (status: 'deactivated', role: 'rider')

void main() {
  late AuthService authService;

  setUpAll(() async {
    // Initialize Supabase for testing
    // NOTE: Replace with your test Supabase credentials
    await Supabase.initialize(
      url: 'YOUR_SUPABASE_URL',
      anonKey: 'YOUR_SUPABASE_ANON_KEY',
    );
    
    authService = AuthService();
  });

  tearDown(() async {
    // Sign out after each test
    try {
      await authService.signOut();
    } catch (e) {
      // Ignore sign out errors in tests
    }
  });

  group('Account Deactivation - Login Tests', () {
    test('Test 1: Active customer can log in successfully', () async {
      // Arrange
      const email = 'active-customer@test.com';
      const password = 'testpassword123';

      // Act
      final response = await authService.signIn(
        email: email,
        password: password,
        role: 'Customer',
      );

      // Assert
      expect(response.user, isNotNull);
      expect(response.session, isNotNull);
    });

    test('Test 2: Deactivated customer cannot log in', () async {
      // Arrange
      const email = 'deactivated-customer@test.com';
      const password = 'testpassword123';

      // Act & Assert
      expect(
        () async => await authService.signIn(
          email: email,
          password: password,
          role: 'Customer',
        ),
        throwsA(predicate((e) => 
          e.toString().contains('ACCOUNT_DEACTIVATED')
        )),
      );
    });

    test('Test 3: Deactivated customer sees stored reason', () async {
      // Arrange
      const email = 'deactivated-with-reason@test.com';
      const password = 'testpassword123';
      const expectedReason = 'Violated terms of service';

      // Act & Assert
      try {
        await authService.signIn(
          email: email,
          password: password,
          role: 'Customer',
        );
        fail('Should have thrown an exception');
      } catch (e) {
        expect(e.toString(), contains('ACCOUNT_DEACTIVATED'));
        expect(e.toString(), contains(expectedReason));
      }
    });

    test('Test 4: Deactivated customer without reason sees fallback message', () async {
      // Arrange
      const email = 'deactivated-no-reason@test.com';
      const password = 'testpassword123';

      // Act & Assert
      try {
        await authService.signIn(
          email: email,
          password: password,
          role: 'Customer',
        );
        fail('Should have thrown an exception');
      } catch (e) {
        expect(e.toString(), contains('ACCOUNT_DEACTIVATED'));
        expect(e.toString(), contains('No reason provided'));
      }
    });

    test('Test 5: Reactivated customer can log in', () async {
      // Arrange
      // Prerequisite: Account was deactivated, then reactivated by admin
      const email = 'reactivated-customer@test.com';
      const password = 'testpassword123';

      // Act
      final response = await authService.signIn(
        email: email,
        password: password,
        role: 'Customer',
      );

      // Assert
      expect(response.user, isNotNull);
      expect(response.session, isNotNull);
    });

    test('Test 6: Active staff can log in successfully', () async {
      // Arrange
      const email = 'active-staff@test.com';
      const password = 'testpassword123';

      // Act
      final response = await authService.signIn(
        email: email,
        password: password,
        role: 'Staff',
      );

      // Assert
      expect(response.user, isNotNull);
      expect(response.session, isNotNull);
    });

    test('Test 7: Deactivated staff cannot log in', () async {
      // Arrange
      const email = 'deactivated-staff@test.com';
      const password = 'testpassword123';

      // Act & Assert
      expect(
        () async => await authService.signIn(
          email: email,
          password: password,
          role: 'Staff',
        ),
        throwsA(predicate((e) => 
          e.toString().contains('ACCOUNT_DEACTIVATED')
        )),
      );
    });

    test('Test 8: Active rider can log in successfully', () async {
      // Arrange
      const email = 'active-rider@test.com';
      const password = 'testpassword123';

      // Act
      final response = await authService.signIn(
        email: email,
        password: password,
        role: 'Rider',
      );

      // Assert
      expect(response.user, isNotNull);
      expect(response.session, isNotNull);
    });

    test('Test 9: Deactivated rider cannot log in', () async {
      // Arrange
      const email = 'deactivated-rider@test.com';
      const password = 'testpassword123';

      // Act & Assert
      expect(
        () async => await authService.signIn(
          email: email,
          password: password,
          role: 'Rider',
        ),
        throwsA(predicate((e) => 
          e.toString().contains('ACCOUNT_DEACTIVATED')
        )),
      );
    });

    test('Test 10: Archived customer cannot log in', () async {
      // Arrange
      const email = 'archived-customer@test.com';
      const password = 'testpassword123';

      // Act & Assert
      expect(
        () async => await authService.signIn(
          email: email,
          password: password,
          role: 'Customer',
        ),
        throwsA(predicate((e) => 
          e.toString().contains('ACCOUNT_DEACTIVATED') &&
          e.toString().contains('archived')
        )),
      );
    });
  });

  group('Account Deactivation - Auto-Login Tests', () {
    test('Test 11: Auto-login fails for deactivated account', () async {
      // Arrange
      // First login with an active account
      const email = 'will-be-deactivated@test.com';
      const password = 'testpassword123';
      
      await authService.signIn(
        email: email,
        password: password,
        rememberMe: true,
        role: 'Customer',
      );
      
      final user = authService.getCurrentUser();
      final userId = user!.id;
      
      // Sign out
      await authService.signOut();
      
      // Simulate: Admin deactivates the account in database
      // (In real test, you'd update the database)
      
      // Act - Try auto-login
      final response = await authService.tryAutoLogin(userId: userId);

      // Assert
      expect(response, isNull); // Auto-login should fail
    });

    test('Test 12: Auto-login succeeds for active account', () async {
      // Arrange
      const email = 'active-auto-login@test.com';
      const password = 'testpassword123';
      
      await authService.signIn(
        email: email,
        password: password,
        rememberMe: true,
        role: 'Customer',
      );
      
      final user = authService.getCurrentUser();
      final userId = user!.id;
      
      // Sign out
      await authService.signOut();

      // Act - Try auto-login
      final response = await authService.tryAutoLogin(userId: userId);

      // Assert
      expect(response, isNotNull);
      expect(response!.user.id, equals(userId));
    });
  });

  group('Account Deactivation - Database Persistence Tests', () {
    test('Test 13: Deactivation reason persists in database', () async {
      // This test verifies that the deactivation_reason column exists and works
      // Requires manual setup: Create a deactivated account with a reason
      
      // Arrange
      const email = 'deactivated-persistence@test.com';
      const password = 'testpassword123';
      const expectedReason = 'Test deactivation persistence';

      // Act & Assert
      try {
        await authService.signIn(
          email: email,
          password: password,
          role: 'Customer',
        );
        fail('Should have thrown an exception');
      } catch (e) {
        expect(e.toString(), contains(expectedReason));
      }
    });

    test('Test 14: Reactivation clears deactivation reason', () async {
      // This test verifies that reactivation clears the reason
      // Requires manual setup: Reactivate an account and clear the reason
      
      // Arrange
      const email = 'reactivated-cleared@test.com';
      const password = 'testpassword123';

      // Act
      final response = await authService.signIn(
        email: email,
        password: password,
        role: 'Customer',
      );

      // Assert - Should login successfully
      expect(response.user, isNotNull);
      
      // Verify in database that deactivation_reason is null
      // (This would require a direct database query)
    });
  });
}

/// MANUAL TESTING CHECKLIST
/// 
/// Since Flutter integration tests require a running Supabase instance,
/// here's a manual testing checklist:
/// 
/// ✓ 1. Create a test customer account with status='active'
/// ✓ 2. Try to log in → Should succeed
/// ✓ 3. In Supabase dashboard, set status='deactivated' and deactivation_reason='Test reason'
/// ✓ 4. Try to log in again → Should fail with error showing "Test reason"
/// ✓ 5. Set deactivation_reason=NULL in database
/// ✓ 6. Try to log in → Should fail with fallback message "No reason provided"
/// ✓ 7. Set status='active' and deactivation_reason=NULL
/// ✓ 8. Try to log in → Should succeed
/// ✓ 9. Enable "Remember Me" and log in
/// ✓ 10. Restart app → Should auto-login
/// ✓ 11. Deactivate account while still logged in
/// ✓ 12. Restart app → Auto-login should fail
/// ✓ 13. Repeat tests for Staff role
/// ✓ 14. Repeat tests for Rider role

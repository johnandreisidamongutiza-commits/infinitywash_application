// Smoke test for the unified login screen.
//
// The login page is the app's logged-out entry point: it carries the brand
// header, the single role-agnostic sign-in form and the help footer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinitywash/screens/login_screen.dart';
import 'supabase_test_setup.dart';

void main() {
  setUpAll(() async {
    await initializeTestSupabase();
  });

  tearDownAll(() async {
    await disposeTestSupabase();
  });

  testWidgets('Unified login screen renders the single sign-in form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump();
    await tester.pump();

    // Branding header.
    expect(find.text('INFINITY WASH'), findsOneWidget);
    expect(find.text('Welcome to\nInfinity Wash'), findsOneWidget);

    // Single email/password form - there is no role picker anymore.
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);

    // Actions and the customer self-registration link.
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Remember me'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);

    // Help footer moved here from the removed role-selection screen.
    expect(find.text('Need help? '), findsOneWidget);
    expect(find.text('Contact support.'), findsOneWidget);

    // Opening the support dialog shows the shop contact details.
    // The footer sits below the fold, so bring it into view first.
    await tester.ensureVisible(find.text('Contact support.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contact support.'));
    await tester.pumpAndSettle();
    expect(find.text('Contact Support'), findsOneWidget);
    expect(find.byIcon(Icons.phone_outlined), findsOneWidget);
  });
}

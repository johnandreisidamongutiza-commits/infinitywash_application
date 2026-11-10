// Hermetic render test for RfidCheckerScreen.
//
// The original version of this test navigated from StaffHomeScreen, but that
// screen constructs Supabase- and Firebase-backed services at build time and
// cannot run in a plugin-less unit test environment. This version exercises
// the screen that had the blank-render bug directly and keeps the same
// regression goal: the screen must render its full body (scanner + idle
// guide) instead of a blank page.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinitywash/screens/staff/orders/rfid_checker_screen.dart';
import 'supabase_test_setup.dart';

void main() {
  setUpAll(() async {
    await initializeTestSupabase();
  });

  tearDownAll(() async {
    await disposeTestSupabase();
  });

  testWidgets('RfidCheckerScreen renders completely without a blank screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(780, 1688); // iPhone 12/13/14 size (390x844 logical)
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: RfidCheckerScreen(),
      ),
    );
    await tester.pump();

    // App bar is present.
    expect(find.text('Loyalty Card Scanner'), findsOneWidget);

    // Idle guide renders (the blank-screen regression guard).
    expect(find.text('How to use'), findsOneWidget);
    expect(find.text('Tap loyalty card to reader'), findsOneWidget);
    expect(find.text('Check loyalty balance'), findsOneWidget);
    expect(find.text('Register new cards'), findsOneWidget);

    // Unmount widget so dispose() is called and subscriptions/controllers are cleaned up
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 60));
  });
}

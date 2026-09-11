import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinitywash/screens/staff/home/staff_home_screen.dart';

void main() {
  testWidgets('Staff HomeScreen to RfidCheckerScreen renders completely without blank screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844); // iPhone 12/13/14 size
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: StaffHomeScreen(),
      ),
    );
    await tester.pump();

    // Tap RFID Checker
    final rfidBtn = find.text('RFID\nChecker');
    expect(rfidBtn, findsOneWidget);
    await tester.tap(rfidBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Verify RfidCheckerScreen body is visible
    expect(find.text('RFID Tag Checker'), findsOneWidget);
    expect(find.text('READER ACTIVE • WAITING FOR SCAN'), findsOneWidget);
    expect(find.text('Waiting for RFID Card or Fob'), findsOneWidget);
    expect(find.text('Mock Counter Scenarios (Hardware Simulator):'), findsOneWidget);
    expect(find.text('Scenario 1: Customer Claiming Clean Laundry'), findsOneWidget);

    // Tap Scenario 1
    await tester.tap(find.text('Scenario 1: Customer Claiming Clean Laundry'));
    await tester.pump(const Duration(milliseconds: 400));

    // Verify customer details
    expect(find.text('Customer Details'), findsOneWidget);
    expect(find.text('Carlos Reyes'), findsOneWidget);
  });
}

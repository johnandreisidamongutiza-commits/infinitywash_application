// The Change Password screen is shared by the customer, staff and rider
// profiles. These tests pin the parity contract down: every role renders the
// same chrome and the same live password-requirement checklist, and the
// "must differ from current" guard that staff and rider used to lack is
// enforced for all three.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinitywash/screens/customer/profile/options/change_password_screen.dart';
import 'package:infinitywash/screens/rider/profile/options/change_password_screen.dart';
import 'package:infinitywash/screens/staff/profile/options/change_password_screen.dart';
import 'package:infinitywash/screens/staff/profile/options/notification_settings_screen.dart';

import 'supabase_test_setup.dart';

/// Role-specific safety note rendered in the header card.
const Map<String, String> _safetyNotes = {
  'customer':
      'Choose a strong password to keep your laundry orders and account details safe.',
  'staff':
      'Choose a strong password to keep the customer orders, payments and records you handle safe.',
  'rider':
      'Choose a strong password to keep your deliveries and account details safe.',
};

final Map<String, Widget> _screens = {
  'customer': const CustomerChangePasswordScreen(),
  'staff': const ChangePasswordScreen(),
  'rider': const RiderChangePasswordScreen(),
};

const List<String> _requirementLabels = [
  'At least 6 characters (up to 72)',
  'Contains both letters and numbers',
  'New passwords match',
  'Different from current password',
];

/// Gives every test a tall viewport so the whole form is on screen.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Every non-empty text currently rendered, in tree order.
List<String> _renderedTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => (t.data ?? t.textSpan?.toPlainText() ?? '').trim())
    .where((s) => s.isNotEmpty)
    .toList();

void main() {
  setUpAll(() async {
    await initializeTestSupabase();
  });

  tearDownAll(() async {
    await disposeTestSupabase();
  });

  for (final entry in _screens.entries) {
    final role = entry.key;
    final screen = entry.value;

    testWidgets('$role: renders the shared Change Password layout', (
      WidgetTester tester,
    ) async {
      _useTallViewport(tester);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump();

      // App bar and header card.
      expect(find.text('Change Password'), findsOneWidget);
      expect(find.text('Protect Your Account'), findsOneWidget);
      expect(find.text(_safetyNotes[role]!), findsOneWidget);

      // Form card.
      expect(find.text('Current Password'), findsOneWidget);
      expect(find.text('New Password'), findsOneWidget);
      expect(find.text('Confirm New Password'), findsOneWidget);
      expect(find.text('Update Password'), findsOneWidget);

      // Requirement checklist, all unmet except "different from current",
      // which is satisfied while the current password is still empty.
      expect(find.text('Password Requirements'), findsOneWidget);
      for (final label in _requirementLabels) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsNWidgets(3));
    });

    testWidgets('$role: checklist tracks what is typed', (
      WidgetTester tester,
    ) async {
      _useTallViewport(tester);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump();

      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(3));

      await tester.enterText(fields.at(0), 'oldpass1');
      await tester.enterText(fields.at(1), 'wash1234');
      await tester.enterText(fields.at(2), 'wash1234');
      await tester.pump();

      // Every requirement is met by a valid, distinct, matching password.
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(4));
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsNothing);

      // Reusing the current password un-ticks "Different from current" only:
      // the confirm field is updated too so the match row stays satisfied.
      await tester.enterText(fields.at(1), 'oldpass1');
      await tester.enterText(fields.at(2), 'oldpass1');
      await tester.pump();
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
      expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
    });

    testWidgets('$role: lays out on a phone-sized viewport without overflow', (
      WidgetTester tester,
    ) async {
      // 360x800 is the narrowest phone profile the app targets; the long
      // requirement labels and the header card must still fit.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Protect Your Account'), findsOneWidget);
      expect(find.text('Update Password'), findsOneWidget);
    });

    testWidgets('$role: refuses a new password equal to the current one', (
      WidgetTester tester,
    ) async {
      _useTallViewport(tester);

      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'wash1234');
      await tester.enterText(fields.at(1), 'wash1234');
      await tester.enterText(fields.at(2), 'wash1234');
      await tester.pump();

      await tester.tap(find.text('Update Password'));
      await tester.pump();

      expect(
        find.text('New password must be different from current password'),
        findsOneWidget,
      );

      // Let the snack bar's 4s timer fire so the test does not tear down with
      // a pending timer.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('all three roles render identical chrome', (
    WidgetTester tester,
  ) async {
    _useTallViewport(tester);

    List<String> normalize(List<String> texts) => texts
        .map((t) => _safetyNotes.values.contains(t) ? '<safety>' : t)
        .toList();

    final customer = await _collectTexts(tester, _screens['customer']!);
    final staff = await _collectTexts(tester, _screens['staff']!);
    final rider = await _collectTexts(tester, _screens['rider']!);

    expect(normalize(staff), normalize(customer));
    expect(normalize(rider), normalize(customer));
  });

  group('NotificationSettingsScreen', () {
    testWidgets('lays out on a phone-sized viewport without overflow', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: NotificationSettingsScreen()),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(Switch), findsNWidgets(2));
    });

    testWidgets('renders the restyled tiles and toggles on tap', (
      WidgetTester tester,
    ) async {
      _useTallViewport(tester);

      await tester.pumpWidget(
        const MaterialApp(home: NotificationSettingsScreen()),
      );
      await tester.pump();

      expect(find.text('Notification Settings'), findsOneWidget);
      expect(find.text('Stay in the Loop'), findsOneWidget);
      expect(find.text('New Order Assigned'), findsOneWidget);
      expect(find.text('Payment Alerts'), findsOneWidget);
      expect(
        find.text('Delivery also depends on your device notification settings.'),
        findsOneWidget,
      );

      List<bool> switchValues() => tester
          .widgetList<Switch>(find.byType(Switch))
          .map((s) => s.value)
          .toList();

      expect(switchValues(), [true, true]);

      // Tapping the card body toggles the switch it belongs to.
      await tester.tap(find.text('New Order Assigned'));
      await tester.pumpAndSettle();
      expect(switchValues(), [false, true]);

      await tester.tap(find.byIcon(Icons.payments_outlined));
      await tester.pumpAndSettle();
      expect(switchValues(), [false, false]);
    });
  });
}

Future<List<String>> _collectTexts(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pump();
  return _renderedTexts(tester);
}

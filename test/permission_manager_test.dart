import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infinitywash/utils/permission_manager.dart';

void main() {
  group('PermissionRequestResult', () {
    test('constructors expose the right flags', () {
      const granted = PermissionRequestResult.granted();
      expect(granted.granted, isTrue);
      expect(granted.deniedForever, isFalse);

      const denied = PermissionRequestResult.denied();
      expect(denied.granted, isFalse);
      expect(denied.deniedForever, isFalse);

      const forever = PermissionRequestResult.deniedForever();
      expect(forever.granted, isFalse);
      expect(forever.deniedForever, isTrue);
    });
  });

  group('isPickerPermissionCode', () {
    test('recognizes image_picker permission denial codes', () {
      expect(PermissionManager.isPickerPermissionCode('camera_access_denied'), isTrue);
      expect(PermissionManager.isPickerPermissionCode('photo_access_denied'), isTrue);
      expect(PermissionManager.isPickerPermissionCode('access_denied'), isTrue);
    });

    test('does not treat other picker errors as permission denials', () {
      expect(PermissionManager.isPickerPermissionCode('camera_in_use'), isFalse);
      expect(PermissionManager.isPickerPermissionCode('invalid'), isFalse);
      expect(PermissionManager.isPickerPermissionCode(''), isFalse);
    });
  });

  group('AppPermission copy', () {
    test('every permission has a rationale and denial copy', () {
      for (final kind in AppPermission.values) {
        expect(kind.label, isNotEmpty, reason: '$kind label');
        expect(kind.rationaleTitle, isNotEmpty, reason: '$kind rationale title');
        expect(kind.rationaleMessage.length, greaterThan(30),
            reason: '$kind rationale should explain the purpose');
        expect(kind.deniedOnceMessage, contains('Settings'),
            reason: '$kind denial copy should point to Settings');
        expect(kind.deniedForeverMessage, contains('Settings'),
            reason: '$kind permanent-denial copy should point to Settings');
      }
    });
  });

  group('dialogs', () {
    Future<void> pumpHarness(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => PermissionManager.confirmRationale(
                      context, AppPermission.camera),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('confirmRationale "Allow" returns true',
        (tester) async {
      await pumpHarness(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(AppPermission.camera.rationaleTitle), findsOneWidget);
      expect(find.text(AppPermission.camera.rationaleMessage), findsOneWidget);

      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('confirmRationale "Not now" dismisses without granting',
        (tester) async {
      await pumpHarness(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('showDeniedDialog shows permanent-denial copy and Settings CTA',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => PermissionManager.showDeniedDialog(
                    context,
                    AppPermission.location,
                    deniedForever: true,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Location access needed'), findsOneWidget);
      expect(find.text(AppPermission.location.deniedForeverMessage),
          findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('ensure', () {
    testWidgets('granted request returns true without denial dialog',
        (tester) async {
      BuildContext? captured;
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                captured = context;
                return Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await PermissionManager.ensure(
                        context,
                        AppPermission.camera,
                        check: () async => false,
                        request: () async =>
                            const PermissionRequestResult.granted(),
                      );
                    },
                    child: const Text('go'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // Purpose dialog still appears once; allowing it fires the request.
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(find.text('Camera access needed'), findsNothing);
      expect(captured, isNotNull);
    });

    testWidgets('denied request shows rationale then denial dialog',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await PermissionManager.ensure(
                      context,
                      AppPermission.camera,
                      check: () async => false,
                      request: () async =>
                          const PermissionRequestResult.deniedForever(),
                    );
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );

      // 1. Purpose explanation appears first.
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text(AppPermission.camera.rationaleTitle), findsOneWidget);

      // 2. Proceeding fires the OS request; denial then shows guidance.
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(find.text('Camera access needed'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
    });
  });
}

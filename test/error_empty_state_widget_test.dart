import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:infinitywash/utils/app_error.dart';
import 'package:infinitywash/widgets/empty_state_widget.dart';
import 'package:infinitywash/widgets/error_state_widget.dart';

void main() {
  group('ErrorStateWidget', () {
    testWidgets('shows the mapped message for a network error',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(error: 'SocketException: offline'),
          ),
        ),
      );

      expect(find.text('Connection problem'), findsOneWidget);
      expect(find.textContaining('No internet connection'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('shows the generic message for unknown errors',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(error: 'weird failure'),
          ),
        ),
      );

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('explicit message takes precedence over the error',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(
              error: 'SocketException: offline',
              message: 'Custom message here',
            ),
          ),
        ),
      );

      expect(find.text('Custom message here'), findsOneWidget);
    });

    testWidgets('Retry button fires the callback',
        (WidgetTester tester) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(
              error: 'boom',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, isTrue);
    });

    testWidgets('no Retry button when onRetry is null',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ErrorStateWidget(error: 'boom')),
        ),
      );

      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('AppError message is shown verbatim',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(
              error: AppError('Your session has expired. Please sign in again.'),
            ),
          ),
        ),
      );

      expect(find.textContaining('session has expired'), findsOneWidget);
    });
  });

  group('EmptyStateWidget', () {
    testWidgets('shows the title and subtitle',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              icon: Icons.inbox_outlined,
              title: 'No orders yet',
              subtitle: 'Orders will appear here.',
            ),
          ),
        ),
      );

      expect(find.text('No orders yet'), findsOneWidget);
      expect(find.text('Orders will appear here.'), findsOneWidget);
    });

    testWidgets('search mode names the query',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget.search(query: 'maria', what: 'chats'),
          ),
        ),
      );

      expect(find.text('No results for "maria"'), findsOneWidget);
      expect(find.byIcon(Icons.search_off), findsOneWidget);
    });

    testWidgets('action button fires the callback',
        (WidgetTester tester) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              title: 'Nothing here',
              actionLabel: 'Refresh',
              onAction: () => pressed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Refresh'));
      expect(pressed, isTrue);
    });
  });

  group('AppError basics', () {
    test('isNetwork reflects the network type', () {
      const err = AppError('offline', type: AppErrorType.network);
      expect(err.isNetwork, isTrue);
    });

    test('toString returns the friendly message', () {
      const err = AppError('Friendly text');
      expect(err.toString(), 'Friendly text');
    });
  });
}

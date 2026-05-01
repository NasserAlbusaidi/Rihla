import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'test_router.dart';

void main() {
  group('GoRouter back navigation', () {
    testWidgets('pop from ledger returns to EventHub', (tester) async {
      final router = testRouter(initialLocation: '/group/g1/event/e1/ledger');
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
      );
      await tester.pumpAndSettle();

      // Verify we're at ledger
      expect(find.text('Ledger:e1'), findsOneWidget);

      // Pop (simulates hardware back button)
      router.pop();
      await tester.pumpAndSettle();

      // Should be at EventHub
      expect(find.text('EventHub:e1'), findsOneWidget);
    });

    testWidgets('pop from EventHub returns to GroupDetail', (tester) async {
      final router = testRouter(initialLocation: '/group/g1/event/e1');
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
      );
      await tester.pumpAndSettle();

      expect(find.text('EventHub:e1'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.text('GroupDetail:g1'), findsOneWidget);
    });

    testWidgets('pop from gear returns to EventHub', (tester) async {
      final router = testRouter(initialLocation: '/group/g1/event/e1/gear');
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gear:e1'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.text('EventHub:e1'), findsOneWidget);
    });

    testWidgets('pop from add expense returns to ledger', (tester) async {
      final router = testRouter(
        initialLocation: '/group/g1/event/e1/ledger/add',
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
      );
      await tester.pumpAndSettle();

      expect(find.text('AddExpense:e1'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.text('Ledger:e1'), findsOneWidget);
    });

    testWidgets('pop from event settle-up returns to ledger', (tester) async {
      final router = testRouter(
        initialLocation: '/group/g1/event/e1/ledger/settle-up',
      );
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
      );
      await tester.pumpAndSettle();

      expect(find.text('EventSettleUp:e1'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.text('Ledger:e1'), findsOneWidget);
    });
  });
}

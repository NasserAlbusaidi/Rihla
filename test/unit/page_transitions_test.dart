// Tests for AppPageRoute and AppBottomSheetRoute.
//
// Covers the buildTransitions override for both route types.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/utils/page_transitions.dart';

void main() {
  group('AppPageRoute', () {
    testWidgets('renders child widget via AppPageRoute push', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  AppPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Text('Destination'),
                    ),
                  ),
                );
              },
              child: const Text('Go'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go'));
      // Pump once to start navigation, then settle animations
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Destination'), findsOneWidget);
    });

    testWidgets('transitionDuration is 300ms', (tester) async {
      final route = AppPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
      );
      expect(route.transitionDuration, equals(const Duration(milliseconds: 300)));
    });
  });

  group('AppBottomSheetRoute', () {
    testWidgets('renders child widget via AppBottomSheetRoute push',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  AppBottomSheetRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Text('Sheet Content'),
                    ),
                  ),
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sheet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Sheet Content'), findsOneWidget);
    });

    testWidgets('transitionDuration is 300ms', (tester) async {
      final route = AppBottomSheetRoute<void>(
        builder: (_) => const SizedBox.shrink(),
      );
      expect(route.transitionDuration, equals(const Duration(milliseconds: 300)));
    });
  });
}

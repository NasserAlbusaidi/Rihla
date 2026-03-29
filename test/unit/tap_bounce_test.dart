import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/shared/animations/tap_bounce.dart';

void main() {
  group('TapBounce', () {
    testWidgets('renders its child widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TapBounce(
              onTap: () {},
              child: const Text('Hello'),
            ),
          ),
        ),
      );
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('with null onTap renders child without GestureDetector',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TapBounce(
              child: Text('No tap'),
            ),
          ),
        ),
      );
      expect(find.text('No tap'), findsOneWidget);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('with enabled=false renders child without GestureDetector',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TapBounce(
              onTap: () {},
              enabled: false,
              child: const Text('Disabled'),
            ),
          ),
        ),
      );
      expect(find.text('Disabled'), findsOneWidget);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('onTapDown initiates animation — ScaleTransition present',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TapBounce(
              onTap: () {},
              child: const SizedBox(width: 100, height: 100, child: Text('Tap')),
            ),
          ),
        ),
      );
      // Verify ScaleTransition is in the tree when enabled + onTap provided
      // Use findsWidgets because Scaffold may contribute additional ScaleTransitions
      expect(find.byType(ScaleTransition), findsWidgets);

      // Simulate tap down
      await tester.startGesture(tester.getCenter(find.byType(TapBounce)));
      await tester.pump(const Duration(milliseconds: 60));

      // Still in tree after tap down, animation running
      expect(find.byType(ScaleTransition), findsWidgets);
    });

    testWidgets('onTapUp calls onTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TapBounce(
              onTap: () => tapped = true,
              child: const SizedBox(width: 100, height: 100, child: Text('Tap')),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TapBounce));
      await tester.pump(const Duration(milliseconds: 150));

      expect(tapped, isTrue);
    });

    testWidgets('onTapCancel does not call onTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TapBounce(
              onTap: () => tapped = true,
              child: const SizedBox(width: 100, height: 100, child: Text('Tap')),
            ),
          ),
        ),
      );

      // Start gesture then cancel it
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TapBounce)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 150));

      expect(tapped, isFalse);
    });

    testWidgets('disposes cleanly without ticker leak', (tester) async {
      // Pump TapBounce, then replace with another widget — framework checks ticker
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TapBounce(
              onTap: () {},
              child: const Text('Disposable'),
            ),
          ),
        ),
      );
      expect(find.text('Disposable'), findsOneWidget);

      // Replace with a different widget tree — triggers dispose
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Text('Replaced'),
          ),
        ),
      );
      expect(find.text('Replaced'), findsOneWidget);
      // If ticker leaks, Flutter test framework would throw an error here
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/shared/animations/fade_in_list.dart';

void main() {
  group('FadeInList', () {
    testWidgets('renders all child widgets', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme,
          home: Scaffold(
            body: FadeInList(
              children: const [
                Text('Item 1'),
                Text('Item 2'),
                Text('Item 3'),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
      expect(find.text('Item 3'), findsOneWidget);
    });

    testWidgets('renders empty children without error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme,
          home: Scaffold(
            body: FadeInList(children: []),
          ),
        ),
      );
      await tester.pump();
      // Should render without throwing
      expect(find.byType(FadeInList), findsOneWidget);
    });

    testWidgets('with disableAnimations=true children render without Animate',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: FadeInList(
                children: const [
                  Text('Alpha'),
                  Text('Beta'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      // No Animate widgets when animations disabled
      expect(find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Animate'),
          findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/shared/animations/staggered_grid.dart';

void main() {
  group('StaggeredGrid', () {
    testWidgets('renders all child widgets', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StaggeredGrid(
              children: const [
                Text('Card 1'),
                Text('Card 2'),
                Text('Card 3'),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Card 1'), findsOneWidget);
      expect(find.text('Card 2'), findsOneWidget);
      expect(find.text('Card 3'), findsOneWidget);
    });

    testWidgets('renders empty children without error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StaggeredGrid(children: []),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(StaggeredGrid), findsOneWidget);
    });

    testWidgets('with disableAnimations=true children render without Animate',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: StaggeredGrid(
                children: const [
                  Text('Gamma'),
                  Text('Delta'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Gamma'), findsOneWidget);
      expect(find.text('Delta'), findsOneWidget);
      // No Animate widgets when animations disabled
      expect(find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Animate'),
          findsNothing);
    });
  });
}

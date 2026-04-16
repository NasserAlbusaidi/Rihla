import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/logistics/widgets/logistics_hero_card.dart';

void main() {
  Widget _wrap({
    int groupCount = 0,
    int memberCount = 0,
    int unassignedCount = 0,
    VoidCallback? onCreateTapped,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: LogisticsHeroCard(
          groupCount: groupCount,
          memberCount: memberCount,
          unassignedCount: unassignedCount,
          onCreateTapped: onCreateTapped ?? () {},
        ),
      ),
    );
  }

  group('LogisticsHeroCard', () {
    testWidgets('renders group count and member count', (tester) async {
      await tester.pumpWidget(_wrap(groupCount: 3, memberCount: 7));
      await tester.pumpAndSettle();

      expect(find.text('3 groups · 7 members'), findsOneWidget);
    });

    testWidgets('does not show unassigned text when unassignedCount is zero',
        (tester) async {
      await tester.pumpWidget(_wrap(groupCount: 2, memberCount: 4, unassignedCount: 0));
      await tester.pumpAndSettle();

      expect(find.textContaining('unassigned'), findsNothing);
    });

    testWidgets('shows unassigned count when unassignedCount > 0', (tester) async {
      await tester.pumpWidget(_wrap(groupCount: 2, memberCount: 3, unassignedCount: 2));
      await tester.pumpAndSettle();

      expect(find.text('2 unassigned'), findsOneWidget);
    });

    testWidgets('calls onCreateTapped when CTA button pressed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(onCreateTapped: () => tapped = true));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Group'));
      expect(tapped, isTrue);
    });
  });
}

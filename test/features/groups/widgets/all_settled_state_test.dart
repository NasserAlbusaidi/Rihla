import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/groups/widgets/all_settled_state.dart';

void main() {
  group('AllSettledState', () {
    testWidgets('renders all-settled empty state with icon and message',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AllSettledState()),
        ),
      );

      // Primary path: at least one Text widget rendered
      expect(find.byType(Text), findsWidgets);

      // Icon present (tick_circle)
      expect(find.byType(Icon), findsWidgets);

      // Specific message text
      expect(find.text('All settled up'), findsOneWidget);
      expect(
        find.text('Everyone is square. No outstanding amounts.'),
        findsOneWidget,
      );
    });
  });
}

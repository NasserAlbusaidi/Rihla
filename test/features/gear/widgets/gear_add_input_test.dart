import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/gear/widgets/gear_add_input.dart';
import 'package:safar/core/theme/app_theme.dart';

void main() {
  group('GearAddInput — rendering', () {
    testWidgets('renders input field with ADD GEAR ITEM... hint text',
        (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: GearAddInput(
              controller: controller,
              isHighPriority: false,
              onPriorityChanged: (_) {},
              onSubmit: () {},
            ),
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.widgetWithText(TextField, 'ADD GEAR ITEM...'), findsOneWidget);
    });

    testWidgets('renders submit (add_circle) icon button', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: GearAddInput(
              controller: controller,
              isHighPriority: false,
              onPriorityChanged: (_) {},
              onSubmit: () {},
            ),
          ),
        ),
      );

      // Two IconButtons: priority toggle + submit. Submit is the second one.
      expect(find.byType(IconButton), findsNWidgets(2));
    });
  });

  group('GearAddInput — callbacks', () {
    testWidgets('calls onSubmit when submit icon button is pressed',
        (tester) async {
      final controller = TextEditingController();
      int submitCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: GearAddInput(
              controller: controller,
              isHighPriority: false,
              onPriorityChanged: (_) {},
              onSubmit: () => submitCount++,
            ),
          ),
        ),
      );

      // Tap the second IconButton (submit)
      final buttons = find.byType(IconButton);
      await tester.tap(buttons.last);
      await tester.pump();

      expect(submitCount, equals(1));
    });

    testWidgets('calls onSubmit when TextField onSubmitted fires', (tester) async {
      final controller = TextEditingController();
      int submitCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: GearAddInput(
              controller: controller,
              isHighPriority: false,
              onPriorityChanged: (_) {},
              onSubmit: () => submitCount++,
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Tent');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submitCount, equals(1));
    });

    testWidgets('calls onPriorityChanged when priority (flash) button tapped',
        (tester) async {
      final controller = TextEditingController();
      bool? changedValue;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: GearAddInput(
              controller: controller,
              isHighPriority: false,
              onPriorityChanged: (v) => changedValue = v,
              onSubmit: () {},
            ),
          ),
        ),
      );

      // Priority button is the first IconButton
      await tester.tap(find.byType(IconButton).first);
      await tester.pump();

      // Was false, toggled → true
      expect(changedValue, isTrue);
    });
  });
}

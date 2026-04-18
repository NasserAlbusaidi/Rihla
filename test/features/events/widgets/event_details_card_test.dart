import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/features/events/widgets/event_details_card.dart';

void main() {
  group('EventDetailsCard', () {
    late TextEditingController nameController;

    setUp(() {
      nameController = TextEditingController();
    });

    tearDown(() {
      nameController.dispose();
    });

    testWidgets('renders name field and date tiles', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(
            body: Form(
              child: EventDetailsCard(
                nameController: nameController,
                startDate: null,
                endDate: null,
                onPickStartDate: () {},
                onPickEndDate: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Event Name'), findsOneWidget);
      expect(find.text('Dates'), findsOneWidget);
      expect(find.text('Start date'), findsOneWidget);
      expect(find.text('End date'), findsOneWidget);
    });

    testWidgets('shows formatted start date when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(
            body: Form(
              child: EventDetailsCard(
                nameController: nameController,
                startDate: DateTime(2026, 6, 15),
                endDate: null,
                onPickStartDate: () {},
                onPickEndDate: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Jun 15, 2026'), findsOneWidget);
      expect(find.text('End date'), findsOneWidget);
    });

    testWidgets('calls onPickStartDate when start date button tapped',
        (tester) async {
      var startTapped = false;

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(
            body: Form(
              child: EventDetailsCard(
                nameController: nameController,
                startDate: null,
                endDate: null,
                onPickStartDate: () => startTapped = true,
                onPickEndDate: () {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Start date'));
      expect(startTapped, isTrue);
    });

    testWidgets('calls onPickEndDate when end date button tapped',
        (tester) async {
      var endTapped = false;

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(
            body: Form(
              child: EventDetailsCard(
                nameController: nameController,
                startDate: null,
                endDate: null,
                onPickStartDate: () {},
                onPickEndDate: () => endTapped = true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('End date'));
      expect(endTapped, isTrue);
    });

    testWidgets('name field validator rejects empty input', (tester) async {
      final formKey = GlobalKey<FormState>();

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(
            body: Form(
              key: formKey,
              child: EventDetailsCard(
                nameController: nameController,
                startDate: null,
                endDate: null,
                onPickStartDate: () {},
                onPickEndDate: () {},
              ),
            ),
          ),
        ),
      );

      formKey.currentState!.validate();
      await tester.pump();

      expect(find.text("Event name can't be empty."), findsOneWidget);
    });
  });
}

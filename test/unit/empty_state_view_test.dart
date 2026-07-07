// Tests for EmptyStateView widget.
//
// Covers the action button path (lines 64-69 in empty_state_view.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:iconsax/iconsax.dart';

import 'package:safar/core/keys/shared_keys.dart';
import 'package:safar/shared/widgets/empty_state_view.dart';

void main() {
  group('EmptyStateView', () {
    testWidgets('renders title and message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: EmptyStateView(
              icon: Iconsax.calendar,
              title: 'No Events',
              message: 'Start by creating your first event',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('No Events'), findsOneWidget);
      expect(find.text('Start by creating your first event'), findsOneWidget);
    });

    testWidgets(
      'renders action button when actionLabel and onAction provided',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: EmptyStateView(
                icon: Iconsax.add_circle,
                title: 'Nothing Here',
                message: 'Tap below to get started',
                actionLabel: 'Create event',
                onAction: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('Create event'), findsOneWidget);
        expect(find.byKey(SharedKeys.emptyStateCtaButton), findsOneWidget);
      },
    );

    testWidgets('action button onPressed calls onAction callback', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: EmptyStateView(
              icon: Iconsax.add_circle,
              title: 'Nothing Here',
              message: 'Tap below to get started',
              actionLabel: 'Create event',
              onAction: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byKey(SharedKeys.emptyStateCtaButton));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('does NOT render action button when actionLabel is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: EmptyStateView(
              icon: Iconsax.calendar,
              title: 'No Events',
              message: 'No action here',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(SharedKeys.emptyStateCtaButton), findsNothing);
    });
  });
}

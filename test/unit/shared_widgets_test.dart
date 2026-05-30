// Shared widget tests for LoadingButton.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/shared/widgets/loading_button.dart';

void main() {

  // ---------------------------------------------------------------------------
  // LoadingButton tests
  // ---------------------------------------------------------------------------

  group('LoadingButton', () {
    testWidgets('renders label text when not loading', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LoadingButton(
              isLoading: false,
              onPressed: () {},
              label: 'Submit',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Submit'), findsOneWidget);
    });

    testWidgets('renders CircularProgressIndicator when loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LoadingButton(
              isLoading: true,
              onPressed: () {},
              label: 'Submit',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Submit'), findsNothing);
    });

    testWidgets('calls onPressed when tapped and not loading', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LoadingButton(
              isLoading: false,
              onPressed: () => tapped = true,
              label: 'Submit',
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('does not call onPressed when loading (button disabled)', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LoadingButton(
              isLoading: true,
              onPressed: () => tapped = true,
              label: 'Submit',
            ),
          ),
        ),
      );
      await tester.pump();

      // Button is disabled when isLoading=true (onPressed is set to null)
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
      expect(tapped, isFalse);
    });

    testWidgets('renders icon when icon is provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LoadingButton(
              isLoading: false,
              onPressed: () {},
              label: 'Create',
              icon: Icons.add,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
    });

    testWidgets('renders without icon when icon is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: LoadingButton(
              isLoading: false,
              onPressed: () {},
              label: 'Save',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('is disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: LoadingButton(
              isLoading: false,
              onPressed: null,
              label: 'Disabled',
            ),
          ),
        ),
      );
      await tester.pump();

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });
  });
}

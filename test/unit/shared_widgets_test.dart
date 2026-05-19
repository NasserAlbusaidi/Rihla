// Shared widget tests for SearchFilterBar, LoadingButton, and other
// shared components that have low coverage.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/shared/widgets/dot_step_indicator.dart';
import 'package:safar/shared/widgets/loading_button.dart';
import 'package:safar/shared/widgets/search_filter_bar.dart';

// ---------------------------------------------------------------------------
// SearchFilterBar tests
// ---------------------------------------------------------------------------

void main() {
  group('SearchFilterBar', () {
    testWidgets('renders search toggle button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SearchFilterBar(
              onSearchChanged: (_) {},
              hintText: 'Search...',
            ),
          ),
        ),
      );
      await tester.pump();

      // Toggle button (GestureDetector with search icon) is rendered
      expect(find.byType(GestureDetector), findsWidgets);
    });

    testWidgets('expands search field when toggle is tapped', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SearchFilterBar(
              onSearchChanged: (_) {},
              hintText: 'Search items',
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap the toggle button to expand
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      // After expansion, a TextField should be visible
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('notifies onSearchChanged when text is entered', (
      tester,
    ) async {
      String? lastQuery;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SearchFilterBar(
              onSearchChanged: (q) => lastQuery = q,
              hintText: 'Search',
            ),
          ),
        ),
      );
      await tester.pump();

      // Expand search
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      // Type in the search field
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      expect(lastQuery, equals('hello'));
    });

    testWidgets('collapses search on second toggle tap and clears query', (
      tester,
    ) async {
      String? lastQuery;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SearchFilterBar(
              onSearchChanged: (q) => lastQuery = q,
              hintText: 'Search',
            ),
          ),
        ),
      );
      await tester.pump();

      // Expand
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      // Type something
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(lastQuery, equals('hello'));

      // Collapse — toggle again
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();

      // onSearchChanged called with empty string on collapse
      expect(lastQuery, equals(''));
    });

    testWidgets('renders filter chips when filters are provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SearchFilterBar(
              onSearchChanged: (_) {},
              filters: const ['All', 'Active', 'Archived'],
              activeFilter: 'All',
              onFilterChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
    });

    testWidgets('renders no filter chips when filters list is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SearchFilterBar(onSearchChanged: (_) {}, filters: const []),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('renders no filter chips when filters is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: SearchFilterBar(onSearchChanged: (_) {})),
        ),
      );
      await tester.pump();

      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('active filter chip appears selected', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SearchFilterBar(
              onSearchChanged: (_) {},
              filters: const ['Alpha', 'Beta'],
              activeFilter: 'Alpha',
              onFilterChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      final alphaChip = chips.firstWhere(
        (c) => (c.label as Text).data == 'Alpha',
      );
      expect(alphaChip.selected, isTrue);
    });

    testWidgets('tapping filter chip calls onFilterChanged', (tester) async {
      String? changedFilter;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SearchFilterBar(
              onSearchChanged: (_) {},
              filters: const ['Alpha', 'Beta'],
              activeFilter: null,
              onFilterChanged: (f) => changedFilter = f,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Beta'));
      await tester.pump();

      expect(changedFilter, equals('Beta'));
    });
  });

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

  group('RTL polish', () {
    testWidgets('ShimmerPlaceholder resolves shimmer from start to end', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: ShimmerPlaceholder(width: 100, height: 20)),
          ),
        ),
      );
      await tester.pump();

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      final gradient = decoration.gradient as LinearGradient;

      expect(gradient.begin, AlignmentDirectional.centerStart);
      expect(gradient.end, AlignmentDirectional.centerEnd);
    });

    testWidgets('DotStepIndicator keeps step order LTR in RTL layouts', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: DotStepIndicator(stepCount: 3, currentStep: 1),
            ),
          ),
        ),
      );
      await tester.pump();

      final row = tester.widget<Row>(find.byType(Row));
      expect(row.textDirection, TextDirection.ltr);
    });
  });

  // ---------------------------------------------------------------------------
  // GlassCard tests
  // ---------------------------------------------------------------------------

  group('GlassCard', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: GlassCard(child: Text('Card Content'))),
        ),
      );
      await tester.pump();

      expect(find.text('Card Content'), findsOneWidget);
    });

    testWidgets('renders with custom padding', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: GlassCard(
              padding: EdgeInsets.all(32),
              child: Text('Padded Content'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Padded Content'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // GradientContainer tests
  // ---------------------------------------------------------------------------

  group('GradientContainer', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: GradientContainer(child: Text('Gradient Content')),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Gradient Content'), findsOneWidget);
    });
  });
}

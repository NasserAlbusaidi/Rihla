import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/core/types/event_ref.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/widgets/edit_expense_scope_section.dart';
import 'package:safar/features/logistics/models/sub_group_model.dart';
import 'package:safar/features/logistics/providers/sub_group_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _groupId = 'g-1';
const _eventId = 'e-1';

Widget _wrap({
  required ExpenseScope scope,
  ValueChanged<ExpenseScope>? onScopeChanged,
  List<SubGroup> subGroups = const [],
}) {
  final eventRef = (groupId: _groupId, eventId: _eventId) as EventRef;
  return ProviderScope(
    overrides: [
      eventSubGroupsProvider(eventRef).overrideWith(
        (ref) => Stream.value(subGroups),
      ),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(
        body: EditExpenseScopeSection(
          groupId: _groupId,
          eventId: _eventId,
          scope: scope,
          onScopeChanged: onScopeChanged ?? (_) {},
          selectedSubGroupId: null,
          onSubGroupIdChanged: (_) {},
          customSplitParticipants: const {},
          onCustomSplitChanged: (_) {},
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EditExpenseScopeSection', () {
    testWidgets('renders SPLIT TYPE label and all four scope tabs',
        (tester) async {
      await tester.pumpWidget(_wrap(scope: ExpenseScope.global));
      await tester.pump();

      expect(find.text('SPLIT TYPE'), findsOneWidget);
      expect(find.text('Global'), findsOneWidget);
      expect(find.text('My Car'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
    });

    testWidgets('calls onScopeChanged when a tab is tapped', (tester) async {
      ExpenseScope? lastScope;
      await tester.pumpWidget(
        _wrap(
          scope: ExpenseScope.global,
          onScopeChanged: (s) => lastScope = s,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Personal'));
      await tester.pump();

      expect(lastScope, equals(ExpenseScope.personal));
    });

    testWidgets(
        'shows car ChoiceChips when scope is subGroup and sub-groups exist',
        (tester) async {
      final carSubGroup = SubGroup(
        id: 'sg-1',
        tripId: _eventId,
        name: 'Car A',
        type: SubGroupType.car,
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        _wrap(scope: ExpenseScope.subGroup, subGroups: [carSubGroup]),
      );
      await tester.pump(); // let stream settle

      expect(find.text('Car A'), findsOneWidget);
    });

    testWidgets('does not show car chips when scope is global', (tester) async {
      final carSubGroup = SubGroup(
        id: 'sg-1',
        tripId: _eventId,
        name: 'Car A',
        type: SubGroupType.car,
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        _wrap(scope: ExpenseScope.global, subGroups: [carSubGroup]),
      );
      await tester.pump();

      // Car chips are only shown when scope == subGroup
      expect(find.text('Car A'), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/features/events/widgets/event_participants_card.dart';
import 'package:safar/features/groups/models/group_member_model.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

GroupMember _buildMember({required String id, required String name}) {
  return GroupMember(
    id: id,
    groupId: 'g1',
    userId: id,
    displayName: name,
    role: 'MEMBER',
    joinedAt: DateTime(2026, 1, 1),
  );
}

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(body: child),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EventParticipantsCard', () {
    final members = [
      _buildMember(id: 'p1', name: 'Alice'),
      _buildMember(id: 'p2', name: 'Bob'),
      _buildMember(id: 'p3', name: 'Carol'),
    ];

    testWidgets('renders N rows for N members', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EventParticipantsCard(
            members: members,
            selectedIds: const {'p1'},
            onSelectAllChanged: (_) {},
            onToggle: (_) {},
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
    });

    testWidgets('calls onToggle with userId when row tapped', (tester) async {
      var lastToggled = '';

      await tester.pumpWidget(
        _wrap(
          EventParticipantsCard(
            members: members,
            selectedIds: const {'p1'},
            onSelectAllChanged: (_) {},
            onToggle: (id) => lastToggled = id,
          ),
        ),
      );

      await tester.tap(find.text('Bob'));
      expect(lastToggled, equals('p2'));
    });

    testWidgets('shows checkmark (Checkbox checked) for selected member', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          EventParticipantsCard(
            members: members,
            selectedIds: const {'p1'},
            onSelectAllChanged: (_) {},
            onToggle: (_) {},
          ),
        ),
      );

      // There are multiple Checkboxes (Select All + one per member).
      // The Checkbox for Alice (p1) should be checked; Bob (p2) and Carol (p3) unchecked.
      final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
      // Index 0 = Select All (not all selected → false), 1 = Alice, 2 = Bob, 3 = Carol
      final values = checkboxes.map((c) => c.value).toList();
      expect(values[1], isTrue, reason: 'Alice (p1) should be checked');
      expect(values[2], isFalse, reason: 'Bob (p2) should be unchecked');
    });

    testWidgets('Select All checkbox checked when all members selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          EventParticipantsCard(
            members: members,
            selectedIds: const {'p1', 'p2', 'p3'},
            onSelectAllChanged: (_) {},
            onToggle: (_) {},
          ),
        ),
      );

      final selectAll = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .first;
      expect(selectAll.value, isTrue);
    });

    testWidgets('calls onSelectAllChanged when Select All tapped', (
      tester,
    ) async {
      Set<String>? received;

      await tester.pumpWidget(
        _wrap(
          EventParticipantsCard(
            members: members,
            selectedIds: const {},
            onSelectAllChanged: (ids) => received = ids,
            onToggle: (_) {},
          ),
        ),
      );

      // Tap the Select All Checkbox
      await tester.tap(find.byType(Checkbox).first);
      expect(received, isNotNull);
      expect(received, containsAll(['p1', 'p2', 'p3']));
    });
  });
}

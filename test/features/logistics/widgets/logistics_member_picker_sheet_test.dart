import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/types/event_ref.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/logistics/models/sub_group_model.dart';
import 'package:safar/features/logistics/providers/sub_group_provider.dart';
import 'package:safar/features/logistics/widgets/logistics_member_picker_sheet.dart';
import 'package:safar/features/trip/models/trip_model.dart';
import 'package:safar/core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _testEvent = Event(
  id: 'event-1',
  name: 'Desert Trip',
  type: EventType.camping,
  groupId: 'group-1',
  createdBy: 'uid-1',
  participantIds: const ['uid-1', 'uid-2', 'uid-3'],
  participantNames: const {
    'uid-1': 'Alice',
    'uid-2': 'Bob',
    'uid-3': 'Carol',
  },
  modules: const EventModules(
    ledger: true,
    gear: false,
    logistics: true,
    vault: false,
    memories: false,
  ),
  currency: 'OMR',
  createdAt: DateTime(2026, 3, 1),
);

final _emptySubGroup = SubGroup(
  id: 'sg-1',
  tripId: 'event-1',
  name: 'Car 1',
  type: SubGroupType.car,
  capacity: 4,
);

final EventRef _testEventRef = (groupId: 'group-1', eventId: 'event-1');

List<Participant> _buildParticipants() {
  return _testEvent.participantIds.map((id) {
    return Participant(
      id: id,
      tripId: 'event-1',
      role: ParticipantRole.member,
      joinedAt: DateTime(2026, 3, 1),
      displayName: _testEvent.participantNames[id],
    );
  }).toList();
}

Widget _wrap({
  SubGroup? subGroup,
  List<SubGroup> allSubGroups = const [],
  void Function(Participant)? onMemberSelected,
}) {
  final sg = subGroup ?? _emptySubGroup;
  return ProviderScope(
    overrides: [
      eventDetailProvider(_testEventRef).overrideWith(
        (_) => Stream.value(_testEvent),
      ),
      eventSubGroupsProvider(_testEventRef).overrideWith(
        (_) => Stream.value(allSubGroups),
      ),
      eventLogisticsParticipantsProvider(_testEvent).overrideWith(
        (_) => _buildParticipants(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: LogisticsMemberPickerSheet(
          subGroup: sg,
          groupId: 'group-1',
          eventId: 'event-1',
          onMemberSelected: onMemberSelected ?? (_) {},
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LogisticsMemberPickerSheet', () {
    testWidgets('renders participant list tiles when all are unassigned',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // 3 participants, none assigned → 3 ListTiles
      expect(find.byType(ListTile), findsNWidgets(3));
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
    });

    testWidgets('calls onMemberSelected when participant tile tapped',
        (tester) async {
      Participant? selected;
      await tester.pumpWidget(_wrap(onMemberSelected: (p) => selected = p));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.displayName, equals('Alice'));
    });

    testWidgets('shows "No unassigned members" when all participants assigned',
        (tester) async {
      // Put all 3 participants into a sub-group so they're all "assigned"
      final fullGroup = SubGroup(
        id: 'sg-full',
        tripId: 'event-1',
        name: 'Car Full',
        type: SubGroupType.car,
        capacity: 4,
        members: [
          SubGroupMember(
            id: 'm1',
            subGroupId: 'sg-full',
            participantId: 'uid-1',
            displayName: 'Alice',
          ),
          SubGroupMember(
            id: 'm2',
            subGroupId: 'sg-full',
            participantId: 'uid-2',
            displayName: 'Bob',
          ),
          SubGroupMember(
            id: 'm3',
            subGroupId: 'sg-full',
            participantId: 'uid-3',
            displayName: 'Carol',
          ),
        ],
      );

      await tester.pumpWidget(_wrap(allSubGroups: [fullGroup]));
      await tester.pumpAndSettle();

      expect(find.text('No unassigned members'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });
  });
}

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safar/core/types/event_ref.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/logistics/models/sub_group_model.dart';
import 'package:safar/features/logistics/providers/sub_group_provider.dart';
import 'package:safar/features/logistics/screens/logistics_screen.dart';
import 'package:safar/features/logistics/services/sub_group_service.dart';
import 'package:safar/features/trip/models/trip_model.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockSubGroupService extends Mock implements SubGroupService {}

class MockUser extends Mock implements firebase_auth.User {}

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

final _testGroup = Group(
  id: 'group-1',
  name: 'Camping Crew',
  inviteCode: 'XYZ789',
  createdBy: 'uid-creator',
  memberIds: const ['uid-creator', 'test-user-uid'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

final _testEvent = Event(
  id: 'event-1',
  name: 'Desert Trip',
  type: EventType.camping,
  groupId: 'group-1',
  createdBy: 'uid-creator',
  participantIds: const ['uid-creator', 'test-user-uid'],
  participantNames: const {
    'uid-creator': 'Alice',
    'test-user-uid': 'Bob',
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

final EventRef _testEventRef = (groupId: 'group-1', eventId: 'event-1');

final _testMember = SubGroupMember(
  id: 'member-doc-1',
  subGroupId: 'sg-1',
  participantId: 'uid-creator',
  displayName: 'Alice',
);

final _testSubGroup = SubGroup(
  id: 'sg-1',
  tripId: 'event-1',
  name: 'Car 1',
  type: SubGroupType.car,
  capacity: 4,
  members: [_testMember],
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrapLogisticsScreen({
  required MockSubGroupService mockService,
  required MockUser mockUser,
  List<SubGroup> subGroups = const [],
  List<Participant> participants = const [],
}) {
  return ProviderScope(
    overrides: [
      subGroupServiceProvider.overrideWithValue(mockService),
      eventSubGroupsProvider(_testEventRef).overrideWith(
        (ref) => Stream.value(subGroups),
      ),
      eventLogisticsParticipantsProvider(_testEvent).overrideWith(
        (ref) => participants,
      ),
      currentUserProvider.overrideWith((ref) => mockUser),
      subGroupLoadingProvider.overrideWith((ref) => false),
    ],
    child: MaterialApp(
      home: LogisticsScreen(event: _testEvent, group: _testGroup),
    ),
  );
}

void main() {
  late MockSubGroupService mockSubGroupService;
  late MockUser mockUser;

  setUp(() {
    mockSubGroupService = MockSubGroupService();
    mockUser = MockUser();
    when(() => mockUser.uid).thenReturn('test-user-uid');

    // Default stubs — tests can override as needed
    when(
      () => mockSubGroupService.removeMember(
        groupId: any(named: 'groupId'),
        eventId: any(named: 'eventId'),
        subGroupId: any(named: 'subGroupId'),
        memberId: any(named: 'memberId'),
      ),
    ).thenAnswer((_) async {});

    when(
      () => mockSubGroupService.addMember(
        groupId: any(named: 'groupId'),
        eventId: any(named: 'eventId'),
        subGroupId: any(named: 'subGroupId'),
        participantId: any(named: 'participantId'),
        displayName: any(named: 'displayName'),
      ),
    ).thenAnswer((_) async {});

    when(
      () => mockSubGroupService.deleteSubGroup(
        groupId: any(named: 'groupId'),
        eventId: any(named: 'eventId'),
        subGroupId: any(named: 'subGroupId'),
      ),
    ).thenAnswer((_) async {});

    when(
      () => mockSubGroupService.createSubGroup(
        groupId: any(named: 'groupId'),
        eventId: any(named: 'eventId'),
        name: any(named: 'name'),
        type: any(named: 'type'),
        capacity: any(named: 'capacity'),
      ),
    ).thenAnswer(
      (_) async => SubGroup(
        id: 'new-sg',
        tripId: 'event-1',
        name: 'New Car',
        type: SubGroupType.car,
        capacity: 4,
      ),
    );

    when(
      () => mockSubGroupService.updateSubGroup(
        groupId: any(named: 'groupId'),
        eventId: any(named: 'eventId'),
        subGroupId: any(named: 'subGroupId'),
        name: any(named: 'name'),
        capacity: any(named: 'capacity'),
      ),
    ).thenAnswer((_) async {});
  });

  group('LogisticsScreen — removeMember', () {
    testWidgets(
      'calls SubGroupService.removeMember with correct memberId after confirmation',
      (tester) async {
        await tester.pumpWidget(_wrapLogisticsScreen(
          mockService: mockSubGroupService,
          mockUser: mockUser,
          subGroups: [_testSubGroup],
        ));
        await tester.pumpAndSettle();

        // The member avatar shows the initial "A" for Alice.
        // Tapping the avatar (the GestureDetector in _buildMemberSlot) opens
        // a confirmation dialog with REMOVE button.
        await tester.tap(find.text('A'));
        await tester.pumpAndSettle();

        // Confirm removal
        expect(find.text('REMOVE'), findsOneWidget);
        await tester.tap(find.text('REMOVE'));
        await tester.pumpAndSettle();

        verify(
          () => mockSubGroupService.removeMember(
            groupId: 'group-1',
            eventId: 'event-1',
            subGroupId: 'sg-1',
            memberId: 'member-doc-1',
          ),
        ).called(1);
      },
    );
  });

  group('LogisticsScreen — deleteSubGroup', () {
    testWidgets(
      'calls SubGroupService.deleteSubGroup after confirming delete dialog',
      (tester) async {
        await tester.pumpWidget(_wrapLogisticsScreen(
          mockService: mockSubGroupService,
          mockUser: mockUser,
          subGroups: [_testSubGroup],
        ));
        await tester.pumpAndSettle();

        // The "more" icon button is the last IconButton in the widget tree
        // (first is the "+" add button in ModuleHeader).
        // Tapping it calls onDeleteGroup → _confirmDeleteGroup → shows dialog.
        await tester.tap(find.byType(IconButton).last);
        await tester.pumpAndSettle();

        // Confirm the delete dialog
        expect(find.text('DELETE'), findsOneWidget);
        await tester.tap(find.text('DELETE'));
        await tester.pumpAndSettle();

        verify(
          () => mockSubGroupService.deleteSubGroup(
            groupId: 'group-1',
            eventId: 'event-1',
            subGroupId: 'sg-1',
          ),
        ).called(1);
      },
    );
  });

  group('LogisticsScreen — createSubGroup', () {
    testWidgets(
      'calls SubGroupService.createSubGroup with capacity from dialog input',
      (tester) async {
        await tester.pumpWidget(_wrapLogisticsScreen(
          mockService: mockSubGroupService,
          mockUser: mockUser,
          subGroups: const [],
        ));
        await tester.pumpAndSettle();

        // The "+" add button in ModuleHeader is the first IconButton.
        // Tapping it opens the "NEW GROUP" create dialog.
        await tester.tap(find.byType(IconButton).first);
        await tester.pumpAndSettle();

        // Dialog should be open
        expect(find.text('NEW GROUP'), findsOneWidget);

        // Enter name
        final nameField = find.widgetWithText(
          TextField,
          'CAR NAME (e.g. DEFENDER 1)',
        );
        await tester.enterText(nameField, 'Defender 1');

        // Enter capacity — find by hint text and clear, then type new value
        final capacityField = find.widgetWithText(TextField, 'CAPACITY');
        await tester.enterText(capacityField, '6');

        // Tap CREATE GROUP
        await tester.tap(find.text('CREATE GROUP'));
        await tester.pumpAndSettle();

        verify(
          () => mockSubGroupService.createSubGroup(
            groupId: 'group-1',
            eventId: 'event-1',
            name: 'Defender 1',
            type: 'CAR',
            capacity: 6,
          ),
        ).called(1);
      },
    );
  });

  group('LogisticsScreen — error handling', () {
    testWidgets(
      'shows snackbar when deleteSubGroup throws',
      (tester) async {
        when(
          () => mockSubGroupService.deleteSubGroup(
            groupId: any(named: 'groupId'),
            eventId: any(named: 'eventId'),
            subGroupId: any(named: 'subGroupId'),
          ),
        ).thenThrow(Exception('network error'));

        await tester.pumpWidget(_wrapLogisticsScreen(
          mockService: mockSubGroupService,
          mockUser: mockUser,
          subGroups: [_testSubGroup],
        ));
        await tester.pumpAndSettle();

        // Open the delete dialog via the more button (last IconButton)
        await tester.tap(find.byType(IconButton).last);
        await tester.pumpAndSettle();

        // Confirm the delete dialog
        await tester.tap(find.text('DELETE'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify snackbar with error message appears
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.textContaining("Couldn't delete group"),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'shows snackbar when createSubGroup throws',
      (tester) async {
        when(
          () => mockSubGroupService.createSubGroup(
            groupId: any(named: 'groupId'),
            eventId: any(named: 'eventId'),
            name: any(named: 'name'),
            type: any(named: 'type'),
            capacity: any(named: 'capacity'),
          ),
        ).thenThrow(Exception('network error'));

        await tester.pumpWidget(_wrapLogisticsScreen(
          mockService: mockSubGroupService,
          mockUser: mockUser,
          subGroups: const [],
        ));
        await tester.pumpAndSettle();

        // Open create dialog via add button in ModuleHeader (first IconButton)
        await tester.tap(find.byType(IconButton).first);
        await tester.pumpAndSettle();

        expect(find.text('NEW GROUP'), findsOneWidget);

        final nameField = find.widgetWithText(
          TextField,
          'CAR NAME (e.g. DEFENDER 1)',
        );
        await tester.enterText(nameField, 'Test Car');

        await tester.tap(find.text('CREATE GROUP'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify snackbar with error message appears
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.textContaining("Couldn't create group"),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'shows snackbar when removeMember throws',
      (tester) async {
        when(
          () => mockSubGroupService.removeMember(
            groupId: any(named: 'groupId'),
            eventId: any(named: 'eventId'),
            subGroupId: any(named: 'subGroupId'),
            memberId: any(named: 'memberId'),
          ),
        ).thenThrow(Exception('network error'));

        await tester.pumpWidget(_wrapLogisticsScreen(
          mockService: mockSubGroupService,
          mockUser: mockUser,
          subGroups: [_testSubGroup],
        ));
        await tester.pumpAndSettle();

        // Tap member avatar initial to open remove dialog
        await tester.tap(find.text('A'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('REMOVE'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.textContaining("Couldn't remove member"),
          ),
          findsOneWidget,
        );
      },
    );
  });
}

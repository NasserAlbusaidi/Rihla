import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/ledger/widgets/edit_expense_payer_selector.dart';
import 'package:safar/features/logistics/providers/sub_group_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';
import 'package:safar/features/trip/providers/trip_provider.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockUser extends Mock implements firebase_auth.User {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _creatorUid = 'uid-creator';
const _otherUid = 'uid-other';
const _eventId = 'event-1';

final _testEvent = Event(
  id: _eventId,
  name: 'Test Event',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: _creatorUid,
  participantIds: const [_creatorUid, _otherUid],
  participantNames: const {
    _creatorUid: 'Alice',
    _otherUid: 'Bob',
  },
  modules: const EventModules(
    ledger: true,
    gear: false,
    logistics: false,
    vault: false,
    memories: false,
  ),
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

final _participants = _testEvent.participantIds.map((id) {
  return Participant(
    id: id,
    tripId: _eventId,
    role: ParticipantRole.member,
    joinedAt: _testEvent.createdAt,
    displayName: _testEvent.participantNames[id],
    avatarUrl: null,
  );
}).toList();

final _creatorParticipant = Participant(
  id: _creatorUid,
  tripId: _eventId,
  role: ParticipantRole.leader,
  joinedAt: _testEvent.createdAt,
  displayName: 'Alice',
  avatarUrl: null,
);

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _wrap({
  required firebase_auth.User? mockUser,
  String? selectedPayerId,
  ValueChanged<String?>? onPayerChanged,
}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith((ref) => mockUser),
      currentParticipantProvider(_eventId)
          .overrideWith((ref) => _creatorParticipant),
      eventLogisticsParticipantsProvider(_testEvent)
          .overrideWith((ref) => _participants),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(
        body: EditExpensePayerSelector(
          event: _testEvent,
          eventId: _eventId,
          selectedPayerId: selectedPayerId,
          onPayerChanged: onPayerChanged ?? (_) {},
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EditExpensePayerSelector', () {
    testWidgets('shows PAID BY label when current user is the event creator',
        (tester) async {
      final mockUser = MockUser();
      when(() => mockUser.uid).thenReturn(_creatorUid);

      await tester.pumpWidget(_wrap(mockUser: mockUser));
      await tester.pump();

      expect(find.text('PAID BY'), findsOneWidget);
    });

    testWidgets(
        'hides PAID BY label when current user is not the event creator',
        (tester) async {
      final mockUser = MockUser();
      when(() => mockUser.uid).thenReturn(_otherUid);

      await tester.pumpWidget(_wrap(mockUser: mockUser));
      await tester.pump();

      expect(find.text('PAID BY'), findsNothing);
    });

    testWidgets('hides PAID BY label when current user is null',
        (tester) async {
      await tester.pumpWidget(_wrap(mockUser: null));
      await tester.pump();

      expect(find.text('PAID BY'), findsNothing);
    });

    testWidgets('calls onPayerChanged when a participant is selected',
        (tester) async {
      final mockUser = MockUser();
      when(() => mockUser.uid).thenReturn(_creatorUid);

      String? lastPayerId;
      await tester.pumpWidget(
        _wrap(
          mockUser: mockUser,
          selectedPayerId: _creatorUid,
          onPayerChanged: (id) => lastPayerId = id,
        ),
      );
      await tester.pump();

      // Open the dropdown
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // Tap 'Bob' — the non-creator participant
      final bobFinder = find.text('Bob').last;
      await tester.tap(bobFinder);
      await tester.pumpAndSettle();

      expect(lastPayerId, equals(_otherUid));
    });
  });
}

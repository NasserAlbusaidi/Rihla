// test/features/events/event_settings_screen_test.dart
//
// Wave 0 stubs for EventSettingsScreen (Phase 31 ECC-02).
// All tests in this file are expected to FAIL until Plan 02 implements
// the screen. This is the RED phase of TDD.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

// ---------------------------------------------------------------------------
// Stub helpers (mirror event_command_center_test.dart pattern)
// ---------------------------------------------------------------------------

final _testGroup = Group(
  id: 'group-1',
  name: 'Adventure Crew',
  inviteCode: 'ABC123',
  createdBy: 'uid-creator',
  memberIds: const ['uid-creator'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

Event _makeEvent({
  String id = 'evt-1',
  String name = 'Summer Trip',
  EventType type = EventType.trip,
  DateTime? startDate,
  DateTime? endDate,
  String createdBy = 'uid-creator',
}) {
  return Event(
    id: id,
    name: name,
    type: type,
    groupId: 'group-1',
    createdBy: createdBy,
    participantIds: const ['uid-creator'],
    participantNames: const {'uid-creator': 'Alice'},
    modules: EventModules.forType(type),
    currency: 'OMR',
    startDate: startDate,
    endDate: endDate,
    createdAt: DateTime(2026, 3, 1),
  );
}

// _wrapSettings will be filled in Plan 02 — stub returns a placeholder widget.
// Tests fail because EventSettingsScreen class does not yet exist.
Widget _wrapSettings({required Event event, String currentUserId = 'uid-creator'}) {
  // TODO(Plan 02): replace with real EventSettingsScreen wrapper
  return const MaterialApp(home: Scaffold(body: Text('NOT_IMPLEMENTED')));
}

// ---------------------------------------------------------------------------
// Tests — all FAIL in RED phase (EventSettingsScreen does not exist)
// ---------------------------------------------------------------------------

void main() {
  group('ECC-02: EventSettingsScreen', () {
    testWidgets('renders event name in text field', (tester) async {
      final event = _makeEvent(name: 'Beach Getaway');
      await tester.pumpWidget(_wrapSettings(event: event));
      await tester.pumpAndSettle();

      // Fails: screen not implemented — shows NOT_IMPLEMENTED placeholder
      expect(find.text('Beach Getaway'), findsOneWidget);
    });

    testWidgets('Save Changes button is present', (tester) async {
      final event = _makeEvent();
      await tester.pumpWidget(_wrapSettings(event: event));
      await tester.pumpAndSettle();

      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('delete event tile is visible for creator', (tester) async {
      final event = _makeEvent(createdBy: 'uid-creator');
      await tester.pumpWidget(_wrapSettings(event: event, currentUserId: 'uid-creator'));
      await tester.pumpAndSettle();

      expect(find.text('Delete event'), findsOneWidget);
    });

    testWidgets('delete event tile is hidden for non-creator', (tester) async {
      final event = _makeEvent(createdBy: 'uid-creator');
      await tester.pumpWidget(_wrapSettings(event: event, currentUserId: 'uid-other'));
      await tester.pumpAndSettle();

      expect(find.text('Delete event'), findsNothing);
    });

    testWidgets('delete tile tap shows confirmation dialog', (tester) async {
      final event = _makeEvent(createdBy: 'uid-creator');
      await tester.pumpWidget(_wrapSettings(event: event, currentUserId: 'uid-creator'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete event'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this event?'), findsOneWidget);
    });
  });
}

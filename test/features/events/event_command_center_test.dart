import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/event_command_center.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

void main() {
  testWidgets('renders current day badge when event is in progress', (
    tester,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final event = _event(
      startDate: today.subtract(const Duration(days: 2)),
      endDate: today.add(const Duration(days: 4)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventDetailProvider((
            groupId: 'group-1',
            eventId: 'event-1',
          )).overrideWith((_) => Stream<Event?>.value(event)),
          groupDetailProvider(
            'group-1',
          ).overrideWith((_) => Stream<Group?>.value(_group)),
          eventExpensesProvider((
            groupId: 'group-1',
            eventId: 'event-1',
          )).overrideWith((_) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const EventCommandCenter(
            groupId: 'group-1',
            eventId: 'event-1',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(EventKeys.dayBadge), findsOneWidget);
    expect(find.text('Day 3 of 7'), findsOneWidget);
  });
}

Event _event({required DateTime startDate, required DateTime endDate}) {
  return Event(
    id: 'event-1',
    name: 'Marrakech',
    type: EventType.trip,
    groupId: 'group-1',
    createdBy: 'uid-1',
    participantIds: const ['uid-1', 'uid-2'],
    participantNames: const {'uid-1': 'Mona', 'uid-2': 'Nasser'},
    modules: const EventModules(),
    startDate: startDate,
    endDate: endDate,
    createdAt: startDate,
  );
}

final _group = Group(
  id: 'group-1',
  name: 'Friends',
  inviteCode: 'ABC123',
  createdBy: 'uid-1',
  memberIds: const ['uid-1', 'uid-2'],
  createdAt: DateTime(2026, 1, 1),
);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/event_command_center.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #289 — the event-hub roster must distinguish two members both named "Ahmed".
void main() {
  testWidgets('roster strip disambiguates two same-named members',
      (tester) async {
    final event = Event(
      id: 'event-1',
      name: 'Muscat weekend',
      type: EventType.trip,
      groupId: 'group-1',
      createdBy: 'uid-sara-3333',
      participantIds: const [
        'uid-sara-3333',
        'uid-ahmed-aaaa',
        'uid-ahmed-bbbb',
      ],
      participantNames: const {
        'uid-sara-3333': 'Sara Said',
        'uid-ahmed-aaaa': 'Ahmed',
        'uid-ahmed-bbbb': 'Ahmed',
      },
      modules: const EventModules(),
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 3),
      createdAt: DateTime(2026, 1, 1),
    );
    final eventRef = (groupId: event.groupId, eventId: event.id);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('uid-sara-3333'),
          eventDetailProvider(
            eventRef,
          ).overrideWith((_) => Stream<Event?>.value(event)),
          groupDetailProvider(
            event.groupId,
          ).overrideWith((_) => Stream<Group?>.value(_group)),
          eventExpensesProvider(eventRef).overrideWith((_) => Stream.value([])),
          eventSettlementsProvider(
            eventRef,
          ).overrideWith((_) => Stream.value(const [])),
          groupMembersProvider(event.groupId).overrideWith(
            (_) => Stream.value([
              _member('uid-sara-3333', 'Sara Said'),
              _member('uid-ahmed-aaaa', 'Ahmed'),
              _member('uid-ahmed-bbbb', 'Ahmed'),
            ]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventCommandCenter(groupId: event.groupId, eventId: event.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ahmed (#aaaa)'), findsOneWidget);
    expect(find.text('Ahmed (#bbbb)'), findsOneWidget);
    expect(find.text('Ahmed'), findsNothing);
  });
}

GroupMember _member(String uid, String name) => GroupMember(
      id: 'doc-$uid',
      groupId: 'group-1',
      userId: uid,
      displayName: name,
      role: 'member',
      joinedAt: DateTime(2026, 1, 1),
    );

final _group = Group(
  id: 'group-1',
  name: 'Friends',
  inviteCode: 'ABC123',
  createdBy: 'uid-sara-3333',
  memberIds: const ['uid-sara-3333', 'uid-ahmed-aaaa', 'uid-ahmed-bbbb'],
  createdAt: DateTime(2026, 1, 1),
);

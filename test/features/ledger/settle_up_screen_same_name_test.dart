import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/settle_up_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// TDD RED — cluster `settle-up-same-name-discriminator` (#196), T4.
///
/// Sibling of `settle_up_screen_test.dart` (merge at GREEN time). Event-scope
/// parity for T3: two same-named participants → the event Settle-Up tiles +
/// net rows must render distinct discriminated strings. The real resolver path
/// inside `SettleUpScreen` runs (no provider mocking of the display maps).
const _groupId = 'group-1';
const _eventId = 'event-1';
const _eventRef = (groupId: _groupId, eventId: _eventId);

final _event = Event(
  id: _eventId,
  groupId: _groupId,
  name: 'Beach Trip',
  type: EventType.trip,
  createdBy: 'uid-sam-aaaa',
  participantIds: const ['uid-sam-aaaa', 'uid-sam-bbbb'],
  participantNames: const {
    'uid-sam-aaaa': 'Sam',
    'uid-sam-bbbb': 'Sam',
  },
  modules: const EventModules(),
  createdAt: DateTime(2026, 5, 16),
);

GroupMember _member(String uid) => GroupMember(
      id: 'member-$uid',
      groupId: _groupId,
      userId: uid,
      displayName: 'Sam',
      role: uid == 'uid-sam-aaaa' ? 'CREATOR' : 'MEMBER',
      joinedAt: DateTime(2026, 5, 16),
    );

// uid-sam-aaaa pays 20.000 OMR, global/equal split → uid-sam-bbbb owes 10.000.
final _expense = Expense(
  id: 'expense-1',
  tripId: _eventId,
  payerParticipantId: 'uid-sam-aaaa',
  amount: Decimal.parse('20.000'),
  description: 'Dinner',
  scope: ExpenseScope.global,
  createdAt: DateTime(2026, 5, 16),
  createdBy: 'uid-sam-aaaa',
);

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('uid-sam-bbbb'),
      eventDetailProvider(_eventRef).overrideWith((_) => Stream.value(_event)),
      eventExpensesProvider(
        _eventRef,
      ).overrideWith((_) => Stream.value([_expense])),
      eventSettlementsProvider(
        _eventRef,
      ).overrideWith((_) => Stream.value(const <Settlement>[])),
      groupMembersProvider(_groupId).overrideWith(
        (_) => Stream.value([
          _member('uid-sam-aaaa'),
          _member('uid-sam-bbbb'),
        ]),
      ),
    ],
    child: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
}

void main() {
  testWidgets(
    'event with two same-named participants → settle-up tiles discriminated',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SettleUpScreen(groupId: _groupId, eventId: _eventId),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Sam (#aaaa)'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Sam (#bbbb)'), findsAtLeastNWidgets(1));
      expect(find.text('Sam'), findsNothing);
    },
  );
}

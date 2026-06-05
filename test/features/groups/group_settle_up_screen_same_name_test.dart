import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// TDD RED — cluster `settle-up-same-name-discriminator` (#196), T3.
///
/// Sibling of `group_settle_up_screen_test.dart` (merge at GREEN time). Drives
/// the REAL `groupBalancesProvider` (NOT overridden) by overriding only its
/// upstream stream providers, so the production `MemberNameResolver` path runs.
///
/// Two LIVE members both named "Sam"; one global/equal-split expense creates a
/// debt between them. Post-fix the transfer tile + "Each person's net" rows
/// must render distinct discriminated strings ("Sam (#…)"), never two
/// identical "Sam"s. The recorded settlement must still persist the RAW name.
const _groupId = 'grp-1';
const _eventId = 'event-1';
const _eventRef = (groupId: _groupId, eventId: _eventId);

final _group = Group(
  id: _groupId,
  name: 'Test Crew',
  inviteCode: 'TST123',
  createdBy: 'uid-sam-aaaa',
  memberIds: const ['uid-sam-aaaa', 'uid-sam-bbbb'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

GroupMember _member(String uid, String name) => GroupMember(
      id: 'member-$uid',
      groupId: _groupId,
      userId: uid,
      displayName: name,
      role: uid == 'uid-sam-aaaa' ? 'CREATOR' : 'MEMBER',
      joinedAt: DateTime(2026, 1, 1),
    );

final _event = Event(
  id: _eventId,
  name: 'Camping Weekend',
  type: EventType.camping,
  groupId: _groupId,
  createdBy: 'uid-sam-aaaa',
  participantIds: const ['uid-sam-aaaa', 'uid-sam-bbbb'],
  participantNames: const {
    'uid-sam-aaaa': 'Sam',
    'uid-sam-bbbb': 'Sam',
  },
  modules: const EventModules(),
  startDate: DateTime(2026, 3, 15),
  createdAt: DateTime(2026, 3, 10),
);

// uid-sam-aaaa pays 10.000 OMR, global/equal split across both members:
// each owes 5.000 → uid-sam-bbbb owes uid-sam-aaaa 5.000 OMR.
final _expense = Expense(
  id: 'expense-1',
  tripId: _eventId,
  payerParticipantId: 'uid-sam-aaaa',
  amount: Decimal.parse('10.000'),
  description: 'Tent',
  scope: ExpenseScope.global,
  createdAt: DateTime(2026, 3, 16),
  createdBy: 'uid-sam-aaaa',
);

Widget _wrap(Widget child, {String? currentUid}) {
  return ProviderScope(
    overrides: [
      // NOTE: groupBalancesProvider is intentionally NOT overridden — the real
      // resolver must run for this RED test to fail for the right reason.
      groupDetailProvider(_groupId).overrideWith((_) => Stream.value(_group)),
      groupMembersProvider(_groupId).overrideWith(
        (_) => Stream.value([
          _member('uid-sam-aaaa', 'Sam'),
          _member('uid-sam-bbbb', 'Sam'),
        ]),
      ),
      groupEventsProvider(_groupId).overrideWith((_) => Stream.value([_event])),
      groupSettlementsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(const <Settlement>[])),
      eventExpensesProvider(
        _eventRef,
      ).overrideWith((_) => Stream.value([_expense])),
      eventSettlementsProvider(
        _eventRef,
      ).overrideWith((_) => Stream.value(const <Settlement>[])),
      currentUserIdProvider.overrideWithValue(currentUid),
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
    'two live members named "Sam" render distinct discriminated names, '
    'not two identical "Sam"',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const GroupSettleUpScreen(groupId: _groupId)),
      );
      // Bounded pumps, NOT pumpAndSettle: the real groupBalancesProvider chain
      // emits its 5 upstream streams asynchronously (loading→data), and the
      // flutter_animate tile tickers otherwise leave a pending timer that
      // pumpAndSettle's settle-check trips on at disposal (same reason
      // pump_rihla_app avoids it). Pump enough to settle the stream chain to
      // data AND run the tile fade/slide animations to completion so no ticker
      // is pending at teardown. find.text reads the widget tree, not pixels.
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // The discriminated strings derive from the last-4 of each uid.
      expect(find.textContaining('Sam (#aaaa)'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Sam (#bbbb)'), findsAtLeastNWidgets(1));
      // No bare "Sam" should survive once both collide.
      expect(find.text('Sam'), findsNothing);

      // #263: the transfer tile's direction line is a RichText (find.text does
      // NOT traverse it by default), so the assertions above were satisfied by
      // the net rows alone while the tile rendered an ambiguous "Sam -> Sam".
      // Assert the discriminator survives INSIDE the tile.
      final tile = find.byType(GroupSettlementTile);
      expect(tile, findsOneWidget);
      expect(
        find.descendant(
          of: tile,
          matching: find.textContaining('Sam (#aaaa)', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.textContaining('Sam (#bbbb)', findRichText: true),
        ),
        findsOneWidget,
      );
    },
  );
}

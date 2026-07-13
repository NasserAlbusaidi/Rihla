import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

const _groupId = 'grp-1204';

/// #1204: two DISTINCT events, same display name AND same day, so
/// `_buildEventLabel` produces the IDENTICAL string ("Dinner — " + date) for
/// both. Before the fix, `_buildPerEventBreakdown` keyed its result map by
/// that label — the second event's slice overwrote the first's, dropping a
/// row and desyncing the displayed sum from the settlement amount (the #752
/// WYSIWYG contract).
final _dinnerA = Event(
  id: 'evt-dinner-a',
  name: 'Dinner',
  type: EventType.custom,
  groupId: _groupId,
  createdBy: 'uid-alice',
  participantIds: const ['uid-alice', 'uid-bob'],
  participantNames: const {'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  modules: const EventModules(),
  startDate: DateTime(2026, 7, 12),
  createdAt: DateTime(2026, 7, 12),
);

final _dinnerB = Event(
  id: 'evt-dinner-b',
  name: 'Dinner',
  type: EventType.custom,
  groupId: _groupId,
  createdBy: 'uid-alice',
  participantIds: const ['uid-alice', 'uid-bob'],
  participantNames: const {'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  modules: const EventModules(),
  startDate: DateTime(2026, 7, 12),
  createdAt: DateTime(2026, 7, 12),
);

Group _group() => Group(
  id: _groupId,
  name: 'Collision Crew',
  inviteCode: 'COL123',
  createdBy: 'uid-alice',
  memberIds: const ['uid-alice', 'uid-bob'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

UserBalance _bal(String id, String name, String net) => UserBalance(
  participantId: id,
  displayName: name,
  totalPaid: Decimal.zero,
  totalOwed: Decimal.zero,
  netBalance: Decimal.parse(net),
);

/// Bob owes Alice 7.000 OMR total: 4.000 earned in evt-dinner-a, 3.000 in
/// evt-dinner-b — TWO nonzero per-event slices under the same display label.
GroupBalances _balances() => (
  balances: <String, List<UserBalance>>{
    'OMR': [
      _bal('uid-alice', 'Alice', '7.000'),
      _bal('uid-bob', 'Bob', '-7.000'),
    ],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.parse('7.000')},
  eventCount: 2,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{
    'uid-alice': {
      'evt-dinner-a': {'OMR': Decimal.parse('4.000')},
      'evt-dinner-b': {'OMR': Decimal.parse('3.000')},
    },
    'uid-bob': {
      'evt-dinner-a': {'OMR': Decimal.parse('-4.000')},
      'evt-dinner-b': {'OMR': Decimal.parse('-3.000')},
    },
  },
  memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
);

Widget _wrap() {
  return ProviderScope(
    overrides: [
      groupDetailProvider(_groupId).overrideWith((_) => Stream.value(_group())),
      groupBalancesProvider(
        _groupId,
      ).overrideWith((_) => AsyncValue.data(_balances())),
      groupSettlementsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(const <Settlement>[])),
      groupEventsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value([_dinnerA, _dinnerB])),
      currentUserIdProvider.overrideWithValue('uid-bob'),
    ],
    child: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const GroupSettleUpScreen(groupId: _groupId),
      ),
    ),
  );
}

void main() {
  testWidgets(
    '#1204: two distinct same-named same-day events both render their own '
    'breakdown row — the displayed rows sum to the settlement amount '
    '(#752 WYSIWYG), never silently overwritten by a colliding label key',
    (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GroupSettlementTile));
      await tester.pumpAndSettle();

      // Both events are named "Dinner" and fall on the same day, so both
      // breakdown rows render the IDENTICAL label text — two widgets, not
      // one merged/overwritten row.
      expect(find.textContaining('Dinner'), findsNWidgets(2));

      // Both per-event slices (4.000 and 3.000, summing to the full 7.000
      // transfer) must be visible — a dropped row would silently desync the
      // displayed breakdown from the recorded settlement amount.
      expect(find.textContaining('4.000', findRichText: true), findsOneWidget);
      expect(find.textContaining('3.000', findRichText: true), findsOneWidget);
    },
  );
}

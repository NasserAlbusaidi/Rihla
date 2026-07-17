import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/keys/shared_keys.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/offline_banner.dart';

// #1255: the GROUP settle-up screen (unlike its event-scope sibling,
// settle_up_screen.dart, and EventCommandCenter) never mounted an
// OfflineBanner at all — so a device that goes offline before opening this
// screen gets no indicator until it fills the payment form and the write is
// rejected. Settlement recording is online-only (#1129, recordSettlement
// callable, no offline queue) — the user needs to know BEFORE they invest
// time filling the sheet, not after.

const _groupId = 'grp-1255';

final _group = Group(
  id: _groupId,
  name: 'Test Crew',
  inviteCode: 'TST123',
  createdBy: 'uid-alice',
  memberIds: const ['uid-alice', 'uid-bob'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

/// Bob owes Alice 7.750 OMR — a non-empty balance so the screen renders the
/// normal SettleUpPageBody (not the "All settled" EmptyStateView branch,
/// which schedules a flutter_animate ticker the CLAUDE.md gotcha warns about).
final _balancesOwed = (
  balances: <String, List<UserBalance>>{
    'OMR': [
      UserBalance(
        participantId: 'uid-alice',
        displayName: 'Alice',
        totalPaid: Decimal.parse('7.750'),
        totalOwed: Decimal.zero,
        netBalance: Decimal.parse('7.750'),
      ),
      UserBalance(
        participantId: 'uid-bob',
        displayName: 'Bob',
        totalPaid: Decimal.zero,
        totalOwed: Decimal.parse('7.750'),
        netBalance: Decimal.parse('-7.750'),
      ),
    ],
  },
  totalSpent: <String, Decimal>{'OMR': Decimal.parse('7.750')},
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
  memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
);

Widget _wrap({required ConnectivityNotifier connectivity}) {
  return ProviderScope(
    overrides: [
      groupDetailProvider(_groupId).overrideWith((_) => Stream.value(_group)),
      groupBalancesProvider(
        _groupId,
      ).overrideWith((_) => AsyncValue.data(_balancesOwed)),
      groupSettlementsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(const <Settlement>[])),
      groupEventsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(const <Event>[])),
      currentUserIdProvider.overrideWithValue('uid-bob'),
      connectivityProvider.overrideWith((ref) => connectivity),
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
  group('#1255: GroupSettleUpScreen offline banner', () {
    testWidgets(
      'shows the offline banner immediately on entry — before the payment '
      'form is ever opened',
      (tester) async {
        final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
          ..setOffline();

        await tester.pumpWidget(_wrap(connectivity: connectivity));
        await tester.pumpAndSettle();

        // No interaction with the record-payment sheet happened — the banner
        // must already be visible on first render.
        expect(find.byKey(SharedKeys.offlineBanner), findsOneWidget);
        expect(find.byType(OfflineBanner), findsOneWidget);
        expect(
          find.text("You're offline — changes will sync later"),
          findsOneWidget,
        );
      },
    );

    testWidgets('shows no offline banner content when online', (
      tester,
    ) async {
      final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
        ..setOnline();

      await tester.pumpWidget(_wrap(connectivity: connectivity));
      await tester.pumpAndSettle();

      // The OfflineBanner widget mounts (it self-gates on connectivity) but
      // renders nothing visible while online.
      expect(find.byKey(SharedKeys.offlineBanner), findsNothing);
      expect(
        find.text("You're offline — changes will sync later"),
        findsNothing,
      );
    });
  });
}

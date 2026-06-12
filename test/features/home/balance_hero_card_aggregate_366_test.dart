import 'package:decimal/decimal.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/widgets/balance_hero_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_amount.dart';

// #366 end-to-end widget proof: a SEEDED aggregate doc (the shape the
// balanceAggregator trigger writes) flows through the REAL provider chain —
// groupServiceProvider → groupBalanceAggregateProvider → homeGroupBalance
// facade → crossGroupHomeBalanceProvider — into the hero card, with ZERO
// per-event reads (no expense/settlement service is even overridden: if the
// once-path ran it would throw [core/no-app], so a rendered number IS the
// proof the aggregate served it).

void main() {
  testWidgets('hero renders the user net from a seeded aggregate doc',
      (tester) async {
    final fakeDb = FakeFirebaseFirestore();
    await fakeDb.doc('groups/g1/aggregates/balance').set({
      'schemaVersion': 2,
      'currency': 'OMR',
      'netMilliByCurrency': {
        'OMR': {'uid-a': 12500, 'uid-b': -12500},
      },
      'perEventNetMilliByCurrency': {
        'e1': {
          'OMR': {'uid-a': 12500, 'uid-b': -12500},
        },
      },
      'eventCount': 1,
      'degraded': false,
      'sourceTimeMs': 1000,
    });

    final group = Group(
      id: 'g1',
      name: 'Group g1',
      inviteCode: 'AAAAAA',
      createdBy: 'uid-a',
      memberIds: const ['uid-a', 'uid-b'],
      createdAt: DateTime(2025),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupServiceProvider.overrideWith(
            (ref) => GroupService.withFirestore(ref, fakeDb),
          ),
          connectivityProvider.overrideWith(
            (ref) => ConnectivityNotifier(
              connectivityProbe: () async => null,
              startPeriodicChecks: false,
            )..setOnline(),
          ),
          currentUserIdProvider.overrideWith((_) => 'uid-a'),
          userGroupsProvider.overrideWith((_) => Stream.value([group])),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: BalanceHeroCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // netMilliByCurrency.OMR 12500 → 12.500 OMR owed to uid-a.
    final amounts = tester
        .widgetList<RAmount>(find.byType(RAmount))
        .map((w) => w.value)
        .toList();
    expect(amounts, contains(Decimal.parse('12.5')));
    expect(find.text('Balance unavailable'), findsNothing);
  });
}

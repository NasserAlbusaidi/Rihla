import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

/// #261 PR-B — the cross-group hero buckets per currency (there is no FX, so
/// amounts in different currencies are NEVER summed). These tests exercise the
/// currency axis directly; the all-OMR behaviour is the single-bucket case.
void main() {
  const uid = 'uid-user';

  Group group(String id, String currency) => Group(
    id: id,
    name: 'Group $id',
    inviteCode: 'AAAAAA',
    createdBy: uid,
    memberIds: const [uid],
    currency: currency,
    createdAt: DateTime(2025, 1, 1),
  );

  // #382 PR-1: the currency now lives IN the balance record (the bucket
  // key) — the provider derives byCurrency from it, not from group.currency.
  GroupBalances balancesWithNet(Decimal net, String currency) => (
    balances: {
      currency: [
        UserBalance(
          participantId: uid,
          displayName: 'User',
          totalPaid: Decimal.zero,
          totalOwed: Decimal.zero,
          netBalance: net,
        ),
      ],
    },
    totalSpent: <String, Decimal>{},
    eventCount: 0,
    perEventBreakdown: const {},
    memberNames: const {},
    memberRawNames: <String, String>{},
  );

  /// groupId -> (currency, net). Builds the container + pumps the live provider.
  Future<CrossGroupBalance> compute(
    List<({String id, String currency, Decimal net})> groups,
  ) async {
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith((_) => uid),
        userGroupsProvider.overrideWith(
          (_) => Stream.value([for (final g in groups) group(g.id, g.currency)]),
        ),
        for (final g in groups)
          groupBalancesProvider(
            g.id,
          ).overrideWith((_) => AsyncValue.data(balancesWithNet(g.net, g.currency))),
      ],
    );
    addTearDown(container.dispose);
    container.listen(crossGroupBalanceProvider, (_, _) {}, fireImmediately: true);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return container.read(crossGroupBalanceProvider).valueOrNull!;
  }

  Decimal d(String s) => Decimal.parse(s);

  test('single OMR group => one OMR bucket (today\'s all-OMR case)', () async {
    final b = await compute([(id: 'g1', currency: 'OMR', net: d('10.000'))]);
    expect(b.byCurrency.length, 1);
    expect(b.byCurrency.single.currency, 'OMR');
    expect(b.byCurrency.single.net, d('10.000'));
    expect(b.byCurrency.single.owedToUser, d('10.000'));
    expect(b.byCurrency.single.userOwes, Decimal.zero);
  });

  test('single USD group => one USD bucket', () async {
    final b = await compute([(id: 'g1', currency: 'USD', net: d('12.34'))]);
    expect(b.byCurrency.single.currency, 'USD');
    expect(b.byCurrency.single.net, d('12.34'));
  });

  test('OMR + USD => two buckets, NO cross-currency sum', () async {
    final b = await compute([
      (id: 'g1', currency: 'OMR', net: d('10.000')),
      (id: 'g2', currency: 'USD', net: d('-10.00')),
    ]);
    expect(b.byCurrency.length, 2);
    // GCC-first: OMR before USD.
    expect(b.byCurrency.map((e) => e.currency).toList(), ['OMR', 'USD']);
    final omr = b.byCurrency.firstWhere((e) => e.currency == 'OMR');
    final usd = b.byCurrency.firstWhere((e) => e.currency == 'USD');
    expect(omr.net, d('10.000'));
    expect(omr.owedToUser, d('10.000'));
    expect(usd.net, d('-10.00'));
    expect(usd.userOwes, d('10.00'));
    // The currency-blind bug would have summed these to net 0 — prove it doesn't.
    expect(b.byCurrency.any((e) => e.net == Decimal.zero), isFalse);
  });

  test('OMR + USD + JPY => three buckets, GCC-first order', () async {
    final b = await compute([
      (id: 'g3', currency: 'JPY', net: d('1200')),
      (id: 'g1', currency: 'OMR', net: d('10.000')),
      (id: 'g2', currency: 'USD', net: d('-40.00')),
    ]);
    expect(b.byCurrency.map((e) => e.currency).toList(), ['OMR', 'USD', 'JPY']);
  });

  test('two OMR groups +5/-5 => one OMR bucket net 0 but SHOWN (owed/owes nonzero)', () async {
    final b = await compute([
      (id: 'g1', currency: 'OMR', net: d('5.000')),
      (id: 'g2', currency: 'OMR', net: d('-5.000')),
    ]);
    expect(b.byCurrency.length, 1);
    expect(b.byCurrency.single.net, Decimal.zero);
    expect(b.byCurrency.single.owedToUser, d('5.000'));
    expect(b.byCurrency.single.userOwes, d('5.000'));
  });

  test('fully-settled single group => empty byCurrency (all settled)', () async {
    final b = await compute([(id: 'g1', currency: 'OMR', net: Decimal.zero)]);
    expect(b.byCurrency, isEmpty);
    expect(b.groupCount, 1);
  });

  test('no groups => empty byCurrency', () async {
    final b = await compute([]);
    expect(b.byCurrency, isEmpty);
    expect(b.groupCount, 0);
  });

  // #70: the all-settled hero currency — the single distinct group currency, or
  // null when zero/multiple distinct currencies (→ agnostic zero, no OMR assumed).
  // (No group() wrapper: the local group(id, currency) helper shadows the
  // flutter_test group().)
  Future<String?> settledCurrency(List<String> currencies) async {
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWith((_) => uid),
        userGroupsProvider.overrideWith(
          (_) => Stream.value([
            for (var i = 0; i < currencies.length; i++)
              group('g$i', currencies[i]),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(
      settledDisplayCurrencyProvider,
      (_, _) {},
      fireImmediately: true,
    );
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return container.read(settledDisplayCurrencyProvider);
  }

  test('settledDisplayCurrencyProvider: single USD group => USD', () async {
    expect(await settledCurrency(['USD']), 'USD');
  });

  test('settledDisplayCurrencyProvider: two OMR groups => OMR', () async {
    expect(await settledCurrency(['OMR', 'OMR']), 'OMR');
  });

  test('settledDisplayCurrencyProvider: OMR + USD => null', () async {
    expect(await settledCurrency(['OMR', 'USD']), isNull);
  });

  test('settledDisplayCurrencyProvider: no groups => null', () async {
    expect(await settledCurrency([]), isNull);
  });
}

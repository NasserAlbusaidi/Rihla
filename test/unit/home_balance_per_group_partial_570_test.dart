import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';

// ---------------------------------------------------------------------------
// #570 — cross-group hero degrades a single unreadable GROUP to a partial drop.
//
// crossGroupHomeBalanceProvider used to early-return AsyncValue.error the moment
// ANY one group's facade was in error → the WHOLE home hero blanked ("Balance
// unavailable") even when every other group read fine. This mirrors the #244
// per-EVENT OR-drop at the GROUP level: drop the unreadable group, set partial,
// sum the survivors — UNLESS every group failed (then stay loud-safe).
//
// We override homeGroupBalanceProvider per group directly (the faithful way to
// drive the fold's error/loading/data branches without fighting the
// aggregate/once chooser).
// ---------------------------------------------------------------------------

extension _SingleCurrencyAccess on CrossGroupBalance {
  CurrencyBalance? get _only => byCurrency.isEmpty ? null : byCurrency.single;
  Decimal get net => _only?.net ?? Decimal.zero;
  Decimal get userOwes => _only?.userOwes ?? Decimal.zero;
}

Group _group(String id) => Group(
      id: id,
      name: 'Group $id',
      inviteCode: 'AAAAAA',
      createdBy: 'uid-a',
      memberIds: const ['uid-a', 'uid-b'],
      createdAt: DateTime(2025, 1, 1),
    );

AsyncValue<HomeGroupBalance> _ok(Map<String, Decimal> userNet) =>
    AsyncValue.data((
      userNet: userNet,
      userPerEventNet: const <String, Map<String, Decimal>>{},
      eventCount: 1,
      partial: false,
      fromAggregate: true,
    ));

AsyncValue<HomeGroupBalance> _okPartial(Map<String, Decimal> userNet) =>
    AsyncValue.data((
      userNet: userNet,
      userPerEventNet: const <String, Map<String, Decimal>>{},
      eventCount: 1,
      partial: true, // a within-group per-event drop (#244)
      fromAggregate: false,
    ));

final _err = AsyncValue<HomeGroupBalance>.error(
  Exception('group read denied'),
  StackTrace.empty,
);

ProviderContainer _make(Map<String, AsyncValue<HomeGroupBalance>> facades) {
  return ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWith((_) => 'uid-a'),
      userGroupsProvider.overrideWith(
        (_) => Stream.value([for (final id in facades.keys) _group(id)]),
      ),
      for (final entry in facades.entries)
        homeGroupBalanceProvider(entry.key).overrideWith((_) => entry.value),
    ],
  );
}

Future<AsyncValue<CrossGroupBalanceOnce>> _readRaw(
  ProviderContainer container,
) async {
  final sub = container.listen(crossGroupHomeBalanceProvider, (_, _) {});
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  final value = container.read(crossGroupHomeBalanceProvider);
  sub.close();
  return value;
}

void main() {
  const d = Decimal.fromInt;

  group('crossGroupHomeBalanceProvider per-GROUP partial (#570)', () {
    test('one group errors among many → dropped + partial, NOT a blank hero',
        () async {
      final container = _make({
        'g1': _ok({'OMR': d(-10)}),
        'g2': _err,
      });
      addTearDown(container.dispose);

      final v = await _readRaw(container);

      expect(v.hasError, isFalse,
          reason: 'a single unreadable group must NOT blank the whole hero');
      final r = v.requireValue;
      expect(r.partial, isTrue, reason: 'g2 dropped → flag incomplete');
      expect(r.balance.net, d(-10), reason: 'survivor g1 only');
      expect(r.balance.userOwes, d(10));
      expect(r.balance.byCurrency.single.currency, 'OMR');
    });

    test('EVERY group errors → still loud-safe (Balance unavailable)', () async {
      final container = _make({
        'g1': _err,
        'g2': _err,
      });
      addTearDown(container.dispose);

      final v = await _readRaw(container);

      expect(v.hasError, isTrue,
          reason: 'total blackout: a zero "all settled" hero would be a lie');
    });

    test('no group errors → partial false, both groups summed', () async {
      final container = _make({
        'g1': _ok({'OMR': d(-10)}),
        'g2': _ok({'OMR': d(-30)}),
      });
      addTearDown(container.dispose);

      final v = await _readRaw(container);

      expect(v.hasError, isFalse);
      final r = v.requireValue;
      expect(r.partial, isFalse);
      expect(r.balance.net, d(-40));
    });

    test('a still-loading group keeps the whole hero loading (skeleton)',
        () async {
      final container = _make({
        'g1': _ok({'OMR': d(-10)}),
        'g2': const AsyncValue<HomeGroupBalance>.loading(),
      });
      addTearDown(container.dispose);

      final v = await _readRaw(container);

      expect(v.isLoading, isTrue,
          reason: 'never a premature partial-zero while a group still loads');
    });

    test('within-group per-event partial still ORs into the cross flag',
        () async {
      final container = _make({
        'g1': _ok({'OMR': d(-10)}),
        'g2': _okPartial({'OMR': d(-5)}),
      });
      addTearDown(container.dispose);

      final v = await _readRaw(container);

      final r = v.requireValue;
      expect(r.partial, isTrue, reason: 'g2 carried a per-event drop');
      expect(r.balance.net, d(-15), reason: 'both groups still summed');
    });

    // Orthogonal axis (verification principle 7): currency. Dropping a USD group
    // must not contaminate the surviving OMR bucket nor leave a phantom USD slot.
    test('dropping a different-currency group leaves only the survivor currency',
        () async {
      final container = _make({
        'g1': _ok({'OMR': d(-10)}), // survives
        'g2': _err, // had USD balance, now unreadable
      });
      addTearDown(container.dispose);

      final v = await _readRaw(container);

      final r = v.requireValue;
      expect(r.partial, isTrue);
      expect(r.balance.byCurrency.length, 1,
          reason: 'no phantom USD bucket from the dropped group');
      expect(r.balance.byCurrency.single.currency, 'OMR');
    });

    test('two healthy currencies stay bucketed separately (no contamination)',
        () async {
      final container = _make({
        'g1': _ok({'OMR': d(-10)}),
        'g2': _ok({'USD': d(5)}),
      });
      addTearDown(container.dispose);

      final v = await _readRaw(container);

      final r = v.requireValue;
      expect(r.partial, isFalse);
      expect(r.balance.byCurrency.length, 2);
      expect(
        r.balance.byCurrency.map((b) => b.currency).toSet(),
        {'OMR', 'USD'},
      );
    });
  });
}

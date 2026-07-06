// #990 — restore-breadcrumb-scoped deviceName self-heal.
//
// A restored account on a fresh device gets its profile name back from its
// own Firestore member doc — but ONLY while the `recovery_name_seed_uid`
// breadcrumb (written by surfaceRecoveryOutcome's VERIFIED success arm)
// matches the current uid. The two Gate P1 pins live here: a shadow
// claimant — anon or later linked-in-place — never has a breadcrumb, so the
// heal never promotes a creator-authored per-group name to the device-wide
// identity (#293). Spec: docs/plans/2026-07-06-devicename-selfheal.md.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/providers/device_name_self_heal_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';

// The literal key is asserted (not the constant) so a silent rename of the
// breadcrumb key — which would orphan every in-flight breadcrumb — fails here.
const _seedKey = 'recovery_name_seed_uid';
const _nameKey = 'settings_device_name';
const _uid = 'restored-uid';

Group _makeGroup(String id) => Group(
  id: id,
  name: 'Group $id',
  inviteCode: 'ABC123',
  createdBy: 'someone',
  memberIds: const [_uid, 'other'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  late List<(String, List<String>)> fetchCalls;

  setUp(() {
    fetchCalls = [];
  });

  FetchOwnMemberName recordingFetch(String? result) => (uid, groupIds) async {
    fetchCalls.add((uid, groupIds));
    return result;
  };

  Future<ProviderContainer> pumpHeal(
    WidgetTester tester, {
    required Map<String, Object> initialPrefs,
    String? currentUid = _uid,
    bool durable = true,
    List<Group>? groups,
    FetchOwnMemberName? fetch,
    StateProvider<String?>? uidState,
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceLocalesProvider.overrideWithValue(const [Locale('en')]),
        userGroupsProvider.overrideWith(
          (ref) => Stream.value(groups ?? [_makeGroup('g1')]),
        ),
        isDurableUserProvider.overrideWithValue(durable),
        if (uidState != null)
          currentUserIdProvider.overrideWith((ref) => ref.watch(uidState))
        else
          currentUserIdProvider.overrideWithValue(currentUid),
        fetchOwnMemberNameProvider.overrideWithValue(
          fetch ?? recordingFetch('Nasser'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            ref.watch(deviceNameSelfHealProvider);
            return const SizedBox();
          },
        ),
      ),
    );
    // First frame commits the postFrameCallback; extra pumps let the groups
    // stream emit, the rebuilt provider's postFrame run, and the async fetch
    // + seed microtasks settle.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets(
    'test 4: breadcrumb == uid + empty name + durable + own member doc '
    '→ deviceName seeded AND breadcrumb cleared',
    (tester) async {
      final container = await pumpHeal(
        tester,
        initialPrefs: {_seedKey: _uid},
      );

      expect(container.read(settingsProvider).deviceName, 'Nasser');
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(_nameKey), 'Nasser');
      expect(prefs.getString(_seedKey), isNull);
      expect(fetchCalls, hasLength(1));
      expect(fetchCalls.single.$1, _uid);
      expect(fetchCalls.single.$2, ['g1']);
    },
  );

  testWidgets(
    'test 6: non-empty deviceName with a breadcrumb present → fetch never '
    'invoked, breadcrumb cleared',
    (tester) async {
      final container = await pumpHeal(
        tester,
        initialPrefs: {_seedKey: _uid, _nameKey: 'Already Set'},
      );

      expect(container.read(settingsProvider).deviceName, 'Already Set');
      expect(fetchCalls, isEmpty);
      expect(
        container.read(sharedPreferencesProvider).getString(_seedKey),
        isNull,
      );
    },
  );

  testWidgets(
    'test 7a: cacheIsolationProvider == true → no attempt, breadcrumb '
    'untouched',
    (tester) async {
      SharedPreferences.setMockInitialValues({_seedKey: _uid});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceLocalesProvider.overrideWithValue(const [Locale('en')]),
          userGroupsProvider.overrideWith(
            (ref) => Stream.value([_makeGroup('g1')]),
          ),
          isDurableUserProvider.overrideWithValue(true),
          currentUserIdProvider.overrideWithValue(_uid),
          fetchOwnMemberNameProvider.overrideWithValue(
            recordingFetch('Nasser'),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(cacheIsolationProvider.notifier).state = true;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              ref.watch(deviceNameSelfHealProvider);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(fetchCalls, isEmpty);
      expect(container.read(settingsProvider).deviceName, '');
      expect(prefs.getString(_seedKey), _uid);
    },
  );

  testWidgets(
    'test 7b: isolation engaging AFTER the fetch resolves → seed dropped '
    'silently (no throw), breadcrumb retained',
    (tester) async {
      final gate = Completer<String?>();
      var calls = 0;
      final container = await pumpHeal(
        tester,
        initialPrefs: {_seedKey: _uid},
        fetch: (uid, groupIds) {
          calls++;
          return gate.future;
        },
      );
      expect(calls, 1); // fetch launched while un-isolated

      container.read(cacheIsolationProvider.notifier).state = true;
      gate.complete('Nasser');
      await tester.pump();
      await tester.pump();

      expect(container.read(settingsProvider).deviceName, '');
      expect(
        container.read(sharedPreferencesProvider).getString(_seedKey),
        _uid,
      );
    },
  );

  testWidgets(
    'test 8a: NO breadcrumb → fetch never invoked, even for a durable user '
    'with groups and an empty name (link-after-claim pin, Gate round 2)',
    (tester) async {
      final container = await pumpHeal(tester, initialPrefs: {});

      expect(fetchCalls, isEmpty);
      expect(container.read(settingsProvider).deviceName, '');
    },
  );

  testWidgets(
    'test 8b: anonymous user without a breadcrumb → fetch never invoked '
    '(shadow-claimant pin, Gate round 1)',
    (tester) async {
      final container = await pumpHeal(
        tester,
        initialPrefs: {},
        durable: false,
      );

      expect(fetchCalls, isEmpty);
      expect(container.read(settingsProvider).deviceName, '');
    },
  );

  testWidgets(
    'test 9: breadcrumb uid != current uid (both non-null) → fetch never '
    'invoked, breadcrumb cleared (stale-swap pin)',
    (tester) async {
      final container = await pumpHeal(
        tester,
        initialPrefs: {_seedKey: 'older-swap-uid'},
      );

      expect(fetchCalls, isEmpty);
      expect(container.read(settingsProvider).deviceName, '');
      expect(
        container.read(sharedPreferencesProvider).getString(_seedKey),
        isNull,
      );
    },
  );

  testWidgets(
    'test 9b: current uid still NULL (auth resolving) → breadcrumb RETAINED, '
    'no fetch; once the uid resolves the heal proceeds (round-3 [P1] pin)',
    (tester) async {
      final uidState = StateProvider<String?>((_) => null);
      final container = await pumpHeal(
        tester,
        initialPrefs: {_seedKey: _uid},
        uidState: uidState,
      );

      expect(fetchCalls, isEmpty, reason: 'must wait, not fetch, on null uid');
      expect(
        container.read(sharedPreferencesProvider).getString(_seedKey),
        _uid,
        reason: 'a null uid must RETAIN the breadcrumb, never clear it',
      );

      // Auth resolves; the explicit revision bump re-evaluates the heal (in
      // production the groups stream re-emission does the same).
      container.read(uidState.notifier).state = _uid;
      container.read(deviceNameSeedRevisionProvider.notifier).state++;
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(container.read(settingsProvider).deviceName, 'Nasser');
      expect(
        container.read(sharedPreferencesProvider).getString(_seedKey),
        isNull,
      );
    },
  );

  testWidgets(
    'test 9c-terminal: fetch returns null (definitive empty) → breadcrumb '
    'CLEARED without seeding',
    (tester) async {
      final container = await pumpHeal(
        tester,
        initialPrefs: {_seedKey: _uid},
        fetch: recordingFetch(null),
      );

      expect(fetchCalls, hasLength(1));
      expect(container.read(settingsProvider).deviceName, '');
      expect(
        container.read(sharedPreferencesProvider).getString(_seedKey),
        isNull,
      );
    },
  );

  testWidgets(
    'test 9c-transient: a THROWING fetch retains the breadcrumb',
    (tester) async {
      final container = await pumpHeal(
        tester,
        initialPrefs: {_seedKey: _uid},
        fetch: (uid, groupIds) async {
          fetchCalls.add((uid, groupIds));
          throw Exception('network down');
        },
      );

      expect(fetchCalls, hasLength(1));
      expect(container.read(settingsProvider).deviceName, '');
      expect(
        container.read(sharedPreferencesProvider).getString(_seedKey),
        _uid,
        reason: 'transient failure must retain the breadcrumb for retry',
      );
    },
  );

  testWidgets(
    'test 10: in-flight guard — re-evaluations while the fetch is pending '
    'run it ONCE; a THROWING fetch resets the guard so a later emission '
    'retries',
    (tester) async {
      final gate = Completer<String?>();
      var calls = 0;
      var shouldThrow = true;
      final container = await pumpHeal(
        tester,
        initialPrefs: {_seedKey: _uid},
        fetch: (uid, groupIds) async {
          calls++;
          if (shouldThrow) {
            await gate.future;
            throw Exception('transient');
          }
          return 'Nasser';
        },
      );
      expect(calls, 1);

      // Two re-evaluations while the first fetch is still pending.
      container.read(deviceNameSeedRevisionProvider.notifier).state++;
      await tester.pump();
      container.read(deviceNameSeedRevisionProvider.notifier).state++;
      await tester.pump();
      expect(calls, 1, reason: 'in-flight guard must dedupe re-evaluations');

      // First fetch fails → guard resets → a later emission retries.
      gate.complete(null);
      await tester.pump();
      shouldThrow = false;
      container.read(deviceNameSeedRevisionProvider.notifier).state++;
      await tester.pump();
      await tester.pump();

      expect(calls, 2, reason: 'a failed fetch must allow a retry');
      expect(container.read(settingsProvider).deviceName, 'Nasser');
      expect(
        container.read(sharedPreferencesProvider).getString(_seedKey),
        isNull,
      );
    },
  );

  // -------------------------------------------------------------------------
  // Test 5: the REAL fetcher against FakeFirebaseFirestore — tombstones and
  // invalid names are skipped; groups are tried in list order; an exhausted
  // roster returns null (the terminal answer).
  // -------------------------------------------------------------------------

  group('fetchOwnMemberNameWith', () {
    test(
      'skips tombstoned and invalid-name docs, takes the first qualifying '
      'doc in group order, matches by userId FIELD not doc id',
      () async {
        final db = FakeFirebaseFirestore();
        // g1: a tombstoned doc and an invalid (33-char) name — both skipped.
        await db
            .collection('groups')
            .doc('g1')
            .collection('members')
            .doc('uuid-legacy')
            .set({
              'userId': _uid,
              'displayName': 'Old Me',
              'isTombstone': true,
            });
        await db
            .collection('groups')
            .doc('g1')
            .collection('members')
            .doc('uuid-legacy-2')
            .set({'userId': _uid, 'displayName': 'A' * 33});
        // g2: someone else's doc (must not match) + the user's valid doc,
        // uuid-keyed to pin FIELD matching.
        await db
            .collection('groups')
            .doc('g2')
            .collection('members')
            .doc('other-uid')
            .set({'userId': 'other-uid', 'displayName': 'Not Me'});
        await db
            .collection('groups')
            .doc('g2')
            .collection('members')
            .doc('uuid-mine')
            .set({'userId': _uid, 'displayName': '  Nasser   Albusaidi '});

        final fetch = fetchOwnMemberNameWith(db);
        final name = await fetch(_uid, ['g1', 'g2']);

        expect(name, 'Nasser Albusaidi', reason: 'normalized before return');
      },
    );

    test('returns null when no group holds a qualifying doc', () async {
      final db = FakeFirebaseFirestore();
      await db
          .collection('groups')
          .doc('g1')
          .collection('members')
          .doc('d')
          .set({'userId': _uid, 'displayName': 'Ghost', 'isTombstone': true});

      final fetch = fetchOwnMemberNameWith(db);
      expect(await fetch(_uid, ['g1']), isNull);
    });
  });
}

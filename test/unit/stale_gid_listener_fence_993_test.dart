import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';

/// #993 — fence guard: after an auth swap/restore, the home provider graph must
/// NOT open child listeners (aggregate / members / events / settlements) for any
/// group id absent from the RESTORED uid's live `watchUserGroups(uid)` result.
///
/// This drives the REAL [userGroupsProvider] off a [FakeFirebaseFirestore] (it
/// is deliberately NOT overridden) so the fence is PROVEN, not assumed: the only
/// thing that can put a group's child providers into the graph is the
/// `memberIds arrayContains uid` query, and a stale group owned by a DIFFERENT
/// uid simply never appears in it. If a future change ever fed a cached/stale
/// gid into the fold without going through the live-groups list, the
/// `getAllProviderElements()` assertions below turn red.
///
/// Direct listener-count introspection isn't exposed by the fake — the faithful
/// achievable proof is "no provider element exists for the stale gid's child
/// families," which is exactly what an open listener would require.
ConnectivityNotifier _online() {
  final notifier = ConnectivityNotifier(
    connectivityProbe: () async => null,
    startPeriodicChecks: false,
  );
  notifier.setOnline();
  return notifier;
}

Map<String, dynamic> _groupDoc({
  required String name,
  required String owner,
  required List<String> memberIds,
  required DateTime createdAt,
}) => {
  'name': name,
  'inviteCode': name.toUpperCase().padRight(6, 'X').substring(0, 6),
  'createdBy': owner,
  'memberIds': memberIds,
  'currency': 'OMR',
  'createdAt': Timestamp.fromDate(createdAt),
};

/// A valid v2 aggregate doc so the ONLINE facade resolves [gLive] on the
/// aggregate branch — keeping it off the once-path (no expense/settlement
/// service wiring needed) while still opening [gLive]'s aggregate listener.
Map<String, dynamic> _aggregateDoc(String uid) => {
  'schemaVersion': 2,
  'currency': 'OMR',
  'netMilliByCurrency': {
    'OMR': {uid: 0},
  },
  'perEventNetMilliByCurrency': const <String, dynamic>{},
  'eventCount': 0,
  'degraded': false,
  'sourceTimeMs': 1000,
};

Future<void> _settle(ProviderContainer container) async {
  for (var i = 0; i < 16; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  const gLive = 'g-live';
  const gStale = 'g-stale';
  const uidRestored = 'uid-restored';
  const uidOther = 'uid-other';

  late FakeFirebaseFirestore fakeDb;

  setUp(() async {
    fakeDb = FakeFirebaseFirestore();
    // gLive belongs to the restored uid; gStale belongs to a DIFFERENT uid and
    // must never enter the restored uid's provider graph.
    await fakeDb.doc('groups/$gLive').set(
          _groupDoc(
            name: 'Live',
            owner: uidRestored,
            memberIds: const [uidRestored],
            createdAt: DateTime(2025, 1, 2),
          ),
        );
    await fakeDb.doc('groups/$gStale').set(
          _groupDoc(
            name: 'Stale',
            owner: uidOther,
            memberIds: const [uidOther],
            createdAt: DateTime(2025, 1, 1),
          ),
        );
    await fakeDb
        .doc('groups/$gLive/aggregates/balance')
        .set(_aggregateDoc(uidRestored));
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        // Real GroupService on the fake DB — the fold's query runs for real.
        groupServiceProvider.overrideWith(
          (ref) => GroupService.withFirestore(ref, fakeDb),
        ),
        connectivityProvider.overrideWith((_) => _online()),
        // Restored session = uidRestored, on BOTH auth surfaces the graph reads
        // (currentUserIdProvider for the folds, firebaseUserProvider for
        // userGroupsProvider). Neither is safe to touch FirebaseAuth in a unit
        // test, so both are pinned to the restored uid.
        currentUserIdProvider.overrideWith((_) => uidRestored),
        firebaseUserProvider.overrideWith(
          (_) => Stream<User?>.value(
            MockUser(uid: uidRestored, isAnonymous: true),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
      'home fold opens child listeners ONLY for the restored uid\'s live groups '
      '— a stale gid owned by another uid never reaches a child provider',
      () async {
    final container = makeContainer();
    // Keep the cross-group fold subscribed so its watched descendants stay in
    // the element graph (this is exactly the home-dashboard subscription).
    container.listen(crossGroupHomeBalanceProvider, (_, _) {}, fireImmediately: true);
    await _settle(container);

    // The fence mechanism: the live-groups query returns ONLY the restored uid's
    // group. gStale (owned by uidOther) is structurally excluded.
    final liveGroupIds =
        (container.read(userGroupsProvider).valueOrNull ?? const [])
            .map((g) => g.id)
            .toList();
    expect(liveGroupIds, [gLive]);

    final origins =
        container.getAllProviderElements().map((e) => e.origin).toSet();

    // Positive control: the fold DID reach gLive's child listeners, so the
    // negative assertions below are meaningful (not vacuously true).
    expect(
      origins.contains(homeGroupBalanceProvider(gLive)),
      isTrue,
      reason: 'the live group must be folded and open its balance facade',
    );
    expect(
      origins.contains(groupBalanceAggregateProvider(gLive)),
      isTrue,
      reason: 'the live group must open its aggregate listener',
    );

    // The fence: NO child listener of any kind opened for the stale gid.
    expect(origins.contains(homeGroupBalanceProvider(gStale)), isFalse);
    expect(origins.contains(groupBalanceAggregateProvider(gStale)), isFalse);
    expect(origins.contains(groupBalancesOnceProvider(gStale)), isFalse);
    expect(origins.contains(groupMembersProvider(gStale)), isFalse);
  });
}

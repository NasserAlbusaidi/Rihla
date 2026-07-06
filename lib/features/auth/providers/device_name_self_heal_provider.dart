import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/cache_isolation_controller.dart';
import '../../../core/utils/name_validators.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../services/recovery_outcome.dart';
import 'auth_provider.dart';

/// Resolves the restored user's own display name from their member docs, or
/// returns `null` ONLY as a definitive answer (every group queried
/// successfully and no doc passed the tombstone + valid-name filter). Any
/// transient failure (network / permission / timeout) THROWS — the caller
/// maps a throw to retain-and-retry, a `null` to clear-without-seeding.
typedef FetchOwnMemberName =
    Future<String?> Function(String uid, List<String> groupIds);

/// Real fetcher factory. Member docs are matched by the `userId` FIELD, never
/// doc id (mixed keying: client docs uid-keyed, server shadows + legacy
/// creators uuid-keyed). `limit(5)` bounds the legacy dual-doc case (a
/// uuid-keyed legacy creator doc AND a uid-keyed recovery copy can coexist).
/// `isShadow` is deliberately NOT filtered: a doc matching `userId == uid` is
/// never an unclaimed shadow, and a claimed one carries the user's
/// balance-owning name (spec D2). Groups arrive in `watchUserGroups` order
/// (createdAt DESC), so the seeded name is deterministically the user's name
/// in their newest qualifying group.
FetchOwnMemberName fetchOwnMemberNameWith(FirebaseFirestore db) {
  return (String uid, List<String> groupIds) async {
    for (final gid in groupIds) {
      final snap = await db
          .collection('groups')
          .doc(gid)
          .collection('members')
          .where('userId', isEqualTo: uid)
          .limit(5)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['isTombstone'] == true) continue;
        final raw = data['displayName'];
        if (raw is! String) continue;
        final normalized = normalizeDisplayName(raw);
        if (displayNameValidationError(normalized) != null) continue;
        return normalized;
      }
    }
    return null;
  };
}

/// Injectable fetch (tests override it, mirroring
/// `recoveryOutcomeProbeProvider`). `FirebaseConfig.firestore` is resolved
/// lazily inside the call so an un-overridden provider never throws
/// `[core/no-app]` at build time in tests.
final fetchOwnMemberNameProvider = Provider<FetchOwnMemberName>(
  (ref) =>
      (uid, groupIds) => fetchOwnMemberNameWith(
        FirebaseConfig.firestore,
      )(uid, groupIds),
);

/// Bumped by `recoveryOutcomeNoticeProvider` once `surfaceRecoveryOutcome`
/// completes, so the heal re-evaluates explicitly after the breadcrumb lands
/// instead of relying on a groups emission happening to arrive afterwards.
final deviceNameSeedRevisionProvider = StateProvider<int>((_) => 0);

/// Survives provider rebuilds (unlike a local flag) so concurrent
/// re-evaluations while the fetch is pending don't launch a second one.
/// Reset after every attempt — the BREADCRUMB, not this flag, is the
/// terminal state.
final deviceNameSelfHealInFlightProvider = StateProvider<bool>((_) => false);

/// #990: restore-breadcrumb-scoped deviceName self-heal.
///
/// Fires ONLY while the `recovery_name_seed_uid` breadcrumb (written by the
/// VERIFIED restore-success arm of `surfaceRecoveryOutcome`) matches the
/// current uid and the local name is still empty — an unscoped
/// empty-name+has-groups heal would promote a claimed shadow's
/// creator-authored per-group name to the device-wide identity (#293; Gate
/// rounds 1+2). Every side effect runs post-frame (mutating other providers
/// from a build body is illegal), and every failure path is silent — this is
/// polish, never a boot blocker.
final deviceNameSelfHealProvider = Provider<void>((ref) {
  final deviceName = ref.watch(settingsProvider.select((s) => s.deviceName));
  // AsyncLoading and the #647 false-empty both fail toward not-firing.
  final groups = ref.watch(userGroupsProvider).valueOrNull ?? const [];
  final isDurable = ref.watch(isDurableUserProvider);
  ref.watch(deviceNameSeedRevisionProvider);

  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      // Isolation gate FIRST — no breadcrumb mutation happens mid-swap.
      if (ref.read(cacheIsolationProvider)) return;
      final prefs = ref.read(sharedPreferencesProvider);
      final breadcrumb = readPendingNameSeed(prefs);
      if (breadcrumb == null) return;

      if (deviceName.trim().isNotEmpty) {
        // Already named (user-set, or a prior seed) — heal resolved.
        unawaited(clearPendingNameSeed(prefs));
        return;
      }

      final currentUid = ref.read(currentUserIdProvider);
      if (currentUid == null) {
        // Auth still resolving (cold-boot AsyncLoading window). RETAIN and
        // wait — clearing here would destroy a valid breadcrumb on every
        // cold boot (Gate round-3 [P1]); a later watched emission re-runs.
        return;
      }
      if (breadcrumb != currentUid) {
        // Stale breadcrumb from an older swap — this uid never heals.
        unawaited(clearPendingNameSeed(prefs));
        return;
      }

      // Belt: a breadcrumb can only be written for a durable swap, so this
      // guards future refactors of the notice, not a live path.
      if (!isDurable || groups.isEmpty) return;

      if (ref.read(deviceNameSelfHealInFlightProvider)) return;
      ref.read(deviceNameSelfHealInFlightProvider.notifier).state = true;

      final groupIds = groups.map((g) => g.id).toList();
      unawaited(() async {
        try {
          final fetch = ref.read(fetchOwnMemberNameProvider);
          final name = await fetch(currentUid, groupIds);
          // Mid-swap re-check: isolation engaging while the fetch was in
          // flight must drop the seed — the outgoing shell is being torn
          // down (mirrors recovery_outcome_notice_provider).
          if (ref.read(cacheIsolationProvider)) return;
          if (name == null) {
            // Terminal: every group queried, nothing seedable. Clear so an
            // all-unseedable roster doesn't re-query on every emission
            // forever.
            await clearPendingNameSeed(prefs);
            return;
          }
          final seeded = await ref
              .read(settingsProvider.notifier)
              .seedDeviceName(name);
          if (seeded ||
              ref.read(settingsProvider).deviceName.trim().isNotEmpty) {
            await clearPendingNameSeed(prefs);
          }
        } catch (e) {
          // Transient fetch failure, or this ref was disposed mid-await by
          // engageIsolation — retain the breadcrumb and retry on a later
          // emission / next boot.
          FirebaseConfig.log('deviceNameSelfHeal: $e');
        } finally {
          try {
            ref.read(deviceNameSelfHealInFlightProvider.notifier).state =
                false;
          } catch (_) {
            // Disposed mid-swap — the fresh boot starts with a fresh flag.
          }
        }
      }());
    } catch (e) {
      FirebaseConfig.log('deviceNameSelfHeal: $e');
    }
  });
});

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../../groups/models/group_model.dart';

/// Upper bound on the outgoing-shell emptiness gate before a cross-UID
/// discard-shell swap (#647 email recover, #648 Google voluntary restore).
/// Generous enough that a settled anon shell's local-cache `memberIds` query
/// (near-instant) never trips it; a pathological hang times out into the
/// fail-safe block. Overridable in tests.
final shellEmptinessGateTimeoutProvider = Provider<Duration>(
  (_) => const Duration(seconds: 5),
);

/// Server-truth probe the gate runs before it may declare a shell empty
/// (#1091): a cold/reinstalled device serves the FIRST `userGroupsProvider`
/// snapshot from an EMPTY local cache, so stream-empty is not account-empty.
/// `true` = server sees ≥1 LIVE membership, `false` = server-confirmed zero
/// live memberships, `null` = inconclusive. Deliberately NOT
/// [hasAnyGroupMembership] (the #839 notice probe): that one counts
/// tombstones on purpose ("did this account ever hold data"), but soft
/// deletes keep `memberIds` intact (deleteGroup.ts), so it would permanently
/// block restore for a shell whose only rows are tombstones. This probe
/// mirrors `watchUserGroups`' live-only in-memory filter instead — missing
/// `isDeleted` (legacy) and malformed docs both count as live (block,
/// fail-safe). No `limit`: tombstones must be filtered client-side, so the
/// full (small) membership row set is fetched.
Future<bool?> hasAnyLiveGroupMembership(FirebaseFirestore db, String uid) async {
  try {
    final snap = await db
        .collection('groups')
        .where('memberIds', arrayContains: uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 4));
    return snap.docs.any((doc) => doc.data()['isDeleted'] != true);
  } catch (_) {
    return null;
  }
}

/// Overridable in tests. Default binds the live Firestore lazily so reading
/// the provider never touches FirebaseConfig in a test.
final shellEmptinessServerProbeProvider =
    Provider<Future<bool?> Function(String uid)>(
  (_) => (uid) => hasAnyLiveGroupMembership(FirebaseConfig.firestore, uid),
);

/// True only when the OUTGOING shell is provably empty — the single condition
/// under which a cross-UID discard-shell swap is non-destructive. Membership is
/// read from the [firebaseUserProvider] + [userGroupsProvider] pair (passed as
/// thunks so this works from both a `Ref` and a `WidgetRef`):
/// `memberIds arrayContains uid`, the same predicate the Profile restore
/// affordance and the durable-credential conflict sheet gate on.
///
/// **Resolves the auth UID FIRST.** [firebaseUserProvider] replays the current
/// user via a microtask, so on cold start a synchronous [userGroupsProvider]
/// read can see `uid == null` → `Stream.value([])` → a FALSE empty. Awaiting the
/// user settles the UID so the membership read targets the real shell. A bare
/// `userGroupsProvider` read (no user-await first) would let a populated shell
/// pass the gate on the first frame — the exact data-loss hole #647/#648 close.
///
/// Fail-safe by construction — a single [Future.timeout] bounds the whole gate;
/// a hang or stream error is caught into `false` (block). Only server-confirmed
/// zero live memberships (or no signed-in user — nothing to orphan) returns
/// true.
Future<bool> outgoingShellProvablyEmpty({
  required Future<User?> Function() readUser,
  required Future<List<Group>> Function() readGroups,
  required Future<bool?> Function(String uid) probeHasLiveData,
  required Duration timeout,
}) async {
  try {
    return await _resolveShellEmpty(readUser, readGroups, probeHasLiveData)
        .timeout(timeout);
  } catch (error, stackTrace) {
    FirebaseConfig.log(
      'Shell-emptiness gate could not confirm an empty shell '
      '(${error.runtimeType}) — blocking the cross-UID swap (fail-safe)',
      stackTrace: stackTrace,
    );
    return false;
  }
}

Future<bool> _resolveShellEmpty(
  Future<User?> Function() readUser,
  Future<List<Group>> Function() readGroups,
  Future<bool?> Function(String uid) probeHasLiveData,
) async {
  final user = await readUser();
  if (user == null) return true; // no shell → nothing to orphan → proceed
  final groups = await readGroups();
  if (groups.isNotEmpty) return false;
  // #1091: stream-empty may be a cold cache (reinstall keeps the Keychain
  // UID, wipes Firestore persistence). Only server-confirmed zero LIVE
  // memberships may proceed; live-data AND inconclusive both block — this
  // gate is destructive, unlike the #839 notice where null stays kind.
  final hasLiveData = await probeHasLiveData(user.uid);
  return hasLiveData == false;
}

import 'dart:async';

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
/// a hang or stream error is caught into `false` (block). Only `data && empty`
/// (or no signed-in user — nothing to orphan) returns true.
Future<bool> outgoingShellProvablyEmpty({
  required Future<User?> Function() readUser,
  required Future<List<Group>> Function() readGroups,
  required Duration timeout,
}) async {
  try {
    return await _resolveShellEmpty(readUser, readGroups).timeout(timeout);
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
) async {
  final user = await readUser();
  if (user == null) return true; // no shell → nothing to orphan → proceed
  final groups = await readGroups();
  return groups.isEmpty;
}

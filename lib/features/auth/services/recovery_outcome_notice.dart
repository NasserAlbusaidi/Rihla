import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/firebase_config.dart';
import 'auth_error_humanizer.dart';
import 'recovery_outcome.dart';

/// Pre-resolved copy for the three outcomes [surfaceRecoveryOutcome] can
/// show. Localization happens in the provider (`appMessengerKey.currentContext`
/// → `AppLocalizations.of(ctx)`, EN fallback if unavailable) so this service
/// stays context-free and unit-testable without a widget tree (#839).
typedef RecoveryOutcomeMessages = ({
  String restoredOk,
  String restoredEmpty,
  String swapIncomplete,
});

/// Data-presence probe for the #839 honest-restore-outcome check: proves the
/// signed-in account holds Rihla data via the same predicate the swap gates
/// use (`groups where memberIds arrayContains uid`, `group_provider.dart`) —
/// there is no `users/{uid}` doc to read instead.
///
/// `Source.server` is mandatory: the restored uid's Firestore cache is empty
/// BY DESIGN at notice time (`CacheUidBarrier.reconcile` clears persistence
/// on the post-swap boot), so a cache-first read would false-report "no
/// data" while merely offline — the same discrimination `activity_service.dart`
/// (`fromCacheEmpty`) and the connectivity probe (`connectivity_provider.dart`)
/// already rely on. `isDeleted` filtering is deliberately skipped: a
/// membership row of a soft-deleted group still proves "this account held
/// Rihla data," which is all this message needs.
///
/// Returns `true` (has data), `false` (server-confirmed empty), or `null` on
/// timeout/`unavailable`/any exception — inconclusive, never treated as empty.
Future<bool?> hasAnyGroupMembership(String uid) async {
  try {
    final snap = await FirebaseConfig.firestore
        .collection('groups')
        .where('memberIds', arrayContains: uid)
        .limit(1)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 4));
    return snap.docs.isNotEmpty;
  } catch (_) {
    return null;
  }
}

/// Surfaces (and clears) a persisted [RecoveryOutcome] on cold boot (#439).
///
/// Pure logic with injected sinks so it unit-tests without Sentry, Firestore,
/// or a messenger; the provider wires the real ones. The capture string is
/// the authoritative release-build signal for a recovery failure — PII-safe
/// by construction (op + code only, never a UID).
///
/// A success marker naming an [RecoveryOutcome.expectedUid] is verified
/// against [currentUid] before the success notice shows (#458) — `ok` only
/// proves the auth API call succeeded BEFORE the forced restart; the swap is
/// real only if it survived the process kill. That mismatch check runs FIRST
/// and is unchanged. Only once the swap is confirmed durable (or was never
/// checkable) does #839 run a [hasData] presence probe to tell a genuinely
/// restored-empty account apart from a wrong/never-linked one:
///   - probe says the account has data → [RecoveryOutcomeMessages.restoredOk]
///   - probe server-confirms zero groups → `.restoredEmpty` (8s, points at
///     the existing Profile → Account → Sign out escape path)
///   - probe is inconclusive (offline/timeout/error) → `.restoredOk` — an
///     inconclusive probe must never scare a genuinely-restored user.
Future<void> surfaceRecoveryOutcome({
  required SharedPreferences prefs,
  required String? Function() currentUid,
  required Future<bool?> Function(String uid) hasData,
  required RecoveryOutcomeMessages messages,
  required void Function(
    String message, {
    bool isError,
    Duration duration,
  })
  showSnack,
  required void Function(String message) capture,
}) async {
  final outcome = readAndClearRecoveryOutcome(prefs);
  if (outcome == null) return;

  if (!outcome.ok) {
    final code = outcome.code ?? 'unknown';
    showSnack(humanizeAuthErrorCode(code), isError: true);
    capture('recovery_failed op=${outcome.op} code=$code');
    return;
  }

  // A successful sign-out needs no toast — the fresh anonymous home says it.
  if (outcome.op != RecoveryOutcome.opGoogle &&
      outcome.op != RecoveryOutcome.opApple &&
      outcome.op != RecoveryOutcome.opRecover) {
    return;
  }

  String? uid;
  var uidReadable = true;
  try {
    uid = currentUid();
  } catch (_) {
    // Auth unreadable (no Firebase app) — trust the claim rather than
    // false-alarm (or probe) on something we cannot verify.
    uidReadable = false;
  }

  if (!uidReadable) {
    showSnack(messages.restoredOk, isError: false);
    return;
  }

  final expected = outcome.expectedUid;
  if (expected != null && uid != expected) {
    showSnack(messages.swapIncomplete, isError: true);
    capture('recovery_swap_not_durable op=${outcome.op}');
    return;
  }

  // #990: the swap is VERIFIED durable — expectedUid was recorded and the
  // live uid matches it (`uid!` is safe: the unreadable-auth and mismatch
  // arms have both already returned). ONLY this arm may write the deviceName
  // self-heal breadcrumb; the guard is an explicit positive `expected != null`
  // because the legacy/unverifiable `expected == null` case falls through
  // here too and must NOT be stamped. Written before the async #839 probe —
  // the probe only picks snack copy and must not gate the heal.
  if (expected != null) {
    await writePendingNameSeed(prefs, uid!);
  }

  // Swap is durable (or expectedUid was never recorded — legacy v1 marker,
  // or a signature that skips the match check). Gate r1: probe against
  // whoever is actually signed in right now.
  final probeUid = uid;
  if (probeUid == null) {
    // Nothing to probe (no signed-in uid) — trust the claim.
    showSnack(messages.restoredOk, isError: false);
    return;
  }

  final has = await hasData(probeUid);
  if (has == false) {
    showSnack(
      messages.restoredEmpty,
      isError: false,
      duration: const Duration(seconds: 8),
    );
    return;
  }

  // has == true, or null (inconclusive) — never scare on an inconclusive probe.
  showSnack(messages.restoredOk, isError: false);
}

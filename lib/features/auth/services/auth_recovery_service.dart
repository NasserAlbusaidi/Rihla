import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/cache_isolation_controller.dart';
import '../../../core/services/cache_uid_barrier.dart';
import '../../../core/services/firebase_functions_service.dart';
import 'auth_email_link_config.dart';
import 'recovery_diagnostics.dart';
import 'recovery_failure_notice.dart';

typedef RecoveryCleanupFailureRecorder =
    void Function({
      required String message,
      required Map<String, Object?> data,
    });

typedef CleanupAnonUidArtifacts =
    Future<CleanupOutcome> Function({
      required String oldUid,
      required String cleanupSecret,
    });

typedef CleanupIntentFactory = Future<String> Function(String oldUid);

/// Orchestrates the email-link account recovery flows from spec §4.
///
/// Lives one layer above [FirebaseConfig.auth] so the Firebase plumbing
/// (sendSignInLinkToEmail / linkWithCredential / signInWithEmailLink /
/// signOut) can be mocked in tests without poking Firebase internals.
///
/// The service holds the "pending email" in SharedPreferences so the
/// send-side (Settings / Recover screens) and the receive-side (bootstrap
/// listener) can hand off across an app restart. Per Firebase anti-phishing,
/// linkWithCredential / signInWithEmailLink both require the *email*
/// alongside the link — we persist it at send time so the receive side
/// doesn't have to ask the user a second time on the same device.
class AuthRecoveryService {
  AuthRecoveryService({
    required FirebaseAuth auth,
    required SharedPreferences prefs,
    required CacheIsolationController cacheIsolationController,
    FirebaseFirestore? firestore,
    CleanupAnonUidArtifacts? cleanupAnonUidArtifacts,
    CleanupIntentFactory? cleanupIntentFactory,
    RecoveryCleanupFailureRecorder? recoveryCleanupFailureRecorder,
    RecoveryDiagnostics diagnostics = const SentryRecoveryDiagnostics(),
  }) : _auth = auth,
       _prefs = prefs,
       _cacheIsolationController = cacheIsolationController,
       _firestore = firestore,
       _diagnostics = diagnostics,
       _cleanupAnonUidArtifacts =
           cleanupAnonUidArtifacts ??
           (({required oldUid, required cleanupSecret}) =>
               FirebaseFunctionsService().cleanupAnonUidArtifacts(
                 oldUid: oldUid,
                 cleanupSecret: cleanupSecret,
               )),
       _cleanupIntentFactory =
           cleanupIntentFactory ??
           ((oldUid) async {
             final secret = _generateCleanupSecret();
             final targetFirestore = firestore ?? FirebaseFirestore.instance;
             await targetFirestore
                 .collection(_cleanupIntentCollection)
                 .doc(oldUid)
                 .set(buildCleanupIntentPayload(secret));
             return secret;
           }),
       _recoveryCleanupFailureRecorder =
           recoveryCleanupFailureRecorder ?? _recordCleanupFailureBreadcrumb;

  final FirebaseAuth _auth;
  final SharedPreferences _prefs;
  final CacheIsolationController _cacheIsolationController;
  final FirebaseFirestore? _firestore;
  final CleanupAnonUidArtifacts _cleanupAnonUidArtifacts;
  final CleanupIntentFactory _cleanupIntentFactory;
  final RecoveryCleanupFailureRecorder _recoveryCleanupFailureRecorder;
  final RecoveryDiagnostics _diagnostics;

  static const _pendingEmailKey = 'auth.pendingLinkEmail';
  static const _inFlightOpKey = 'auth.inFlightOp';
  static const _cleanupIntentCollection = 'recoveryCleanupIntents';
  static final Random _secureRandom = Random.secure();

  static String _generateCleanupSecret() {
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i += 1) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return base64UrlEncode(bytes);
  }

  /// TTL window for `recoveryCleanupIntents` docs (#170). Generously longer
  /// than the 15-min server-side validity (`cleanupIntentMaxAgeMs`) so a
  /// Firestore TTL keyed on `expiresAt` never reaps an intent that is still
  /// valid, even under realistic client clock skew. (TTL deletion is itself
  /// best-effort and may lag — this is the earliest-eligible instant.)
  static const Duration _cleanupIntentTtl = Duration(hours: 24);

  /// Builds the exact `recoveryCleanupIntents/{oldUid}` write map (#170).
  ///
  /// Pure so the OUTBOUND wire shape — the contract the `validCleanupIntent`
  /// rules gate admits and the TTL keys on — is unit-testable without driving
  /// the full recovery flow. `createdAt` stays a server-timestamp sentinel (the
  /// security control: server validity reads `createdAt`, not `expiresAt`);
  /// `expiresAt` is a concrete client `Timestamp` the TTL reaps on.
  @visibleForTesting
  static Map<String, Object?> buildCleanupIntentPayload(
    String secret, {
    DateTime Function()? clock,
  }) {
    final now = (clock ?? DateTime.now)();
    return {
      'secret': secret,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(now.toUtc().add(_cleanupIntentTtl)),
    };
  }

  static void _recordCleanupFailureBreadcrumb({
    required String message,
    required Map<String, Object?> data,
  }) {
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: message,
          category: 'auth.recovery.cleanup',
          level: SentryLevel.warning,
          data: Map<String, dynamic>.from(data),
        ),
      ),
    );
  }

  /// In-flight email-link operation kind. `'link'` attaches to the current
  /// anon UID via [User.linkWithCredential]; `'recover'` swaps to the
  /// previously-linked UID via [FirebaseAuth.signInWithEmailLink]. Tracked
  /// so the deep-link bootstrap can dispatch correctly when the user taps
  /// the email link.
  static const String opLink = 'link';
  static const String opRecover = 'recover';

  String? readPendingEmail() {
    final value = _prefs.getString(_pendingEmailKey);
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<void> setPendingEmail(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(email, 'email', 'must not be empty');
    }
    await _prefs.setString(_pendingEmailKey, trimmed);
  }

  Future<void> clearPendingEmail() async {
    await _prefs.remove(_pendingEmailKey);
  }

  String? readInFlightOp() {
    final value = _prefs.getString(_inFlightOpKey);
    if (value == opLink || value == opRecover) return value;
    return null;
  }

  Future<void> _setInFlightOp(String op) async {
    assert(op == opLink || op == opRecover);
    await _prefs.setString(_inFlightOpKey, op);
  }

  Future<void> clearInFlightOp() async {
    await _prefs.remove(_inFlightOpKey);
  }

  /// Send a sign-in link to attach [email] to the current anonymous user.
  ///
  /// Persists [email] to SharedPreferences so the bootstrap listener can
  /// complete the flow on receive without a second prompt. Calls
  /// [FirebaseAuth.sendSignInLinkToEmail] with the centralized action code
  /// settings from [AuthEmailLinkConfig].
  Future<void> linkEmailToCurrentUser(String email) async {
    await setPendingEmail(email);
    await _setInFlightOp(opLink);
    await _auth.sendSignInLinkToEmail(
      email: email.trim(),
      actionCodeSettings: AuthEmailLinkConfig.actionCodeSettings(),
    );
    _diagnostics.breadcrumb('send.link.queued');
    FirebaseConfig.log('Recovery: link email send queued (email redacted)');
  }

  /// Send a recovery sign-in link for a device that's never been linked.
  ///
  /// Same wire-level call as [linkEmailToCurrentUser]; kept as a separate
  /// entry point so the receive-side can disambiguate via the persisted
  /// `inFlightOp` flag in later phases (spec §4 / plan §P4).
  Future<void> sendRecoveryLink(String email) async {
    await setPendingEmail(email);
    await _setInFlightOp(opRecover);
    await _auth.sendSignInLinkToEmail(
      email: email.trim(),
      actionCodeSettings: AuthEmailLinkConfig.actionCodeSettings(),
    );
    _diagnostics.breadcrumb('send.recover.queued');
    FirebaseConfig.log('Recovery: recovery link send queued (email redacted)');
  }

  /// Attach the email-link credential to the current Firebase user.
  ///
  /// Used when the user pressed "Link my email" in Settings (the anon UID
  /// is preserved). Reads the email from SharedPreferences unless
  /// [overrideEmail] is supplied (spec §4.7 / different-device path).
  /// Clears the pending email on success.
  Future<UserCredential> completeEmailLink(
    String emailLink, {
    String? overrideEmail,
  }) async {
    final email = (overrideEmail ?? readPendingEmail())?.trim();
    if (email == null || email.isEmpty) {
      throw StateError(
        'No pending email available to complete link — call setPendingEmail '
        'first or pass overrideEmail',
      );
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No current user; ensureAnonymousSession first');
    }
    final credential = EmailAuthProvider.credentialWithLink(
      email: email,
      emailLink: emailLink,
    );
    _diagnostics.breadcrumb('link.complete.attempt');
    final UserCredential result;
    try {
      result = await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      // Non-restarting path: immediate capture is reliable here.
      _diagnostics.captureFailure('link.complete.fail', code: e.code);
      rethrow;
    }
    await clearPendingEmail();
    await clearInFlightOp();
    _diagnostics.breadcrumb('link.complete.ok');
    FirebaseConfig.log('Recovery: linked email to uid ${result.user?.uid}');
    return result;
  }

  /// Sign in as the previously-linked user, then restart (#45).
  ///
  /// Used by the Home "Restore from email" path (spec §4.2). The current
  /// anonymous UID is replaced, so this is a cross-UID swap: engage the
  /// cache-isolation overlay FIRST (covers all cached UI + tears down the
  /// leaf subscription holders), flush pending writes, mark the on-device
  /// Firestore cache dirty BEFORE the auth change, then swap via the sign-in
  /// itself, await the server cleanup to its natural terminal state and
  /// trigger a true restart. The cold boot's cache barrier clears the
  /// outgoing UID's cache before the first read. A FAILED sign-in leaves the
  /// current session signed in — the guaranteed restart returns to it (#414).
  Future<UserCredential> completeRecovery(
    String emailLink, {
    String? overrideEmail,
    Duration pendingWritesTimeout = const Duration(seconds: 5),
  }) async {
    final email = (overrideEmail ?? readPendingEmail())?.trim();
    if (email == null || email.isEmpty) {
      throw StateError(
        'No pending email available to complete recovery — call '
        'setPendingEmail first or pass overrideEmail',
      );
    }
    final retiringUser = _auth.currentUser;
    final oldUid = retiringUser != null && retiringUser.isAnonymous
        ? retiringUser.uid
        : null;

    // Cover cached UI and stop the leaf subscriptions before any auth change.
    _cacheIsolationController.engageIsolation();

    // Once isolation is engaged, the overlay covers everything until a restart.
    // The finally GUARANTEES that restart — and clears the op-state first — on
    // BOTH success and failure, so a failed swap (e.g. an expired link) can
    // never strand the user on the overlay or loop the bootstrap on a dead
    // link next boot (divergence from plan §3.5; see #45 plan "Failure paths").
    final uidFp =
        oldUid == null ? null : RecoveryDiagnostics.fingerprint(oldUid);
    _diagnostics.breadcrumb('recover.start', data: {'uid': uidFp});
    try {
      String? cleanupSecret;
      if (oldUid != null && oldUid.isNotEmpty) {
        try {
          cleanupSecret = await _cleanupIntentFactory(oldUid);
        } catch (error, stackTrace) {
          _recoveryCleanupFailureRecorder(
            message: 'Recovery cleanup intent creation failed',
            data: {'errorType': error.runtimeType.toString()},
          );
          FirebaseConfig.log(
            'Recovery: cleanup intent creation failed (${error.runtimeType})',
            stackTrace: stackTrace,
          );
        }
      }
      try {
        final firestore = _firestore ?? FirebaseFirestore.instance;
        await firestore.waitForPendingWrites().timeout(pendingWritesTimeout);
      } on TimeoutException {
        FirebaseConfig.log(
          'Recovery: waitForPendingWrites timed out after '
          '${pendingWritesTimeout.inSeconds}s — continuing recovery',
        );
      }

      // Durable cross-restart marker: the cold boot clears the cache even if
      // the process dies before restart(). Awaited so it is flushed (§6.4).
      await markFirestorePersistenceDirty(_prefs);

      // No explicit signOut: signInWithEmailLink replaces the current session
      // on success, and on failure (e.g. a consumed single-use link) the
      // current user MUST survive — signing out first is how a no-email anon
      // account gets orphaned (#414, the #213 failure class).
      _diagnostics.breadcrumb('recover.signIn.attempt', data: {'uid': uidFp});
      final UserCredential result;
      try {
        result = await _auth.signInWithEmailLink(
          email: email,
          emailLink: emailLink,
        );
      } on FirebaseAuthException catch (e) {
        // The finally below restarts via a native System.exit(0) that discards
        // in-flight async Sentry sends AND pre-empts the bootstrap's error
        // SnackBar — so persist the reason durably (awaited → flushed) BEFORE
        // restart; the next cold boot surfaces it and emits the Sentry event.
        await writeRecoveryFailureNotice(_prefs, code: e.code, op: opRecover);
        _diagnostics.breadcrumb('recover.signIn.fail', data: {'code': e.code});
        FirebaseConfig.log('Recovery: signInWithEmailLink failed (${e.code})');
        rethrow;
      }
      _diagnostics.breadcrumb(
        'recover.signIn.ok',
        data: {'uidChanged': result.user?.uid != oldUid},
      );
      // Belt-and-suspenders: clear any stale marker from a prior failed attempt
      // so a later SUCCESS can't surface a false "expired" message on next boot
      // (the narrow case where the post-boot surface didn't run after the prior
      // restart).
      await clearRecoveryFailureNotice(_prefs);
      FirebaseConfig.log('Recovery: recovered uid ${result.user?.uid}');

      if (oldUid != null &&
          oldUid.isNotEmpty &&
          cleanupSecret != null &&
          result.user?.uid != oldUid) {
        // Await the scrub to its natural terminal state (no custom cap — the
        // callable's 60s default client timeout bounds it). The server
        // completes the scrub regardless of the imminent restart (gen2 onCall
        // is not aborted by client disconnect), so this is byte-for-byte
        // main's scrub outcome and restart cannot truncate a scrub main would
        // have finished (§3.6).
        await _cleanupWithInlineRetry(
          oldUid: oldUid,
          cleanupSecret: cleanupSecret,
        );
      }

      return result;
    } finally {
      // Clear the op-state (a stale inFlightOp would make the next boot's
      // bootstrap re-enter recovery and loop on a dead link — R3 P2-4), then
      // restart. Each step is independently guarded so a failed prefs write can
      // NEVER skip restart() and strand the overlay (codex re-gate [P2]); the
      // restart() itself is fail-safe (surfaces a manual affordance on channel
      // failure), so it always runs last.
      _diagnostics.breadcrumb('recover.restart');
      await _safeClearRecoveryOpState();
      await _cacheIsolationController.restart();
    }
  }

  /// Drives the idempotent cleanup callable to a terminal state with ONE
  /// inline retry (#427) — still inside the isolation overlay, seconds after
  /// intent creation, so the 15-min intent is valid and (on a structured
  /// partial failure) provably unconsumed: the server deletes the intent only
  /// when every group migrated. A group left behind keeps `memberIds:[oldUid]`
  /// and silently vanishes from the restored account's balances, so a partial
  /// merge is money-wrong, not cosmetic.
  ///
  /// Never throws: the credential must reach the bootstrap and the `finally`
  /// restart must run regardless of the cleanup's fate.
  Future<void> _cleanupWithInlineRetry({
    required String oldUid,
    required String cleanupSecret,
  }) async {
    var firstAttemptThrew = false;
    try {
      final outcome = await _cleanupAnonUidArtifacts(
        oldUid: oldUid,
        cleanupSecret: cleanupSecret,
      );
      if (outcome.complete) {
        FirebaseConfig.log('Recovery: anon uid cleanup completed');
        return;
      }
      FirebaseConfig.log(
        'Recovery: anon uid cleanup partial '
        '(${outcome.cascadeFailed.length} group(s) failed) — retrying once',
      );
    } catch (error, stackTrace) {
      firstAttemptThrew = true;
      FirebaseConfig.log(
        'Recovery: anon uid cleanup failed (${error.runtimeType}) — '
        'retrying once',
        stackTrace: stackTrace,
      );
    }
    try {
      final retry = await _cleanupAnonUidArtifacts(
        oldUid: oldUid,
        cleanupSecret: cleanupSecret,
      );
      if (retry.complete) {
        FirebaseConfig.log('Recovery: anon uid cleanup completed on retry');
        return;
      }
      _recoveryCleanupFailureRecorder(
        message: 'Recovery cleanup incomplete',
        data: {'groupsFailed': retry.cascadeFailed},
      );
      FirebaseConfig.log(
        'Recovery: anon uid cleanup still partial after retry '
        '(${retry.cascadeFailed.length} group(s) stranded under old uid)',
      );
    } catch (error, stackTrace) {
      if (firstAttemptThrew &&
          error is FirebaseFunctionsException &&
          error.code == 'permission-denied') {
        // The first attempt threw client-side (e.g. a 60s timeout) but the
        // server ran to completion and CONSUMED the intent — permission-denied
        // on the retry means there is no intent left because the migration
        // already fully succeeded. Recording it would file a false alarm.
        FirebaseConfig.log(
          'Recovery: cleanup retry permission-denied after a thrown first '
          'attempt — intent consumed by a completed first invocation',
        );
        return;
      }
      _recoveryCleanupFailureRecorder(
        message: 'Recovery cleanup incomplete',
        data: {'errorType': error.runtimeType.toString()},
      );
      FirebaseConfig.log(
        'Recovery: anon uid cleanup retry failed (${error.runtimeType})',
        stackTrace: stackTrace,
      );
    }
  }

  /// Best-effort clear of the recovery op-state. Each removal is guarded on its
  /// own so one failing prefs write neither skips the other nor blocks the
  /// guaranteed restart in [completeRecovery]'s `finally`.
  Future<void> _safeClearRecoveryOpState() async {
    try {
      await clearPendingEmail();
    } catch (error, stackTrace) {
      FirebaseConfig.log(
        'Recovery: clearPendingEmail failed (${error.runtimeType})',
        stackTrace: stackTrace,
      );
    }
    try {
      await clearInFlightOp();
    } catch (error, stackTrace) {
      FirebaseConfig.log(
        'Recovery: clearInFlightOp failed (${error.runtimeType})',
        stackTrace: stackTrace,
      );
    }
  }

  /// Sign out the current device, then restart (#45). Linked-email users only
  /// (OD-2).
  ///
  /// Sign-out swaps the linked UID for a fresh anonymous one, so it is a
  /// cross-UID swap: engage the cache-isolation overlay first, flush pending
  /// writes (default 5s) so unsynced edits aren't lost, mark the cache dirty,
  /// sign out, then trigger a true restart. The cold boot re-mints the anon
  /// session and the barrier clears the outgoing UID's cache. There is no
  /// in-session anon mint — it would run `clearPersistence()` on a started
  /// Firestore instance, which throws (P1-1).
  Future<void> signOutCurrentDevice({
    Duration pendingWritesTimeout = const Duration(seconds: 5),
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw StateError(
        'signOutCurrentDevice requires a user with a linked email',
      );
    }
    _cacheIsolationController.engageIsolation();
    // finally guarantees the restart even if signOut throws, so the overlay
    // can never strand the user (divergence from plan §3.5; see plan doc).
    try {
      try {
        final firestore = _firestore ?? FirebaseFirestore.instance;
        await firestore.waitForPendingWrites().timeout(pendingWritesTimeout);
      } on TimeoutException {
        FirebaseConfig.log(
          'Recovery: waitForPendingWrites timed out after '
          '${pendingWritesTimeout.inSeconds}s — signing out anyway',
        );
      }
      await markFirestorePersistenceDirty(_prefs);
      await _auth.signOut();
    } finally {
      await _cacheIsolationController.restart();
    }
  }
}

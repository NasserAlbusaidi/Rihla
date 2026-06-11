import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/cache_isolation_controller.dart';
import '../../../core/services/cache_uid_barrier.dart';
import 'auth_email_link_config.dart';
import 'google_sign_in_gateway.dart';

/// Produces a Firebase [AuthCredential] from an interactive Google sign-in
/// (#441 PR1). Defaults to [GoogleSignInGateway.obtainCredential]; injected
/// in tests because the plugin singleton needs live platform channels.
typedef GoogleCredentialFactory = Future<AuthCredential> Function();

/// Removes the current device's FCM token doc (#441 PR3). Injected so the
/// discard-shell restore swap can delete `fcm_tokens/{oldUid}` BEFORE the UID
/// changes (owner-only rules make it un-deletable afterward) without
/// [AuthRecoveryService] depending on the notification layer. Wired in the
/// provider to `notificationService.removeToken`; defaults to a no-op so the
/// existing constructor callers and tests that don't exercise restore are
/// unaffected.
typedef FcmTokenRemover = Future<void> Function();

/// True when a LINK attempt (#441 PR2 gate) failed because the chosen Google
/// account already backs a different Firebase user. One-account-per-email can
/// surface EITHER code, and [FirebaseAuthException.credential] is nullable
/// (flutterfire #9920) — so we branch on the code alone and the caller
/// re-obtains/reuses the Google credential for [AuthRecoveryService.restoreWithGoogle].
///
/// PR3's own restore path ([FirebaseAuth.signInWithCredential]) never throws
/// these — they are link-only — so this classifier exists purely for the gate.
bool isGoogleAccountAlreadyInUse(Object error) =>
    error is FirebaseAuthException &&
    (error.code == 'credential-already-in-use' ||
        error.code == 'email-already-in-use');

/// Orchestrates the email-link + Google account flows (link / restore).
///
/// Lives one layer above [FirebaseConfig.auth] so the Firebase plumbing
/// (sendSignInLinkToEmail / linkWithCredential / signInWithEmailLink /
/// signOut) can be mocked in tests without poking Firebase internals.
///
/// Since #441 PR4 the email RECOVER half is a no-merge discard-shell swap
/// ([restoreWithEmailLink], mirroring [restoreWithGoogle]) — the cross-UID
/// merge engine (cleanup intents + `cleanupAnonUidArtifacts`) has no client
/// writer anymore. See
/// docs/plans/2026-06-11-durable-credential-recovery-rearchitecture.md.
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
    GoogleCredentialFactory? googleCredentialFactory,
    FcmTokenRemover? removeFcmToken,
  }) : _auth = auth,
       _prefs = prefs,
       _cacheIsolationController = cacheIsolationController,
       _firestore = firestore,
       _removeFcmToken = removeFcmToken ?? _noopFcmTokenRemover,
       _googleCredentialFactory =
           googleCredentialFactory ?? _defaultGoogleCredentialFactory;

  final FirebaseAuth _auth;
  final SharedPreferences _prefs;
  final CacheIsolationController _cacheIsolationController;
  final FirebaseFirestore? _firestore;
  final GoogleCredentialFactory _googleCredentialFactory;
  final FcmTokenRemover _removeFcmToken;

  static Future<void> _noopFcmTokenRemover() async {}

  /// Shared gateway so [GoogleSignIn.initialize] runs once per process, not
  /// once per service instance.
  static final GoogleSignInGateway _defaultGoogleGateway =
      GoogleSignInGateway();

  static Future<AuthCredential> _defaultGoogleCredentialFactory() =>
      _defaultGoogleGateway.obtainCredential();

  static const _pendingEmailKey = 'auth.pendingLinkEmail';
  static const _inFlightOpKey = 'auth.inFlightOp';

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
    final result = await user.linkWithCredential(credential);
    await clearPendingEmail();
    await clearInFlightOp();
    FirebaseConfig.log('Recovery: linked email to uid ${result.user?.uid}');
    return result;
  }

  /// Attach a Google credential to the current Firebase user (#441 PR1).
  ///
  /// Same-UID by construction ([User.linkWithCredential]) — no cache
  /// isolation, no restart, no inFlightOp handshake; the whole flow is one
  /// in-session round trip through the Credential Manager sheet. Conflict
  /// errors (`credential-already-in-use` / `email-already-in-use`) propagate
  /// unchanged: the gate UI (#441 PR2/PR3) owns the discard-shell decision
  /// and must never resolve it by signing the anon user out.
  Future<UserCredential> linkGoogleToCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No current user; ensureAnonymousSession first');
    }
    final credential = await _googleCredentialFactory();
    final result = await user.linkWithCredential(credential);
    FirebaseConfig.log('Recovery: linked Google to uid ${result.user?.uid}');
    return result;
  }

  /// Restore the durable Google-backed account on this device, then restart
  /// (#441 PR3). This is a cross-UID swap (the throwaway anon shell is replaced
  /// by the Google-owned UID), so it runs the full cache-isolation protocol —
  /// mirroring [completeRecovery]/[signOutCurrentDevice] but via
  /// [FirebaseAuth.signInWithCredential] and WITHOUT the merge engine: the
  /// post-gate shell is provably empty (PR2 gates `fcm_tokens` writes and drops
  /// `recoveryCleanupIntents`), so there is nothing to migrate.
  ///
  /// Ordering is load-bearing:
  /// 1. Obtain the credential FIRST — interactive, so a user-cancel / missing
  ///    idToken / missing serverClientId throws here with the anon shell fully
  ///    intact (no overlay, no swap, no restart). [credential] lets the PR2
  ///    gate-conflict path reuse the Google credential from its failed link.
  /// 2. Remove the FCM token BEFORE the swap — owner-only `fcm_tokens` rules
  ///    make `fcm_tokens/{oldUid}` un-deletable once `request.auth.uid` changes,
  ///    and [CacheIsolationController.engageIsolation] invalidates the
  ///    notification provider, so this must precede both. Best-effort.
  /// 3. Engage isolation (cover cached UI + tear down leaf subscriptions)
  ///    BEFORE any auth change; the `finally` GUARANTEES the restart on success
  ///    AND failure so the overlay can never strand the user.
  /// 4. Flush pending writes, mark the cache dirty (awaited, so the cold boot
  ///    clears the outgoing UID's cache even if the process dies before
  ///    restart), then swap. NO explicit signOut: a failed swap MUST leave the
  ///    current anon user signed in (#414/#213), and the guaranteed restart
  ///    returns to it.
  Future<UserCredential> restoreWithGoogle({
    AuthCredential? credential,
    Duration pendingWritesTimeout = const Duration(seconds: 5),
  }) async {
    final googleCredential = credential ?? await _googleCredentialFactory();

    // Owner-only rules block deleting fcm_tokens/{oldUid} after the UID swaps,
    // and engageIsolation invalidates the notification provider — so remove the
    // token while still signed in as the outgoing anon UID. Best-effort by
    // placement: this runs before isolation and outside the try/finally, so a
    // throw aborts the restore with the shell intact rather than stranding it.
    await _removeFcmToken();

    _cacheIsolationController.engageIsolation();
    try {
      try {
        final firestore = _firestore ?? FirebaseFirestore.instance;
        await firestore.waitForPendingWrites().timeout(pendingWritesTimeout);
      } on TimeoutException {
        FirebaseConfig.log(
          'Restore: waitForPendingWrites timed out after '
          '${pendingWritesTimeout.inSeconds}s — restoring anyway',
        );
      }
      await markFirestorePersistenceDirty(_prefs);
      final result = await _auth.signInWithCredential(googleCredential);
      FirebaseConfig.log('Restore: restored uid ${result.user?.uid}');
      return result;
    } finally {
      await _cacheIsolationController.restart();
    }
  }

  /// Restore the previously-linked account via an email sign-in link, then
  /// restart (#441 PR4 — the slim email fallback, D3). Cross-UID
  /// discard-shell swap: identical protocol to [restoreWithGoogle], WITHOUT
  /// the merge engine — the post-gate anon shell is provably empty (PR2
  /// gates `fcm_tokens` writes; PR4 deleted the cleanup-intent writer), so
  /// there is nothing to migrate and `cleanupAnonUidArtifacts` is never
  /// invoked.
  ///
  /// Ordering is load-bearing (see [restoreWithGoogle]); the one addition is
  /// the email-path op-state (`pendingLinkEmail` / `inFlightOp`), cleared in
  /// the `finally` alongside the guaranteed restart so a dead link can never
  /// boot-loop the bootstrap (R3 P2-4). NO explicit signOut: a failed swap
  /// MUST leave the current user signed in (#414/#213).
  Future<UserCredential> restoreWithEmailLink(
    String emailLink, {
    String? overrideEmail,
    Duration pendingWritesTimeout = const Duration(seconds: 5),
  }) async {
    final email = (overrideEmail ?? readPendingEmail())?.trim();
    if (email == null || email.isEmpty) {
      throw StateError(
        'No pending email available to restore — call setPendingEmail '
        'first or pass overrideEmail',
      );
    }

    // Owner-only rules block deleting fcm_tokens/{oldUid} after the UID
    // swaps, and engageIsolation invalidates the notification provider — so
    // remove the token while still signed in as the outgoing UID. Placed
    // before isolation and outside the try/finally: a throw aborts the
    // restore with the shell intact rather than stranding the overlay.
    await _removeFcmToken();

    _cacheIsolationController.engageIsolation();
    try {
      try {
        final firestore = _firestore ?? FirebaseFirestore.instance;
        await firestore.waitForPendingWrites().timeout(pendingWritesTimeout);
      } on TimeoutException {
        FirebaseConfig.log(
          'Restore: waitForPendingWrites timed out after '
          '${pendingWritesTimeout.inSeconds}s — restoring anyway',
        );
      }
      await markFirestorePersistenceDirty(_prefs);
      final result = await _auth.signInWithEmailLink(
        email: email,
        emailLink: emailLink,
      );
      FirebaseConfig.log('Restore: restored uid ${result.user?.uid}');
      return result;
    } finally {
      // Clear the op-state (a stale inFlightOp would make the next boot's
      // bootstrap re-enter recovery and loop on a dead link — R3 P2-4), then
      // restart. Each step is independently guarded so a failed prefs write
      // can NEVER skip restart() and strand the overlay; the restart() itself
      // is fail-safe (surfaces a manual affordance on channel failure), so it
      // always runs last.
      await _safeClearRecoveryOpState();
      await _cacheIsolationController.restart();
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

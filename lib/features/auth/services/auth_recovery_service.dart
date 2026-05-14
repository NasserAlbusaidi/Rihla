import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/firebase_config.dart';
import 'auth_email_link_config.dart';

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
    FirebaseFirestore? firestore,
    Future<void> Function()? anonymousSessionFactory,
  }) : _auth = auth,
       _prefs = prefs,
       _firestore = firestore,
       _anonymousSessionFactory =
           anonymousSessionFactory ?? FirebaseConfig.ensureAnonymousSession;

  final FirebaseAuth _auth;
  final SharedPreferences _prefs;
  final FirebaseFirestore? _firestore;
  final Future<void> Function() _anonymousSessionFactory;

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
    FirebaseConfig.log('Recovery: link email send queued for ${email.trim()}');
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
    FirebaseConfig.log('Recovery: recovery link send queued for ${email.trim()}');
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
    FirebaseConfig.log(
      'Recovery: linked email to uid ${result.user?.uid}',
    );
    return result;
  }

  /// Sign in fresh as the previously-linked user.
  ///
  /// Used by the Home "Restore from email" path (spec §4.2). The current
  /// anonymous UID is replaced — the P2 cache invalidator must wipe
  /// `safar_cache.db` before the new UID surfaces in any provider.
  Future<UserCredential> completeRecovery(
    String emailLink, {
    String? overrideEmail,
  }) async {
    final email = (overrideEmail ?? readPendingEmail())?.trim();
    if (email == null || email.isEmpty) {
      throw StateError(
        'No pending email available to complete recovery — call '
        'setPendingEmail first or pass overrideEmail',
      );
    }
    final result = await _auth.signInWithEmailLink(
      email: email,
      emailLink: emailLink,
    );
    await clearPendingEmail();
    await clearInFlightOp();
    FirebaseConfig.log(
      'Recovery: recovered uid ${result.user?.uid}',
    );
    return result;
  }

  /// Sign out the current device. Linked-email users only (OD-2).
  ///
  /// Awaits pending Firestore writes (default 5s timeout per spec §7.6)
  /// before signing out so unsynced local edits aren't lost. Then signs
  /// out and ensures a fresh anonymous session via [FirebaseConfig].
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
    try {
      final firestore = _firestore ?? FirebaseFirestore.instance;
      await firestore.waitForPendingWrites().timeout(pendingWritesTimeout);
    } on TimeoutException {
      FirebaseConfig.log(
        'Recovery: waitForPendingWrites timed out after '
        '${pendingWritesTimeout.inSeconds}s — signing out anyway',
      );
    }
    await _auth.signOut();
    await _anonymousSessionFactory();
  }
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/notification_service.dart';
import '../widgets/durable_credential_sheet.dart';

typedef DurableCredentialSheetPresenter =
    Future<bool> Function(BuildContext context);

/// Screen-side chokepoint for the durable-credential requirement (#441 PR2).
///
/// One named predicate per surface so a future policy (PR3+) wraps a single
/// branch. The hard enforcement lives in [GroupService] (typed exception)
/// and in firestore.rules / the join callable — this gate only owns the UX.
final durableCredentialGateProvider = Provider<DurableCredentialGate>((ref) {
  return DurableCredentialGate(ref);
});

class DurableCredentialGate {
  DurableCredentialGate(
    this._ref, {
    bool Function()? isAnonymous,
    DurableCredentialSheetPresenter? presentSheet,
  }) : _isAnonymousOverride = isAnonymous,
       _presentSheet = presentSheet ?? showDurableCredentialSheet;

  final Ref _ref;
  final bool Function()? _isAnonymousOverride;
  final DurableCredentialSheetPresenter _presentSheet;

  bool get _needsGate {
    final override = _isAnonymousOverride;
    if (override != null) return override();
    try {
      return FirebaseConfig.currentUser?.isAnonymous ?? false;
    } catch (_) {
      // No-Firebase widget tests (#390); rules are the hard backstop.
      return false;
    }
  }

  /// True ⇒ proceed with the write. Shows the blocking Google sheet for
  /// anonymous users; re-saves the FCM token post-link because a user who
  /// enabled push while still anonymous has no token doc yet, and pushes
  /// matter exactly right after the first join.
  Future<bool> ensure(BuildContext context) async {
    if (!_needsGate) return true;
    final linked = await _presentSheet(context);
    if (linked && _ref.read(settingsProvider).pushNotificationsEnabled) {
      unawaited(_ref.read(notificationServiceProvider).initialize());
    }
    return linked;
  }
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/local_database.dart';
import '../providers/auth_provider.dart';
import 'cold_start_cache_barrier.dart';

/// Function the listener calls to wipe the local SQLite cache. Indirected
/// through a provider so tests can override with a fake that records calls.
typedef CacheWipeFn = Future<void> Function();

final cacheWipeFnProvider = Provider<CacheWipeFn>((ref) {
  return LocalDatabase.wipeAndReinitialize;
});

/// Wipes the local SQLite cache when the active Firebase UID changes
/// mid-session.
///
/// Cold-start identity drift is handled by [runColdStartCacheBarrier] inside
/// `_AuthGate._bootSequence` before `SafarApp` renders — see lib/main.dart.
/// This listener picks up subsequent UID swaps (sign-out + new anon session,
/// email-link recovery completing in-foreground).
///
/// Wipes serialize through a single Future chain so overlapping transitions
/// cannot race or double-wipe. After each wipe resolves, the new UID (when
/// non-null) is persisted to SharedPreferences so the cold-start barrier on
/// the next launch recognizes the identity as already-recorded. A UID→null
/// transition still wipes but does not touch prefs; the next anon session is
/// established on the following launch and the cold-start barrier handles
/// the drift.
///
/// First emission is treated as the cold-start baseline: no wipe, no persist.
/// The cold-start barrier already established `prefs[lastObservedUidPrefsKey]`
/// equal to the settled UID before this listener was subscribed.
final uidChangeListenerProvider = Provider<void>((ref) {
  String? lastUid;
  var seenInitial = false;
  Future<void> wipeChain = Future.value();
  final wipe = ref.read(cacheWipeFnProvider);
  final prefs = ref.read(sharedPreferencesProvider);

  ref.listen<AsyncValue<firebase_auth.User?>>(
    authUserChangesProvider,
    (previous, next) {
      final newUid = next.valueOrNull?.uid;
      if (!seenInitial) {
        seenInitial = true;
        lastUid = newUid;
        return;
      }
      if (newUid == lastUid) return;

      final previousUid = lastUid;
      lastUid = newUid;
      FirebaseConfig.log(
        'UidChangeListener: uid $previousUid -> $newUid; wiping cache',
      );

      wipeChain = wipeChain
          .then((_) => wipe())
          .then((_) async {
            if (newUid != null) {
              try {
                await prefs.setString(lastObservedUidPrefsKey, newUid);
              } catch (error, stack) {
                Sentry.captureException(error, stackTrace: stack);
              }
            }
            Sentry.addBreadcrumb(
              Breadcrumb(
                category: 'auth.cache',
                message: 'mid_session_wipe',
              ),
            );
          })
          .catchError((Object error, StackTrace stack) {
            FirebaseConfig.log(
              'UidChangeListener: cache wipe failed',
              error: error,
              stackTrace: stack,
            );
            Sentry.captureException(error, stackTrace: stack);
          });
    },
  );
});

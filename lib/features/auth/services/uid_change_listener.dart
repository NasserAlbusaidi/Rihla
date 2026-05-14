import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/services/local_database.dart';
import '../providers/auth_provider.dart';

/// Function the listener calls to wipe the local SQLite cache. Indirected
/// through a provider so tests can override with a fake that records calls.
typedef CacheWipeFn = Future<void> Function();

final cacheWipeFnProvider = Provider<CacheWipeFn>((ref) {
  return LocalDatabase.wipeAndReinitialize;
});

/// Wipes the local SQLite cache when the active Firebase UID changes.
///
/// Account-recovery spec FR-CACHE-1 / OD-3: `safar_cache.db` is a per-UID
/// hydration of Firestore reads. On any UID swap (sign-out + new anon
/// session, or recovery via email-link) the file must be deleted before
/// providers serve rows from the previous user.
///
/// First emission is treated as the cold-start baseline — we record the UID
/// but do not wipe. Any subsequent emission with a different UID triggers
/// the cache wipe. Identical UIDs (e.g. profile/email mutations from
/// `linkWithCredential`) are ignored — the UID is preserved through
/// linking, so cache state remains valid.
final uidChangeListenerProvider = Provider<void>((ref) {
  String? lastUid;
  var seenInitial = false;
  final wipe = ref.read(cacheWipeFnProvider);

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
      unawaited(
        wipe().catchError((Object error, StackTrace stack) {
          FirebaseConfig.log(
            'UidChangeListener: cache wipe failed',
            error: error,
            stackTrace: stack,
          );
        }),
      );
    },
  );
});

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/settings_provider.dart';
import '../services/durable_account_marker.dart';
import 'auth_provider.dart';

/// #469: marks the device "durable account established" the moment a
/// non-anonymous user is observed on the auth stream — covering in-place link,
/// restore swap, and a durable session at cold boot (`fireImmediately`). This
/// observe-the-state approach has no missed-path hole (an enumerated set of
/// link/restore call sites would miss the widget's already-linked branch).
///
/// Watched by [appBootstrapProvider]. The marker is read at delete time to gate
/// an anon-shell delete (#469) and cleared by the deletion service on a
/// successful durable delete.
final durableAccountMarkerProvider = Provider<void>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  ref.listen<AsyncValue<User?>>(
    authUserChangesProvider,
    (_, next) {
      final user = next.valueOrNull;
      if (user != null && !user.isAnonymous) {
        unawaited(markDurableAccountEstablished(prefs));
      }
    },
    fireImmediately: true,
  );
});

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import '../extensions/build_context_l10n.dart';

/// A coarse, user-facing classification of a thrown error.
///
/// Deliberately small: users don't need the Firebase error taxonomy, only
/// what they can act on (retry, wait, or "you can't do that"). The pure
/// [classifyError] is table-testable without a [BuildContext]; [friendlyMessageFor]
/// maps it to a localized string.
enum FriendlyError {
  /// Offline / unreachable backend / timed out — the user should retry.
  network,

  /// permission-denied / unauthenticated — the action wasn't allowed.
  permissionDenied,

  /// Rate-limited / quota — the user should wait and retry.
  tooManyRequests,

  /// Anything else — a generic "something went wrong".
  unexpected,
}

/// Classify [error] into a [FriendlyError]. Pure — no context, no l10n.
///
/// Handles the three Firebase exception families (auth / functions / firestore
/// all extend [FirebaseException]) by their `code`, plus [TimeoutException].
/// Unknown codes and unknown error types fall through to [FriendlyError.unexpected]
/// so the raw detail is never shown — it goes to Sentry at the call site instead.
FriendlyError classifyError(Object error) {
  if (error is TimeoutException) return FriendlyError.network;

  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
        return FriendlyError.permissionDenied;
      case 'unavailable':
      case 'network-request-failed':
      case 'deadline-exceeded':
        return FriendlyError.network;
      case 'too-many-requests':
      case 'resource-exhausted':
        return FriendlyError.tooManyRequests;
      default:
        return FriendlyError.unexpected;
    }
  }

  return FriendlyError.unexpected;
}

/// A short, localized, user-facing cause phrase for [error].
///
/// Designed to slot into the existing action-context templates, e.g.
/// `l10n.groupFailedLeave(friendlyMessageFor(context, e))` →
/// "Failed to leave group: Please check your connection and try again."
/// The raw error is NOT surfaced — log it with `Sentry.captureException(e)`
/// at the catch site.
String friendlyMessageFor(BuildContext context, Object error) {
  final l10n = context.l10n;
  switch (classifyError(error)) {
    case FriendlyError.network:
      return l10n.errorNetwork;
    case FriendlyError.permissionDenied:
      return l10n.errorPermissionDenied;
    case FriendlyError.tooManyRequests:
      return l10n.errorTooManyRequests;
    case FriendlyError.unexpected:
      return l10n.errorUnexpected;
  }
}

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../l10n/generated/app_localizations.dart';

/// Why a settlement write failed, coarse enough to pick a user-facing message
/// that doesn't lie about the cause (#360).
///
/// Settle-up previously mapped *every* failure to "check your connection", so a
/// real `PERMISSION_DENIED` / validation rejection was misattributed to the
/// network. Since #1129 the settlement create is the `recordSettlement`
/// callable, which throws [FirebaseFunctionsException] — its CODE+DETAILS pair
/// distinguishes a server-side cap rejection (retryable after refresh) from a
/// true denial; classify the callable branch FIRST because
/// [FirebaseFunctionsException] extends [FirebaseException].
enum SettlementWriteErrorKind {
  /// Transient connectivity / backend reachability — retry once online.
  network,

  /// The write was refused: rules permission, auth, or value/shape validation.
  denied,

  /// #1129: the server recomputed a different world than the client observed —
  /// over-outstanding cap, stale decomposition, or a conflicting doc at the
  /// dedup id. Refresh-and-retry semantics, NOT a denial. The over-outstanding
  /// case carries `details.kind == 'over-outstanding'` + `outstandingFils`;
  /// screens may render the parameterized #773 balance-changed copy from it
  /// (see [overOutstandingFils]).
  staleBalance,

  /// Anything else — surface a neutral "try again", never a false network claim.
  unknown,
}

SettlementWriteErrorKind classifySettlementWriteError(Object error) {
  if (error is FirebaseFunctionsException) {
    final details = error.details;
    final kind = details is Map ? details['kind'] : null;
    return switch (error.code) {
      'unavailable' || 'deadline-exceeded' || 'cancelled' =>
        SettlementWriteErrorKind.network,
      'already-exists' => SettlementWriteErrorKind.staleBalance,
      'failed-precondition'
          when kind == 'over-outstanding' || kind == 'stale-decomposition' =>
        SettlementWriteErrorKind.staleBalance,
      'permission-denied' ||
      'unauthenticated' ||
      'invalid-argument' ||
      'failed-precondition' ||
      'out-of-range' => SettlementWriteErrorKind.denied,
      _ => SettlementWriteErrorKind.unknown,
    };
  }
  if (error is FirebaseException) {
    return switch (error.code) {
      'unavailable' || 'deadline-exceeded' || 'cancelled' =>
        SettlementWriteErrorKind.network,
      'permission-denied' ||
      'unauthenticated' ||
      'invalid-argument' ||
      'failed-precondition' ||
      'out-of-range' ||
      'already-exists' => SettlementWriteErrorKind.denied,
      _ => SettlementWriteErrorKind.unknown,
    };
  }
  return SettlementWriteErrorKind.unknown;
}

/// #1129: the fresh server-side outstanding (integer subunits) from an
/// `over-outstanding` rejection, or null for every other error. Lets the
/// screens reuse the parameterized #773 `settleUpBalanceChangedReviewAgain`
/// copy with the LIVE number instead of the generic fallback.
int? overOutstandingFils(Object error) {
  if (error is! FirebaseFunctionsException) return null;
  final details = error.details;
  if (details is! Map || details['kind'] != 'over-outstanding') return null;
  final fils = details['outstandingFils'];
  return fils is int ? fils : null;
}

/// The localized snackbar message for a classified settlement write failure.
String settlementWriteErrorMessage(
  AppLocalizations l10n,
  SettlementWriteErrorKind kind,
) {
  return switch (kind) {
    SettlementWriteErrorKind.network => l10n.settleUpRecordFailed,
    SettlementWriteErrorKind.denied => l10n.settleUpRecordFailedDenied,
    // Parameterless fallback — the over-outstanding case is intercepted by the
    // screens via [overOutstandingFils] and rendered with the #773 copy.
    SettlementWriteErrorKind.staleBalance => l10n.settleUpRecordFailedGeneric,
    SettlementWriteErrorKind.unknown => l10n.settleUpRecordFailedGeneric,
  };
}

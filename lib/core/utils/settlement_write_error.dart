import 'package:firebase_core/firebase_core.dart';

import '../../l10n/generated/app_localizations.dart';

/// Why a settlement write failed, coarse enough to pick a user-facing message
/// that doesn't lie about the cause (#360).
///
/// Settle-up previously mapped *every* failure to "check your connection", so a
/// real `PERMISSION_DENIED` / validation rejection was misattributed to the
/// network. The settlement write (`SettlementService.addSettlement`) does
/// `await …doc().set()` and only ever throws a [FirebaseException] (or an
/// [ArgumentError] for a programming bug), so classifying on the Firestore
/// error code is sufficient — no `dart:io` socket inspection needed.
enum SettlementWriteErrorKind {
  /// Transient connectivity / backend reachability — retry once online.
  network,

  /// The write was refused: rules permission, auth, or value/shape validation.
  denied,

  /// Anything else — surface a neutral "try again", never a false network claim.
  unknown,
}

SettlementWriteErrorKind classifySettlementWriteError(Object error) {
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

/// The localized snackbar message for a classified settlement write failure.
String settlementWriteErrorMessage(
  AppLocalizations l10n,
  SettlementWriteErrorKind kind,
) {
  return switch (kind) {
    SettlementWriteErrorKind.network => l10n.settleUpRecordFailed,
    SettlementWriteErrorKind.denied => l10n.settleUpRecordFailedDenied,
    SettlementWriteErrorKind.unknown => l10n.settleUpRecordFailedGeneric,
  };
}

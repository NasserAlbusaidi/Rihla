import 'package:firebase_core/firebase_core.dart';

/// True when [error] is a Firestore `permission-denied` — the caller lost read
/// access (removed from the group / group deleted / un-shared). Such a listen
/// is TERMINAL: retrying just re-denies. Pair with `NoAccessView` (a terminal
/// no-access state, no Retry) instead of a retryable error view.
///
/// Extracted (#1237) from the private copies in group_detail_screen /
/// event_command_center at the 3rd UI duplication.
bool isPermissionDenied(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';

## auth/ — Anonymous Firebase Auth + Email-Link Recovery

### providers/
- **auth_provider.dart**: `authStateProvider` (Firebase auth stream), `currentUserProvider`, `authUserChangesProvider` (fires on profile/email mutations too), `uidProvider`, `linkedEmailProvider`, `firebaseAuthProvider`, `authRecoveryServiceProvider`. (`currentUserIdProvider` lives in `features/groups/providers/group_balance_provider.dart`; `dataDeletionServiceProvider` is defined in `services/data_deletion_service.dart`.)
- **cache_isolation_controller_provider.dart**: In-session cache-isolation overlay injected into `AuthRecoveryService` for cross-UID Firestore on-device cache teardown.
- **auth_email_link_bootstrap_provider.dart**: One-shot bootstrap that consumes an in-flight email-link op (`opLink` vs `opRecover`) stored in SharedPreferences and routes the cold/warm-start handler through `AuthRecoveryService` to complete linking or recovery.

### services/
- **auth_recovery_service.dart**: Orchestrates the email-link link/send/recover flows. Methods: `linkEmailToCurrentUser`, `sendRecoveryLink`, `completeEmailLink`, `completeRecovery`, `signOutCurrentDevice`, plus pending-email and in-flight-op (`opLink`/`opRecover`) SharedPreferences helpers. Uses Firebase Auth's email-link mechanism with App Links / Universal Links continue URLs.
- **data_deletion_service.dart**: Server-driven account-deletion cascade via the `deleteAccount` callable (Firebase Auth user → Firestore docs → FCM tokens); on success marks the Firestore SDK cache dirty for cross-UID teardown. (Email-link redaction via `redactForLogging` lives in `auth_email_link_config.dart`, not here.)
- _(`uid_change_listener.dart` was removed in #50 with the SQLite cache. Cross-UID isolation of the Firestore on-device cache is now LIVE (#68): cold-start `CacheUidBarrier` + `FirestoreCacheGate` (`lib/core/services/`) plus the in-session `cache_isolation_controller_provider.dart` overlay in this directory.)_
- **auth_email_link_config.dart**: `ActionCodeSettings` factory with `handleCodeInApp: true` and the project's continue URL pinned to Firebase Hosting.

### screens/
- **link_email_screen.dart**: Enter-email screen for opt-in linking; calls `linkEmailToCurrentUser`.
- **link_email_sent_screen.dart**: "Check your email" confirmation after a link request.
- **recover_screen.dart**: Enter-email screen from the Home empty-state recovery CTA; calls `sendRecoveryLink`.
- **recover_pending_screen.dart**: "Check your email" confirmation after a recovery request.

### widgets/
- **delete_account_dialog.dart**: Confirmation dialog before triggering the server-side account-deletion cascade.
- **delete_account_retry_dialog.dart**: Retry prompt shown when a deletion attempt fails partway.
- **sign_out_confirm_dialog.dart**: Confirmation dialog for signing out the current device.
- **merge_on_recover_dialog.dart**: Merge consent shown when recovery starts on a device that already has groups (#427) — the anon UID stays signed in and `completeRecovery`'s server migration merges its data into the restored account (replaced the sign-out-first dialog, whose pre-send sign-out orphaned the device's data).

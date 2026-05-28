## auth/ — Anonymous Firebase Auth + Email-Link Recovery

### providers/
- **auth_provider.dart**: `authStateProvider` (Firebase auth stream), `currentUserProvider`, `currentUserIdProvider`, `authServiceProvider`, `authRecoveryServiceProvider`, `dataDeletionServiceProvider`. `AuthService` handles token checks and `isAuthenticated`.
- **auth_email_link_bootstrap_provider.dart**: One-shot bootstrap that consumes an in-flight email-link op (`opLink` vs `opRecover`) stored in SharedPreferences and routes the cold/warm-start handler through `AuthRecoveryService` to complete linking or recovery.

### services/
- **auth_recovery_service.dart**: Orchestrates the email-link link/send/recover flows. Methods: `sendLinkRequest`, `sendRecoveryLink`, `linkEmailToCurrentUser`, `completeEmailLink`, plus pending-email and in-flight-op SharedPreferences helpers. Uses Firebase Auth's email-link mechanism with App Links / Universal Links continue URLs.
- **data_deletion_service.dart**: Server-driven account deletion cascade (Firebase Auth user → Firestore docs → FCM tokens). Sentry breadcrumbs redact email PII.
- _(`uid_change_listener.dart` removed in #50 with the SQLite cache. Cross-UID isolation of the Firestore on-device cache is a pending follow-up — issue #45 / PR 2.)_
- **auth_email_link_config.dart**: `ActionCodeSettings` factory with `handleCodeInApp: true` and the project's continue URL pinned to Firebase Hosting.

### screens/
- **link_email_screen.dart**: Enter-email screen for opt-in linking; calls `linkEmailToCurrentUser`.
- **link_email_sent_screen.dart**: "Check your email" confirmation after a link request.
- **recover_screen.dart**: Enter-email screen from the Home empty-state recovery CTA; calls `sendRecoveryLink`.
- **recover_pending_screen.dart**: "Check your email" confirmation after a recovery request.

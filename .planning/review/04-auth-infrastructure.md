# Auth & Core Infrastructure — CRITICAL + MEDIUM

**3/4 FIXED | 1 partially fixed**

## ~~4. Anonymous Auth Failure Is Silent~~ FIXED

`main.dart` now wraps auth in `_AuthGate` StatefulWidget using FutureBuilder. On failure: error reported to Sentry, user sees retry screen with "Try Again" button. On success: transitions to SafarApp. `firebase_config.dart` rethrows `FirebaseAuthException` so the error propagates correctly.

## ~~20. Database Init Hang~~ FIXED

`local_database.dart` database getter now wraps `_initDatabase()` in try-catch: on failure, completes the completer with error (unblocking waiters), resets `_initCompleter = null` so next access retries. `close()` resets completer too.

## 23. Connectivity Check Burns Firestore Reads — PARTIALLY FIXED

Still reads from `inviteCodes` every 60 seconds, but since inviteCodes now requires auth (security fix 1c), the read pattern is at least authenticated. Timer still runs when backgrounded. Comment in code is now stale (references inviteCodes being "publicly readable" which is no longer true).

**Fix:** Use Firebase `.info/connected` listener. Pause timer when backgrounded.

## ~~24. OpenContainer Bypasses GoRouter~~ STILL OPEN

`home_screen.dart:204-228` — Group cards still use `OpenContainer` from animations package, creating routes outside GoRouter. Deep links won't match, redirect guards don't apply.

**Fix:** Replace with GoRouter navigation + custom hero animation within the router.

## Files Involved

- `lib/core/config/firebase_config.dart`
- `lib/core/services/local_database.dart`
- `lib/core/providers/connectivity_provider.dart`
- `lib/features/home/screens/home_screen.dart`

---
phase: 27-wire-notification-service
plan: 01
subsystem: infra
tags: [riverpod, fcm, notifications, provider-wiring]

requires:
  - phase: 26-settings-support
    provides: "ProfileNotificationsSection toggle that persists pushNotificationsEnabled via settingsProvider"
provides:
  - "appBootstrapProvider activated in SafarApp.build() — ref.listen fires on push toggle"
  - "Integration test proving notification sync wiring end-to-end"
affects: []

tech-stack:
  added: []
  patterns: ["Provider<void> activation via ref.watch in root widget"]

key-files:
  created:
    - test/core/providers/app_bootstrap_wiring_test.dart
  modified:
    - lib/main.dart

key-decisions:
  - "Single ref.watch(appBootstrapProvider) in SafarApp.build() — void return, activation-only"

patterns-established:
  - "Root-level provider activation: watch Provider<void> in app root to activate ref.listen callbacks"

requirements-completed: [NOTIF-02]

duration: 5min
completed: 2026-04-02
---

# Phase 27: Wire Notification Service Summary

**appBootstrapProvider wired into SafarApp.build() so push notification toggle triggers FCM initialize/removeToken**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-02
- **Completed:** 2026-04-02
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments
- Added `ref.watch(appBootstrapProvider)` to `SafarApp.build()` — activates the provider's `ref.listen` on `pushNotificationsEnabled`
- Created integration test proving the full chain: toggle -> settingsProvider -> appBootstrapProvider.ref.listen -> NotificationService.initialize()/removeToken()
- All existing profile and settings tests pass without regression

## Task Commits

1. **Task 1: Wire appBootstrapProvider + verification test** - `a24dc96` (feat)

## Files Created/Modified
- `lib/main.dart` - Added import + ref.watch(appBootstrapProvider) in SafarApp.build()
- `test/core/providers/app_bootstrap_wiring_test.dart` - Integration test verifying notification sync fires on settings changes

## Decisions Made
None - followed plan as specified.

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- NOTIF-02 gap closed — notification service fully wired
- v2.2 milestone gap closure complete
- Ready to proceed to v2.3 phases (Groups, Events & Modules)

---
*Phase: 27-wire-notification-service*
*Completed: 2026-04-02*

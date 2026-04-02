---
phase: 27-wire-notification-service
status: passed
verified: 2026-04-02
requirements: [NOTIF-02]
---

# Phase 27: Wire Notification Service — Verification

## Goal
Notification toggle actually controls FCM — appBootstrapProvider activated in widget tree.

## Must-Haves

### 1. appBootstrapProvider is watched in SafarApp.build()
- **Status:** PASS
- **Evidence:** `grep -c "ref.watch(appBootstrapProvider)" lib/main.dart` returns `1`
- **Location:** `lib/main.dart:71`

### 2. Toggling push notifications calls initialize()/removeToken()
- **Status:** PASS
- **Evidence:** `flutter test test/core/providers/app_bootstrap_wiring_test.dart` — 3/3 tests pass
- **Tests verify:**
  - pushNotificationsEnabled=true → `NotificationService.initialize()` called
  - pushNotificationsEnabled toggled off → `NotificationService.removeToken()` called

## Requirement Traceability

| Requirement | Description | Status |
|-------------|-------------|--------|
| NOTIF-02 | User can toggle push notifications on/off | PASS — toggle persists preference AND triggers FCM via appBootstrapProvider |

## Automated Checks

| Check | Result |
|-------|--------|
| `grep ref.watch(appBootstrapProvider) lib/main.dart` | 1 match |
| `flutter test test/core/providers/app_bootstrap_wiring_test.dart` | 3/3 pass |
| `flutter test test/features/profile/` | 16/16 pass (no regressions) |
| `flutter analyze lib/main.dart` | No issues |

## Score

**2/2 must-haves verified — PASSED**

## Human Verification

None required — all checks are automated and the wiring is deterministic.

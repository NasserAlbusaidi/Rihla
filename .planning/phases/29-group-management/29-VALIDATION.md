---
phase: 29
slug: group-management
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-02
---

# Phase 29 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (built-in Flutter SDK) |
| **Config file** | `pubspec.yaml` (flutter test section) |
| **Quick run command** | `flutter test test/features/groups/group_settings_screen_test.dart` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/features/groups/group_settings_screen_test.dart`
- **After every plan wave:** Run `flutter test test/features/groups/`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| T1 | 01 | 1 | GroupSettingsScreen renders with card sections | widget | `flutter test test/features/groups/group_settings_screen_test.dart` | Wave 0 — new | ○ |
| T2 | 01 | 1 | GroupInfoSection shows name, currency, invite code | widget | same | Wave 0 — new | ○ |
| T3 | 01 | 1 | GroupMembersSection shows members with creator badge | widget | same | Wave 0 — new | ○ |
| T4 | 01 | 1 | Creator badge renders for creator only | widget | same | Wave 0 — new | ○ |
| T5 | 02 | 1 | Non-creator does not see delete tile | widget | same | Wave 0 — new | ○ |
| T6 | 02 | 1 | All members see leave tile | widget | same | Wave 0 — new | ○ |
| T7 | 02 | 1 | Leave dialog appears on tap | widget | same | Wave 0 — new | ○ |
| T8 | 02 | 1 | Delete dialog appears on tap (creator) | widget | same | Wave 0 — new | ○ |
| T9 | 02 | 1 | Remove blocked by non-zero balance shows SnackBar | widget | same | Wave 0 — new | ○ |
| T10 | 02 | 1 | Existing group_screens_test.dart tests still pass | widget | `flutter test test/features/groups/group_screens_test.dart` | Exists — update | ○ |

---

## Wave 0 Checklist

- [ ] Test file created: `test/features/groups/group_settings_screen_test.dart`
- [ ] Quick run command works: `flutter test test/features/groups/group_settings_screen_test.dart`
- [ ] Existing tests updated: `test/features/groups/group_screens_test.dart`

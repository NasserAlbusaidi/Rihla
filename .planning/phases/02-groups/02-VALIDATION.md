---
phase: 2
slug: groups
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-26
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test + fake_cloud_firestore 4.x |
| **Config file** | `pubspec.yaml` (dev_dependencies) |
| **Quick run command** | `flutter test test/unit/` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/unit/`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | GRP-01 | unit | `flutter test test/unit/group_model_test.dart` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 | 1 | GRP-02 | unit | `flutter test test/unit/invite_code_test.dart` | ❌ W0 | ⬜ pending |
| 02-02-01 | 02 | 1 | GRP-01 | unit | `flutter test test/unit/group_service_test.dart` | ❌ W0 | ⬜ pending |
| 02-02-02 | 02 | 1 | GRP-03 | unit | `flutter test test/unit/group_join_test.dart` | ❌ W0 | ⬜ pending |
| 02-03-01 | 03 | 2 | GRP-06 | widget | `flutter test test/features/groups/` | ❌ W0 | ⬜ pending |
| 02-03-02 | 03 | 2 | GRP-07 | widget | `flutter test test/features/home/` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/unit/group_model_test.dart` — stubs for GRP-01 (group creation model)
- [ ] `test/unit/invite_code_test.dart` — stubs for GRP-02 (invite code generation/validation)
- [ ] `test/unit/group_service_test.dart` — stubs for GRP-01, GRP-03 (Firestore service)
- [ ] `test/unit/group_join_test.dart` — stubs for GRP-03 (join flow)
- [ ] `test/features/groups/` — widget test directory for group screens
- [ ] `fake_cloud_firestore` in dev_dependencies — if not already added in Phase 1

*Existing flutter_test infrastructure covers framework basics.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Share sheet opens with invite code | GRP-02 | Platform share sheet not testable in unit tests | Create group → tap share → verify share sheet appears with code |
| Groups persist across app restart | GRP-06 | Requires full app lifecycle | Create group → kill app → reopen → verify group in list |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

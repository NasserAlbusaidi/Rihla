---
phase: 24
slug: visual-density-polish
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-01
---

# Phase 24 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test + mocktail |
| **Config file** | `pubspec.yaml` (dev_dependencies) |
| **Quick run command** | `flutter test test/features/` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/features/`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 24-01-01 | 01 | 1 | CARD-01 | widget | `flutter test test/features/home_test.dart` | ❌ W0 | ⬜ pending |
| 24-01-02 | 01 | 1 | CARD-02 | widget | `flutter test test/features/home_test.dart` | ❌ W0 | ⬜ pending |
| 24-02-01 | 02 | 1 | CHRT-01 | widget | `flutter test test/features/home_test.dart` | ❌ W0 | ⬜ pending |
| 24-02-02 | 02 | 1 | CHRT-02 | widget | `flutter test test/features/home_test.dart` | ❌ W0 | ⬜ pending |
| 24-03-01 | 03 | 1 | LAYT-01 | widget | `flutter test test/features/home_test.dart` | ❌ W0 | ⬜ pending |
| 24-03-02 | 03 | 1 | LAYT-02 | widget | `flutter test test/features/home_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/features/home_test.dart` — stubs for CARD-01, CARD-02, CHRT-01, CHRT-02, LAYT-01, LAYT-02
- [ ] Test fixtures for GroupCard with mock group events provider
- [ ] Test fixtures for WeeklySpendingCard with mock spending data

*Existing test infrastructure (mocktail, provider overrides) covers framework needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Accent strip color is visually distinct per group | CARD-01 | Color perception requires visual inspection | Run app, view 3+ groups, verify each card has different accent color |
| Chart bar labels are readable at device size | CHRT-01 | Font size legibility is device-dependent | Run app on device/emulator, check label text is readable without squinting |
| Dashboard spacing rhythm feels tight | LAYT-01 | Subjective visual density assessment | Run app, scroll dashboard, verify no large whitespace gaps between sections |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

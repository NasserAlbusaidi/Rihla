---
phase: 18
slug: home-dashboard-redesign
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-29
---

# Phase 18 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (built-in) + mocktail |
| **Config file** | `pubspec.yaml` (test dependencies already configured) |
| **Quick run command** | `flutter test test/features/home/` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/features/home/`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 18-01-01 | 01 | 1 | NAV-01 | unit | `flutter test test/features/home/` | ❌ W0 | ⬜ pending |
| 18-01-02 | 01 | 1 | NAV-02 | unit | `flutter test test/features/home/` | ❌ W0 | ⬜ pending |
| 18-01-03 | 01 | 1 | NAV-04 | widget | `flutter test test/features/home/` | ❌ W0 | ⬜ pending |
| 18-01-04 | 01 | 1 | NAV-06 | widget | `flutter test test/features/home/` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/features/home/` — test directory for home dashboard widgets
- [ ] Test stubs for BalanceHeroCard, QuickActionTray, GroupCard, EmptyStateView
- [ ] Provider mocks for crossGroupBalanceProvider, userGroupsProvider

*Existing test infrastructure (mocktail, provider overrides) covers framework needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 60fps scroll performance | NAV-04 (SC4) | Requires physical device + DevTools Performance view | Run on mid-range Android, scroll group list, check no frame > 16ms |
| Visual color-coding accuracy | NAV-01 (SC1) | Widget tests can check semantics but not visual rendering | Verify green/red/gray balance colors render correctly on device |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

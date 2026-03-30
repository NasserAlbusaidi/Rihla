---
phase: 20
slug: group-detail-event-hub-redesign
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-30
---

# Phase 20 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (widget tests) |
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
| TBD | TBD | TBD | SCRN-01 | widget | `flutter test test/features/group_detail_screen_test.dart` | ✅ | ⬜ pending |
| TBD | TBD | TBD | SCRN-02 | widget | `flutter test test/features/ledger_test.dart` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Update `test/features/group_detail_screen_test.dart` — adapt for stats grid replacing GroupBalanceHero
- [ ] Update `test/features/ledger_test.dart` — adapt for new expense hero label
- [ ] Add `animations` package to `pubspec.yaml` for OpenContainer

*Existing infrastructure covers most phase requirements. Wave 0 adds the `animations` dependency and fixes test assertions broken by the redesign.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| ContainerTransform animation smoothness | SCRN-01 | Visual animation quality cannot be automated | Navigate from HomeScreen group card to group detail; verify smooth morphing transition |
| Past event opacity visual distinction | SCRN-01 | Opacity rendering is visual | Create events with past dates; verify 60% opacity visual recession |
| Earthy palette consistency | SCRN-02 | Color harmony is visual judgment | Compare event hub against Phase 16 Stitch mockup |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

---
phase: 21
slug: module-screens-redesign
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-30
---

# Phase 21 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (Flutter 3.41.5) + mocktail ^1.0.4 |
| **Config file** | none (uses flutter test command directly) |
| **Quick run command** | `flutter test test/features/ledger_test.dart test/features/gear_screen_mutations_test.dart test/features/logistics_screen_mutations_test.dart` |
| **Full suite command** | `flutter test --no-pub` |
| **Estimated runtime** | ~11 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test --no-pub`
- **After every plan wave:** Run `flutter test --no-pub`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 11 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 21-01-01 | 01 | 1 | SCRN-03 | Widget | `flutter test test/features/ledger_test.dart` | ✅ (needs new assertions) | ⬜ pending |
| 21-01-02 | 01 | 1 | SCRN-03 | Widget | `flutter test test/features/ledger_test.dart` | ❌ W0 | ⬜ pending |
| 21-01-03 | 01 | 1 | SCRN-03 | Widget | `flutter test test/features/ledger_test.dart` | ❌ W0 | ⬜ pending |
| 21-02-01 | 02 | 1 | SCRN-04 | Widget | `flutter test test/features/gear_screen_mutations_test.dart` | ❌ W0 | ⬜ pending |
| 21-02-02 | 02 | 1 | SCRN-04 | Widget | `flutter test test/features/activity_screen_test.dart` | ❌ W0 | ⬜ pending |
| 21-02-03 | 02 | 1 | SCRN-04 | Widget | `flutter test test/features/memories_screen_test.dart` | ❌ W0 | ⬜ pending |
| 21-02-04 | 02 | 1 | SCRN-04 | Unit | `flutter test test/features/empty_state_view_test.dart` | ❌ W0 | ⬜ pending |
| 21-03-01 | 03 | 2 | SCRN-05 | Widget | `flutter test test/features/groups/create_join_group_test.dart` | ✅ (verify no regression) | ⬜ pending |
| 21-03-02 | 03 | 2 | SCRN-05 | Unit | `flutter test test/unit/dot_step_indicator_test.dart` | ❌ W0 | ⬜ pending |
| 21-04-01 | 04 | 3 | SCRN-06 | Widget | `flutter test test/features/onboarding_screen_test.dart` | ❌ W0 | ⬜ pending |
| 21-04-02 | 04 | 3 | SCRN-06 | Widget | `flutter test test/features/splash_screen_test.dart` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/features/ledger/ledger_hero_card_test.dart` — stubs for SCRN-03 hero card
- [ ] `test/features/ledger/expense_card_test.dart` — stubs for SCRN-03 three-line card
- [ ] `test/features/gear/gear_hero_card_test.dart` — stubs for SCRN-04 gear hero
- [ ] `test/features/activity/activity_screen_test.dart` — stubs for SCRN-04 activity timeline
- [ ] `test/features/memories/memories_screen_test.dart` — stubs for SCRN-04 photo grid
- [ ] `test/unit/empty_state_view_test.dart` — stubs for EmptyStateView gradient circle param
- [ ] `test/unit/dot_step_indicator_test.dart` — stubs for SCRN-05 step dots
- [ ] `test/features/onboarding/onboarding_screen_test.dart` — stubs for SCRN-06 light background
- [ ] `test/features/splash/splash_screen_test.dart` — stubs for SCRN-06 warm sand

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Color-coded balance amounts visually correct | SCRN-03 | Color perception requires visual inspection | Inspect ledger with positive/negative/zero balances, verify green/red/gray |
| Empty state illustrations render correctly | SCRN-04 | Illustration visual quality is subjective | Navigate to each module with no data, verify illustration + CTA |
| Earthy palette "feels" cohesive | SCRN-03-06 | Aesthetic coherence is subjective | Full app walkthrough comparing to UI-SPEC mockups |
| Onboarding flow visual identity | SCRN-06 | Animation + transition quality | Step through all 3 onboarding pages, verify warm earthy identity |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 11s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

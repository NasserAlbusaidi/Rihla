---
phase: 20
slug: group-detail-event-hub-redesign
status: draft
nyquist_compliant: true
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
| P01-T01 | 01 | 0 | SCRN-01 | widget | `flutter test test/features/group_detail_screen_test.dart` | Yes | ⬜ pending |
| P01-T02 | 01 | 1 | SCRN-01 | widget + analyze | `flutter analyze lib/features/groups/widgets/group_stats_grid.dart lib/features/events/widgets/event_card.dart && flutter test test/features/group_detail_screen_test.dart` | Partial (group_stats_grid.dart new) | ⬜ pending |
| P01-T03 | 01 | 1 | SCRN-01 | widget + full suite | `flutter test test/features/group_detail_screen_test.dart && flutter test` | Yes | ⬜ pending |
| P02-T01 | 02 | 0 | SCRN-02 | widget | `flutter test test/features/events/event_command_center_test.dart` | Yes | ⬜ pending |
| P02-T02 | 02 | 1 | SCRN-02 | widget + analyze | `flutter analyze lib/features/events/screens/event_expense_hero.dart lib/features/events/widgets/event_module_list.dart && flutter test test/features/events/event_command_center_test.dart` | Yes | ⬜ pending |
| P02-T03 | 02 | 2 | SCRN-02 | analyze + full suite | `flutter analyze lib/features/events/screens/event_command_center.dart lib/features/home/screens/home_screen.dart && flutter test` | Yes | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Add `animations` package to `pubspec.yaml` (P01-T01)
- [ ] Extend `GroupKeys` with 6 new keys (P01-T01)
- [ ] Update `group_detail_screen_test.dart` assertions for stats grid (P01-T01)
- [ ] Extend `EventKeys` with 4 new keys (P02-T01)
- [ ] Update `event_command_center_test.dart` SPENDING → TOTAL EXPENSES (P02-T01)

*Wave 0 prepares test infrastructure and adds the `animations` dependency.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| ContainerTransform animation smoothness | SCRN-02 | Visual animation quality cannot be automated | Navigate from HomeScreen group card to group detail; verify smooth morphing transition |
| Past event opacity visual distinction | SCRN-01 | Opacity rendering is visual | Create events with past dates; verify 60% opacity visual recession |
| Earthy palette consistency | SCRN-02 | Color harmony is visual judgment | Compare event hub against Phase 16 Stitch mockup |
| Stats grid above the fold | SCRN-01 | Viewport-dependent layout | On ~390px device, verify stats grid + settle-up CTA visible without scrolling |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** ready

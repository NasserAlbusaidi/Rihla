---
phase: 16
slug: stitch-workflow-design-reference
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-28
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Flutter test (existing) |
| **Config file** | pubspec.yaml (no separate test config) |
| **Quick run command** | `flutter test test/unit/design_tokens_test.dart --no-pub` |
| **Full suite command** | `flutter test --no-pub` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/unit/design_tokens_test.dart --no-pub`
- **After every plan wave:** Run `flutter test --no-pub`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 16-01-01 | 01 | 1 | FOUND-03 | manual | `test -f .planning/design/home-screen-spec.md` | N/A | ⬜ pending |
| 16-01-02 | 01 | 1 | FOUND-03 | manual | `test -f .planning/phases/16-*/prompts/home-screen-prompt.md` | N/A | ⬜ pending |
| 16-02-01 | 02 | 1 | FOUND-03 | manual | `test -f .planning/design/group-detail-spec.md` | N/A | ⬜ pending |
| 16-02-02 | 02 | 1 | FOUND-03 | manual | `test -f .planning/phases/16-*/prompts/group-detail-prompt.md` | N/A | ⬜ pending |
| 16-03-01 | 03 | 1 | FOUND-03 | manual | `test -f .planning/design/event-hub-spec.md` | N/A | ⬜ pending |
| 16-03-02 | 03 | 1 | FOUND-03 | manual | `test -f .planning/phases/16-*/prompts/event-hub-prompt.md` | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. Phase 16 produces no executable code — all deliverables are markdown design artifacts.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Stitch prompts include full earthy palette hex values | FOUND-03 | Content quality — file existence is automated but content completeness requires review | Verify each prompt file contains all 30 AppColorTokens hex values |
| Design specs include token mapping tables | FOUND-03 | Structural content check — presence of mapping table per spec | Verify each spec file contains `## Token Mapping` section with non-empty table |
| Post-generation checklist covers all 4 checks | FOUND-03 | Content completeness | Verify checklist has: color token mapping, spacing consistency, component reuse, accessibility |
| CLAUDE.md Stitch workflow section exists | FOUND-03 | Documentation completeness | Verify CLAUDE.md contains `Stitch-to-Flutter` workflow section |
| WCAG compliance for all color pairings in specs | FOUND-03 | Design correctness | Verify no spec uses textMuted (#A89888) for body text; all foreground/background pairs pass AA |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

---
phase: 15
slug: design-token-system
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-28
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (SDK) |
| **Config file** | none (pubspec.yaml `flutter_test` dep) |
| **Quick run command** | `flutter test test/unit/design_tokens_test.dart --no-pub` |
| **Full suite command** | `flutter test --no-pub` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `flutter test test/unit/design_tokens_test.dart --no-pub`
- **After every plan wave:** Run `flutter test --no-pub`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 1 | FOUND-01 | unit | `flutter test test/unit/design_tokens_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 15-01-02 | 01 | 1 | FOUND-01 | unit | `flutter test test/unit/design_tokens_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 15-01-03 | 01 | 1 | FOUND-02 | unit | `flutter test test/unit/design_tokens_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 15-02-01 | 02 | 1 | FOUND-01 | static | `flutter analyze` | existing | ⬜ pending |
| 15-02-02 | 02 | 1 | FOUND-01 | unit | `flutter test test/unit/design_tokens_test.dart --no-pub` | ❌ W0 | ⬜ pending |
| 15-03-01 | 03 | 2 | FOUND-01 | static | `flutter analyze` | existing | ⬜ pending |
| 15-03-02 | 03 | 2 | FOUND-01 | unit | `flutter test test/unit/design_tokens_test.dart --no-pub` | existing | ⬜ pending |
| 15-04-01 | 04 | 2 | FOUND-04 | manual CI | `grep -rn "Color(0x" lib/ --include="*.dart"` | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/unit/design_tokens_test.dart` — stubs for FOUND-01 (token registration, field values, context extension access) and FOUND-02 (contrast ratio assertions for all text-on-background combinations)
- [ ] No new conftest or fixture files needed — tests use `MaterialApp(theme: AppTheme.lightTheme)`

*Existing infrastructure covers framework dependencies. Only the test file is new.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| CI step exits 1 on hardcoded Color(0xFF...) in non-exempt lib/ file | FOUND-04 | CI-only grep step; no Dart test appropriate | Run `grep -rn "Color(0x" lib/ --include="*.dart" \| grep -v "app_theme.dart" \| grep -v "tokens/" \| grep -v "expense_category_model.dart"` locally — expect 0 matches after migration |
| App renders with warm earthy palette after hot restart | FOUND-01 | Visual verification | Hot restart app, confirm terracotta buttons, sand backgrounds, olive/teal/bronze module accents |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

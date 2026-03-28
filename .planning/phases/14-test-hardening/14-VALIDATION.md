---
phase: 14
slug: test-hardening
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-28
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | flutter_test (SDK-bundled, Flutter 3.41.5) |
| **Config file** | none — standard `flutter test` |
| **Quick run command** | `flutter test test/unit/widget_coverage_test.dart` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | ~120 seconds (full suite) |

---

## Sampling Rate

- **After every task commit:** Run `flutter test <specific_test_file>`
- **After every plan wave:** Run `flutter test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds (single file), 120 seconds (full suite)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 14-01-01 | 01 | 1 | FOUND-05 | unit | `flutter test` (full suite passes after key additions) | Yes — existing suite | ⬜ pending |
| 14-01-02 | 01 | 1 | FOUND-05 | smoke | Manual rename 'Ledger' → 'Treasury' + `flutter test` | Yes — D-13 protocol | ⬜ pending |
| 14-01-03 | 01 | 1 | FOUND-05 | regression | `flutter test` (624 tests pass) | Yes | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. Key class files (`lib/features/*/keys/*.dart`, `lib/core/keys/shared_keys.dart`) are source files, not test infrastructure.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Rename resilience (D-13) | FOUND-05 | Requires temporary code modification + revert | 1. Rename 'Ledger' → 'Treasury' in source 2. Run `flutter test` 3. Confirm only content-validation tests fail 4. Revert rename |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

---
status: partial
phase: 37-dark-theme-migration
source: [37-VERIFICATION.md]
started: 2026-04-18T10:20:00Z
updated: 2026-04-18T10:20:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Real-device theme cycle (System → Light → Dark)
expected: All cards/heroes render with richer black shadow tint in Dark (Color(0x59000000)), lighter slate tint in Light (Color(0x14111827)). System-chrome (status bar / navigation bar) icon brightness flips immediately without navigating away. Setting persists across app restart.
result: [pending]

### 2. MANUAL-QA.md §2 22-screen walkthrough in Dark mode
expected: Every elevated surface (hero cards, list rows, floating action buttons, dialogs, bottom sheets) shows the darker shadow tint in Dark mode. No card appears 'flat' or loses separation from the background. No residual light-theme artifact (pale borders, unexpected white fills) on any screen.
result: [pending]

### 3. Rapid Light↔Dark toggle (5x in succession)
expected: Smooth cross-fade via MaterialApp themeMode; no layout shift, no single-frame flash of the wrong theme, no shadow ghosting.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps

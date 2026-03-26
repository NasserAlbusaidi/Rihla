---
status: partial
phase: 02-groups
source: [02-VERIFICATION.md]
started: 2026-03-26T00:00:00Z
updated: 2026-03-26T00:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Group creation and invite code sharing
expected: Group created in Firestore, invite code appears in share sheet, copy button copies to clipboard, share button opens native OS share sheet
result: [pending]

### 2. Join group via invite code
expected: Entering a valid 6-char code adds user to group, auto-submits at 6 chars, navigates to GroupDetailScreen showing group content
result: [pending]

### 3. Group persistence across app restarts
expected: Firestore offline persistence serves group data on relaunch without network call; group is NOT gone after app restart
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps

---
status: partial
phase: 02-groups
source: [02-VERIFICATION.md]
started: 2026-03-26T00:00:00Z
updated: 2026-03-26T00:00:00Z
---

## Current Test

[UAT in progress]

## Tests

### 1. Group creation and invite code sharing
expected: Group created in Firestore, invite code appears in share sheet, copy button copies to clipboard, share button opens native OS share sheet
result: passed (after fixes)

### 2. Join group via invite code
expected: Entering a valid 6-char code adds user to group, auto-submits at 6 chars, navigates to GroupDetailScreen showing group content
result: passed (after fixes — security rules, name field, sequential writes)

### 3. Group persistence across app restarts
expected: Firestore offline persistence serves group data on relaunch without network call; group is NOT gone after app restart
result: passed (after fixes)

## Summary

total: 3
passed: 3
issues: 2
pending: 0
skipped: 0
blocked: 0

## Gaps

### 1. Firebase anonymous auth not resilient (fixed)
status: resolved
description: ensureAnonymousSession() crashed app on auth failure — no try-catch.
fix: Added try-catch to FirebaseConfig and skip-when-unconfigured to SupabaseConfig.

### 2. .firebaserc wrong project ID (fixed)
status: resolved
description: .firebaserc had "rihla-app" but actual project is "rihla-safar".
fix: Updated .firebaserc.

### 3. WriteBatch security rules ordering (fixed)
status: resolved
description: createGroup single WriteBatch failed — member subcollection rule needs group to exist first.
fix: Split into two writes.

### 4. Composite index missing (fixed)
status: resolved
description: arrayContains + orderBy query needs composite index.
fix: Added to firestore.indexes.json and deployed.

### 5. Auth session not persisted across restarts (fixed)
status: resolved
description: New anonymous UID created every restart. Provider captured stale null UID.
fix: authStateChanges().first + reactive firebaseUserProvider.

### 6. Join security rules blocked non-members (fixed)
status: resolved
description: joinGroup tried to read group doc and update memberIds, but isMember() check blocked non-members.
fix: Added isValidJoin() rule allowing authenticated users to add only their UID to memberIds. Sequential writes instead of batch.

### 7. Blank member names (fixed)
status: resolved
description: deviceName defaulted to empty string. Create/join screens used read-only display.
fix: Editable name field on both screens. Saved to settings before create/join. Fallback to 'Anonymous' in GroupService.

### 8. Pull-to-refresh not functional
status: failed
description: Pull-to-refresh gesture on home screen groups list does not reload data.

### 9. Join group auto-submit fires before name entry
status: resolved
description: Auto-submit at 6 chars could fire before user enters name. Added name-empty check that shows snackbar.
fix: _joinGroup checks trimmedName.isEmpty before proceeding.

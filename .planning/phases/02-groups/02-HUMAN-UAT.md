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
result: passed (after fixes — see Gaps below)

### 2. Join group via invite code
expected: Entering a valid 6-char code adds user to group, auto-submits at 6 chars, navigates to GroupDetailScreen showing group content
result: [pending]

### 3. Group persistence across app restarts
expected: Firestore offline persistence serves group data on relaunch without network call; group is NOT gone after app restart
result: passed (after fixes — see Gaps below)

## Summary

total: 3
passed: 2
issues: 1
pending: 1
skipped: 0
blocked: 0

## Gaps

### 1. Firebase anonymous auth not resilient (fixed)
status: resolved
description: ensureAnonymousSession() crashed app on auth failure — no try-catch. Both Firebase and Supabase auth init lacked error handling.
fix: Added try-catch to FirebaseConfig and skip-when-unconfigured to SupabaseConfig.

### 2. .firebaserc wrong project ID (fixed)
status: resolved
description: .firebaserc had project ID "rihla-app" but actual Firebase project is "rihla-safar". Blocked rule and index deployment.
fix: Updated .firebaserc to "rihla-safar".

### 3. WriteBatch security rules ordering (fixed)
status: resolved
description: createGroup used a single WriteBatch for group + inviteCode + member docs. Firestore security rules evaluate each doc against current DB state — member subcollection rule calls get() on group doc that doesn't exist yet in same batch → permission-denied.
fix: Split into two writes — group+inviteCode batch first, then member doc after group exists.

### 4. Composite index missing (fixed)
status: resolved
description: userGroupsProvider query (arrayContains memberIds + orderBy createdAt) requires a Firestore composite index. Not auto-created.
fix: Added index to firestore.indexes.json and deployed.

### 5. Auth session not persisted across restarts (fixed)
status: resolved
description: ensureAnonymousSession() checked currentUser synchronously after initializeApp() — null because auth restoration is async. Created new anonymous UID every restart. Also userGroupsProvider captured UID once at provider creation, never updated.
fix: Wait for authStateChanges().first before checking. Added firebaseUserProvider so groups query re-runs when auth restores.

### 6. Pull-to-refresh not functional
status: failed
description: Pull-to-refresh gesture on home screen groups list does not reload data.

### 7. Join group flow
status: pending
description: Not yet tested by user.

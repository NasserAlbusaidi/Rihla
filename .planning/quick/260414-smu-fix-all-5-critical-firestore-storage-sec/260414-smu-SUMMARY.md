---
type: quick
category: security
phase: null
plan: 260414-smu
subsystem: security-rules
tags: [firestore, storage, security, rules]
key-files:
  created: []
  modified:
    - security/firestore.rules
    - security/storage.rules
decisions:
  - "Replaced generic wildcard subcollection rule with explicit members/activity/settlements — prevents undiscovered subcollection access"
  - "Activity logs are append-only (no update/delete) — immutable audit trail"
  - "inviteCodes delete scoped to authenticated users (not membership) — batch delete in deleteGroup() deletes group doc in same batch, so membership check is impossible"
  - "Storage membership-based access deferred — requires Cloud Functions custom claims infrastructure"
metrics:
  duration: "4m 6s"
  completed: "2026-04-14T16:45:19Z"
  tasks: 3
  files: 2
---

# Quick Task 260414-smu: Fix All 5 Critical Firestore/Storage Security Vulnerabilities

Hardened Firestore rules with explicit subcollection rules, owner-only FCM tokens, shape-validated invite codes, creator-only group delete, and role-lock on member updates. Added server-side 25MB file size limits to Storage rules.

## Changes Made

### Task 1: Firestore Rules Hardening (31e1618)

**1e - Replaced generic wildcard subcollection rule** with three explicit blocks:
- `members/{memberId}` — read/create/delete for group members, update with role-lock (`request.resource.data.role == resource.data.role`)
- `activity/{activityId}` — read/create for group members, update/delete denied (append-only)
- `settlements/{settlementId}` — full read/write for group members

**1a - Added fcm_tokens rules:** Owner-only (`request.auth.uid == userId`) read/write. Doc ID is the user's UID, matching the client pattern in notification_service.dart.

**1c - Tightened inviteCodes rules:**
- Read: authenticated users only (was `allow read: if true`)
- Create: authenticated + shape validation (`hasOnly(['groupId', 'createdAt'])`)
- Update: denied
- Delete: authenticated (needed for deleteGroup batch)

**1d - Creator-only group delete:** `request.auth.uid == resource.data.createdBy` (was `allow delete: if false`).

### Task 2: Storage Rules Hardening (d068f6c)

- Separated read/write permissions (previously combined)
- Added `request.resource.size < 25 * 1024 * 1024` on both `trip-documents` and `trip-memories` write paths
- Documented membership-based access limitation in file comments

### Task 3: Syntax Validation and Client Alignment

- Balanced braces validated in both files
- No generic wildcard subcollection rule remains
- All 7 client write paths verified against new rules:
  - fcm_tokens/{userId} -- notification_service.dart set/delete
  - groups/{groupId} -- group_provider.dart create/update/delete
  - groups/{groupId}/members/{memberId} -- group_provider.dart create/update/delete
  - groups/{groupId}/activity/{activityId} -- group_activity_service.dart create
  - groups/{groupId}/settlements/{settlementId} -- group_settlement_service.dart create/read
  - inviteCodes/{code} -- group_provider.dart create/read/delete
  - groups/{groupId}/events/{eventId}/** -- unchanged, already explicit
- Firebase deploy skipped (403 permission error on safar-app project) -- deploy manually

## Deviations from Plan

None -- plan executed exactly as written.

## Threat Mitigations Applied

| Threat ID | Mitigation | Status |
|-----------|-----------|--------|
| T-sec-01 | Role field locked via `request.resource.data.role == resource.data.role` on member updates | Complete |
| T-sec-02 | inviteCodes shape-validated on create, update denied, auth required | Complete |
| T-sec-03 | fcm_tokens owner-only via `request.auth.uid == userId` | Complete |
| T-sec-04 | Server-side 25MB limit via `request.resource.size` | Complete |
| T-sec-05 | Creator-only group delete via `request.auth.uid == resource.data.createdBy` | Complete |
| T-sec-06 | Storage membership access — accepted risk, auth-only check | Documented |

## Known Stubs

None.

## Commits

| Task | Commit | Files |
|------|--------|-------|
| 1 | 31e1618 | security/firestore.rules |
| 2 | d068f6c | security/storage.rules |
| 3 | (validation only, no file changes) | -- |

---
type: quick
category: security
files_modified:
  - security/firestore.rules
  - security/storage.rules
autonomous: true
must_haves:
  truths:
    - "fcm_tokens collection allows owner-only read/write (uid == docId)"
    - "Group subcollection wildcard replaced with explicit members/activity/settlements rules"
    - "Role field is immutable on member document updates"
    - "inviteCodes readable only by authenticated users, writable only during group create batch"
    - "Group creator can delete their own group document"
    - "Storage rules enforce 25MB file size limit server-side"
  artifacts:
    - path: "security/firestore.rules"
      provides: "All 5 Firestore vulnerability fixes"
    - path: "security/storage.rules"
      provides: "File size limits and tighter auth"
---

<objective>
Fix all 5 critical Firestore/Storage security vulnerabilities identified in `.planning/review/01-security.md`.

Purpose: Close privilege escalation, silent write failures, and open-access holes in production security rules.
Output: Hardened `firestore.rules` and `storage.rules` files.
</objective>

<context>
@security/firestore.rules
@security/storage.rules
@.planning/review/01-security.md
@lib/core/services/notification_service.dart
@lib/features/groups/providers/group_provider.dart
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix Firestore rules (1e, 1a, 1c, 1d) -- structural wildcard + 3 collection fixes</name>
  <files>security/firestore.rules</files>
  <action>
Rewrite `security/firestore.rules` with these changes, in order:

**1e -- Replace generic group subcollection wildcard (lines 103-111) with explicit rules:**

Remove the catch-all `match /{subcollection}/{docId}` block entirely. Replace with three explicit subcollection match blocks under `match /groups/{groupId}`:

```
match /members/{memberId} {
  function isGroupMemberForMembers() {
    return request.auth != null &&
      request.auth.uid in
        get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds;
  }
  allow read: if isGroupMemberForMembers();
  allow create: if isGroupMemberForMembers();
  // Lock role field on updates -- prevents MEMBER -> CREATOR escalation
  allow update: if isGroupMemberForMembers()
    && request.resource.data.role == resource.data.role;
  allow delete: if isGroupMemberForMembers();
}

match /activity/{activityId} {
  function isGroupMemberForActivity() {
    return request.auth != null &&
      request.auth.uid in
        get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds;
  }
  allow read: if isGroupMemberForActivity();
  allow create: if isGroupMemberForActivity();
  // Activity logs are append-only (no updates or deletes)
  allow update, delete: if false;
}

match /settlements/{settlementId} {
  function isGroupMemberForSettlements() {
    return request.auth != null &&
      request.auth.uid in
        get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds;
  }
  allow read, write: if isGroupMemberForSettlements();
}
```

**1a -- Add fcm_tokens rules (new top-level match block):**

Add after the default deny-all block, before the inviteCodes block:

```
match /fcm_tokens/{userId} {
  allow read, write: if request.auth != null
    && request.auth.uid == userId;
}
```

This matches the client pattern in `notification_service.dart` which uses `doc(userId)` where userId = `FirebaseConfig.currentUser?.uid`. Owner-only: the doc ID IS the user's UID.

**1c -- Tighten inviteCodes rules:**

Replace the current inviteCodes block (lines 11-14) with:

```
match /inviteCodes/{code} {
  // Read: authenticated users only (join flow needs to look up groupId)
  allow read: if request.auth != null;
  // Write: only via group create/delete batch (authenticated)
  // The inviteCode doc stores {groupId, createdAt} -- validate shape
  allow create: if request.auth != null
    && request.resource.data.keys().hasOnly(['groupId', 'createdAt'])
    && request.resource.data.groupId is string;
  allow update: if false;
  allow delete: if request.auth != null;
}
```

Note on `allow delete`: The `deleteGroup()` method in group_provider.dart deletes the invite code doc as part of the group deletion batch (line 312). The delete happens in the same batch as the group doc delete. Since we cannot cross-reference group membership during a batch delete (the group doc is being deleted in the same batch), we scope delete to authenticated users. This is acceptable because invite code docs are lookup-only (contain only groupId + createdAt) and knowing a code to delete it requires being in the group to read the inviteCode field.

**1d -- Allow group creator to delete group:**

Replace `allow delete: if false;` (line 44) with:

```
allow delete: if request.auth != null
  && request.auth.uid == resource.data.createdBy;
```

This checks the `createdBy` field on the group document matches the requesting user's UID. The `createdBy` field is set at group creation time (group_provider.dart line 93) and is never updated. No Cloud Function needed.

Note: Cascade subcollection cleanup is deferred -- orphaned events/subcollections under a deleted group are invisible without group membership (per existing code comment at group_provider.dart line 295).

**Verify client code alignment:**
- `notification_service.dart` writes to `fcm_tokens/{userId}` where userId = `FirebaseConfig.currentUser?.uid` -- matches `request.auth.uid == userId` rule.
- `group_provider.dart` `deleteGroup()` reads group doc first (line 304), then batch-deletes members + inviteCode + group doc -- the read requires membership (passes isMember()), the group delete requires createdBy match (passes new rule), the member deletes require membership (passes isGroupMemberForMembers()), the inviteCode delete requires auth (passes).
- `group_provider.dart` `createGroup()` writes inviteCode doc with `{groupId, createdAt}` -- matches the `hasOnly` shape validation.
- `group_provider.dart` `joinGroup()` reads inviteCode doc -- passes `allow read: if request.auth != null`.
  </action>
  <verify>
    <automated>cd /Users/nasseralbusaidi/Desktop/Personal/Rihla && grep -c "match /fcm_tokens" security/firestore.rules && grep -c "match /members/" security/firestore.rules && grep -c "match /activity/" security/firestore.rules && grep -c "match /settlements/" security/firestore.rules && grep "allow delete" security/firestore.rules | grep -c "createdBy" && ! grep -q "match /{subcollection}/{docId}" security/firestore.rules && echo "ALL_CHECKS_PASS"</automated>
  </verify>
  <done>
    - Generic wildcard subcollection rule removed
    - Explicit members/activity/settlements rules with role-lock on member updates
    - fcm_tokens collection has owner-only rules
    - inviteCodes scoped to authenticated users with shape validation
    - Group delete scoped to creator via createdBy field
    - No /{subcollection}/{docId} wildcard remains
  </done>
</task>

<task type="auto">
  <name>Task 2: Fix storage rules (1b) -- file size limits</name>
  <files>security/storage.rules</files>
  <action>
Rewrite `security/storage.rules` to add server-side file size enforcement.

Firebase Storage rules CANNOT perform Firestore lookups for membership verification. The realistic hardening here is: enforce file size limits server-side (the 25MB client-side check in DocumentService is bypassable) and separate read/write permissions.

Replace the current storage rules with:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {

    // Trip documents: authenticated users, 25MB max upload
    match /trip-documents/{eventId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null
        && request.resource.size < 25 * 1024 * 1024;
    }

    // Trip memories (photos): authenticated users, 25MB max upload
    match /trip-memories/{eventId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null
        && request.resource.size < 25 * 1024 * 1024;
    }

    // Default: deny all other paths
    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

Note: Membership-based storage access would require either (a) custom claims set by Cloud Functions (significant infra work) or (b) encoding membership data in storage metadata paths. Both are deferred as follow-up. The file size limit is the high-value fix here -- it prevents abuse (uploading arbitrarily large files) that the client-side check cannot prevent.

Add a comment at the top of the file documenting the limitation:

```
// NOTE: Storage rules cannot query Firestore for membership.
// Membership-based access requires Cloud Functions custom claims (follow-up).
// Current rules: authenticated + file size limit.
```
  </action>
  <verify>
    <automated>cd /Users/nasseralbusaidi/Desktop/Personal/Rihla && grep -c "request.resource.size" security/storage.rules && grep -c "25 \* 1024 \* 1024" security/storage.rules && echo "SIZE_LIMITS_PRESENT"</automated>
  </verify>
  <done>
    - Server-side 25MB file size limit on both storage paths
    - Read and write permissions separated (not combined allow read, write)
    - Limitation documented in file comments
  </done>
</task>

<task type="auto">
  <name>Task 3: Validate rules syntax and verify client alignment</name>
  <files>security/firestore.rules, security/storage.rules</files>
  <action>
Run validation to confirm both rules files are syntactically correct and the client code paths still align.

1. Check Firestore rules parse correctly:
   - Ensure balanced braces (every `{` has matching `}`)
   - Ensure `rules_version = '2'` is present
   - Ensure no duplicate match paths

2. Cross-reference every Firestore write path in client code against rules:
   - `fcm_tokens/{userId}` -- set/delete by notification_service.dart -- covered by fcm_tokens rule
   - `groups/{groupId}` -- create/update/delete by group_provider.dart -- covered by groups rule
   - `groups/{groupId}/members/{memberId}` -- create/update/delete by group_provider.dart -- covered by members rule
   - `groups/{groupId}/activity/{activityId}` -- create by group_activity_service.dart -- covered by activity rule
   - `groups/{groupId}/settlements/{settlementId}` -- create/read by group_settlement_service.dart -- covered by settlements rule
   - `inviteCodes/{code}` -- create/read/delete by group_provider.dart -- covered by inviteCodes rule
   - `groups/{groupId}/events/{eventId}` -- covered by existing events rule (unchanged)
   - Event module subcollections -- covered by existing module rule (unchanged)

3. Run `flutter analyze` to confirm no Dart changes are needed (rules-only fix).

4. Deploy rules to Firebase (if firebase CLI available):
   ```bash
   firebase deploy --only firestore:rules,storage --project safar-app
   ```
   If firebase CLI not available or deploy fails, skip -- rules are committed and can be deployed manually.
  </action>
  <verify>
    <automated>cd /Users/nasseralbusaidi/Desktop/Personal/Rihla && python3 -c "
import re
# Validate balanced braces in firestore.rules
with open('security/firestore.rules') as f:
    content = f.read()
    opens = content.count('{')
    closes = content.count('}')
    assert opens == closes, f'Unbalanced braces: {opens} opens vs {closes} closes'
    assert 'rules_version' in content
    assert '/{subcollection}/{docId}' not in content, 'Generic wildcard still present'
    assert 'fcm_tokens' in content, 'fcm_tokens rule missing'
    assert 'request.resource.data.role == resource.data.role' in content, 'Role lock missing'
    assert 'createdBy' in content, 'Creator delete rule missing'
# Validate storage.rules
with open('security/storage.rules') as f:
    content = f.read()
    opens = content.count('{')
    closes = content.count('}')
    assert opens == closes, f'Unbalanced braces: {opens} opens vs {closes} closes'
    assert 'request.resource.size' in content, 'Size limit missing'
print('ALL_VALIDATIONS_PASS')
"</automated>
  </verify>
  <done>
    - Both rules files have valid syntax (balanced braces, correct version header)
    - No generic wildcard subcollection rule remains in firestore.rules
    - All 5 client write paths verified against new rules
    - Role escalation locked via immutable role field on updates
    - flutter analyze passes (no Dart changes needed)
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Client -> Firestore | Any anonymous auth user can craft arbitrary write requests |
| Client -> Storage | Any anonymous auth user can upload/download if they know the path |
| Group member -> Group data | Members should not escalate to creator role |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-sec-01 | Elevation of Privilege | groups/{gid}/members/{mid} | mitigate | Lock `role` field via `request.resource.data.role == resource.data.role` on update rules |
| T-sec-02 | Tampering | inviteCodes/{code} | mitigate | Shape-validate create (`hasOnly`), deny update, require auth for read |
| T-sec-03 | Information Disclosure | fcm_tokens/{uid} | mitigate | Owner-only access via `request.auth.uid == userId` |
| T-sec-04 | Denial of Service | storage upload | mitigate | Server-side 25MB file size limit via `request.resource.size` |
| T-sec-05 | Tampering | groups/{gid} delete | mitigate | Creator-only delete via `request.auth.uid == resource.data.createdBy` |
| T-sec-06 | Information Disclosure | storage paths | accept | Storage cannot verify Firestore membership; auth-only check remains. Low risk: paths require knowing eventId (UUID). Follow-up: custom claims via Cloud Functions |
</threat_model>

<verification>
1. Firestore rules file has no generic wildcard subcollection match
2. fcm_tokens, inviteCodes, members, activity, settlements all have explicit rules
3. Role field immutable on member updates
4. Group delete scoped to creator
5. Storage has 25MB server-side limit
6. Both files have balanced braces and correct syntax
</verification>

<success_criteria>
- All 5 vulnerabilities from 01-security.md are addressed
- No client code changes required (rules-only fix)
- notification_service.dart FCM token writes will succeed (were silently failing)
- group_provider.dart deleteGroup() will succeed for creators (was blocked)
- No member can escalate their role via subcollection wildcard
</success_criteria>

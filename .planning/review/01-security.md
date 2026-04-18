# Security — CRITICAL

**4/5 FIXED | 1 partially fixed (storage rules need Cloud Functions)**

## 1. Firestore Security Rules

### ~~1a. `fcm_tokens` Has No Rules~~ FIXED

Owner-only read/write now enforced: `request.auth.uid == userId`.

### 1b. Storage Rules Allow Any Authenticated User — PARTIALLY FIXED

Rules now enforce `request.auth != null` and 25MB file size limit server-side. However, membership-based path validation is not possible in Storage rules without Cloud Functions custom claims. Documented as a known constraint requiring follow-up.

### ~~1c. `inviteCodes` Is Publicly Readable~~ FIXED

Now requires `request.auth != null` for reads. No longer publicly accessible.

### ~~1d. `deleteGroup()` Is Blocked by Rules~~ FIXED

Delete now allowed for group creator only: `request.auth.uid == resource.data.createdBy`.

### ~~1e. Group Subcollection Wildcard Allows Role Escalation~~ FIXED

Generic wildcard replaced with explicit subcollection rules. Members subcollection has role-lock: `request.resource.data.role == resource.data.role` prevents escalation.

## Files Involved

- `security/firestore.rules`
- `security/storage.rules`
- `lib/core/services/notification_service.dart`
- `lib/features/groups/providers/group_provider.dart`

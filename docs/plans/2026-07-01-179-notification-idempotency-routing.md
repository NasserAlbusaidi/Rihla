# Issue 179 Slice: Notification Idempotency And Claim Tap Routing

## Scope

This slice intentionally does not implement multi-device tokens, expense edit/delete pushes, member-left/remove pushes, or group-deleted pushes. A broader `#179` tail spec hit repeated Gate P1s around those surfaces, so this first slice addresses the code-verifiable acceptance item that can be safely isolated:

- Existing Firestore/Eventarc notification triggers must be idempotent on the CloudEvent id.
- Existing claim-request notifications already emitted by `claimRequestNotifier` must route somewhere useful when tapped.

## Current Code Facts Verified

- `sendToUids` reads `fcm_tokens/{uid}`, sends one FCM message per stored token, prunes invalid parent token docs, catches all errors, and currently has no idempotency marker (`functions/src/notifications/fcmSender.ts:43-112`).
- `expenseAuditLogger` uses CloudEvent `event.id` as an idempotent activity-log doc id, proving wrapped v2 Firestore tests pass `id` and that the id is stable for at-least-once retry modeling (`functions/src/triggers/expenseAuditLogger.ts:172-190`, `functions/test/triggers/expenseAuditLogger.test.ts:14-20`).
- `settlementNotifier` has two `onDocumentCreated` exports and calls `sendToUids` without a dedupe key (`functions/src/triggers/settlementNotifier.ts:73-90`).
- `expenseNotifier` calls `sendToUids` on `onDocumentCreated` without a dedupe key (`functions/src/triggers/expenseNotifier.ts:136-149`).
- `eventNotifier` calls `sendToUids` on `onDocumentCreated` without a dedupe key (`functions/src/triggers/eventNotifier.ts:82-95`).
- `claimRequestNotifier` emits `claim_request` and `claim_decided` data payloads without a dedupe key (`functions/src/triggers/claimRequestNotifier.ts:88-117`).
- `requestClaimShadow` is pre-join; a declined requester is not added to `memberIds`, so member-only routes can permission-deny for declined claim decisions (`functions/src/callables/requestClaimShadow.ts:9-17`, `functions/src/callables/decideClaimRequest.ts:245-251`).
- `claimRequestNotifier` is already exported from `functions/src/index.ts`; no new Cloud Function export is needed for this slice (`functions/src/index.ts:24-26`).
- `_routeFromData` recognizes `settlement`, `member_join`, `expense`, and `event`, but not `claim_request` or `claim_decided` (`lib/core/services/notification_service.dart:299-321`).
- Existing claim surfaces are routeable without `state.extra`: group settings is `/group/:gid/settings`, group detail is `/group/:gid` (`AGENTS.md` route tree, and router paths in `lib/core/router/app_router.dart`).
- Group settings can be direct-entered by a notification tap after this slice, but its top-bar back button currently only pops when `canPop()` and has no fallback (`lib/features/groups/screens/group_settings_screen.dart:140-144`).

## Data Contract

Add optional idempotency to `sendToUids`:

```ts
interface SendToUidsOptions {
  dedupeKey?: string;
}

sendToUids(
  uids: string[],
  build: CopyBuilder,
  data: Record<string, string>,
  options?: SendToUidsOptions,
): Promise<void>
```

When `options.dedupeKey` is a non-empty string:

- Compute `deliveryId = sha256(dedupeKey)` as a hex string.
- Transactionally create `notificationDeliveries/{deliveryId}` with:

```ts
{
  key: dedupeKey,
  data,
  createdAt: FieldValue.serverTimestamp()
}
```

- If the marker already exists, return before reading tokens or calling FCM.
- If the marker create fails, fail closed: log a warning and return without sending. Existing notification behavior is best-effort and must not throw into a committed domain write.
- If sending later fails, do not delete the marker. This prevents duplicate tray buzzes on Eventarc redelivery and accepts that best-effort notification delivery can be lost after a post-marker transient failure.

Rules:

- Do not add a client rules match. `notificationDeliveries` remains default-deny under `match /{document=**}`. Admin SDK writes it from Cloud Functions.

## Dedupe Keys

Pass CloudEvent-id based keys from existing Firestore triggers:

- Event settlement: `settlement:event:${gid}:${eid}:${settlementId}:${event.id}`
- Group settlement: `settlement:group:${gid}:${settlementId}:${event.id}`
- Expense created: `expense:create:${gid}:${eid}:${expenseId}:${event.id}`
- Event created: `event:create:${gid}:${eid}:${event.id}`
- Claim request/decision: `claim:${gid}:${requestId}:${event.id}`

Do not add a dedupe key to `notifyMemberJoin` in this slice. `joinGroupByInviteCode` is a callable, not an Eventarc trigger, and already gates the notification on a committed first join with `didJoin`.

Implementation detail for helper signatures:

- Change `notifySettlement(gid, eid, snap)` to `notifySettlement(gid, eid, settlementId, eventId, snap)` and build the settlement dedupe key inside the helper.
- Change `notifyExpenseCreated(gid, eid, snap)` to `notifyExpenseCreated(gid, eid, expenseId, eventId, snap)` and build the expense dedupe key inside the helper.
- Change `notifyEventCreated(gid, eid, snap)` to `notifyEventCreated(gid, eid, eventId, snap)` and build the event dedupe key inside the helper.
- In `claimRequestNotifier`, build the dedupe key inline at each `sendToUids` call using `event.params.gid`, `event.params.requestId`, and `event.id`.

## Claim Notification Payloads And Tap Routing

Before routing notification taps to group settings, update `_SettingsTopBar` so its back button is direct-entry safe:

```dart
if (GoRouter.of(context).canPop()) {
  GoRouter.of(context).pop();
} else {
  GoRouter.of(context).go('/home');
}
```

This is required because `/group/:gid/settings` can now be opened directly from a cold notification tap.

Update `_routeFromData`:

- `claim_request` with `groupId` routes to `/group/$groupId/settings`, because the creator acts on claim requests from group settings.
- `claim_decided` must include `decision: 'claimed' | 'declined'`, `routeability: 'member' | 'pre_join'`, and should include the group's `inviteCode` read from `groups/{gid}.inviteCode`.
- `claim_decided` with `decision == 'claimed'` routes to `/group/$groupId`, because the requester has become a member after approval.
- `claim_decided` with `decision == 'declined'` and `routeability == 'member'` routes to `/group/$groupId`, because the requester is already a readable group member even though this specific claim request was declined.
- `claim_decided` with `decision == 'declined'` and `routeability != 'member'` routes to `/join/$inviteCode` when `inviteCode` is present, because the requester remains pre-join and cannot read `/group/$groupId`. If `inviteCode` is absent, route to `/join-group`.
- Legacy `claim_decided` payloads that have no `decision` cannot be resolved safely. Route them to `/join-group` as a pre-join-safe fallback instead of claiming they can land in the correct group/decision state.

Update `claimRequestNotifier` payloads:

- Claim request branch remains `{ type: 'claim_request', groupId: gid }`.
- Claim decision branch becomes:

```ts
{
  type: 'claim_decided',
  groupId: gid,
  decision: afterStatus,
  inviteCode: groupInviteCode,
  routeability: groupMemberIds.includes(requesterUid) ? 'member' : 'pre_join'
}
```

`groupInviteCode` and `groupMemberIds` are read from the same group doc lookup currently used for group name/creator. If the group doc has no invite code, send an empty string and let the client fall back to `/join-group` for pre-join declined decisions. This routeability field is required because a false-negative `alreadyClaimed` approval can mark a request declined after the requester has already become a group member.

Keep existing behavior unchanged for `settlement`, `member_join`, `expense`, and `event`. Unknown types stay ignored. Missing or empty `groupId` stays ignored for claim types.

## Read/Write Classification

- `sendToUids` is BOTH: reads token docs, writes `notificationDeliveries` when deduping, sends FCM IPC, and may delete `fcm_tokens/{uid}` on prunable failures.
- Existing trigger modules are BOTH through `sendToUids`; they do not mutate their domain docs.
- `notifyMemberJoin` is also BOTH through `sendToUids`, but remains no-options/no-dedupe in this slice because it is callable-gated by `joinGroupByInviteCode.didJoin`, not Eventarc redelivery.
- `_routeFromData` is INBOUND navigation only; it does not persist data.

## Verification Principles Applied

1. Shared path callsites are classified above. There is no display-formatted string that crosses into persistence in this slice.
2. Concrete paths and exports were checked against live code and cited above.
3. New write path `notificationDeliveries/{deliveryId}` is read by `sendToUids` only as an existence marker for idempotency. Fields `key`, `data`, and `createdAt` are diagnostic/write-only. It has no client consumer and remains default-deny.
4. No model field migration or scrub list is involved.
5. Exact map keys, callback signature, dedupe keys, and route paths are specified.
6. No arithmetic.
7. Orthogonal pass: claim-notification routing is included because the idempotency work touches existing notification payload types; declined claim decisions can be either pre-join or already-member, so the payload carries `routeability` from the current `groups/{gid}.memberIds` snapshot.

## TDD Plan

Write tests before implementation:

1. `functions/test/notifications/fcmSender.test.ts`
   - same `dedupeKey` called twice sends once and creates one marker;
   - different `dedupeKey`s send twice;
   - existing no-options behavior still sends.
   - cleanup must clear `notificationDeliveries`.
2. Existing trigger tests:
   - `settlementNotifier.test.ts`, `expenseNotifier.test.ts`, `eventNotifier.test.ts`, and `claimRequestNotifier.test.ts` must each assert same CloudEvent `id` retry sends once for each Eventarc notification callsite. `notifyMemberJoin` remains no-options because it is callable-gated by `didJoin`.
   - `claimRequestNotifier.test.ts` must parameterize CloudEvent ids. Use the same id only for the retry pair; use distinct ids for distinct request/decision transitions.
   - Every changed notifier test cleanup helper must clear `notificationDeliveries`; helpers that touch FCM tokens should continue to use recursive cleanup where already present or be upgraded if they only delete parent token docs.
3. `test/unit/notification_service_test.dart`
   - tapping `claim_request` routes to `/group/<gid>/settings`;
   - tapping `claim_decided` claimed routes to `/group/<gid>`;
   - tapping `claim_decided` declined routes to `/join/<inviteCode>` when present and `/join-group` when absent;
   - tapping `claim_decided` declined with `routeability: 'member'` routes to `/group/<gid>`;
   - tapping legacy `claim_decided` without `decision` routes to `/join-group`;
   - missing groupId for claim types is ignored.
4. `test/features/groups/group_settings_screen_test.dart`
   - direct-entry group settings back button routes to `/home` when it cannot pop.

Verification commands:

- `cd functions && npm run test:emulator -- test/notifications/fcmSender.test.ts test/triggers/settlementNotifier.test.ts test/triggers/expenseNotifier.test.ts test/triggers/eventNotifier.test.ts test/triggers/claimRequestNotifier.test.ts`
- `flutter test test/unit/notification_service_test.dart test/features/groups/group_settings_screen_test.dart`
- `cd functions && npm run build`
- `flutter analyze`

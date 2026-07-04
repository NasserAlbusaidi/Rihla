# #783 notificationDeliveries TTL spec

## Scope

Issue #783 reports that FCM idempotency markers at `notificationDeliveries/{sha256(dedupeKey)}` are permanent. This change makes those marker docs self-reaping by adding an `expiresAt` timestamp to new marker writes and adding a Firestore TTL field override for `notificationDeliveries.expiresAt`.

This is server-only persistence hygiene. It must not change push send behavior within the 90-day marker-retention window, token pruning, notification copy, routes, money, rules authorization, or client code. It intentionally changes dedupe retention from forever to 90 days: after Firestore TTL deletes a marker, the same ancient `dedupeKey` may notify again. That is accepted because the TTL window is longer than the trigger retry horizon and because permanent dedupe markers are the bug.

## Verified live contracts before implementation

- OUTBOUND write path: `functions/src/notifications/fcmSender.ts:35-55` writes a marker only when `dedupeKey.trim()` is non-empty. The marker id is `sha256(key)` and the transaction returns `false` without writing when the doc already exists.
- Pre-change marker shape: `functions/src/notifications/fcmSender.ts:49-53` wrote `{ key, data, createdAt }`, with `createdAt: FieldValue.serverTimestamp()` and no `expiresAt`.
- Read path: `functions/src/notifications/fcmSender.ts:47-48` only checks marker existence. It does not read `createdAt`, `data`, or any new marker field.
- Caller behavior: `functions/src/notifications/fcmSender.ts:84-86` aborts the send when `claimDeliveryMarker` returns false, preserving dedupe semantics.
- FCM send path: `functions/src/notifications/fcmSender.ts:87-145` reads `fcm_tokens`, localizes copy, calls `sendEach`, and prunes unrecoverable tokens. It does not depend on marker fields after claim succeeds.
- Existing focused tests: `functions/test/notifications/fcmSender.test.ts:158-181` asserts same-key sends once and one marker exists with `key` and `data`; `:184-202` asserts different keys send independently.
- Existing TTL config convention: `firestore.indexes.json:55-94` uses `fieldOverrides` entries with `"fieldPath": "expiresAt"` and `"ttl": true` for server-owned ephemeral collections.
- Server-only rules convention: `security/firestore.rules:280-299` and `:1217-1224` document TTL-backed Admin-SDK-only collections with `allow read, write: if false`. There is currently no explicit `notificationDeliveries` match; recursive default deny already blocks clients.

Baseline run before spec:

- `npm run build` in `functions`: PASS.
- `npm run lint` in `functions`: PASS.
- `../tool/run_firebase_emulator_tests.sh test/notifications/fcmSender.test.ts` in `functions`: PASS, 11 tests.

## Implementation contract

1. In `functions/src/notifications/fcmSender.ts`, replace the Firestore import with `getFirestore, Timestamp` from `firebase-admin/firestore`. Remove `FieldValue` because `createdAt` stops using `FieldValue.serverTimestamp()` and `functions/tsconfig.json` has `noUnusedLocals: true`.
2. Add a module-level TTL constant:
   - `const NOTIFICATION_DELIVERY_TTL_MS = 90 * 24 * 60 * 60 * 1000;`
   - 90 days is intentionally longer than any plausible trigger retry window and mirrors issue #783's suggested 30-90 day range.
3. In `claimDeliveryMarker`, compute one `now = Timestamp.now()` inside the transaction before `tx.create`.
4. Change marker create payload to exactly:
   - `key`
   - `data`
   - `createdAt: now`
   - `expiresAt: Timestamp.fromMillis(now.toMillis() + NOTIFICATION_DELIVERY_TTL_MS)`
5. Do not change marker id, transaction ordering, existence check, catch behavior, logger fields, or `sendToUids` behavior.
6. Add a `firestore.indexes.json` `fieldOverrides` entry:
   - `collectionGroup: "notificationDeliveries"`
   - `fieldPath: "expiresAt"`
   - `ttl: true`
   - indexes matching the existing TTL entries: ascending collection, descending collection, array-contains collection.
7. Do not add a scheduled reaper. Firestore TTL is the reaper for this collection.
8. Do not change `security/firestore.rules` unless Gate requires an explicit match. The current default-deny surface already blocks client access; this issue is storage retention, not authorization.

## Data contract

Marker docs after the change:

```ts
{
  key: string,
  data: Record<string, string>,
  createdAt: Timestamp,
  expiresAt: Timestamp,
}
```

`data` is opaque routing payload copied unchanged from each notifier into the marker for observability only. The marker writer does not interpret the keys. Verified current deduped caller payloads:

- `expenseNotifier`: `{ type: 'expense', groupId, eventId }` at `functions/src/triggers/expenseNotifier.ts:138-145`.
- `eventNotifier`: `{ type: 'event', groupId, eventId }` at `functions/src/triggers/eventNotifier.ts:88-95`.
- `settlementNotifier`: `{ type: 'settlement', groupId, eventId? }` at `functions/src/triggers/settlementNotifier.ts:72-85`.
- `claimRequestNotifier` request branch: `{ type: 'claim_request', groupId }` at `functions/src/triggers/claimRequestNotifier.ts:100-107`.
- `claimRequestNotifier` decision branch: `{ type: 'claim_decided', groupId, decision, inviteCode, routeability }` at `functions/src/triggers/claimRequestNotifier.ts:124-137`.

`memberJoinNotifier` calls `sendToUids` without a `dedupeKey` and therefore does not write `notificationDeliveries`; see `functions/src/notifications/memberJoinNotifier.ts:20-27` and `fcmSender.ts:39-40`.

Existing marker docs without `expiresAt` continue to exist indefinitely unless a separate migration stamps or deletes them. A duplicate-key send does not overwrite them because `claimDeliveryMarker` returns `false` as soon as the marker exists. This is acceptable for #783 because the change prevents unbounded growth for new markers without weakening dedupe for old marker docs. Backfilling legacy docs is out of scope and would require an explicit policy for old dedupe windows.

## Test plan

RED first:

- Extend `functions/test/notifications/fcmSender.test.ts` same-dedupe-key test to assert:
  - `createdAt` is a Firestore `Timestamp`.
  - `expiresAt` is a Firestore `Timestamp`.
  - `expiresAt.toMillis() - createdAt.toMillis()` equals `90 * 24 * 60 * 60 * 1000`.
- This should fail before implementation because the marker has no `expiresAt`.

GREEN:

- Implement the marker field and TTL field override.
- Run:
  - `../tool/run_firebase_emulator_tests.sh test/notifications/fcmSender.test.ts`
  - `npm run build`
  - `npm run lint`
  - `npm run test:emulator -- test/notifications/fcmSender.test.ts test/triggers/settlementNotifier.test.ts test/triggers/eventNotifier.test.ts test/triggers/expenseNotifier.test.ts test/triggers/claimRequestNotifier.test.ts` if time allows, because `npm run test:emulator` runs Jest from `functions/`.

## Verification principles self-check

1. Shared read/write callsites classified: the only changed write is `claimDeliveryMarker` OUTBOUND; its only read is existence-only in the same transaction. No display-formatted string reaches a write boundary.
2. Concrete claims verified against live code with line-numbered reads above.
3. Read path traced: marker docs are read only by transaction existence check; TTL service reads `expiresAt` by config, not application code.
4. No model type exists for marker docs. Fields enumerated from the only writer.
5. Data contract spells exact marker keys and declares `data` opaque pass-through, with current caller payloads enumerated above.
6. Arithmetic decomposition: not applicable to money. The only arithmetic is TTL millis addition from one timestamp.
7. Orthogonal axes considered: notification copy/locale untouched, token pruning untouched, dedupe identity untouched, client rules unchanged/default-denied, old marker docs remain valid.

## Out of scope

- Backfilling or deleting legacy marker docs with no `expiresAt`.
- Changing dedupe key construction in notification triggers.
- Changing FCM token TTL/pruning.
- Changing notification copy/l10n/RTL.
- Deploying production TTL policy manually in this code change. The code/config change makes the deploy ceremony possible; deployment is a separate operational step.

## Gate + verification results

- Gate round 1: rubric reviewer returned 2 P1 / 2 P2; adversary returned 0 P1 / 1 P2. The P1s were spec defects: cwd-relative test paths and inaccurate legacy-doc overwrite wording.
- Gate round 2 after spec revision: rubric reviewer returned 0 P1 / 0 P2 / 0 P3; adversary returned 0 P1 / 0 P2 / 0 P3.
- RED: `../tool/run_firebase_emulator_tests.sh test/notifications/fcmSender.test.ts` failed on missing `marker.expiresAt`.
- GREEN: focused `fcmSender.test.ts`, notification trigger bundle, `npm run build`, `npm run lint`, `git diff --check`, and full `npm run test:emulator` all passed.

RED excerpt captured before implementation:

```text
FAIL test/notifications/fcmSender.test.ts
  sendToUids
    ...
    x same dedupeKey sends once and writes one marker

  ● sendToUids › same dedupeKey sends once and writes one marker

    expect(received).toBeInstanceOf(expected)

    Expected constructor: Timestamp

    Received value has no prototype
    Received value: undefined

      184 |     });
      185 |     expect(marker.createdAt).toBeInstanceOf(Timestamp);
    > 186 |     expect(marker.expiresAt).toBeInstanceOf(Timestamp);
          |                              ^
      187 |     expect(marker.expiresAt.toMillis() - marker.createdAt.toMillis()).toBe(
      188 |       notificationDeliveryTtlMs,
      189 |     );

Test Suites: 1 failed, 1 total
Tests:       1 failed, 10 passed, 11 total
```

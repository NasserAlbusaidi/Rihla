# #1141 Membership Fence for Notification Senders — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Membership-scoped push notifications re-check a FRESH `groups/{gid}.memberIds` immediately before delivery, fail-closed, so a user who lost membership between domain-commit and trigger-send no longer receives group/event/money/claim details they can no longer read.

**Architecture:** One fence, one mechanism: `sendToUids` (`functions/src/notifications/fcmSender.ts`) gains an opt-in `requireCurrentMembershipOf: gid` option. When set, it reads `groups/{gid}` fresh, intersects the target uids with `memberIds`, and on any lookup failure (doc missing, field absent/non-array, read error) sends **nothing** — never falling back to committed recipients. The fence runs **before** the dedupe-marker claim so a refused/empty send never burns the marker. Six membership-scoped callsites opt in (`eventNotifier`, `expenseNotifier`, `eventSettlementNotifier`+`groupSettlementNotifier` via shared `notifySettlement`, `notifyMemberJoin`, `claimRequestNotifier` Branch A). Claim-decision Branch B is **intentionally cross-membership** and is test-pinned as NOT fenced. No rules change, no client change, no new exported functions (deploy-drift extractor unaffected).

**Tech Stack:** Cloud Functions (Node 22 / TS), firebase-admin, Jest + Firestore emulator (`cd functions && npm run test:emulator -- <file> -t "<name>"`; bare `npm test` HANGS — no emulator).

**Verified baseline (all read this session, `main` @ `c45a811f`):**
- `functions/src/notifications/fcmSender.ts:81-153` — `sendToUids` checks only token existence; marker claim currently runs first (`:88`).
- `functions/src/triggers/eventNotifier.ts:79-96` — targets = committed `participantIds` minus creator.
- `functions/src/triggers/expenseNotifier.ts:125-146` — targets = split share-set ∪ payer, minus creator; share-set may name departed historical event participants.
- `functions/src/triggers/settlementNotifier.ts:62-96` — targets = payer/recipient minus creator; one shared `notifySettlement` behind both exports (`:99-119`).
- `functions/src/notifications/memberJoinNotifier.ts:9-28` — targets = PRE-join snapshot `existingMemberIds` minus joiner; called post-commit from `joinGroupByInviteCode.ts:350`.
- `functions/src/triggers/claimRequestNotifier.ts:86-110` (Branch A → `createdBy`, unchecked against `memberIds`), `:112-140` (Branch B → requester, intentionally cross-membership; `routeability` already reads `memberIds`).
- `functions/src/callables/decideClaimRequest.ts:203-207` — claim decisions already require the creator to be a CURRENT member (#1132), so Branch A's recipient contract is "current member".
- No notifier trigger sets `retry` (grepped) — duplicate invocations are the only re-delivery path, which is why the fence must not burn the dedupe marker.

**Design decisions (locked; Gate reviews these):**
1. **Fence inside `sendToUids`, not per-callsite helpers.** The read lands as close to the FCM fan-out as possible (smallest race window), fail-closed is implemented exactly once, and a callsite cannot get the ordering wrong. Callsite-specific policy (issue requirement) is expressed by *passing or omitting the option*.
2. **Intersect `memberIds`, NOT `activeMemberIds` (#1144 R5).** Tombstone ids sit in `memberIds` but never in `fcm_tokens` (deleteAccount cascade deletes the token doc), and unclaimed-shadow uuids never authenticate so never mint tokens — so the two sets are delivery-equivalent, and `memberIds` avoids the absent-field legacy fallback (`activeMemberIds` is absent on pre-#1144 groups). deleteAccount **swaps** uid→tombstoneId in `memberIds`, so deleted-account uids are dropped by the fence too — consistent.
3. **Fence before marker.** A membership-lookup failure or a post-fence-empty target set returns BEFORE `claimDeliveryMarker`, so a duplicate trigger invocation (at-least-once delivery) can still deliver to eligible recipients later. Side effect (deliberate): an all-empty/all-filtered send no longer claims a marker — nothing to dedupe. **Redelivery honesty (Gate R1 adversary):** the duplicate-invocation safety net exists only for the five TRIGGER senders. `notifyMemberJoin` is a fire-and-forget direct call from the join callable (`joinGroupByInviteCode.ts:350`) — no redelivery path exists, and the fence ADDS a `groups/{gid}` read that `notifyMemberJoin` never had, so a transient read failure there permanently loses the "X joined" announcement. **Accepted, do NOT fail-open member_join:** member_join is already the contract's one best-effort, lost-row-at-worst notification (CLAUDE.md #1140 note), its recipients are guarded by a sub-millisecond window only, and fail-closed keeps the fence single-semantics.
4. **Group soft-delete is a named residual, out of scope.** A group soft-deleted between commit and trigger still has `memberIds`; its members may still receive a push for it. Recipients are still members — not a privacy leak, just degraded UX. Not fenced here.
5. **The leave-after-final-lookup race is unavoidable and documented.** Firestore membership revocation and FCM delivery cannot be atomic. The fence shrinks the exposure window from commit→send (unbounded trigger latency) to fresh-read→send (milliseconds); it cannot close it. Tests and docs state this.
6. **Existing recipient semantics untouched:** actor/joiner exclusion, zero-share filtering, correction-marker skip, dedupe keys, token pruning, localized copy — all unchanged; existing tests keep pinning them (their group seeds gain `memberIds`).

**Residuals / accepted:** (a) the read→send race (decision 5); (b) soft-deleted-group pushes (decision 4); (c) Branch B intentionally reaches non-members — pinned by test, not a bug; (d) +1 `groups/{gid}` read per fenced send (the name-resolve read and the fence read stay separate — merging them would hand the fence a staler snapshot and break the single-mechanism design); (e) a member_join fence refusal is unrecoverable (decision 3) — accepted for the best-effort notification class.

**Gate record:** Round 1 (2026-07-11): rubric 0 P1 / 0 P2 / 3 P3; adversary 0 P1 / 1 P2 / 1 P3 — union P1-clean in the same round, Gate passed. The adversary P2 (false universal-redelivery rationale in decision 3) and rubric P3s (Task 6 seed over-statement, double-read note) are folded into this revision.

---

### Task 1: Fence in `sendToUids` (RED → GREEN)

**Files:**
- Modify: `functions/src/notifications/fcmSender.ts`
- Test: `functions/test/notifications/fcmSender.test.ts`

**Step 1: Write the failing tests.** Extend `fcmSender.test.ts`. Add a group seed helper + clear `groups` in `clearNotificationState`:

```ts
async function clearNotificationState(): Promise<void> {
  const db = getFirestore();
  await db.recursiveDelete(db.collection('fcm_tokens'));
  await db.recursiveDelete(db.collection('notificationDeliveries'));
  await db.recursiveDelete(db.collection('groups'));
}

async function seedGroup(gid: string, memberIds: string[]): Promise<void> {
  await getFirestore().doc(`groups/${gid}`).set({ id: gid, name: 'G', memberIds });
}
```

New describe block:

```ts
describe('membership fence (#1141)', () => {
  test('drops targets absent from fresh memberIds, keeps current members', async () => {
    await seedGroup('g1', ['a']);
    await seedToken('a', 'tok-a', 'en');
    await seedToken('departed', 'tok-departed', 'en');
    const sendEach = mockSendEach([{ success: true }]);

    await sendToUids(['a', 'departed'], build, { type: 'expense', groupId: 'g1' }, {
      requireCurrentMembershipOf: 'g1',
    });

    expect(sendEach).toHaveBeenCalledTimes(1);
    const tokens = sendEach.mock.calls[0][0].map((m: { token: string }) => m.token);
    expect(tokens).toEqual(['tok-a']);
  });

  test('group doc missing → sends nothing', async () => {
    await seedToken('a', 'tok-a', 'en');
    const sendEach = mockSendEach([]);

    await sendToUids(['a'], build, { type: 'expense', groupId: 'missing' }, {
      requireCurrentMembershipOf: 'missing',
    });

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('memberIds absent → sends nothing (fail-closed, never committed fallback)', async () => {
    await getFirestore().doc('groups/g2').set({ id: 'g2', name: 'G' }); // no memberIds
    await seedToken('a', 'tok-a', 'en');
    const sendEach = mockSendEach([]);

    await sendToUids(['a'], build, { type: 'expense', groupId: 'g2' }, {
      requireCurrentMembershipOf: 'g2',
    });

    expect(sendEach).not.toHaveBeenCalled();
  });

  test('fence refusal does not burn the dedupe marker', async () => {
    await seedToken('a', 'tok-a', 'en');
    const sendEach = mockSendEach([{ success: true }]);

    // First attempt: group missing → nothing sent, marker NOT claimed.
    await sendToUids(['a'], build, { type: 'expense', groupId: 'g3' }, {
      dedupeKey: 'k-1141', requireCurrentMembershipOf: 'g3',
    });
    expect(sendEach).not.toHaveBeenCalled();
    const markers = await getFirestore().collection('notificationDeliveries').get();
    expect(markers.size).toBe(0);

    // Duplicate invocation after the group exists: same key still deliverable.
    await seedGroup('g3', ['a']);
    await sendToUids(['a'], build, { type: 'expense', groupId: 'g3' }, {
      dedupeKey: 'k-1141', requireCurrentMembershipOf: 'g3',
    });
    expect(sendEach).toHaveBeenCalledTimes(1);
  });

  test('post-fence empty target set does not burn the dedupe marker', async () => {
    await seedGroup('g4', ['member-without-token']);
    await seedToken('departed', 'tok-departed', 'en');
    const sendEach = mockSendEach([]);

    await sendToUids(['departed'], build, { type: 'expense', groupId: 'g4' }, {
      dedupeKey: 'k-empty', requireCurrentMembershipOf: 'g4',
    });

    expect(sendEach).not.toHaveBeenCalled();
    const markers = await getFirestore().collection('notificationDeliveries').get();
    expect(markers.size).toBe(0);
  });

  test('option absent → committed targets pass through unchanged', async () => {
    // No group doc at all; legacy behavior must not require one.
    await seedToken('a', 'tok-a', 'en');
    const sendEach = mockSendEach([{ success: true }]);

    await sendToUids(['a'], build, { type: 'claim_decided', groupId: 'nowhere' });

    expect(sendEach).toHaveBeenCalledTimes(1);
  });
});
```

**Step 2: Run to verify RED.**
Run: `cd functions && npm run test:emulator -- test/notifications/fcmSender.test.ts -t "membership fence"`
Expected: the drop/nothing tests FAIL (fence not implemented — departed targets still receive).

**Step 3: Implement the fence.** In `fcmSender.ts`:

```ts
export interface SendToUidsOptions {
  dedupeKey?: string;
  /**
   * #1141 membership fence. When set to a group id, targets are intersected
   * with a FRESH read of groups/{gid}.memberIds immediately before delivery;
   * lookup failure (missing doc, absent/non-array field, read error) sends
   * NOTHING — never the committed recipient list. Pass it wherever the
   * recipient contract is "current group member"; omit it for deliberate
   * cross-membership sends (claim-decision Branch B).
   * The unavoidable residue: a member who leaves after this read but before
   * FCM fan-out still receives the push — revocation and delivery cannot be
   * atomic. The fence shrinks the window from commit→send to read→send.
   */
  requireCurrentMembershipOf?: string;
}
```

```ts
// #1141 — fresh membership read for the fence. null = lookup failed or the
// group/field is unusable; callers treat null as "send nothing" (fail-closed).
async function currentMemberIds(gid: string): Promise<Set<string> | null> {
  try {
    const snap = await getFirestore().doc(`groups/${gid}`).get();
    if (!snap.exists) return null;
    const ids = snap.data()?.memberIds;
    if (!Array.isArray(ids)) return null;
    return new Set(ids.filter((v): v is string => typeof v === 'string'));
  } catch (error) {
    logger.warn('fcm membership fence lookup failed', { gid, error: String(error) });
    return null;
  }
}
```

Restructure the top of `sendToUids` (uid dedupe first, fence second, marker third; token reads and everything below unchanged):

```ts
export async function sendToUids(
  uids: string[],
  build: CopyBuilder,
  data: Record<string, string>,
  options: SendToUidsOptions = {},
): Promise<void> {
  try {
    const db = getFirestore();
    let uniqueUids = [
      ...new Set(uids.filter((u) => typeof u === 'string' && u.length > 0)),
    ];

    const fenceGid =
      typeof options.requireCurrentMembershipOf === 'string'
        ? options.requireCurrentMembershipOf.trim()
        : '';
    if (fenceGid.length > 0) {
      const members = await currentMemberIds(fenceGid);
      if (members === null) {
        logger.warn('fcm membership fence refused send', { gid: fenceGid });
        return;
      }
      uniqueUids = uniqueUids.filter((uid) => members.has(uid));
    }
    if (uniqueUids.length === 0) return;

    // Marker AFTER the fence: a refused/empty send must not burn the dedupe
    // key — a duplicate trigger invocation is the only redelivery path
    // (no notifier sets retry).
    if (!(await claimDeliveryMarker(options.dedupeKey, data))) return;

    const snaps = await Promise.all(
      uniqueUids.map((uid) => db.doc(`fcm_tokens/${uid}`).get()),
    );
    // ... rest of the function byte-identical ...
```

**Step 4: Run to verify GREEN.**
Run: `cd functions && npm run test:emulator -- test/notifications/fcmSender.test.ts`
Expected: ALL pass (fence block + every pre-existing test — pre-existing tests pass no option and must be untouched).

**Step 5: Commit.**
```bash
git add functions/src/notifications/fcmSender.ts functions/test/notifications/fcmSender.test.ts
git commit -m "feat(functions): #1141 membership fence in sendToUids — fresh memberIds intersect, fail-closed, marker-safe"
```

### Task 2: `eventNotifier` opts in

**Files:**
- Modify: `functions/src/triggers/eventNotifier.ts:88-96`
- Test: `functions/test/triggers/eventNotifier.test.ts`

**Step 1: Failing test.** Update the file's `seedGroup` helper to seed `memberIds` and update EVERY existing call (default cast = all uids the test sends to, plus the creator):

```ts
async function seedGroup(gid: string, name: string, memberIds: string[]): Promise<void> {
  await getFirestore().doc(`groups/${gid}`).set({ id: gid, name, memberIds });
}
```

New test:

```ts
test('#1141: departed participant in committed doc gets no push; current ones still do', async () => {
  await seedGroup('g1', 'Muscat Trip', ['creator-1', 'staying-1']);
  await seedMember('g1', 'creator-1', 'Ali');
  await seedToken('staying-1');
  await seedToken('departed-1'); // still holds a token, no longer a member
  const sendEach = mockSendEach(1);

  await wrap(eventCreated(
    { createdBy: 'creator-1', participantIds: ['creator-1', 'staying-1', 'departed-1'], name: 'Dinner' },
    { gid: 'g1', eid: 'e1' },
  ));

  expect(tokensOf(sendEach)).toEqual(['tok-staying-1']);
});
```

**Step 2: RED.** Run: `cd functions && npm run test:emulator -- test/triggers/eventNotifier.test.ts`
Expected: the new test FAILS (departed-1 receives); pre-existing tests pass once their seeds carry `memberIds`.

**Step 3: Implement.** In `notifyEventCreated`, add the option:

```ts
    { dedupeKey: `event:create:${gid}:${eid}:${eventId}`, requireCurrentMembershipOf: gid },
```

**Step 4: GREEN.** Same command; all pass.

**Step 5: Commit.** `git commit -m "fix(functions): #1141 eventNotifier fences targets to fresh memberIds"`

### Task 3: `expenseNotifier` opts in

**Files:**
- Modify: `functions/src/triggers/expenseNotifier.ts:138-146`
- Test: `functions/test/triggers/expenseNotifier.test.ts`

Same shape as Task 2. Update the file's group seed helper(s) to carry `memberIds` on every existing test. New test: an expense whose `splitDistribution` names a departed historical event participant (positive share, valid token, absent from `memberIds`) → no push to them; current split parties still receive. Then add `requireCurrentMembershipOf: gid` to the `sendToUids` options. RED → GREEN → commit `fix(functions): #1141 expenseNotifier fences targets to fresh memberIds`.

### Task 4: both settlement notifiers opt in (one shared body)

**Files:**
- Modify: `functions/src/triggers/settlementNotifier.ts:88-96`
- Test: `functions/test/triggers/settlementNotifier.test.ts`

Seed-helper update as above. TWO new tests, one per export (the issue's acceptance boxes name both scopes):
1. Event settlement whose recipient departed → no push; payer-as-creator excluded as before.
2. Group settlement whose counterparty left after commit (present in doc, absent from fresh `memberIds`) → no push.

Implement by adding `requireCurrentMembershipOf: gid` to the single `sendToUids` call in `notifySettlement` (covers both exports). RED → GREEN → commit `fix(functions): #1141 settlement notifiers fence targets to fresh memberIds`.

### Task 5: `notifyMemberJoin` opts in — direct unit test

**Files:**
- Modify: `functions/src/notifications/memberJoinNotifier.ts:20-27`
- Create: `functions/test/notifications/memberJoinNotifier.test.ts`
- Check: `functions/test/callables/joinGroupByInviteCode.test.ts` (its join-flow sends now require the seeded group's `memberIds` to include recipients — they do by construction; fix seeds only if red)

**Step 1: Failing test.** The callable test cannot interleave a leave between snapshot and send, so pin the fence at the notifier unit (it is an exported plain function — no wrap needed). New file, modeled on `fcmSender.test.ts` conventions (emulator, `mockSendEach`, seed helpers):

```ts
test('#1141: pre-join member who left before send gets no member-joined push', async () => {
  // Fresh group state: 'stale-member' already left; joiner committed.
  await seedGroup('g1', ['creator-1', 'joiner-1']);
  await seedToken('creator-1', 'tok-creator-1', 'en');
  await seedToken('stale-member', 'tok-stale', 'en');
  const sendEach = mockSendEach([{ success: true }]);

  // Pre-join snapshot still names stale-member.
  await notifyMemberJoin('g1', 'joiner-1', 'Zed', 'G', ['creator-1', 'stale-member']);

  const tokens = sendEach.mock.calls[0][0].map((m: { token: string }) => m.token);
  expect(tokens).toEqual(['tok-creator-1']);
});
```

Also pin: fresh-lookup failure sends nothing (`notifyMemberJoin` against a missing group → `sendEach` never called), and the joiner stays excluded even though the fresh `memberIds` now contains them.

**Step 2: RED.** `cd functions && npm run test:emulator -- test/notifications/memberJoinNotifier.test.ts`

**Step 3: Implement.**

```ts
  await sendToUids(
    targets,
    (locale) => ({ ... }),
    { type: 'member_join', groupId: gid },
    { requireCurrentMembershipOf: gid },
  );
```

**Step 4: GREEN** (new file + `joinGroupByInviteCode.test.ts` both). **Step 5: Commit** `fix(functions): #1141 member-join push fences pre-join snapshot to fresh memberIds`.

### Task 6: claim Branch A fenced; Branch B pinned cross-membership

**Files:**
- Modify: `functions/src/triggers/claimRequestNotifier.ts:100-108`
- Test: `functions/test/triggers/claimRequestNotifier.test.ts`

**Step 1: Failing tests.** NO seed migration needed here (Gate R1 rubric verified): `claimRequestNotifier.test.ts`'s `seedGroup` already defaults `memberIds=[createdBy]` and its `clearAll` already clears `groups` — existing tests pass the fence unchanged. Just add two new tests:

```ts
test('#1141 Branch A: departed stale createdBy gets no claim-request push', ...);
  // group createdBy 'creator-1', memberIds WITHOUT 'creator-1', token seeded → sendEach never called
test('#1141 Branch B stays cross-membership: declined requester outside memberIds still notified', ...);
  // pending→declined, requesterUid NOT in memberIds, token seeded → push delivered, routeability 'pre_join'
```

(If an existing Branch B `pre_join` routeability test already proves delivery to a non-member, extend its name/asserts to explicitly pin "#1141: NOT fenced" rather than duplicating it.)

**Step 2: RED** (Branch A test fails — departed creator still notified; Branch B test already passes and must KEEP passing after the fix — it is the regression tripwire for an over-eager blanket fence).

**Step 3: Implement.** Branch A's send only:

```ts
        { type: 'claim_request', groupId: gid },
        { dedupeKey, requireCurrentMembershipOf: gid },
```

Branch B's `sendToUids` call is untouched. Keep the existing `createdBy.length === 0 || createdBy === requesterUid` guard — it is the fail-closed layer for a failed `resolveGroup`.

**Step 4: GREEN.** **Step 5: Commit** `fix(functions): #1141 claim Branch A fenced to current-member creator; Branch B pinned cross-membership`.

### Task 7: docs, lint, full suite

**Files:**
- Modify: `docs/CLOUD-FUNCTIONS.md` (§ "Firestore triggers — push notifications", ~L155-205)

**Step 1:** Document the fence in the notifier section: which senders pass `requireCurrentMembershipOf`, Branch B's deliberate exemption, fail-closed semantics, fence-before-marker ordering, and the honest race note: *"revocation and FCM delivery are not atomic — a member who leaves after the fence read but before fan-out can still receive that one push; the fence shrinks the window from commit→send to read→send, it cannot close it."*

**Step 2:** `cd functions && npm run lint && npm run build` — clean.

**Step 3:** Full functions suite: `cd functions && npm run test:emulator` — all green.

**Step 4:** Commit: `docs(functions): #1141 membership-fence contract + non-atomic race note`. The PR body AND the final squash-inherited commit body carry `Closes #1141`.

---

**Out of scope / untouched:** `security/firestore.rules`, all client code (`lib/`), `functions/src/index.ts` exports, `notification_service.dart` tap routing (recipients-only change), scheduled functions, `writeRateMonitor`.

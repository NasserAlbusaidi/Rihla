# #1133 Part A — deleteAccount scrubs `closedBy` + `spendingSnapshot` PII Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** The account-deletion cascade must scrub the deleted user's raw UID from `event.closedBy` and from the frozen `spendingSnapshot` blob (`biggest.payer` / `payers[].id` / `owed` keys), and drop the verbatim frozen expense description(s) inside `spendingSnapshot.biggest`, so no deleted-user PII survives on a closed event doc **in any group the user is a member of at deletion time** (the cascade only reaches `memberIds array-contains uid` groups — R4) — WITHOUT dropping any frozen owed amount on the #1099 re-join collision.

**Architecture:** Extend the per-event scrub inside `cascadeGroupAfterMarker` (`functions/src/callables/deleteAccount.ts`) — the SHARED per-group scrub reused by both `deleteAccount` and `deletionReaper` — to (1) re-key `closedBy` uid→`tombstoneId` and (2) scrub `spendingSnapshot` via a NEW purpose-built `scrubSpendingSnapshot` that gates on an explicit uid-reference check, re-keys the three uid slots, drops the frozen descriptions, and — critically — merge-SUMS `owed` buckets on the #1099 tombstone-collision (never last-write-wins drops). No `security/firestore.rules` change (the Admin SDK bypasses rules on the cascade write; the client only READS the scrubbed blob via the total-parse `SpendingSnapshot.fromMap`).

**Tech Stack:** TypeScript (Node 22), firebase-admin Firestore, Jest under the Firebase emulator (Java 21).

**Scope boundary:** This plan is **Part A only** (Functions + deploy + RED test). **Part B** (rewrite `hosting/delete-data.html` to describe the shipped instant self-serve deletion) is a separate Gate-exempt hosting-docs PR, tracked in the same issue #1133, NOT covered here.

> **Round-2 note (Gate history):** Round 1 (both reviewers) surfaced a P1 — the original design reused `rewriteMetadata` (a last-write-wins re-keyer) for `owed`, silently DROPPING a frozen owed amount on the #1099 re-join re-delete collision (bucket holds both prior tombstone `T` and re-added uid `U`; `U→T` clobbers `T`'s value). This revision replaces that with a purpose-built scrubber using `mergeUidMapKey` (the exact precedent the file uses for `splitDistribution`, `:244-251`). Also folded: uid-only collateral gate (was name-substring-sensitive), `Refs`-not-`Closes`, real test-helper names, and the accepted-residuals list.

---

## Verification principles — run against live code while authoring

**1. Classify every callsite on a shared read/write path (INBOUND / OUTBOUND / BOTH).**

Both scrubbed fields are written ONLY by the Admin SDK cascade and read ONLY for display:

- `event.closedBy` — **INBOUND (display-only).** Reads: `event_command_center.dart:273-276` → `_ClosedBanner` (`:974-989`, name or fallback-to-`eventClosedBanner` on null); `trip_receipt_builder.dart:226` → `nameForId` (`:57-60` = `resolvedUniverse[id] ?? stripped(id)`, never a raw id). Writes: `event_service.dart:227` (close → `closedBy: uid`, rule-pinned to `auth.uid`) / `:258` (reopen → `null`).
- `event.spendingSnapshot` — **INBOUND (display-only).** Written by the client at close (`event_service.dart:233`), cleared on reopen via `FieldValue.delete()` (`:263`), parsed by the TOTAL-PARSE `SpendingSnapshot.fromMap` (`spending_snapshot.dart:147-157`, never throws), displayed on the recap. Docstring (`:11-15`): OPAQUE & DISPLAY-ONLY — `recomputeNet` / the balance oracle / any Cloud Function NEVER read it. `grep -rn 'closedBy\|spendingSnapshot' functions/src` = **0 hits** → no server reader today.

Neither field is OUTBOUND. ⇒ Re-keying uids / dropping descriptions is display-only and cannot perturb the oracle or client↔server parity.

**2. Verify every concrete claim against code.**

- `deletedUserSentinel='deleted-user'`, `deletedMemberName='Deleted member'` (`deleteAccount.ts:24-25`).
- `tombstoneId` = deterministic `deleted-<sha1(uid)[:8]>` (`:117-128`); Phase C ALWAYS writes a tombstone member doc `{userId: tombstoneId, displayName:'Deleted member', isTombstone:true}` (`:631-639`) and re-keys `memberIds` uid→tombstoneId (`:616`) ⇒ tombstoneId resolves to "Deleted member" in every roster/name lookup.
- `mergeUidMapKey(value, oldUid, newUid)` (`shared/mapReKey.ts`): SUM-on-collision map re-keyer; returns `{value, changed}` or `null` for non-map input; with an ABSENT target key it behaves identically to a plain rename (docstring). `toFiniteNumber` (same file) zeroes forged non-numerics. `replaceUid` / `renameMapKey` also there.
- `eventUpdate` block `:498-525`; `createdBy` re-key `:519-521`.
- Snapshot serialized shape (`spending_snapshot.dart:88-142`) — the ONLY raw-uid slots: `biggest.<ccy>.payer` (string), `payers.<ccy>[].id` (string), `owed.<ccy>.<uid>` (map KEY). The ONLY free-text slot: `biggest.<ccy>.desc` (verbatim `Expense.description`, `event_recap.dart:187`). `id`/`amt`/`cat`/`v`/counts/`categories` carry NO uid or free text.
- Close write shape (`event_service.dart:222-233`): `{isClosed:true, closedAt, closedBy, updatedAt, spendingSnapshot?}` — fixtures must include `isClosed:true` + `closedAt` for prod fidelity.

**3. Trace one read-path per write-path.** Write = cascade sets `closedBy=tombstoneId`, `spendingSnapshot=<scrubbed>`. Reads: banner/receipt resolve `closedBy` by name (tombstoneId → "Deleted member"); the recap total-parses the snapshot (uids → tombstoneId → "Deleted member"; absent `desc` → null → biggest-expense row shows the category-name fallback, `event_recap_screen.dart` + the #722 share card both fallback on null desc). Reopen reads only the NEW `closedBy==null` (`firestore.rules` `validEventCloseToggle`), never the old tombstoneId value — no stale-scrub coupling.

**4. Enumerate fields from the type, not the spec's list.** `SpendingSnapshot.toMap` keys (exhaustive): `v, participantCount, expenseCount, totals, biggest{<ccy>{id,amt,desc?,cat?,payer}}, payers{<ccy>[{id,amt}]}, categories{<ccy>[{cat,amt}]}, owed{<ccy>{<uid>:amt}}`. PII ⊆ `{biggest.*.payer, biggest.*.desc, payers.*.id, owed.*.<uid-key>}`. `categories` has NO uid. No other slot.

**5. Spell out the data contract.**

- `closedBy`: `if (eventData.closedBy === uid) eventUpdate.closedBy = tombstoneId;` — scalar exact-equality.
- `spendingSnapshot`: `scrubSpendingSnapshot(eventData.spendingSnapshot, uid, tombstoneId) → { value, changed }`; write `eventUpdate.spendingSnapshot = value` ONLY when `changed === true`.
  - **Collateral gate (uid-only, not name-substring):** `changed` is true ⇔ `snapshotReferencesUid(snapshot, uid)` — the uid appears as `biggest.<ccy>.payer`, a `payers.<ccy>[].id`, or an OWN key of some `owed.<ccy>`. Events whose snapshot never names the deleted user's uid are left byte-for-byte untouched (no desc drop, no re-key) ⇒ a co-member's unrelated frozen recap is safe. (The gate keys on the UID only — never on the display-name substring — so a surviving member's `desc` containing the deleted user's name does not trip the scrub.)
  - **Slot semantics:** `biggest.<ccy>.payer` uid→tombstoneId (scalar); drop `biggest.<ccy>.desc` for every ccy; `payers.<ccy>[].id` uid→tombstoneId (scalar); `owed.<ccy>` re-key uid→tombstoneId via `mergeUidMapKey` (SUM on collision).

**6. Verify arithmetic decomposition / conservation.** The snapshot is display-only and never summed by any oracle, so there is no money-truth invariant here — but the fix must still not silently LOSE a frozen figure. `owed.<ccy>` is a uid-keyed money map: the normal (no-collision) case re-keys the value unchanged (only the label becomes "Deleted member"); the #1099 collision case (bucket holds both `T` and `U`) is SUMMED by `mergeUidMapKey` (`{T:2500,U:1000}` → `{T:3500}`), so `Σ owed` across the bucket is preserved — never last-write-wins dropped. `payers.<ccy>` is a LIST, so a re-key of `.id` changes a field with NO possible key-collision loss; the collision merely yields two `{id:T}` rows (both amounts retained). This is the exact `splitDistribution`-vs-`participantNames` distinction the file already encodes (`mapReKey.ts` docstrings): SUM for money maps, overwrite/plain for the rest.

**7. Adversarial pass on orthogonal axes (identity + time).**

- **Identity — same-uid re-join re-delete (#1099):** deletion of `U` fails partway (auth user survives) → `U` re-joins → an event closes with `owed.OMR` holding BOTH the prior tombstone `T` (residual via re-keyed `participantIds`) and re-added `U` → `deletionReaper` re-runs the cascade, REUSES base tombstone `T` (`:478-483`). The fix SUMS `owed` (no drop). `payers` keeps two `T` rows (accepted cosmetic). Pinned by Task-1 test 3.
- **Identity — false re-key:** the only object keys equal to `uid` live in `owed.<ccy>`; ccy codes / `v`/`id`/`amt`/`cat`/`payer` literals never equal a Firebase uid; the only string VALUES equal to `uid` are `biggest.payer` / `payers[].id`; `biggest.id` is an expenseId, `cat` a categoryId. No false positive.
- **Time — reopen/re-close:** `reopenEvent` nulls `closedBy` and `FieldValue.delete()`s `spendingSnapshot` (`event_service.dart:258,263`); a post-deletion re-close rebuilds from live docs whose ids were already tombstoned. No stale-scrub interaction. Clean.
- **Time — idempotency:** second pass — `closedBy` already `tombstoneId`(≠uid) → skip; `snapshotReferencesUid` finds no uid → `changed=false` → snapshot untouched (not re-stripped). Desc-drop + re-key land together in one `writer.update`; a torn batch leaves the uid present → retry redoes both. No partial state.
- **`closedBy` sentinel — `tombstoneId`, NOT `deletedUserSentinel`** (deviates from the issue's suggestion): `closedBy` is name-resolved on two live surfaces (banner + receipt), exactly like `actorId` (cascade already re-keys that to `tombstoneId`); `deletedUserSentinel` has no member doc → renders 'Unknown'/fallback. Both non-PII; `tombstoneId` is display-correct. Both round-1 reviewers independently confirmed this choice.

### Accepted residuals (documented, no code change — so they are not later mis-filed as scrub failures)

- **R1 — offline stale-close replay:** a surviving member who closes the event OFFLINE with a pre-scrub cache queues a `closeEvent` write embedding the raw uid + verbatim `desc`; it can replay AFTER the cascade completes, re-persisting PII, with no event-onUpdate trigger/reaper backstop. Best-effort residual, companion to the documented concurrent-edit race (`deleteAccount.ts:505-509`). No real users yet (#202).
- **R2 — payers duplicate tombstone rows:** on the #1099 collision, `payers.<ccy>` may list `{id:T}` twice — non-lossy (both frozen paid-figures retained), cosmetic (recap lists "Deleted member" twice). Not merged because a list re-key cannot lose data (unlike the map `owed`).
- **R3 — within a REFERENCED event, all `biggest.<ccy>.desc` are dropped** even when the biggest expense in some currency was authored by a surviving member — a cosmetic label loss on an opaque, non-authoritative, frozen recap. Privacy-completeness (no possible leak) over recap fidelity; the alternative (null `desc` only when `biggest.payer==uid`) LEAKS the "created-but-did-not-pay" case, which a privacy fix must not do. (Round-2 adversary confirmed the *inverse* leak — a uid-free snapshot still carrying a deleted-user-authored desc — is UNREACHABLE: expense creators are event participants (#1131) and `calculateBalances` emits a `UserBalance` per participant per currency, so the uid is always an `owed.<ccy>` key ⇒ the gate always trips for events the user touched. The uid-only gate has no participant-shaped hole.)
- **R4 — groups the user LEFT before deletion are outside the cascade entirely.** The cascade only enumerates `memberIds array-contains uid` groups (`deleteAccount.ts:466,823`); `leaveGroup`/`removeMember` never prune event `participantIds`, so a close-event → leave-group → delete-account sequence leaves the raw uid in `closedBy`/`spendingSnapshot` (and every other field) in that group forever. This is a PRE-EXISTING cascade-wide scoping boundary shared by every scrubbed field — inherited, NOT introduced by this fix. Both round-2 reviewers flagged it for naming so it isn't later mis-filed as a scrub-field bug. (A cascade-scope fix is a separate issue, out of scope here.)
- **R5 — online concurrent close mid-cascade** — a surviving admin closing the event from partially-scrubbed provider state, or replaying a queued offline close (R1), can freeze a snapshot carrying the raw uid after the event pass already ran; same accepted concurrent-edit class as `deleteAccount.ts:505-509`. No trigger/reaper re-scrubs a completed deletion. Best-effort under the no-real-users policy (#202).

---

## Task 1: RED — event doc retains deleted-user identity in `closedBy` + `spendingSnapshot`

**Files:** Test — `functions/test/callables/deleteAccount.test.ts` (new `describe('#1133 …')` block near the existing event-scrub assertions ~L360-430). Use the file's real helpers: `wrapped({ data: {}, auth: { uid: deletedUid } } as any)` to invoke; `seedAuthUser()`, `seedGroup`, `seedMember(groupId, uid)` (auto-sets displayName; 3rd arg is a DATA object, not a name), `seedEvent(groupId, eventId, data)`, `expectNoDeletedIdentity(data)`, `tombstoneIdFor(uid)` (`:146-147`).

**Step 1: Write the failing tests**

```typescript
describe('#1133 closedBy + spendingSnapshot scrub', () => {
  const DESC_PII = 'dinner-at-my-secret-address-42';

  it('scrubs closedBy uid and spendingSnapshot uids/descriptions from the closed event', async () => {
    await seedAuthUser();
    await seedGroup('groupA', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('groupA', deletedUid);
    await seedMember('groupA', otherUid);
    await seedEvent('groupA', 'eventA', {
      createdBy: otherUid,
      isClosed: true,
      closedAt: new Date('2026-01-06T00:00:00.000Z'),
      closedBy: deletedUid,
      spendingSnapshot: {
        v: 1, participantCount: 2, expenseCount: 1,
        totals: { OMR: 5000 },
        biggest: { OMR: { id: 'e1', amt: 5000, desc: DESC_PII, cat: 'food', payer: deletedUid } },
        payers: { OMR: [{ id: deletedUid, amt: 5000 }, { id: otherUid, amt: 0 }] },
        categories: { OMR: [{ cat: 'food', amt: 5000 }] },
        owed: { OMR: { [deletedUid]: 2500, [otherUid]: 2500 } },
      },
    });

    await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    const event = (await getFirestore().doc('groups/groupA/events/eventA').get()).data();
    expectNoDeletedIdentity(event);
    const t = tombstoneIdFor(deletedUid);
    expect(event?.closedBy).toBe(t);
    const snap = event?.spendingSnapshot;
    expect(snap.biggest.OMR.payer).toBe(t);
    expect(snap.biggest.OMR).not.toHaveProperty('desc');
    expect(snap.payers.OMR.map((p: { id: string }) => p.id)).toContain(t);
    expect(Object.keys(snap.owed.OMR)).toContain(t);
    expect(JSON.stringify(snap)).not.toContain(DESC_PII);
    expect(snap.owed.OMR[t]).toBe(2500);        // amount preserved on re-key
    expect(snap.owed.OMR[otherUid]).toBe(2500);
  });

  it('SUMS (never drops) owed on the #1099 tombstone-collision re-delete', async () => {
    const t = tombstoneIdFor(deletedUid);
    await seedAuthUser();
    await seedGroup('groupC', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('groupC', deletedUid);
    await seedMember('groupC', otherUid);
    await seedEvent('groupC', 'eventC', {
      createdBy: otherUid,
      isClosed: true,
      closedAt: new Date('2026-01-06T00:00:00.000Z'),
      closedBy: otherUid,
      // Collision: owed holds BOTH the prior tombstone T and the re-added uid U.
      spendingSnapshot: {
        v: 1, participantCount: 2, expenseCount: 1,
        totals: { OMR: 3500 },
        biggest: { OMR: { id: 'e1', amt: 3500, payer: otherUid } },
        payers: { OMR: [{ id: deletedUid, amt: 3500 }] },
        categories: { OMR: [{ cat: 'food', amt: 3500 }] },
        owed: { OMR: { [t]: 1000, [deletedUid]: 2500 } },
      },
    });

    await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    const snap = (await getFirestore().doc('groups/groupC/events/eventC').get()).data()?.spendingSnapshot;
    // MERGE-SUM, not last-write-wins drop (2500) and not overwrite: 1000 + 2500.
    expect(snap.owed.OMR[t]).toBe(3500);
    expect(snap.owed.OMR).not.toHaveProperty(deletedUid);
  });

  it('leaves an unrelated event snapshot (no deleted-user reference) byte-for-byte untouched', async () => {
    await seedAuthUser();
    await seedGroup('groupB', [deletedUid, otherUid], { createdBy: otherUid });
    await seedMember('groupB', deletedUid);
    await seedMember('groupB', otherUid);
    const untouched = {
      v: 1, participantCount: 1, expenseCount: 1,
      totals: { OMR: 1000 },
      biggest: { OMR: { id: 'x1', amt: 1000, desc: 'others-only-dinner', payer: otherUid } },
      payers: { OMR: [{ id: otherUid, amt: 1000 }] },
      categories: { OMR: [{ cat: 'food', amt: 1000 }] },
      owed: { OMR: { [otherUid]: 1000 } },
    };
    await seedEvent('groupB', 'eventB', {
      createdBy: otherUid, participantIds: [otherUid],
      participantNames: { [otherUid]: otherName },
      isClosed: true, closedAt: new Date('2026-01-06T00:00:00.000Z'), closedBy: otherUid,
      spendingSnapshot: untouched,
    });

    await wrapped({ data: {}, auth: { uid: deletedUid } } as any);

    const event = (await getFirestore().doc('groups/groupB/events/eventB').get()).data();
    expect(event?.spendingSnapshot).toEqual(untouched); // no collateral desc drop
  });
});
```

**Step 2: Run to verify failure for the right reason**
Run: `cd functions && npm run test:emulator -- callables/deleteAccount.test.ts -t "#1133"`
Expected: tests 1 & 2 FAIL pre-fix (event doc still contains `deletedUid` in `closedBy`+snapshot; `biggest.OMR.desc` still `DESC_PII`; owed collision either drops to 2500 or leaves `deletedUid`). Test 3 PASSES pre-fix (proves non-vacuous). Capture the failing output verbatim for the PR.

---

## Task 2: GREEN — scrub `closedBy` + `spendingSnapshot` in the per-event cascade

**Files:** Modify `functions/src/callables/deleteAccount.ts` — import `toFiniteNumber`; add `isRecord`, `snapshotReferencesUid`, `scrubSpendingSnapshot` (near `hasChanged`, ~L196); extend the per-event `eventUpdate` block (`:519-521`).

**Step 1: Import + helpers**

No import change needed — keep the existing `:15` import (`mergeUidMapKey` is already imported; do NOT add `toFiniteNumber` — `functions/tsconfig.json` has `noUnusedLocals:true` and `npm run build` is the predeploy gate, so an unused import is a hard build failure. `mergeUidMapKey` applies NaN-coercion internally):
```typescript
import { mergeUidMapKey, replaceUid, renameMapKey } from './shared/mapReKey';
```

Add below `hasChanged` (~L196):
```typescript
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

// #1133: does the deleted user's uid appear anywhere in the frozen snapshot? Its
// ONLY raw-uid slots are biggest.<ccy>.payer, payers.<ccy>[].id, and owed.<ccy>
// map KEYS. The collateral gate: an event whose snapshot never names the uid is
// left byte-for-byte untouched (no desc drop, no re-key), so a co-member's
// unrelated frozen recap is safe. Keys on the UID ONLY — never the display-name.
function snapshotReferencesUid(snapshot: Record<string, unknown>, uid: string): boolean {
  const { biggest, payers, owed } = snapshot;
  if (isRecord(biggest)) {
    for (const ref of Object.values(biggest)) {
      if (isRecord(ref) && ref.payer === uid) return true;
    }
  }
  if (isRecord(payers)) {
    for (const list of Object.values(payers)) {
      if (Array.isArray(list) && list.some((p) => isRecord(p) && p.id === uid)) return true;
    }
  }
  if (isRecord(owed)) {
    for (const bucket of Object.values(owed)) {
      if (isRecord(bucket) && Object.prototype.hasOwnProperty.call(bucket, uid)) return true;
    }
  }
  return false;
}

// #1133: scrub the frozen, OPAQUE, DISPLAY-ONLY spendingSnapshot on a closed
// event. The live-doc scrubs never reach it: biggest.<ccy>.payer / payers.<ccy>[].id
// / owed.<ccy> keys hold raw participant uids, and biggest.<ccy>.desc is a verbatim
// frozen copy of Expense.description. Re-key uids to the tombstone (→ "Deleted
// member" on the recap, mirroring participantNames) and drop every frozen
// description — but ONLY when the snapshot references the uid, so an unrelated
// event's snapshot (incl. OTHER members' descriptions) takes zero collateral. The
// balance oracle NEVER reads this field, so re-keying/dropping degrades only a
// cosmetic recap label, never a balance.
//
// owed.<ccy> is a uid-keyed MONEY map: on the #1099 re-join re-delete collision
// (bucket holds BOTH prior tombstone T and re-added uid U) the two frozen figures
// are SUMMED via mergeUidMapKey — the precedent the file uses for splitDistribution
// (:244-251) — never last-write-wins dropped. payers is a LIST so a re-key loses
// nothing (a collision leaves two tombstone rows, accepted cosmetic). Idempotent:
// a second pass finds no uid ⇒ changed=false ⇒ no-op.
function scrubSpendingSnapshot(
  snapshot: unknown,
  uid: string,
  tombstoneId: string,
): { value: unknown; changed: boolean } {
  if (!isRecord(snapshot) || !snapshotReferencesUid(snapshot, uid)) {
    return { value: snapshot, changed: false };
  }

  const scrubBiggest = (biggest: unknown): unknown => {
    if (!isRecord(biggest)) return biggest;
    const next: Record<string, unknown> = {};
    for (const [ccy, ref] of Object.entries(biggest)) {
      if (!isRecord(ref)) { next[ccy] = ref; continue; }
      const rest = { ...ref };
      delete rest.desc; // drop the frozen verbatim description (avoids the unused
                        // `_desc` rest-sibling lint the destructure form triggers)
      if (rest.payer === uid) rest.payer = tombstoneId;
      next[ccy] = rest;
    }
    return next;
  };

  const scrubPayers = (payers: unknown): unknown => {
    if (!isRecord(payers)) return payers;
    const next: Record<string, unknown> = {};
    for (const [ccy, list] of Object.entries(payers)) {
      next[ccy] = Array.isArray(list)
        ? list.map((item) => (isRecord(item) && item.id === uid ? { ...item, id: tombstoneId } : item))
        : list;
    }
    return next;
  };

  const scrubOwed = (owed: unknown): unknown => {
    if (!isRecord(owed)) return owed;
    const next: Record<string, unknown> = {};
    for (const [ccy, bucket] of Object.entries(owed)) {
      const merged = mergeUidMapKey(bucket, uid, tombstoneId); // SUM on collision
      next[ccy] = merged === null ? bucket : merged.value;
    }
    return next;
  };

  return {
    value: {
      ...snapshot,
      biggest: scrubBiggest(snapshot.biggest),
      payers: scrubPayers(snapshot.payers),
      owed: scrubOwed(snapshot.owed),
    },
    changed: true,
  };
}
```

**Step 2: Wire into the per-event loop** — inside `cascadeGroupAfterMarker`, right after the `createdBy` re-key (`:519-521`):
```typescript
    if (eventData.createdBy === uid) {
      eventUpdate.createdBy = deletedUserSentinel;
    }
    // #1133: closedBy is an actor-identity field resolved to a display NAME in the
    // closed banner + trip receipt (like actorId, unlike the non-resolved event
    // createdBy) — re-key to the tombstone so it renders "Deleted member".
    if (eventData.closedBy === uid) {
      eventUpdate.closedBy = tombstoneId;
    }
    // #1133: scrub the frozen spendingSnapshot (uids + verbatim descriptions).
    const snapshotScrub = scrubSpendingSnapshot(eventData.spendingSnapshot, uid, tombstoneId);
    if (snapshotScrub.changed) {
      eventUpdate.spendingSnapshot = snapshotScrub.value;
    }
```

**Step 3:** Run the #1133 tests → PASS. **Step 4:** Run the FULL `deleteAccount.test.ts` suite → all green (idempotency/retry/reaper/orphan legs inherit the fix via the shared `runAccountDeletionCascade`; `deletionReaper` needs no separate change).

**Step 5: Commit.** Conventional; body carries **`Refs #1133`** (NOT `Closes` — Part B is outstanding; squash auto-closes from the commit message per the #447 class) and names Part B (`hosting/delete-data.html` rewrite) as the remaining box. Paste the RED-before/GREEN-after output.
```bash
git add functions/src/callables/deleteAccount.ts functions/test/callables/deleteAccount.test.ts docs/plans/2026-07-11-1133-deleteaccount-pii-scrub.md
git commit  # fix(privacy): scrub closedBy + spendingSnapshot PII in deleteAccount (Refs #1133)
```

---

## Task 3: Doc truth-sweep
- `docs/CLOUD-FUNCTIONS.md` — `deleteAccount` cascade: add `closedBy` + `spendingSnapshot` to the per-event scrubbed-field list.
- `CLAUDE.md` — only if the deletion invariant enumerates scrubbed fields (grep `Account deletion`); keep terse.
- Do NOT touch `docs/PRODUCTION-READINESS.md` deploy blockers.

## Definition of done (Part A)
- [ ] RED tests 1 & 2 fail pre-fix for the right reason (pasted output), pass post-fix; test 3 passes pre-fix (non-vacuous).
- [ ] Full `deleteAccount.test.ts` suite green.
- [ ] `closedBy` uid→tombstoneId; snapshot payer/payers/owed uids→tombstoneId; every `biggest.desc` dropped; `owed` collision SUMMED (no drop); unrelated-event snapshot untouched.
- [ ] No `security/firestore.rules` / client change.
- [ ] `Refs #1133` in commit + PR body; Part B named as the remaining box.
- [ ] Pending-deploy flagged (Functions change) — do NOT deploy without user go-ahead.

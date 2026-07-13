# #1205 — client/server universe parity on empty-string `payerParticipantId`

**Issue:** #1205 · **Area:** money-math / oracle parity · **Gate-category:** yes (BalanceCalculator parity + Cloud Functions)

## Problem (verified against live code this session)

- Server `functions/src/callables/groupNetBalance.ts` (financial fold, expense payers):
  `if (typeof e.payerParticipantId === 'string') financial.add(e.payerParticipantId);`
  `typeof '' === 'string'` is **true**, so a persisted `''` payer enters `financial`, is not
  in `liveMemberIds`, joins the universe, seeds a phantom `''` row that receives the paid
  credit, and inflates the equal-split divisor (n+1 vs n).
- Client `lib/features/ledger/providers/expense_provider.dart:124-125`:
  `if (e.payerParticipantId.isNotEmpty) e.payerParticipantId,` — **excludes** `''`.
- Client comment at `expense_provider.dart:118-123` claims the oracle's `typeof` gate
  excludes `''` — **false**.
- Settlement parties are **consistent on both sides** (client null-gates only, `''` passes;
  server `typeof` gates, `''` passes) — deliberately OUT OF SCOPE.

Reachability: `firestore.rules` (`data.payerParticipantId in participants()`, ~L848) blocks
`''` on create — only forged / Admin-SDK / legacy docs. But `recomputeNet`'s threat model
explicitly defends against forged docs (#192/#223 backstop), so the divergence is real debt:
settle-up caps, `deleteGroup`/`leaveGroup`/`removeMember` zero-gates, and the balance
aggregate would all disagree with the client ledger on such a doc.

## Decision: server excludes `''` (client unchanged)

Align the **server to the client**, not the reverse:

1. Client behavior is the display truth users see; a `''` phantom row in the ledger is garbage.
2. The #928 salvage contract: the client total-parse factory salvages a **non-string** payer
   to `''` and drops it; the server `typeof` gate drops non-strings too. Excluding `''`
   server-side makes the unified semantics "no valid payer ⇒ paid credit dropped" on both
   sides — consistent with the existing "drop owed for keys outside the universe" philosophy.
3. One change site: the expense-payer fold in `groupNetBalance.ts` is shared by
   `deleteGroup`/`leaveGroup`/`removeMember`/`recordSettlement` caps/`balanceAggregator`
   (no second copy to drift) — all consumers realign at once.

## Changes

1. **`functions/src/callables/groupNetBalance.ts`** — expense-payer fold only:
   ```ts
   if (typeof e.payerParticipantId === 'string' && e.payerParticipantId !== '') {
     financial.add(e.payerParticipantId);
   }
   ```
   Settlement-party folds UNCHANGED. Update the adjacent parity comment to name the `''`
   exclusion explicitly.
2. **`lib/features/ledger/providers/expense_provider.dart:118-123`** — rewrite the comment:
   the oracle now **explicitly excludes `''`** (post-this-change); the client `isNotEmpty`
   guard mirrors it. No client code change.
3. **RED regression test (Functions/jest, emulator runner):** seed an expense doc with
   `payerParticipantId: ''` (**the literal empty STRING** — the existing #928 fixture at
   `groupNetBalance.test.ts:404-436` uses a non-string `42`, already dropped by `typeof`,
   and does NOT cover this) via the Admin SDK, run the oracle, assert (a) no `''` key in
   the resulting nets, (b) the equal-split divisor matches the client (n, not n+1). Must
   fail before the fix. Use `cd functions && npm run test:emulator -- <file> -t "<name>"`
   (never bare `npm test` — #1157 guard). Also touch up the #928 test comment at
   `groupNetBalance.test.ts:352-353` ("gates it with typeof === 'string'"), which goes
   stale post-fix. Additionally pin the SETTLEMENT-interaction case: a live settlement
   referencing `''` (`groupNetBalance.ts:654-657`, deliberately unchanged) must STILL put
   `''` in the universe — this guards against a future "strip the sentinel everywhere"
   edit silently over-removing and re-diverging from the client (whose settlement fold
   also passes `''`).
4. **Client pin: already exists** — `malformed_doc_fencing_test.dart:117-157` (test 4)
   feeds a salvaged-`''` payer through `eventBalanceUniverse` and asserts no phantom row.
   Do NOT add a redundant client test.

## Verification-principles evidence

- **Callsite classification:** the fold is OUTBOUND (feeds settle caps, departure zero-gates,
  aggregate writes). Change narrows the server universe to match the client — the read-path
  per write-path is the settle-up cap (`recordSettlement` recomputes outstanding via this fold).
- **Arithmetic decomposition:** dropping `''` removes both its paid credit AND its divisor
  slot — exactly the client's arithmetic; conservation within the universe is unchanged.
- **Orthogonal axis for reviewers:** settlements (deliberately untouched — `''` settlement
  parties still fold on both sides) and the #928 non-string salvage path (already consistent).

## Out of scope

Settlement-party `''` handling (consistent today); any rules change (create already blocked);
client universe code.

## Post-merge

Functions change ⇒ deploy ceremony (`tool/pending_deploy.sh` → `deploy-ceremony`). No real
users ⇒ deploys freely.

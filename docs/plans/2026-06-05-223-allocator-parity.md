# Spec: close the deleteGroup `allocateExact` in-tolerance residual parity gap (#223)

**Date:** 2026-06-05
**Surface:** server money-path (`functions/src/callables/deleteGroup.ts`) — **Gate mandatory.**
**Origin:** Fresh-context adversarial refute of the "#223 sum-validation is redundant, safe to close" verdict. The refute survived on the "infeasible in rules" half but **broke** the "redundant compensating control" half by finding a live client↔server allocator divergence. Verified against code 2026-06-05.

---

## 1. Problem (verified against code, not docs)

A within-tolerance **exact** split (`0 < |sum(values) − amountFils| ≤ tolerance`, tolerance = 0.001) makes the **client show the group settled** while the **server `deleteGroup` gate computes a non-zero net and refuses deletion**. Reachable on the **legitimate** path (the #250 save guard admits within-tolerance exact splits), not only via forged/Admin/legacy writes.

Three load-bearing facts, each read directly:

1. **Client closes the residual.** `BalanceCalculator._allocateExact` (`lib/features/ledger/providers/expense_provider.dart:507-543`): after the out-of-tolerance guard, `residual = amount − total`; if non-zero it is closed onto the alphabetically-last recipient that can absorb it without going negative (the "last absorbable" loop, 524-531), with an unabsorbable→equal fallback (532-539). Result: `sum(owed) == amount` exactly → client net = 0.
2. **Server does NOT.** TS `allocateExact` (`functions/src/callables/deleteGroup.ts:212-222`): out-of-tolerance → `allocateEqual`; otherwise `return new Map(distribution)` **verbatim** — no residual close-out. Server `sum(owed) == forged/entered sum ≠ amount`.
3. **The gate is an exact-zero check.** `deleteGroup.ts:692`: `outstanding = [...net.entries()].filter(([, v]) => !v.isZero())`; `outstanding.length > 0 → throw failed-precondition` (693-697). **No tolerance.** So the server's residual blocks deletion.

**Repro (OMR, scale 1000, tolerance 0.001 = 1 fils):** expense 10.000, exact `{alice:5.000, bob:5.001}` (sum 10.001, drift exactly 0.001, `0.001 > 0.001` is false → in-tolerance, no fallback). Passes `splitValuesNonNegative` (`firestore.rules:492`, `"5000,5001"` matches `^[0-9,]+$`). Client nets to all-zero after the residual close-out; server net carries −0.001 → `deleteGroup` blocks. Stacks linearly (50 such expenses → 0.050 divergence).

**Mode scope:** `exact` is the *unique* diverging mode. `percent`/`shares` route their in-tolerance case through `allocateWeighted` (last-recipient-absorbs, `deleteGroup.ts:180-198`), which already conserves; `shares` cannot be "non-summing" (any positive total normalizes). Confirmed by the refute + code.

## 2. Root cause

Not a value-domain hole and not a missing rules fold. It is **allocator non-parity**: the TS `deleteGroup` oracle is missing the Dart residual close-out. CLAUDE.md and `expense_provider.dart:260` assert the two mirror "byte-for-byte"; that is **false** in the in-tolerance exact band (obs 24201 noted the divergence during #249 work; it was never fixed).

## 3. Fix (GREEN)

Port the Dart residual close-out into TS `allocateExact`. Target shape (mirror `expense_provider.dart:507-543` exactly):

```ts
function allocateExact(amount, distribution, currency) {
  const total = sumValues(distribution);
  if (total.minus(amount).abs().gt(SPLIT_TOLERANCE)) {
    return allocateEqual(amount, distribution.keys(), currency);   // unchanged out-of-tolerance guard
  }
  const residual = amount.minus(total);
  if (residual.isZero()) return new Map(distribution);             // exact — unchanged
  // in-tolerance non-zero residual: close onto the alphabetically-last recipient
  // that can absorb it without going negative (mirror Dart 524-531).
  const sortedKeys = [...distribution.keys()].sort();
  let target = null;
  for (let i = sortedKeys.length - 1; i >= 0; i--) {
    if (distribution.get(sortedKeys[i]).plus(residual).gte(0)) { target = sortedKeys[i]; break; }
  }
  if (target == null) {
    return allocateEqual(amount, distribution.keys(), currency);   // unabsorbable → equal (mirror Dart 532-539)
  }
  const out = new Map();
  for (const k of sortedKeys) out.set(k, k === target ? distribution.get(k).plus(residual) : distribution.get(k));
  return out;
}
```

Decimal API: use the existing `Money`/Decimal helpers already in the file (`.minus/.plus/.gte/.isZero`); match how `allocateEqual`/`allocateWeighted` use them. Keep `allocateEqual`'s own remainder-onto-last contract intact.

**Direction justification (rejected alternative):** do NOT instead relax the gate to `|net| > someTolerance`. That papers over the divergence with a gate tolerance, masks genuinely-tiny intended balances, and leaves the oracle non-parity for every other consumer. Fixing the allocator keeps the gate's exact `isZero()` correct (a settled group nets to exact zero on both sides) and restores the byte-for-byte oracle CLAUDE.md already promises.

## 4. RED tests (write first, watch fail for the right reason)

- **TS (the real RED):** `functions/test/callables/deleteGroup.test.ts` — follow the existing `testEnv.wrap(deleteGroup)` + emulator-seed pattern (do NOT export the private `recomputeNet`). Seed a group/event, expense 10.000 OMR, exact `{a:5.000, b:5.001}` (sum 10.001, drift exactly 0.001 → in-tolerance), no settlements; assert `deleteGroup` **succeeds** (today it throws `failed-precondition` because the server net carries −0.001). Greens after the port.
- **Dart (contract pin):** `test/unit/delete_group_balance_parity_test.dart` — same fixture, assert `netFor(balances, a) == 0 && netFor(balances, b) == 0` (Dart already closes the residual → documents the value the server is REQUIRED to match; complements the existing case-1/12 fixtures which don't exercise the in-tolerance exact band).
- **Close-out coverage:** the residual close-out lives only in the in-tolerance band, which exists at scale ≥ 100. Use **OMR (scale 1000)** for the primary fixture; optionally add a **USD (scale 100)** variant. The "last absorbable recipient" selection is exercised by an over-allocation in-tolerance fixture e.g. `{a:5.001, b:5.000}` on 10.000 (residual −0.001; alphabetically-last `b` is the absorber chosen by the end-iterating loop).

**Gate-corrected (do NOT write these):**
- **No JPY close-out test** — at scale=1 the smallest nonzero `|sum−amount|` is 1 yen ≫ 0.001, so the in-tolerance non-zero-residual band is **empty**; a JPY fixture only re-tests the pre-existing out-of-tolerance equal fallback, not the new close-out. If a JPY case is kept, label it explicitly as an out-of-tolerance-fallback assertion.
- **No "unabsorbable→equal fallback" test** — that branch requires *every* key to fail `value + residual ≥ 0`, which is **unreachable for an in-tolerance positive amount** (Dart's own comment, `expense_provider.dart:534`). It is defensive code reachable only by a direct forged unit call; do not assert it via the allocator/gate path.

## 5. Out of scope (do not bundle)

- The rules-fold "sum validation in CEL" — **infeasible** (no fold, no participant cap, mode-dependent invariant); this stays documented as the accepted limitation, NOT attempted.
- The async validation trigger (rejected: redundant with the now-parity-correct oracle).
- #249/#255 universe-construction (already shipped) — this fix is the *allocation* step, not the universe step.

## 6. #223 closure (after this lands)

The value-domain half closes honestly: non-negative guard shipped + tested (`firestore-rules-publish-readiness.test.ts:1347+`); sum invariant enforced at the compute boundary by the oracle, now parity-correct on the **in-tolerance exact residual** band; rules-level sum validation documented infeasible.

**Scoped CLAUDE.md edit (Gate P3):** do NOT claim full byte-for-byte parity. The accurate statement is: *"`allocateExact`'s in-tolerance residual close-out is now mirrored client↔server; negative-value guards remain client-only (new negatives are rules-blocked at `firestore.rules:492`; #192)."* The server `allocateExact`/`allocateShares`/`allocatePercent` still lack the Dart negative-value→equal-fallback guards (`deleteGroup.ts:212-234` vs `expense_provider.dart:457/492/554`) — **out of scope here**, filed as a follow-up. Legacy/Admin negative docs are the only writes that hit it (rules block all new ones).

## 7. Verification principles applied

- **Callsite classification:** the persisted `splitDistribution` is BOTH (read by client display + client balance + server gate). The OUTBOUND-to-a-money-decision path is the server gate — the one that diverged.
- **One read-path per write-path:** "who reads a within-tolerance exact split after write?" → client `_allocateExact` (closes) AND server `allocateExact` (didn't) → the divergence.
- **Arithmetic decomposition:** `net = paid + settlementAdj − owed`; the bug is in the `owed` fold (`deleteGroup.ts:618-620`) consuming a non-conserving `allocations` map.
- **Adversarial / orthogonal axis:** the refute exercised the deletion-gate axis (not the display axis), which is where the consequence lives.

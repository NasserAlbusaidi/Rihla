# #872 — Weighted-split remainder must never land on a declared-0-share participant

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix `_allocateWeighted` (client) and `allocateWeighted` (server oracle) so the rounding remainder lands on the alphabetically-last **positive-weight** recipient, never a declared-0-share key — in the same change on both sides, preserving byte-for-byte oracle parity.

**Architecture:** Both allocators currently sort **all** distribution keys and hand the last one `amount − allocated`. A 0-share key that sorts last therefore absorbs the truncation residual (up to n−1 subunits), violating the pinned "0 share = owes nothing" invariant. The fix mirrors `_spreadProportional`'s positive-weight filter: pick the remainder target as the last positive-weight key; 0-weight keys keep their quantized share (exactly 0). Map shape (all keys present) and sorted key order are preserved.

**Tech Stack:** Dart (`decimal`), TypeScript (`decimal.js` `Money` clone, ROUND_DOWN), Jest + Firestore emulator, flutter_test.

---

## Verified facts (re-checked against code 2026-07-04, this session)

- Client: `lib/features/ledger/providers/expense_provider.dart:754-780` — `_allocateWeighted` sorts all keys; `isLast = i == sortedRecipients.length - 1` gets `amount - allocated`. No weight filter.
- Server: `functions/src/callables/groupNetBalance.ts:163-181` — `allocateWeighted` identical shape (`sorted[sorted.length-1]` absorbs). The **only** TS copy (grep: no other `allocateWeighted` under `functions/src/`); shared by `recomputeNet` → `deleteGroup`/`leaveGroup`/`removeMember`.
- Reference implementation: `_spreadProportional` (`expense_provider.dart:602-623`) filters `e.value > 0` before choosing the remainder key; falls back to equal spread only when NO key is positive.
- Quantization **truncates toward zero on both sides** (`MoneySerializer.toSubunits` via `.toBigInt()`, `money_serializer.dart:30-33`; TS `quantize` `Decimal.ROUND_DOWN`, `groupNetBalance.ts:62-66`). Therefore non-remainder shares always under-allocate ⇒ the residual is **always ≥ 0**; a negative owed via rounding overshoot is unreachable. The defect is a spurious positive owed on a 0-share key, magnitude ≤ (n−1) subunits.
- Callers guarantee ≥ 1 positive weight when `_allocateWeighted`/`allocateWeighted` is reached:
  - shares: negatives → equal fallback; `totalShares <= 0` → equal fallback (`expense_provider.dart:637-650`, `groupNetBalance.ts:194-200`).
  - percent: negatives → equal fallback; `|total − 100| > 0.001` → equal fallback (`expense_provider.dart:736-749`, `groupNetBalance.ts:265-271`).
  - Only call sites: `expense_provider.dart:652,751`; `groupNetBalance.ts:201,272`. `_allocateEqual` and the itemized `_spreadProportional` path are unaffected.
- Persisted `splitDistribution` is raw user weights (shares = integer counts, `decodeSplitValue` `groupNetBalance.ts:95-106`), never allocator output ⇒ no schema/write-path change. Allocator output feeds balance display **and** settle-up amounts ⇒ classify OUTBOUND; both sides must change together or the oracle drifts.
- Existing tests pin "remainder → last sorted pid" only with **all-positive** weights (`balance_calculations_test.dart:94-113,181-201`) and pin a zero entry that is **not** last (`:283-303`). No test pins the buggy behavior.

### Reproduction by expression (RED cases)

OMR (scale 1000), amount 1.000, shares `{p1: 1, p2: 2, p3: 0}` (p3 sorts last):

- Today: p1 = trunc(1/3) = 0.333, p2 = trunc(2/3) = 0.666, p3 = 1.000 − 0.999 = **0.001** ← 0-share key owes money.
- Fixed: remainder key = p2 (last positive): p1 = 0.333, p3 = 0.000, p2 = 1.000 − 0.333 = **0.667**. Conservation holds exactly.

Percent mirror: amount 1.000, `{p1: 33.33, p2: 66.67, p3: 0}` (sums to 100): today p3 = 0.001; fixed p3 = 0.000, p2 = 0.667.

## The fix (identical on both sides)

Choose `remainderKey` = alphabetically-last key with weight > 0 (defensive fallback to whole-table-last if none — unreachable via the guarded callers, kept so the function never throws on a direct future caller). Every other key gets its truncation-quantized share (0-weight ⇒ exactly 0); `remainderKey` gets `amount − allocated`. Rebuild the map in sorted key order so iteration order is unchanged.

**Dart** (`expense_provider.dart` `_allocateWeighted`):

```dart
static Map<String, Decimal> _allocateWeighted(
  Decimal amount,
  Map<String, Decimal> weights,
  Decimal denominator,
  String currency,
) {
  final sortedRecipients = weights.keys.toList()..sort();
  // The rounding remainder lands on the alphabetically-last POSITIVE-weight
  // recipient — never a declared-0-share key (#872), mirroring
  // _spreadProportional. Callers guarantee at least one positive weight
  // (negatives → equal fallback, total > 0), so orElse is defensive only.
  final remainderKey = sortedRecipients.lastWhere(
    (id) => weights[id]! > Decimal.zero,
    orElse: () => sortedRecipients.last,
  );
  final allocations = <String, Decimal>{};
  var allocated = Decimal.zero;
  for (final recipientId in sortedRecipients) {
    if (recipientId == remainderKey) continue;
    final allocation = _toCurrencyPrecision(
      ((amount * weights[recipientId]!) / denominator).toDecimal(
        scaleOnInfinitePrecision: 10,
      ),
      currency,
    );
    allocations[recipientId] = allocation;
    allocated += allocation;
  }
  allocations[remainderKey] = amount - allocated;
  return {for (final id in sortedRecipients) id: allocations[id]!};
}
```

**TS** (`groupNetBalance.ts` `allocateWeighted`):

```ts
function allocateWeighted(
  amount: Decimal,
  weights: Map<string, Decimal>,
  denominator: Decimal,
  currency: string,
): Map<string, Decimal> {
  const sorted = [...weights.keys()].sort();
  // #872: remainder lands on the alphabetically-last POSITIVE-weight key,
  // never a declared-0-share one — byte-for-byte mirror of the client
  // _allocateWeighted (expense_provider.dart). Callers guarantee >=1 positive
  // weight; the whole-table-last fallback is defensive only.
  let remainderKey = sorted[sorted.length - 1];
  for (let i = sorted.length - 1; i >= 0; i--) {
    if (weights.get(sorted[i])!.gt(0)) {
      remainderKey = sorted[i];
      break;
    }
  }
  const allocations = new Map<string, Decimal>();
  let allocated = new Money(0);
  for (const id of sorted) {
    if (id === remainderKey) continue;
    const allocation = quantize(amount.times(weights.get(id)!).div(denominator), currency);
    allocations.set(id, allocation);
    allocated = allocated.plus(allocation);
  }
  allocations.set(remainderKey, amount.minus(allocated));
  return new Map(sorted.map((id) => [id, allocations.get(id)!]));
}
```

### Behavior deltas (exhaustive)

1. Weighted split where a 0-weight key sorts last **and** division doesn't terminate exactly: the residual moves from the 0-share key to the last positive key. This is the bug fix.
2. All-positive weighted splits: `remainderKey == sortedRecipients.last` ⇒ **byte-identical** output (existing pinned tests stay green).
3. 0-weight key NOT last: already got quantize(0) = 0; unchanged.
4. Legacy prod docs carrying a 0-share-last distribution re-display under the fixed math on both sides after client ship + backend deploy. No real users yet ⇒ no compat ordering (contract: server changes deploy freely).

### Known adjacent edge, explicitly out of scope

Percent totals in-tolerance **above** 100 (e.g. 100.001) with a tiny-positive last key could theoretically drive `amount − allocated` negative by a hair; this exists identically **before and after** this change (parity preserved) and is unreachable through the UI (percent editor normalizes). Not touched here; note for a future hardening pass if #192-style server value validation lands.

## Verification-principles run (out loud)

1. **Callsite classification:** allocator output → `calculateBalances` → balance display + settle-up write amounts ⇒ OUTBOUND. Both implementations changed in the same PR; parity suites re-run.
2. **Concrete claims:** all file:line references above re-read this session (2026-07-04), not cited from memory.
3. **Read-path per write-path:** no persisted field changes; the only "write" influenced is settlement amounts derived from displayed balances — covered by conservation asserts (sum(net) == 0).
4. **Fields from type:** no model change.
5. **Data contracts:** allocator signature, map key-set, and sorted iteration order preserved on both sides.
6. **Arithmetic decomposition:** `sum(allocations) == amount` holds by construction (`remainderKey` gets `amount − allocated`); truncation ⇒ every non-remainder share ≤ exact share ⇒ remainder ≥ its exact share ≥ 0.
7. **Orthogonal adversarial pass:** exercised axes — zero-not-last (green today, stays green), all-positive (pinned, byte-identical), JPY scale 1 (remainder = whole yen, same contract), negative weights (pre-filtered, never reach the allocator), all-zero weights (unreachable; defensive orElse), percent-over-100-in-tolerance (documented above, unchanged).

---

## Task 1: Client RED — regression cases in `balance_calculations_test.dart`

**Files:**
- Modify: `test/unit/balance_calculations_test.dart` (add after the `'shares mode with a zero entry stays valid (zero is not negative)'` test, ~line 303)

**Step 1: Write the failing tests**

Follow the file's existing helpers (`expense(...)`, `owedFor(...)`, `participants`). Table across clean/edge cases per the money-code testing rule:

```dart
test('shares remainder never lands on a declared-0-share key sorting last '
    '(#872)', () {
  final balances = BalanceCalculator.calculateBalances(
    expenses: [
      expense(
        amount: '1.000',
        splitMode: SplitMode.shares,
        splitDistribution: {
          'p1': Decimal.fromInt(1),
          'p2': Decimal.fromInt(2),
          'p3': Decimal.zero,
        },
      ),
    ],
    participants: participants,
  )['OMR']!;

  expect(owedFor(balances, 'p1'), Decimal.parse('0.333'));
  expect(owedFor(balances, 'p2'), Decimal.parse('0.667'));
  expect(owedFor(balances, 'p3'), Decimal.zero);
});

test('percent remainder never lands on a declared-0-percent key sorting last '
    '(#872)', () {
  final balances = BalanceCalculator.calculateBalances(
    expenses: [
      expense(
        amount: '1.000',
        splitMode: SplitMode.percent,
        splitDistribution: {
          'p1': Decimal.parse('33.33'),
          'p2': Decimal.parse('66.67'),
          'p3': Decimal.zero,
        },
      ),
    ],
    participants: participants,
  )['OMR']!;

  expect(owedFor(balances, 'p1'), Decimal.parse('0.333'));
  expect(owedFor(balances, 'p2'), Decimal.parse('0.667'));
  expect(owedFor(balances, 'p3'), Decimal.zero);
});
```

(Adapt helper signatures to the file's actual `expense`/`participants` fixtures — read the top of the file first. If `p3` is not in the default `participants`, reuse the existing pid names so the universe covers all three keys.)

**Step 2: Run to verify RED**

Run: `flutter test test/unit/balance_calculations_test.dart`
Expected: exactly the two new tests FAIL — p3 owed `0.001` instead of `0.000` (and p2 `0.666` instead of `0.667`). Every pre-existing test stays green. If a pre-existing test fails, STOP — an assumption above is wrong.

**Step 3: Commit RED? No.** Keep the failing tests uncommitted; commit lands with the fix (Task 2) so the tree stays green per commit.

## Task 2: Client GREEN — fix `_allocateWeighted`

**Files:**
- Modify: `lib/features/ledger/providers/expense_provider.dart:754-780` (exact replacement in "The fix" above)

**Step 1:** Apply the Dart replacement.

**Step 2:** Run: `flutter test test/unit/balance_calculations_test.dart` → all green.

**Step 3:** Run the adjacent money suites:
`flutter test test/unit/split_rounding_test.dart test/unit/expense_split_distribution_test.dart test/unit/itemized_split_allocator_test.dart test/unit/delete_group_balance_parity_test.dart test/unit/group_balance_provider_test.dart`
Expected: all green (no behavior change for all-positive weights).

**Step 4: Commit**

```bash
git add lib/features/ledger/providers/expense_provider.dart test/unit/balance_calculations_test.dart
git commit -m "fix(money): weighted-split remainder skips declared-0-share keys (#872)"
```

## Task 3: Server RED — mirrored case in `groupNetBalance.test.ts`

**Files:**
- Modify: `functions/test/callables/groupNetBalance.test.ts` (new `describe('#872 weighted remainder vs 0-share key', ...)` with its own seed — copy the `seedFixture` shape: group, members `alice`/`bob`/`zed`, one event with `participantIds: [alice, bob, zed]`, one expense `amountFils: 1000, currency: 'OMR', payerParticipantId: 'alice', splitMode: 'shares', splitDistribution: {alice: 1, bob: 2, zed: 0}`)

**Step 1: Write the failing test**

Assert on `recomputeNet` output (match the existing tests' access pattern for per-uid net):
- alice net = +667 milli (paid 1000, owes 333)
- bob net = −667 milli
- zed net = 0 (assert `(net for zed ?? 0) == 0`)

**Step 2: Run to verify RED**

Run: `cd functions && npm run test:emulator -- groupNetBalance.test.ts -t "872"`
Expected: FAIL — zed carries −1 milli (owes 0.001), bob −666.

## Task 4: Server GREEN — fix `allocateWeighted`

**Files:**
- Modify: `functions/src/callables/groupNetBalance.ts:163-181` (exact replacement in "The fix" above)

**Step 1:** Apply the TS replacement.

**Step 2:** Run: `cd functions && npm run test:emulator -- groupNetBalance.test.ts` → all green.

**Step 3:** Run the shared-allocator consumers:
`cd functions && npm run test:emulator -- deleteGroup.test.ts` (references `allocateWeighted` behavior in its parity comments).

**Step 4: Commit**

```bash
git add functions/src/callables/groupNetBalance.ts functions/test/callables/groupNetBalance.test.ts
git commit -m "fix(functions): mirror #872 weighted-remainder guard in the server oracle"
```

## Task 5: Whole-tree verification + PR

**Step 1:** `flutter analyze` → clean.
**Step 2:** `flutter test` → full suite green.
**Step 3:** `cd functions && npm run build` (tsc) → clean. Full emulator suite if time permits: `bash tool/run_firebase_emulator_tests.sh`.
**Step 4:** Push branch, open PR:
- Title: `fix(money): weighted-split remainder never lands on a 0-share participant (#872)`
- Body: `Closes #872`, RED evidence (paste the failing-before-fix output from Tasks 1/3), spec pointer to this plan, **pending-deploy note** (server oracle changed ⇒ `tool/pending_deploy.sh` will show drift until the next backend deploy ceremony).
- Route through `/automerge` (Gate-category: `expense_provider.dart` + `functions/**` ⇒ fresh-context diff review + refuter — never raw merge).

**Step 5:** After merge: leave deploy to the `deploy-ceremony` flow; do NOT advance `backend-deployed` by hand.

---

## Gate status

- [ ] Round 1: rubric reviewer + orthogonal adversary (fresh-context, zero session history) — pending
- Implementation MUST NOT start until both verdicts are P1-clean in the same round.

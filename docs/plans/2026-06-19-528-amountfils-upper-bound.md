# #528 — amountFils upper bound (int64 → JS-number divergence above 2^53)

**Date:** 2026-06-19 · **Issue:** #528 · **Class:** Gate-category (MoneySerializer boundary + firestore.rules) → fresh-context Gate MANDATORY before code.

## Problem

`amountFils` (integer subunits persisted to Firestore) has no upper bound at any layer:

- Client: `MoneySerializer.toSubunits` = `(amount * scale).toBigInt().toInt()` (`lib/core/services/money_serializer.dart:25`). Dart native `BigInt.toInt()` wraps to 64-bit signed. The expense editor rejects only `amount <= 0` (`expense_editor_body.dart:269`) — no upper cap.
- Rules: `positiveInt(value) = value is int && value > 0` (`firestore.rules:80-82`). Caps nothing above.
- Server read: the oracle reads `amountFils` as a JS `number` (`groupNetBalance.ts`), and `balanceAggregator.ts` encodes net via `value.times(1000).toNumber()`.

Above `2^53`, a Dart-stored int64 and the JS-`number` read diverge → the deleteGroup/leaveGroup/removeMember byte-for-byte oracle parity breaks, with no guard on either side. Same defense-in-depth class as `splitValuesNonNegative` (#192/#194); the magnitude required (~9 trillion OMR) is physically absurd, so this is a robustness floor, not a live exploit.

## Decision: cap value

Cap at **`amountFils <= 9007199254740991`** (`Number.MAX_SAFE_INTEGER`, `2^53 − 1`) — the conventional JS safe-integer boundary; every integer in `[−2^53+1, 2^53−1]` round-trips exactly through a double.

> Deviation from the issue text, which proposed `< MAX_SAFE_INTEGER`. `<=` is correct: `MAX_SAFE_INTEGER` itself is exactly representable. Off-by-one, harmless either way; pinned by the boundary test.

## Surface (verified against `main`, 2026-06-19)

`positiveInt` has exactly TWO callsites, both `amountFils`:
- `firestore.rules:92` — `validSettlementCore` (event + group settlements).
- `firestore.rules:549` — expense create/update.

So extending `positiveInt` caps expense **and** settlement `amountFils` in one edit, and touches no non-money field (positiveInt is amountFils-exclusive).

Client write paths through `toSubunits` (8 callsites, all OUTBOUND — feed a write): `expense_model.dart:230,355`, `expense_service.dart:187,254,349`, `settlement_service.dart:98` (event settle-up), `group_settlement_service.dart:83` (group settle-up). (`expense_provider.dart:645` is an internal precision round-trip, NOT a write.)

> **[Gate P2-3] The split/weight "transitive ≤-amount bound" does NOT exist — fix the reasoning, then consciously scope these out.** Rules do NOT enforce `sum(splitDistribution) == amountFils` (`firestore.rules:489` `splitValuesNonNegative` is a digits-only regex, no sum/upper check). So a forged/Admin exact-split value CAN exceed 2^53 even with capped `amountFils`. Net divergence is contained NOT by a transitive bound but by: (a) exact-split tolerance-fallback — `allocateExact` re-splits equally when `sum ≠ amount` (`groupNetBalance.ts:218`), discarding an oversized entry; (b) shares/percent `allocateWeighted` renormalizes against the capped `amount` (`:176`), so output ≤ amount regardless of weight magnitude. `shares`/`percent` WEIGHTS (`expense_model.dart:355-357`: percent ×1000, shares raw) are separate integers this cap does NOT touch and stay rules-legal at any positive size — scoped out deliberately, because renormalization makes their magnitude irrelevant to `net`.

> **[Gate P3-2] Settle-up gets rules-only rejection (no friendly guard) — stated decision.** Only the expense editor gets `editorAmountTooLarge`. Event (`settle_up_screen.dart` → `settlement_service.dart:98`) and group (`group_settlement_service.dart:83`) settle-up paths have no client cap; an over-cap settlement surfaces as generic `permission-denied`. Acceptable: a >9-trillion-unit settlement is non-reachable in normal use and there are no field users ("no real users yet → server changes deploy freely"). Not an omission — a decision.

## Fix (three layers)

### 1. Rules — extend `positiveInt`
```
function positiveInt(value) {
  return value is int && value > 0 && value <= 9007199254740991;
}
```
Covers both `amountFils` callsites.

> **[Gate P2-2] Int64-vs-lossy-double evaluation is MOOT at this cap — don't claim the boundary test settles it.** The cap `2^53−1` is the largest exact double; `2^53` is exact and `> cap`, and `2^53+1` rounds to `2^53` (still `> cap`). So NO integer above the cap can alias to `≤ cap` under either exact-int64 or lossy-double comparison — both evaluate identically for all integer inputs. The cap is therefore safe regardless of how the rules engine types the literal, but the accept-`…991`/reject-`…992` test proves the *cap behavior*, not the *precision question* (it passes either way). Keep the test as a behavior/regression pin; drop any claim that it discriminates a lossy engine.

### 2. Client — `MoneySerializer` guard, computed on BigInt BEFORE `.toInt()`
The cap check must run on the `BigInt`, or the very `.toInt()` wraparound it prevents corrupts the check.
```
static const int maxSafeSubunits = 9007199254740991; // Number.MAX_SAFE_INTEGER

/// True if [amount] in [currency] fits the safe-integer subunit range.
/// Computed on BigInt (no toInt()) so an over-cap amount can't wrap mid-check.
static bool fitsSafeSubunits(Decimal amount, String currency) {
  final raw = (amount * Decimal.fromInt(_scale(currency))).toBigInt();
  return raw <= BigInt.from(maxSafeSubunits);
}
```
`expense_editor_body._submit` calls `fitsSafeSubunits` after the `<= 0` check; on false → `_showSnack(context.l10n.editorAmountTooLarge)` and return. (Same pattern as the existing `editorAmountGreaterThanZero` guard.)

> **[Gate P2-1] Use `effectiveCurrency`, NOT `widget.currency`.** The editor denominates money by the `effectiveCurrency` getter (`expense_editor_body.dart:185` = `_isEdit ? widget.currency : _selectedCurrency`); in add-mode after the currency picker, `widget.currency` is stale. All write paths use `effectiveCurrency` (`:324/:538/:688`). The guard MUST be `fitsSafeSubunits(amount, effectiveCurrency)` or it caps against the wrong scale (verified 2026-06-19).

### 3. l10n
New `editorAmountTooLarge` (EN + AR), e.g. EN "Amount is too large." — neutral. Add to `app_en.arb` / `app_ar.arb`, regenerate.

## Verification principles

1. **Callsite classification** — `toSubunits` is OUTBOUND everywhere (no display-only caller). The cap belongs at the write boundary; rules are the backstop for forged/Admin writes.
2. **Read-path per write-path** — `amountFils` is read by `groupNetBalance.ts` (oracle, as JS number), `balanceAggregator.ts` (×1000 → toNumber), and client `fromSubunits`. Capping at `2^53−1` keeps every read inside exact-double range → parity holds. Named answer ✔.
3. **Arithmetic decomposition** — N/A (not changing allocation); the aggregate `netMilli` is server-derived from capped `amountFils`, so it stays bounded (display cache, never OUTBOUND).
4. **Adversarial axis** — fix is on *magnitude*; exercise the orthogonal axis *currency scale*: OMR (×1000) hits the cap at a 1000× smaller major-unit amount than JPY (×1). The boundary test table MUST cover a high-scale currency (OMR/KWD/BHD ×1000) and JPY (×1), since the same major-unit amount yields wildly different `amountFils`.

## TDD

- **RED (rules, emulator):** in `firestore-rules-publish-readiness.test.ts` — expense/settlement create with `amountFils = 9007199254740991` **accepted**; `= 9007199254740992` (2^53) **rejected**. This also empirically settles the literal-precision question (subtlety #1).
- **RED (Dart, table-driven — money code):** `fitsSafeSubunits` clean / at-cap / over-cap across scales (OMR ×1000, USD ×100, JPY ×1); editor `_submit` shows `editorAmountTooLarge` over-cap, persists at/under.
- **GREEN:** implement layers 1–3. Re-run RED → full `flutter test` + scoped emulator run + `flutter analyze`.

## Out of scope
- Aggregate `netMilli` cap (derived from capped `amountFils`; display-only).
- Per-value `splitDistribution` cap (bounded by total; keeps `splitValuesNonNegative`).
- Lower-bound / negative handling (unchanged; `> 0` stays).

## Gate outcome (fresh-context Opus, 2026-06-19) — VERDICT: 0 P1, 3 P2, 2 P3 → ready

No correctness blocker. Cap value, `<=`, BigInt approach, and rules coverage all verified sound. Resolved:
1. **positiveInt is amountFils-exclusive** (`:92`, `:549`); all four amountFils value paths (expense create/update, event+group settlement) route through it; the other 5 mentions are key-lists. **No write path bypasses the cap.**
2. **Literal precision moot** at this cap (P2-2 above) — test is a behavior pin, not a precision discriminator.
3. **`Decimal.toBigInt()` is arbitrary-precision, truncating, non-throwing** — the client BigInt check is exact at all magnitudes; no overflow mid-check.
4. **`<=` correct** (not the issue's `<`, which would reject the valid `2^53−1`).
5. P2/P3 folded above: use `effectiveCurrency` (P2-1); correct precision rationale (P2-2); correct split/weight reasoning + scope-out (P2-3); enumerate `group_settlement_service.dart:83` (P3-1); state settle-up rules-only decision (P3-2).

# Spec — #249: conservation breaks when a split references a departed member

**Issue:** #249 · **Milestone:** 1.0 release readiness · **Date:** 2026-06-04
**Decision (user, 2026-06-04):** *Keep the absent member in the books* — fold former split-recipients into the per-event universe so their owed share is retained with a visible trace; do **not** auto-reassign to the payer, redistribute, or hard-error.
**Gate:** mandatory (money math + participant-set shape, read+write paths). This doc is the artifact the fresh-context Opus reviewers review. **Round 1 (3 reviewers) returned 3 P1s + 3 P2s — all resolved below; see §10 changelog.**

---

## 1. The bug (verified against `origin/main`, 2026-06-04)

`BalanceCalculator.calculateBalances` (`lib/features/ledger/providers/expense_provider.dart:149-297`) keys `paidMap`/`owedMap`/`settlementAdjustmentMap` strictly on the passed `participants` set (`:157-162`, `:261-263`) and emits results by mapping over `participants` (`:281`). The owed fold drops any allocation whose key is not already a participant:

- `:194-198` — `splitDistribution` modes (shares/exact/percent): `if (owedMap.containsKey(entry.key))` — non-participant key silently dropped.
- `:248-256` — scope path (incl. `custom` via `customSplitParticipants`, `:221`): `if (owedMap.containsKey(recipientId))` — same drop.

Meanwhile the payer always records the full amount (`:176-178`). So when a split assigns owed to a UID absent from `participants`, that owed value vanishes while the offsetting paid does not → `sum(netBalance) ≠ 0`, single-currency, today.

**These drop-guards are correct and stay.** They are the backstop against forged / rules-bypassing writes (the #223/#192 surface, deferred). The bug is not in the calculator — it is that the **participant set handed in is incomplete**. A prior attempt that loosened the calculator itself was reverted as over-broad, and it cannot work anyway: results map over `participants` (`:281`), so a key added only to `owedMap` is never emitted.

### Who is recovered today, and who isn't

The authoritative aggregate path **does** re-include former financial actors — but only **payers and settlement parties**, never split *recipients*:

- `lib/features/groups/providers/group_balance_provider.dart:249-264` — `eventFinancialUids = {expense payers} ∪ {settlement payers/recipients}`; `eventLocalFormerActors = eventFinancialUids.difference(liveMemberIds)` (`:258`); `eventParticipantUids = event.participantIds ∪ eventLocalFormerActors` (`:261-264`); fed to `calculateBalances` at `:284`.
- `functions/src/callables/deleteGroup.ts:520-533` — server `recomputeNet` (`:473`) builds the identical set (`financial` = payers + settlement parties), `universe = participantIds ∪ (financial − liveMemberIds)`.

A member who **only ever owed** (split recipient, never paid, never settled) and then left is in neither set → dropped → conservation breaks, and they "vanish from the books with no trace" (the issue's stated harm).

### Why a real user hits this — and the critical caveat the Gate caught

Firestore rules enforce membership **at write time**:
- create: `validExpenseCreate` → `validExpenseBase(data, /*enforceParticipantKeys*/ true)` (`security/firestore.rules:571`) → `validExpenseSplit` requires `splitDistribution.keys().hasOnly(participants())` (`:480`); `customSplitParticipants.hasOnly(participants())` is unconditional (`:556`).
- update: same, gated by `affectsExpenseAllocation()` (`:624`, `:587-599`). `participants()` reads `event.participantIds` (`:471`).

So for a **rules-compliant write**, a split key validates only if it is in `participantIds` at write time; it becomes an orphan only when the member is later removed from `event.participantIds` (events allow participant edits, `:466`). Members are soft-deleted (tombstoned), never hard-removed — so a departed member still has a member doc and is in `allMemberIds`.

**[Gate R1 — P1] BUT a forged / rules-bypassing write can plant a split key that was NEVER a member** (the exact case `deleteGroup.test.ts:480-502` test 12 guards: a `shares` expense with key `ghost` ∉ participantIds, ghost is not a member). If #249 folded *every* split key into the universe unconditionally, it would credit that forged ghost, make `sum(net)==0` for forged data, and **flip test 12 from REJECT→ACCEPT — silently weakening the deleteGroup forged-write gate**. Therefore the new recipient fold is **member-gated** (see §3): only a key that is a *known group member* (live or tombstoned) is folded; a non-member key stays out of the universe so the calculator's drop-guard still fires on it. The existing payer/settlement fold is **left exactly as-is** (not member-gated) — its established behavior is pinned by a test whose former actor is a non-member payer (`group_balance_provider_test.dart` former-PAYER case), and changing it is out of scope.

### Reproduction (issue's, exact-split axis)

10.000 OMR paid by A, `exact` `{A:6.000, GHOST:4.000}` where GHOST is a *tombstoned member* removed from `participantIds`, current participants `{A,B}` → A owed 6.000, GHOST's 4.000 dropped, A paid 10.000 → `sum(netBalance) = +4.000 ≠ 0`.

---

## 2. Decision & rejected alternatives

**Chosen — keep the absent member in the books.** Extend the per-event *former-actor* set to also include **split recipients that are known group members** (`splitDistribution` keys ∪ `customSplitParticipants`, ∩ `allMemberIds`). The departed member becomes a participant → the calculator's drop-guard passes for them → their negative net (they owe) is emitted → `sum(netBalance) == 0` with a visible, named trace.

Rejected: **reassign onto the payer** (misattributes the debt, loses the trace); **redistribute the orphaned share across remaining** (silently rewrites what present members owe); **hard error / assert** (a stale roster would block the ledger from rendering).

**This requires NO change to `BalanceCalculator.calculateBalances`.** It is a fix to participant-set assembly at the call sites. The drop-guards remain as defense-in-depth, and member-gating preserves them against forged writes.

---

## 3. Single source of truth — the per-event balance universe

For one event, given its live `expenses`, live `settlements`, and the group's `liveMemberIds` (members where `!isTombstone`) and `allMemberIds` (every member doc, live OR tombstoned):

```
payersAndSettlers(ev) =
    { e.payerParticipantId                         for e in expenses, non-null }
  ∪ { s.payerParticipantId, s.recipientParticipantId  for s in settlements, non-null }

splitRecipientKeys(ev) =                                                   // NEW
    { keys(e.splitDistribution)  for e in expenses where e.splitMode ∈ {shares,exact,percent} and splitDistribution non-empty }
  ∪ { e.customSplitParticipants  for e in expenses where e.scope == custom and customSplitParticipants non-empty }

formerActors(ev) =
    ( payersAndSettlers(ev) − liveMemberIds )                              // EXISTING — NOT member-gated
  ∪ ( ( splitRecipientKeys(ev) ∩ allMemberIds ) − liveMemberIds )          // NEW — member-gated (§1 P1)

universe(ev) = event.participantIds ∪ formerActors(ev)
```

The `splitRecipientKeys` clause and its `∩ allMemberIds` gate are the **entire behavioural change**. Equal/global/sub_group/personal recipients are always ⊆ participants and introduce no *new* orphan keys — but see §4-bis for the divisor side-effect they DO cause once `universe` grows. Nulls skipped. Sets dedupe (a UID appearing in multiple roles folds once).

**Parity:** the Dart helper and the TS `recomputeNet` change must implement this set **identically** (a divergence makes the `deleteGroup` gate disagree with the client = money-wrong). "Identical" is scoped to *universe construction*; the pre-existing Dart↔TS allocator drift (Dart `_allocateExact` has a negative-guard + in-tolerance residual close-out, TS `allocateExact` does not) is **out of scope (#250)** and is not touched here — see §8.

---

## 4. Fix sites (exact)

### Dart — one shared pure helper, called at every event-level `calculateBalances` site

New pure function (no `ref`), beside `BalanceCalculator` in `lib/features/ledger/providers/expense_provider.dart`:

```dart
/// The balance universe for ONE event: current participantIds plus any FORMER
/// GROUP MEMBER (∈ allMemberIds, ∉ liveMemberIds) appearing in this event's
/// records as a payer, settlement party, OR split recipient (splitDistribution
/// key / customSplitParticipant). The recipient/custom fold is gated to
/// allMemberIds so a forged non-member key stays OUT (the calculator's
/// drop-guard then still fires on it — preserves #223/#192 + deleteGroup test
/// 12). Payer/settlement fold is NOT member-gated (unchanged established
/// behavior; mirrors deleteGroup.ts:520-533).
Set<String> eventBalanceUniverse({
  required Event event,
  required List<Expense> expenses,
  required List<Settlement> settlements,
  required Set<String> allMemberIds,
  required Set<String> liveMemberIds,
});
```

Callers (each builds `Participant`s by mapping the returned UID set through the name resolver it ALREADY uses, so a folded former member renders with a real name — **mandatory, see §5**):

- **A. `group_balance_provider.dart:249-288`** — replace the inline `eventFinancialUids`/`eventLocalFormerActors`/`eventParticipantUids` (`:249-264`) with `eventBalanceUniverse(...)`. `allMemberIds` already exists (`:238`), `liveMemberIds` (`:239-242`). Names already resolve over the expanded set (`resolveGroupScoped` at `:267-282`, and `allUids`/`memberNames`/`memberRawNames` at `:329-352`). **Authoritative aggregate — core fix.**
- **B. `ledger_screen.dart:135-157`** — the LIVE event-ledger per-member balance (`calculateBalances` at `:153`); currently `participants = event.participantIds` only (`:135-148`). It has `groupMembers` (`:128`) → derive `allMemberIds`/`liveMemberIds`; build participants from `eventBalanceUniverse(...)`, resolving each UID via the `resolveEventScoped` it already calls (`:136`). **[Gate R1 — P1: this, not `eventBalancesProvider`, is the live surface.]**
- **C. `settle_up_screen.dart:96-134`** — event settle-up (`calculateBalances` at `:134`); **OUTBOUND** (balances → optimizer → settlement writes). Currently builds `displaysByUid`/`userRawNames` and `participants` from `event.participantIds` only (`:96-120`). Expand ALL THREE to iterate `eventBalanceUniverse(...)` (it watches `groupMembersProvider` at `:93-94`). **[Gate R2 — P2: the name maps are OUTBOUND, a hard precondition, see §5.]**
- **D. `expense_provider.dart` `eventBalancesProvider` (decl `:92`, participants `:113`, calc `:123`)** — currently feeds only `event_command_center.dart:111` (reachability disputed: CLAUDE.md calls `EventCommandCenter` dead-but-kept; memory disputes it). Apply the helper here too so correctness does not depend on resolving that dispute — add a `groupMembersProvider(params.eventRef.groupId)` watch for `allMemberIds`/`liveMemberIds`, build participants from the universe. (If members aren't trivially available, this provider's INBOUND-only status makes it the one acceptable defer — but prefer fixing it.)

`_buildPerEventBreakdown` (`group_balance_provider.dart:402-441`, calc `:429`) **stays `participantIds`-only** — intentional (`:367-369`), pinned by `group_balance_provider_test.dart:628-629`. Do not touch.

### TS — mirror in the server (parity)

- **E. `functions/src/callables/deleteGroup.ts:483-534`** — in the members loop (`:483-490`) build `allMemberIds` (every member doc, regardless of tombstone) alongside the existing `liveMemberIds` (tombstoned docs are read here, only excluded from `liveMemberIds` by the `isTombstone !== true` test at `:487`). Extend the per-event `financial`/`universe` construction (live block is `:517-534`: `financial` `:520-529`, `universe` `:530-533`) with the member-gated split-recipient clause: decode `splitDistribution` keys for non-`equally` modes and `customSplitParticipants` for `custom` scope, fold a key only if `allMemberIds.has(uid) && !liveMemberIds.has(uid)`. Decoders exist (`decodeDistribution`/`decodeSplitMode`, used at `:553-554`; `stringArray` at `:464`). The payer/settlement fold (`:531-533`) is unchanged. **Also update the stale in-code comment at `:518-519`** ("Mirrors group_balance_provider.dart:225-241") to the live `:249-264`. Fold `splitDistribution` keys AND `customSplitParticipants` **symmetrically with the Dart helper** — for a `custom` expense that also carries a distribution the calculator takes the distribution path and ignores `customSplitParticipants` (a no-op for that expense's own allocation), so the extra key only matters for the §4-bis divisor; both engines must fold the same union or the universes diverge.

---

## 4-bis. Accepted side-effect: co-event equal-split divisor (Gate R1 — P1, R1 — P2)

Folding a former member into `universe` (hence into `participants`) also enlarges the divisor for any **equal-split scope expense** (`global`/`sub_group`/`custom`-with-empty-set) in the **same event**, because those paths set `splitRecipients = participants.map(...).toSet()` (`expense_provider.dart:214/224/230`) and `perHead = amount / splitCount` (`:238`). The server mirrors this via `recipients = [...universe]` (`deleteGroup.ts:568-578`). So a global expense logged *after* the member left is re-divided to also charge that former member.

This is **pre-existing, established behavior for former PAYERS** — pinned by the existing former-PAYER test (`group_balance_provider_test.dart`, "event-b split 3 ways" including `uid-former`). #249 extends the same model to former recipients. It is **accepted, not a new bug**:
- `sum(netBalance) == 0` is preserved (the former member absorbs a share; the books still balance).
- It is consistent: a former member who was financially in the event shares that event's costs, whether they appear as payer or recipient.
- The data model has no per-expense membership timestamp; per-event participation is binary. Making recipients behave differently from payers would be an inconsistency, not a fix.

It does NOT contradict §2's rejected "redistribute the *orphaned share* across remaining" — that was about splitting GHOST's *explicit* owed among others; here GHOST keeps their explicit owed and additionally shares co-event equal expenses, exactly as a re-included former payer does. **This side-effect is explicitly in scope and MUST be covered by a test (§7 case 4).** The `splitDistribution` path is unaffected (its `splitRecipients` are the distribution keys, not `participants`, so the divisor doesn't change — confirmed by Gate R3).

---

## 5. Name resolution is OUTBOUND, not optional (Gate R2 — P2)

A folded former member must render with a real name, and at the OUTBOUND settle-up surface the **raw** name (no render-only `(#last4)` #196 suffix) must reach the settlement write map:
- **A (group):** already correct — `computeGroupBalances` resolves all `allUids` and exposes `memberRawNames` (raw, `:350-352`) for writes vs `memberNames` (disambiguated, display).
- **B (ledger display):** INBOUND; `resolveEventScoped` over the expanded set suffices.
- **C (event settle-up, OUTBOUND):** `displaysByUid`/`userRawNames` (`:96-109`) currently cover only `participantIds`. They MUST be rebuilt over `eventBalanceUniverse(...)`; otherwise the optimizer can surface a transfer involving a folded UID with no entry in `userRawNames`, and `_showRecordPaymentSheet` (`:213-225`) would write a settlement with an empty/wrong `payerName`/`recipientName`. Expanding the name maps is a **hard precondition of shipping C**, not an optional nicety. (Settlement *writes* to a non-participant are independently blocked by rules `:654-655`, but the UI/name correctness is on us.)

---

## 6. Callsite classification (principle 1)

| Surface | File:line | Class | In #249? |
|---|---|---|---|
| Group aggregate (live) | `group_balance_provider.dart:284` `computeGroupBalances` | **BOTH** (feeds group settle-up writes) | **YES — core (A)** |
| Group aggregate (one-shot) | `groupBalancesOnceProvider`/`crossGroupBalanceOnceProvider` `:592-670` | INBOUND (home) | YES — same `computeGroupBalances`, free |
| Server recompute | `deleteGroup.ts:473 recomputeNet` | OUTBOUND (delete gate) | **YES — parity (E)** |
| Event ledger display | `ledger_screen.dart:153` | INBOUND | **YES (B)** |
| Event settle-up | `settle_up_screen.dart:134` | **OUTBOUND** | **YES (C)** + name maps |
| Event balances provider | `expense_provider.dart:123` → `event_command_center.dart:111` | INBOUND (disputed reachability) | YES (D) |
| Per-event breakdown | `group_balance_provider.dart:429` | INBOUND drill-down | **NO** — stays `participantIds`-only (`:367-369`; test `:628-629`) |

---

## 7. Arithmetic / worked examples

### 7a. Owed-only conservation (custom scope + settlement — settlements axis, Gate R1 verified clean)
Live `{A,B}`; `C` a **tombstoned member** removed from `participantIds`. E1: 9.000 OMR paid **A**, `scope=custom`, `customSplitParticipants={A,B,C}` → 3.000 each.
- Buggy: `splitRecipientKeys={A,B,C}` not folded → universe `{A,B}` → C's 3.000 dropped → A net +6.000, B −3.000, **sum +3.000 ≠ 0**. ✗
- Fixed: C ∈ `allMemberIds`, ∉ `liveMemberIds` → folded → universe `{A,B,C}` → A +6.000, B −3.000, **C −3.000, sum 0** ✓. Re-add event settlement S1 (C paid A 3.000, written while C was a participant; settlementAdj C +3.000 / A −3.000 per `:266-277`): A `9−3−3=+3`, C `0+3−3=0`, B `−3`, **sum 0** ✓.

### 7b. Forged ghost still rejected (security axis, Gate R3 — the test-12 invariant)
Same as `deleteGroup.test.ts:480-502`: `shares` `{OWNER:1, MEMBER:1, ghost:1}`, ghost **not a member**. `ghost ∈ splitRecipientKeys` but `ghost ∉ allMemberIds` → NOT folded → drop-guard fires → owner net +4000 → **deletion REFUSED** (test 12 stays GREEN). ✓

### 7c. Divisor side-effect (Gate R1 — must test; §4-bis)
Live `{A,B}`, tombstoned `C`. E1: 6.000 `custom {A,B,C}` paid A (2.000 each). E2: 6.000 `global` paid A. Fixed universe `{A,B,C}`: E2 splits 2.000 each → C owes 2.000 of E2 (a global expense logged in an event C was in). Totals: A paid 12.000, owed 4.000 → +8.000; B owed 4.000 → −4.000; C owed 4.000 → −4.000; **sum 0** ✓. Behavior matches former-payer handling; accepted.

### 7d. JPY non-OMR remainder (currency axis, Gate R3 verified clean)
JPY (scale 1). E1: 100 JPY paid A, `custom {A,B,C}`, C tombstoned → perHead 33, remainder 1 → sorted `[A,B,C]`, C absorbs → A 33, B 33, C 34. A paid 100. A +67, B −33, **C −34, sum 0** ✓. C was always in `customSplitParticipants`, so folding C does not change the sorted recipient set or who absorbs the remainder — no money shifts on the `splitDistribution`/`custom` path.

---

## 8. Out of scope (explicit)
- **#223** server-side sum/over-allocation validation — deferred to Post-launch hardening (rules can't fold; decided 2026-06-04).
- **Dart↔TS `allocateExact` drift** (Dart negative-guard + in-tolerance close-out vs TS verbatim) — **#250's territory**; not touched. The §7 client≡server parity assertions use drift-free fixtures by construction.
- **Multi-currency** (#61) — single-currency suffices.
- **Per-event breakdown** former-actor inclusion — intentionally `participantIds`-only.
- **Existing former-PAYER fold semantics** (not member-gated) — unchanged.

---

## 9. Test plan — RED first (money code = table-driven clean/edge/error)

> Helper change: `_makeMember` (`test/unit/group_balance_provider_test.dart:42-55`) has no tombstone flag; add `bool isTombstone = false` so cases 1/2/4 can seed a **tombstoned** member split-recipient (the existing former-PAYER case 3 uses a non-member and is unaffected).

1. **`test/unit/group_balance_provider_test.dart` — PRIMARY (orthogonal to existing former-PAYER test).** NEW: *former split-recipient who is a tombstoned member (owed-only, never payer/settler) is kept in aggregate; `sum(netBalance)==0`.* Mirror §7a owed-only. RED now (dropped), GREEN after. Assert C present with expected negative net; `balances.fold(netBalance)==0`; C **absent** from `perEventBreakdown` (the intentional invariant stays) AND assert the group settle-up suggestion still conserves despite C's empty breakdown — the optimizer reads `balances` (`group_settle_up_screen.dart:112-113`), not the breakdown, so the empty drill-down (`:201-204`) is an accepted cosmetic gap, identical to the existing former-PAYER case.
2. **custom-scope + event-settlement variant** (full §7a incl. S1) — exercises the settlement fold + conservation together.
3. **REGRESSION GUARD:** existing former-PAYER test (non-member payer, asserts `net==20.000`, breakdown excludes it) stays GREEN — proves payer fold is unchanged and the change is additive.
4. **Divisor side-effect (§4-bis / §7c):** mixed event = `custom {A,B,C}` + a `global` expense; assert C is charged a share of the global expense AND `sum(netBalance)==0`. Pins the accepted behavior so it can't silently regress.
5. **Forged-ghost guard (§7b):** NEW Dart unit test — a `splitDistribution`/`custom` key that is NOT a member is **dropped**, net stays non-zero (mirrors test 12 client-side). Locks member-gating.
6. **`functions/test/callables/deleteGroup.test.ts`:** (a) **test 12 stays GREEN** (forged ghost still REFUSED — explicit regression assertion); (b) NEW: a tombstoned-member split-recipient is folded into `recomputeNet`'s universe, net conserves, deletion proceeds. RED now for (b), GREEN after §4-E.
7. **`test/unit/balance_calculations_test.dart` — contract pin:** with a complete universe (`participants` includes the former member), `exact`/`custom` conserves. Documents the calculator is correct; the bug was set-construction. (GREEN by design.)
8. **Event-level surfaces:** widget test that `ledger_screen` (B) shows the folded former member; event settle-up (C) test that the optimizer's suggested transfers conserve AND a folded former member resolves to a real raw name (no `(#last4)` leak into a write).

`flutter analyze` clean; `flutter test` full; `npm --prefix functions test` (Jest, Java 21 + emulator).

---

## 10. Round-1 Gate changelog (3 fresh reviewers)
- **[P1, R3] Forged-ghost re-credit breaks deleteGroup test 12 / #223 backstop** → §3 member-gates the new recipient clause to `allMemberIds`; §7b + §9.6a pin test-12 survival; §1 caveat rewritten (the "always a former member" claim now scoped to compliant writes, with forged writes explicitly excluded by gating).
- **[P1, R2] Spec fixed a dead provider; live event ledger is `ledger_screen.dart:153`** → §4-B retargeted to `ledger_screen.dart:135-157`; `eventBalancesProvider` demoted to §4-D; shared helper applied at all callers (moots the EventCommandCenter dead/alive dispute).
- **[P1, R1] Hidden divisor side-effect on co-event equal-split expenses** → new §4-bis (accepted, consistent with former-payer model, conserves) + §7c worked example + §9.4 mandatory test.
- **[P2, R2] Settle-up name maps are OUTBOUND** → §5 makes name-map expansion a hard precondition of shipping C.
- **[P2, R3] "byte-for-byte parity" overstated** → §3 + §8 scope parity to universe construction; allocator drift is #250.
- **[P2, R1] server divisor parity understated** → §4-bis documents the `[...universe]` transitive divisor change.
- **[P3 ×] line/path citations** → full paths + corrected line numbers throughout.

**Round 2 (2 fresh reviewers) — 0 P1. CLEAR.** Verdicts `0 P1 / 0 P2 / 3 P3` (security/parity) and `0 P1 / 1 P2 / 1 P3` (callers/divisor). Confirmed member-gating sound both sides, test 12 + tests 11/11b + former-PAYER test survive, no forged write newly credited, all 5 callers covered, divisor matches former-payer behavior. Refinements folded in: `_makeMember` `isTombstone` flag (§9), server citation `:517-534` + stale-comment fix (§4-E), Dart/TS custom+distribution symmetry (§4-E), `perEventBreakdown` empty-drill-down accepted as cosmetic gap with a conserves-assertion (§9.1). No blockers remain.

## 11. Branch / merge
Branch `fix/issue-249-conservation` off `main`. Low overlap with in-flight #253/#254 (different regions); rebase after they land. One PR, `Closes #249`. If §4-D (`eventBalancesProvider`) is deferred, `Refs #249` follow-up naming the unmet box.

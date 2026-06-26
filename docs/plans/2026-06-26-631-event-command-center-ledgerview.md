# #631 — EventCommandCenter → ledgerViewProvider (drop the duplicate calculateBalances)

**Date:** 2026-06-26
**Issue:** #631 (perf, money, tech-debt — P3). Sibling of #628 (just merged).
**Gate-category:** YES (money wiring — reroutes the per-event balance pass; touches the money file `expense_provider.dart`).
**Spec line for PR:** Point `EventCommandCenter` at the memoized `ledgerViewProvider` instead of `eventBalancesProvider` + inline `disambiguateEventScoped`/`calculateTotalExpensesByCurrency`; delete the now-dead `eventBalancesProvider`.

---

## Problem (verified against live code)

`_Content.build` (`event_command_center.dart:109-151`) recomputes, **inline in build()**, on every rebuild (any watched stream emit):
- `MemberNameResolver.disambiguateEventScoped(event, members)` — O(participants×members),
- `BalanceCalculator.calculateTotalExpensesByCurrency(expenses)` — O(expenses),
- and reads `eventBalancesProvider`, which runs a **second** full `BalanceCalculator.calculateBalances` pass over the same event streams that `ledgerViewProvider` (the ledger surface) also runs.

So the event's balance math exists **twice** in two non-shared providers. `eventRecapProvider` already reuses `ledgerViewProvider` for exactly this reason (precedent, `event_recap_provider.dart:18`).

`event_command_center.dart:114` is the **only** production consumer of `eventBalancesProvider` (verified: `grep -rn eventBalancesProvider lib/`). The only test reference is `event_command_center_test.dart` (overrides). So `eventBalancesProvider` becomes dead on swap — and it IS the duplicate `calculateBalances` the issue names.

## Latent bug fixed (secondary)
`eventBalancesProvider` is keyed by `({EventRef eventRef, Event event})`, but `Event.==` is **id-only** (`event_model.dart`). So after a same-id participant rename/add, `_Content` rebuilds with a fresh `event`, but the family key compares **equal** → Riverpod serves the cached provider WITHOUT re-running its body with the new `event` param → stale `participantNames` in the participants fed to `calculateBalances`, until expenses/settlements/members re-emit. `ledgerViewProvider` is keyed by `EventRef` alone and watches `eventDetailProvider` **internally**, so it is always fresh. The swap removes this staleness asymmetry (issue calls this out).

---

## The change

### 1. `_Content.build` (`event_command_center.dart`)

Replace:
```dart
final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
final balancesAsync = ref.watch(eventBalancesProvider((eventRef: eventRef, event: event)));
final groupMembers = ref.watch(groupMembersProvider(groupId)).valueOrNull ?? [];

final expenses = expensesAsync.valueOrNull ?? const <Expense>[];
final buckets = balancesAsync.valueOrNull ?? const <String, List<UserBalance>>{};
final participantDisplayNames = MemberNameResolver.disambiguateEventScoped(event: event, members: groupMembers);
final totals = BalanceCalculator.calculateTotalExpensesByCurrency(expenses);
final myLines = nonZeroNetsGccFirst(myNetByCurrency(buckets, currentUid));
```
with:
```dart
final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
final view = ref.watch(ledgerViewProvider(eventRef));
final groupMembers = ref.watch(groupMembersProvider(groupId)).valueOrNull ?? [];

final expenses = expensesAsync.valueOrNull ?? const <Expense>[];
final buckets = view.balances;
final participantDisplayNames = view.rosterDisplayNames;
final totals = view.eventTotal;
final myLines = nonZeroNetsGccFirst(myNetByCurrency(buckets, currentUid));
```

- `expensesAsync` STAYS (drives `_resolveState(hasExpenses:)`, recent rows, "N expenses" count, ledger-strip visibility).
- `groupMembers` STAYS — `_RecentExpensesSection`→`_RecentRow` takes it for the departed-payer `resolveEventScoped` fallback (`event_command_center.dart:846,940-945`). Now only a cheap list read; no inline calc.
- All downstream consumers (`_breakdownFor`, `_RosterStrip`, `_RecentRow`, `_LedgerSummaryStrip`, `_BalanceHero`) are UNCHANGED — they keep receiving `buckets`/`participantDisplayNames`/`totals`/`myLines` with identical types.

### 2. Delete `eventBalancesProvider` (`expense_provider.dart:96-153`)
Pure deletion of the now-dead `Provider.family`. `eventBalanceUniverse` (`expense_provider.dart:179`) STAYS — it is the shared helper `ledgerViewProvider` (and the server oracle's Dart mirror) still use.

### 3. Migrate `event_command_center_test.dart`
The existing tests inject pre-baked balances decoupled from expenses via `eventBalancesProvider(...).overrideWith(AsyncValue.data(buckets))`. Replace with an override of `ledgerViewProvider(eventRef).overrideWithValue(<synthetic LedgerView>)`:
- `balances`: `buckets ?? {currency: balances!}` (same injected value as today),
- `eventTotal`: `BalanceCalculator.calculateTotalExpensesByCurrency(expenses)` (mirrors the real provider + the current inline code — keeps "N expenses"/currency-code assertions faithful),
- `rosterDisplayNames`: `{for (final id in event.participantIds) id: event.participantNames[id]!}` (plain names; matches the prior render intent),
- remaining record fields (`participants`, `expensePayerDisplayNames`, `settlementDisplayNames`, `owedByExpenseId`): empty defaults — the command center never reads them.

Add a `_ledgerView({...})` helper building the full record. `event_command_center_same_name_test.dart` needs **NO** change: it overrides `groupMembersProvider` (not `eventBalancesProvider`) and exercises the REAL name-map path — post-swap it runs the real `ledgerViewProvider` and must still assert `Ahmed (#aaaa)`/`Ahmed (#bbbb)` (a free equivalence guarantee for #289).

### 4. New regression/equivalence test (TDD RED → GREEN)
The old widget tests OVERRODE the balance provider, so they never executed the calculator. Add one widget test that drives the **real** `ledgerViewProvider` (no override) with real `eventExpensesProvider`+`groupMembersProvider` data and asserts the hub renders the correct hero state from the shared pass — proving the swap computes balances end-to-end, not just rewires an injection point. (Define-done test for a behavior-preserving refactor.)

---

## Equivalence proof (the 7 verification principles)

**1. Classify callsites (INBOUND/OUTBOUND/BOTH).** Every rerouted value is **INBOUND / display-only**: `buckets`→hero lines/roster dots/breakdown amounts (render), `participantDisplayNames`→names (render), `totals`→ledger strip (render). None feeds a write path, `recomputeNet`, or the rules. `ledgerViewProvider`'s own doc pins its outputs INBOUND. No OUTBOUND surface touched.

**2. Verify every concrete claim against code.** Done: `eventBalancesProvider` def `expense_provider.dart:96`; sole consumer `event_command_center.dart:114`; `ledgerViewProvider` exposes `balances/eventTotal/rosterDisplayNames` `ledger_view_provider.dart:24-38,208-217`; `calculateOptimalSettlements` name source `expense_provider.dart:926-930`; `UserBalance.displayName` nullable `expense_model.dart:412`.

**3. Trace one read-path per change.** Reads of `buckets`: `myNetByCurrency` (numbers only), `_breakdownFor`→`calculateOptimalSettlements`, `_RosterStrip` dots. Reads of `participantDisplayNames`: `_RosterStrip` name, `_RecentRow._compactPayerName`, `_breakdownFor` userNames. Reads of `totals`: `_LedgerSummaryStrip`. All enumerated above; all unchanged consumers.

**4. Enumerate fields from the type.** `LedgerView` record (7 fields, `ledger_view_provider.dart:24-38`): `participants, balances, eventTotal, rosterDisplayNames, expensePayerDisplayNames, settlementDisplayNames, owedByExpenseId`. Command center reads exactly `balances`, `eventTotal`, `rosterDisplayNames`. Other 4 unused — confirmed by grep of consumers.

**5. Spell out the data contract.**
- `buckets`: `Map<String,List<UserBalance>>`. **Numbers identical** — both providers build participants over the *same* `eventBalanceUniverse(event, expenses, settlements, allMemberIds, liveMemberIds)` (identical args) and call the same `calculateBalances(expenses, settlements, participants)`; `netBalance` is keyed by uid, independent of `Participant.displayName`. The ONLY field that differs is `UserBalance.displayName` (eventBalances: `event.participantNames[id] ?? memberNameByUid[id]`, raw; ledgerView: `format(resolveEventScoped(...))`, former-aware).
- `participantDisplayNames`: identical strings for every LIVE participant (same `resolveEventScoped`, same `liveNameCounts` — former members never count toward #196 collisions, so departed universe members in ledgerView's superset don't change live discriminators). `rosterDisplayNames` is a **superset** (adds departed universe members).
- `totals`: byte-identical (both `calculateTotalExpensesByCurrency(eventExpensesProvider(eventRef))`).

**6. Verify arithmetic decomposition.** N/A — no aggregate is being decomposed. `myNetByCurrency`/dots/breakdown read per-uid `netBalance` directly from the (identical) bucket map.

**7. Adversarial pass on an ORTHOGONAL axis (identity / departed-member).** The fix axis is *provider wiring*; the adversarial axis is *member identity*. Where can output differ?
   - **(a) Departed member in the settle-up breakdown.** `calculateOptimalSettlements` uses `userNames?[uid] ?? balance.displayName`. For a departed member (∈ universe, ∉ participantIds): today `userNames`(=disambiguateEventScoped over participantIds) MISSES them → falls to `balance.displayName` = raw name; after, `userNames`(=rosterDisplayNames over universe) HAS them → former-aware string. **Outcome: departed members render `Name (former member)` instead of raw — a CHANGE, and an improvement (consistent with the roster, which already labels them former).** Live members: byte-identical.
   - **(b) Departed payer in a recent row.** Today `participantDisplayNames[payerId]` misses departed → `_RecentRow` falls to `resolveEventScoped(groupMembers, fallbackName: payerName)`; after, `rosterDisplayNames[payerId]` hits (former-aware) → `compactDisambiguated`. Both yield a former-aware compact name; identical for any departed member who is a tombstoned group member (the realistic case). Differs only for a departed *non-member* payer with no member doc and no `event.participantNames` entry (today: persisted `payerName`; after: "Former member") — an ultra-edge a rules-compliant write can't reach (a payer was a participant at write time).
   - **(c) Same-name LIVE members (#289).** Unchanged — pinned by `event_command_center_same_name_test.dart` running the real path.
   - **(d) Self / empty / mixed-currency states.** Driven by `expensesAsync` + bucket numbers, both unchanged.

**Verdict:** numerically identical; name-identical for all live members; the only output deltas are edge-case *improvements* for departed members (former-member labeling made consistent across hub surfaces) plus the latent same-id-`Event` staleness fix. Net behavior change is strictly an improvement on the same axis the roster already handled.

---

## Risks / mitigations
- **Coverage gate (80%):** deleting `eventBalancesProvider` (~58 lines) removes mostly-overridden (uncovered) code; the real money logic (`eventBalanceUniverse`) stays and is independently tested. New end-to-end test adds real-path coverage. If the gate dips, fall back to keeping `eventBalancesProvider` and only doing the swap (note in PR). Verify with `flutter test` before pushing.
- **Theme purity:** no new `Color(...)`/`.textMuted` — pure provider rewiring. Still run `bash tool/check_theme_purity.sh`.
- **Scope:** swap + delete-its-own-duplicate + test migration = one concern (the issue's stated goal). No bundled cleanup.

## Verification checklist
- [ ] `flutter analyze` clean
- [ ] `bash tool/check_theme_purity.sh` clean
- [ ] `flutter test test/features/events/` green (migrated + same_name + new equivalence test)
- [ ] `flutter test` full suite green (incl. ledger + recap, which share ledgerViewProvider)
- [ ] Gate verdict has no [P1]

# #628 — Ledger `_Body`: hoist filter-independent roster/hero/timeline off the chip-tap path

## Problem (verified against live code, not the issue prose)

A category-chip tap in `LedgerScreen` is `setState(() => _categoryFilter = cat)` on
`_LedgerScreenState` (`ledger_screen.dart:111`). That rebuilds `_Body.build()` in full.
`_Body.build()` re-runs, on **every** tap, a block of derivations that do **not** depend on
`categoryFilter` (`ledger_screen.dart:169–266`):

- `currentPid` (`:169`), `myDisplayName` loop (`:176–185`), `myLines` (`:186`) — `myNetByCurrency` pass.
- `bucketPeopleCount` closure (`:190`), `othersByPid` pivot (`:203–210`).
- `roster` assembly with a per-person `myNetByCurrency` call + `roster.sort` (`:211–241`) — O(C×M²)+O(M log M).
- the hero block: `hasExpenses`, `isSettled`, `singleLine`, `heroKind`, `heroLines`, `rosterState` (`:243–266`).
- `settlementDisplayNames` restoration (`:159–167`) — cheap O(settlements) l10n string pass.

The genuinely **filter-dependent** work (legitimately re-run per tap) is only
`filteredExpenses`/`filteredSettlements` (`:268–277`), the `timeline` merge+sort (`:278–281`),
and `groupTimelineByDay` (`:282–286`).

Note `BalanceCalculator.calculateBalances` and the `resolveEventScoped` name maps are **already**
memoized in `ledgerViewProvider` (that was #106). This issue is the second half of the same
pattern: the *derivation of roster/hero from those memoized balances* was left inline.

Separately, `groupTimelineByDay` allocates a fresh `DateFormat.MMMd(localeName)` on every call
(`ledger_timeline.dart:53`) — a small per-tap allocation independent of the above.

## Scope — one concern: stop re-deriving the filter-independent perspective on a chip tap

### In scope
1. **P2 — Hoist the perspective derivation** into a new memoized derived provider
   `ledgerPerspectiveProvider`, keyed by `({EventRef eventRef, String? currentPid})`:
   - watches `ledgerViewProvider(eventRef)` (memoized balances + `rosterDisplayNames`) and
     `eventExpensesProvider(eventRef)` (for `hasExpenses` only — mirrors how `eventRecapProvider`
     watches it for `expenseCount`; **no change to `LedgerView`'s shape**, so `eventRecapProvider`
     is untouched).
   - computes: `myDisplayName` (raw, nullable), `myLines`, `roster` (with the display-name l10n
     fallback **deferred**), `heroKind`, `heroLines`, `singleLine`, `isSettled`, `rosterState`.
   - **`BuildContext`-free** — the two l10n fallbacks (`ledgerMemberFallback` for a nameless roster
     person, `ledgerYou` for a nameless self) stay deferred to the widget, exactly like the
     existing `LedgerSettlementNames` null-deferral pattern in `ledgerViewProvider`.
2. **P3 — Cache `DateFormat.MMMd` by `localeName`** in `ledger_timeline.dart` (module-level memo
   map) so `groupTimelineByDay` stops allocating a formatter per call.

### Out of scope (declined, documented)
- **Memoizing the unfiltered merged+sorted timeline list.** Marginal: `groupTimelineByDay`
  *must* stay widget-side (it needs `DateTime.now()` + `l10n` — the #106 invariant), and the
  merge+sort is O(N log N) on a small N that is dwarfed by the upstream balance pass. The chip-tap
  timeline regroup is *legitimately* filter-dependent. Declining keeps the PR a single concern;
  noted in the PR body. → #628 still closes (the actionable timeline optimization is the
  `DateFormat` cache; the day-grouping staying widget-side is by design).
- `myNetByCurrency`'s O(C×M²) → O(C×M) pivot is **#630**, a separate Gate-category issue. After
  this hoist the per-person calls run once per data change (not per tap); #630 then reduces the
  cost of that single run. They compose; this PR does not touch `myNetByCurrency`.

## The new provider (faithful relocation — every line moves verbatim)

**Gate-R1 P3 resolved (layering):** the provider returns **only primitives** (Decimal / String /
records / maps) — it does NOT import or reference the widget enums (`LedgerHeroKind`,
`LedgerHeroLine`, `LedgerRosterState`). The widget assembles those trivially-cheap O(1) hero
values from `myLines` + `hasExpenses` + a hoisted per-currency people-count map. This both kills
the provider→widget import smell AND leaves the chip-tap path free of *all* O(C×M) balance work
(the hero enums are pure O(fewLines) map lookups widget-side).

```dart
// ledger_perspective_provider.dart
typedef LedgerPerspectiveRef = ({EventRef eventRef, String? currentPid});

/// One roster entry with the display-name l10n fallback DEFERRED
/// (null displayName ⇒ widget substitutes l10n.ledgerMemberFallback), mirroring
/// [LedgerSettlementNames]. Keeps the provider BuildContext-free.
typedef LedgerRosterEntry = ({
  String participantId,
  String? displayName,
  Decimal signedAmount,
  String? currency,
});

typedef LedgerPerspective = ({
  String? myDisplayName,                              // null ⇒ widget applies ledgerYou
  List<({String currency, Decimal net})> myLines,    // nonZeroNetsGccFirst(myNetByCurrency(...))
  List<LedgerRosterEntry> roster,                    // pivot + sort, fallback deferred
  Map<String, int> peopleCountByCurrency,            // hoisted bucketPeopleCount (others, non-zero)
});
```

Inside the provider (relocated **verbatim** from `_Body.build()` — the expensive balance pivots only):
- `myDisplayName`: loop `data.balances.values` → first `b.participantId == currentPid` → `b.displayName` (break-on-first).
- `myLines = nonZeroNetsGccFirst(myNetByCurrency(data.balances, currentPid))`.
- `peopleCountByCurrency[c] = (data.balances[c] ?? []).where((b) => b.participantId != currentPid && b.netBalance != Decimal.zero).length` for each bucket `c` (== the old `bucketPeopleCount(c)`).
- `othersByPid` pivot (putIfAbsent, first wins) → `roster` (displayName = `rosterDisplayNames[pid] ?? other.displayName`, **nullable**; `signedAmount = -line.net`; one entry per non-zero bucket, else a single `Decimal.zero` entry) → `roster.sort((a,b) => b.signedAmount.abs().compareTo(a.signedAmount.abs()))`.

`_Body.build()` after the hoist (all cheap, no balance pivots):
- compute `currentPid = event.participantIds.contains(currentUserId) ? currentUserId : null` (O(participants)) — stays widget-side; it's the provider key.
- `final p = ref.watch(ledgerPerspectiveProvider((eventRef: eventRef, currentPid: currentPid)));`
- map `p.roster` → `List<LedgerRosterPerson>` applying `displayName ?? other.displayName-already-folded ?? context.l10n.ledgerMemberFallback` (cheap O(roster) — only the l10n fallback remains here).
- assemble hero (O(1)/O(fewLines), no balance loop): `hasExpenses` (from `expenses.isNotEmpty`),
  `isSettled = hasExpenses && p.myLines.isEmpty`, `singleLine = p.myLines.length == 1 ? p.myLines.first : null`,
  `heroKind`, `heroLines = [for l in p.myLines: (currency: l.currency, net: l.net, peopleCount: p.peopleCountByCurrency[l.currency] ?? 0)]`, `rosterState`.
- keep `settlementDisplayNames` restoration (cheap l10n) + `myDisplayName ?? ledgerYou` at render.
- keep the filter-dependent `filteredExpenses`/`filteredSettlements`/`timeline`/`days`.

Note: `hasExpenses` stays widget-side off `_Body.expenses` (`ledger_screen.dart:99`); the provider
need not re-derive it (the hero enums that consume it are widget-side now). The provider's only
freshness inputs are `ledgerViewProvider(eventRef)` (balances + rosterDisplayNames) — it no longer
needs to watch `eventExpensesProvider` at all. Simpler than the original spec.

## Memoization argument (why a chip tap no longer recomputes)
- Key `(eventRef, currentPid)`: `eventRef` constant; `currentPid = event.participantIds.contains(uid) ? uid : null`
  — both `uid` and `event.participantIds` are stable across a chip-tap `setState`. ⇒ key stable.
- Watched deps: `ledgerViewProvider(eventRef)` returns the **same** cached record across chip taps
  (its own key + watched streams are unchanged — #106), and `eventExpensesProvider(eventRef)` is a
  cached `AsyncData`. ⇒ no dep change.
- Stable key + unchanged deps ⇒ Riverpod serves the cached `LedgerPerspective`. Recompute fires
  only on a real data change (balances/expenses re-emit) or a `currentPid` change. ∎

## Verification principles (run now, reported in the PR/commit)

1. **Callsite classification (INBOUND/OUTBOUND/BOTH).** Every value the perspective provider
   produces — `roster.signedAmount`, `myLines`, `heroLines`, `singleLine`, `heroKind`,
   `rosterState` — is consumed **INBOUND only**: rendered into `LedgerHeroStatement` /
   `LedgerRosterStrip`. None feeds a write, `recomputeNet`, or the rules. No OUTBOUND/BOTH callsite.
2. **Every concrete claim verified against code.** `ledgerViewProvider` consumers = exactly
   `ledger_screen.dart:150` + `event_recap_provider.dart:18` (grep). `myNetByCurrency`/
   `nonZeroNetsGccFirst`/`calculateTotalExpensesByCurrency` live in `expense_provider.dart:947–987`.
   `currentUserIdProvider` in `group_balance_provider.dart:528`. Display types
   (`LedgerRosterPerson`, `LedgerHeroLine`, `LedgerHeroKind`, `LedgerRosterState`) confirmed in
   `ledger_roster_strip.dart` / `ledger_hero_block.dart`.
3. **One read-path per write-path.** No write path exists in this change (display-only). The read
   path "who renders these amounts?" → `_Body` slivers (hero, roster strip). Named.
4. **Fields enumerated from the type.** `LedgerView` record fields enumerated from
   `ledger_view_provider.dart:24–38`; the perspective record enumerated above; `LedgerRosterPerson`
   fields from its class (`participantId`, `displayName`, `signedAmount`, `currency?`).
5. **Data contracts spelled out.** Exact record shapes above. Roster fallback contract: provider
   stores `String? displayName` (null ⇒ no resolved name); widget maps `?? ledgerMemberFallback`.
   Settlement contract unchanged (still in widget).
6. **Arithmetic decomposition.** No aggregate is being re-decomposed. Amounts move byte-for-byte:
   the provider runs the **identical** `myNetByCurrency` / `nonZeroNetsGccFirst` calls the widget
   ran, on the **identical** `data.balances` input. `signedAmount = -line.net` preserved verbatim.
7. **Adversarial pass on an orthogonal axis.** The fix is on the *memoization/locality* axis;
   the worked tests exercise the *identity/currency* axis — a departed split-recipient (#249
   universe), a same-name disambiguation surface, and a **multi-currency** roster (two buckets for
   one person → two roster entries) — to prove the relocation preserves per-currency bucketing and
   former-member handling, not just the happy single-currency net.

## Gate
Money-**display** wiring (relocates balance-derived display math; consumes `BalanceCalculator`
output). Not money-*math* and no rules/Functions/routing/schema-write-path — but close enough to
displayed money that the contract's Gate is run before implementation (cheap insurance against a
wrong-balance blind spot: wrong currency bucket, dropped sign, or stale memoization).

## TDD
This is a perf refactor, so "done" = **behavior preserved** + **memoization proven**.

- **Provider behavior (RED→GREEN), `ledger_perspective_provider_test.dart`:** extend the
  `ledger_view_provider_test.dart` container harness. Assert the perspective reproduces the old
  inline results for: single-currency net (`myLines`, `roster` signed amounts), a settled event
  (`isSettled`, `heroKind == settled`, `rosterState == settled`), an empty event
  (`heroKind == empty`, `rosterState == empty`), a **multi-currency** roster (one person → two
  entries, GCC-first), a departed split-recipient in the roster (#249), and the nameless-person
  fallback deferral (`roster` entry `displayName == null`, not the l10n string).
- **Memoization (the actual bug):** read `ledgerPerspectiveProvider(ref)` twice with unchanged
  deps → `identical(p1, p2)` (Riverpod serves cache). And a read with a **different `currentPid`**
  key → a distinct value (proves the key discriminates perspective).
- **Widget parity, `ledger_screen_test.dart`:** the existing roster/hero/same-name tests must stay
  green unchanged (they assert the rendered output) — that is the behavior-preservation proof at
  the screen level. Add: after tapping a category chip, the roster strip + hero still render the
  same people/amounts (filter only changes the timeline).
- `flutter analyze` clean; `bash tool/check_theme_purity.sh` (no new tokens, but run it);
  `flutter test test/features/ledger/` then full suite.

## Files
- `lib/features/ledger/providers/ledger_perspective_provider.dart` (new)
- `lib/features/ledger/screens/ledger_screen.dart` (`_Body.build` reads the provider; cheap residue stays)
- `lib/features/ledger/utils/ledger_timeline.dart` (`DateFormat.MMMd` cache by localeName)
- `test/features/ledger/ledger_perspective_provider_test.dart` (new)
- `test/features/ledger/ledger_screen_test.dart` (add post-filter parity assertion)

## Commit / PR
- `perf(ledger): hoist filter-independent roster/hero off the chip-tap rebuild (Closes #628)`
- PR body: `Closes #628`; note the unfiltered-timeline memo declined-as-marginal; RED→GREEN
  evidence for the memoization test; Gate verdict.

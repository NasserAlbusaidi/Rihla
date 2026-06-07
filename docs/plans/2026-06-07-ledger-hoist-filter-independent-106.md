# Plan — #106 perf(ledger): hoist filter-independent balance/name-map work out of `_Body` rebuild

**Date:** 2026-06-07
**Branch:** `perf/106-ledger-hoist-filter-independent`
**Issue:** #106 (P2, perf, tech-debt). **Gate-category** — touches the `BalanceCalculator` read-path and carries a former-member rendering regression risk. Gate is MANDATORY before code.

## Problem (verified against `main` @ 41f4519)

A category-chip tap is `onCategoryFilter -> setState(() => _categoryFilter = cat)` (`ledger_screen.dart:102`). That re-runs `_LedgerScreenState.build`, which constructs a **new** `_Body` (closures passed → not const-equal), so Flutter cannot skip `_Body.build`. Inside `_Body.build` (`:133-291`) the filter-**independent** work runs unconditionally on every tap and every Firestore snapshot:

- `eventBalanceUniverse` + N× `MemberNameResolver.resolveEventScoped` → `displaysByUid` / `participants` (`:137-164`)
- `disambiguate` + `liveNameCounts` (`:169-170`)
- `BalanceCalculator.calculateBalances` — full `Decimal` pass over all expenses+settlements (`:175-179`)
- `roster` build + sort (`:193-209`)
- `expensePayerDisplayNames` — O(expenses) `resolveEventScoped` (`:248-261`)
- `settlementDisplayNames` — O(settlements) `resolveEventScoped` ×2 (`:262-291`)

Only `filteredExpenses` / `filteredSettlements` / `timeline` / `days` (`:229-247`) actually depend on `_categoryFilter`.

Honestly P2: O(n) in-memory `Decimal` work, discrete low-frequency taps, trip-realistic event sizes. Real CPU/battery waste on snapshot churn; not multi-frame jank at realistic sizes.

## Design

Introduce one derived `Provider.family` that does the filter-independent heavy lifting once, memoized by `EventRef`. `_Body` becomes a `ConsumerWidget`, reads the bundle via `ref.watch`, and keeps **only** the filter pass + cheap l10n-dependent display shaping inline.

### New file: `lib/features/ledger/providers/ledger_view_provider.dart`

```dart
typedef LedgerView = ({
  List<Participant> participants,
  List<UserBalance> balances,
  Decimal eventTotal,
  Map<String, String> rosterDisplayNames,
  Map<String, String> expensePayerDisplayNames,
  // Nullable parts: null ⇒ "unknown party" ⇒ widget applies l10n.ledgerSomeone /
  // ledgerSomeoneLower. Keeps ALL l10n out of the provider (pure, testable).
  Map<String, ({String? payerName, String? recipientName})> settlementDisplayNames,
});

final ledgerViewProvider = Provider.family<LedgerView, EventRef>((ref, eventRef) { ... });
```

The provider **watches**: `eventDetailProvider(eventRef)`, `eventExpensesProvider(eventRef)`, `eventSettlementsProvider(eventRef)`, `groupMembersProvider(eventRef.groupId)`. It reproduces the inline `:137-291` logic **verbatim** (same `eventBalanceUniverse`, same `resolveEventScoped` calls, same `calculateBalances`), differing only in that the two l10n fallbacks are deferred (stored as `null`, not resolved). It degrades exactly like the inline code does today: `valueOrNull ?? <empty>` for each stream; `members` empty → participantIds-only universe (the prior behaviour). Non-`autoDispose`, matching its sibling `eventBalancesProvider` and the `eventExpenses/Settlements` streams it derives from.

**`eventDetailProvider.valueOrNull == null` → return an empty `LedgerView` (defensive).** This branch is **UNREACHABLE during render** and exists only so a provider-level test (or a stray read) can't NPE: `_LedgerScreenState.build` watches the SAME `eventDetailProvider(eventRef)` and builds `_Body` ONLY inside `eventAsync.when(data: (event) { if (event == null) return _NotFoundState; ... })` (`ledger_screen.dart:72-104`). A Riverpod provider has exactly one value per frame, so the provider's `eventDetailProvider.valueOrNull` equals the screen's `event` in any frame where `_Body` (the sole watcher of `ledgerViewProvider`) renders — and `_Body` only renders when that value is non-null. (On invalidate/refresh, `AsyncValue.when`'s default `skipLoadingOnRefresh: true` re-shows the prior `event` via `data:`, still non-null; on a true cold load with no prior value the screen shows `_LoadingState` and `_Body` is not built.) So no transient-null flicker is possible — refutes the "one empty frame" hazard.

### Exact `settlementDisplayNames` contract (no l10n in the provider)

The provider stores, for every settlement id, the value **minus** the l10n fallback — i.e. the original `ledger_screen.dart:266-289` with the `?? l10n…` clauses removed:

```dart
settlement.id: (
  payerName: settlement.payerParticipantId == null
      ? settlement.payerName                       // nullable, VERBATIM persisted — no resolveEventScoped
      : MemberNameResolver.discriminatedLabel(      // ALWAYS non-null (worst case formerMemberLiteral)
          settlement.payerParticipantId!,
          MemberNameResolver.resolveEventScoped(
            uid: settlement.payerParticipantId!, event: event, members: members,
            fallbackName: settlement.payerName),
          liveCounts),
  recipientName: settlement.recipientParticipantId == null
      ? settlement.recipientName
      : MemberNameResolver.discriminatedLabel(/* …recipient, ledgerSomeoneLower side… */),
),
```

`_Body` restores the non-null map the consumers require with this **exact** post-pass (and nothing looser):

```dart
final settlementDisplayNames = <String, ({String payerName, String recipientName})>{
  for (final e in data.settlementDisplayNames.entries)
    e.key: (
      payerName:     e.value.payerName     ?? context.l10n.ledgerSomeone,
      recipientName: e.value.recipientName ?? context.l10n.ledgerSomeoneLower,
    ),
};
```

**Load-bearing invariant:** `MemberNameResolver.resolveEventScoped` NEVER returns null (worst case `MemberDisplay(rawName: formerMemberLiteral)`, `member_name_resolver.dart:66`), and `discriminatedLabel`/`format` never return null. So in the **non-null-participant** branch the stored value is ALWAYS non-null and the widget's `?? l10n` is a guaranteed no-op there — the provider can never substitute a raw `payerName` or `Someone` where the original showed a resolved+discriminated label. The provider stores `null` ONLY in the (participantId == null ∧ persisted name == null) case, which is the EXACT case where the original produced `l10n.ledgerSomeone`. Four-combination equivalence (matches `:266-289` value-for-value):

| `participantId` | persisted name | provider stores | widget post-pass → | original `:266-289` |
|---|---|---|---|---|
| null | null | `null` | `ledgerSomeone` | `ledgerSomeone` ✓ |
| null | `"Sam"` | `"Sam"` | `"Sam"` | `"Sam"` ✓ |
| `u1` (resolvable) | any | `discriminatedLabel(resolveEventScoped(u1,…))` | same (no-op `??`) | same ✓ |
| `u1` (unresolvable) | `"Sam"` | `format(MemberDisplay("Sam", former))` = `"Sam (former member)"` | same (no-op `??`) | same ✓ |

The day card (`ledger_day_card.dart:160-168`) and search sheet (`ledger_search_sheet.dart:523-539`) each carry their own `map[id]?.x ?? settlement.x ?? l10n` tail; in the original that tail is **dead** (the map value is always non-null), and this post-pass keeps it non-null, so the tail stays dead and behaviour is byte-identical. The search `_filter` (`:521-524`) searches BOTH `settlement.payerName` (raw) AND the map value — unchanged, because the map value is unchanged.

**Why key by `EventRef`, not `({EventRef, Event})` (like `eventBalancesProvider`):** `Event.==`/`hashCode` are **id-only** (`event_model.dart:224-229`). A family key carrying `Event` would compare equal after a same-id participant rename/add, so Riverpod would serve a stale cached value built from the OLD `event` — a regression vs. today's inline code, which reads `event` fresh each build. Keying by `EventRef` and watching `eventDetailProvider` *inside* the provider gives BOTH: stable across chip-tap rebuilds (key unchanged → memoized → `calculateBalances` not re-entered) AND fresh on real event changes (the watched stream re-emits → recompute).

### `ledger_screen.dart` changes

- `_LedgerScreenState.build`: stop watching `groupMembersProvider` (now the provider's job); stop passing `groupMembers` to `_Body`. Everything else (event/expenses/settlements/currentUserId extraction + loading/error/not-found guards) unchanged.
- `_Body`: `StatelessWidget` → `ConsumerWidget`; drop the `groupMembers` field. In `build(context, ref)`:
  - `final data = ref.watch(ledgerViewProvider((groupId: groupId, eventId: eventId)));`
  - **Stays inline (cheap, l10n-dependent or filter-dependent):**
    - `currentPid` (`event.participantIds.contains(currentUserId)`)
    - `myBalance = _resolveMyBalance(data.balances, currentPid, l10n.ledgerYou)`
    - `roster` from `data.balances` + `data.rosterDisplayNames` + `l10n.ledgerMemberFallback`
    - `hasExpenses` / `isSettled` / `heroKind` / `rosterState` / `peopleCount`
    - settlement-name l10n post-pass: `data.settlementDisplayNames` → non-null records via `?? l10n.ledgerSomeone` / `?? l10n.ledgerSomeoneLower`
    - the filter pass: `filteredExpenses` / `filteredSettlements` / `timeline` / `days`
  - Consumes `data.participants.length`, `data.expensePayerDisplayNames`, the post-passed `settlementDisplayNames`, `data.eventTotal` in the widget tree (unchanged shapes).
- `_resolveMyBalance` static helper unchanged.

No change to `_CoverHeader`, `LedgerDayCard`, `showLedgerSearchSheet`, `LedgerRosterStrip`, `LedgerCategoryStrip`, or any model. The rendered output is byte-identical.

### Test seam (RED→GREEN for a *perf* refactor)

The output does not change, so a classic wrong-output failing test doesn't apply. The perf property ("a chip tap no longer re-enters `calculateBalances`") needs an invocation counter. Precedent: `BalanceCalculator.onSplitFallback` static hook (#250).

```dart
/// Test-only invocation counter (#106). Proves a category-chip tap no longer
/// re-enters [calculateBalances] (work is memoized in [ledgerViewProvider]).
/// Reset in test setUp; never read in production.
@visibleForTesting
static int debugCalculateBalancesCount = 0;
```

Increment as the first line of `calculateBalances`. Single `int++`, no effect on output, same library so `@visibleForTesting` write is legal.

**Confound control (the counter is global; other callers exist).** `calculateBalances` is also called by `eventBalancesProvider` (`expense_provider.dart:144`) and `computeGroupBalances` (`group_balance_provider.dart:313,458`). Verified the LedgerScreen widget tree contains exactly ONE `calculateBalances` call — the inline `ledger_screen.dart:175` — and NO ledger widget watches `eventBalancesProvider` / `groupBalancesProvider` / `crossGroupBalance` (greped across the screen + every `ledger_*` widget). So a **focused** `LedgerScreen` pump (no home dashboard / no balance-watching widgets) sees only the ledger's own calls. The test additionally **resets `debugCalculateBalancesCount = 0` immediately before the chip tap** and asserts the *delta* across the tap is 0 — so any setup/initial-build calls are irrelevant, and the only thing measured is "did the tap itself re-enter `calculateBalances`." A chip tap is a pure `setState(_categoryFilter)` that invalidates no stream, so nothing else can recompute during that frame. As a structural corroboration, the post-refactor test also attaches a `ProviderObserver` and asserts `ledgerViewProvider` logged **zero** recomputes across the tap.

## Tests (TDD — write first, watch RED on current `main`)

`test/features/ledger/ledger_filter_recompute_test.dart`:

1. **RED→GREEN perf (load-bearing):** pump `LedgerScreen` (FakeFirebaseFirestore-backed via existing ledger harness — focused, no home widgets) on a multi-expense event spanning ≥2 categories. `pumpAndSettle`, then `BalanceCalculator.debugCalculateBalancesCount = 0`, tap a category chip, `pump()`. Assert (a) the count delta is **0**, and (b) filtering visibly changed — a row from the now-unselected category is gone (`findsNothing`) while a row from the selected one remains. On current `main` (a) FAILS (the tap re-enters `calculateBalances`, delta ≥ 1); after the refactor it PASSES. Post-refactor, also assert via a `ProviderObserver` that `ledgerViewProvider` recomputed 0 times across the tap.
2. **Refactor-safety / former-member render:** the event has an expense paid by a **departed** member (tombstoned `GroupMember`, not in `event.participantIds`). Assert the ledger renders that payer with the ` (former member)` suffix both before AND after the refactor (guards the explicit regression risk the issue calls out).

`test/features/ledger/ledger_view_provider_test.dart` (provider-level, post-refactor):

3. Memoization corroboration: two `container.read(ledgerViewProvider(ref))` with unchanged deps return `identical` `.balances` (a Provider.family caches by definition — corroborates test 1, it is NOT the load-bearing chip-tap proof; test 1 is).
4. Former-member payer present in `expensePayerDisplayNames` with ` (former member)`; departed **split-recipient** (member-gated, #249) folded into `balances` (the universe contract holds through the provider).
5. **`settlementDisplayNames` four-combination contract** (pins the exact provider-store, NOT the post-passed value): (a) `payerParticipantId == null ∧ payerName == null` ⇒ stored `payerName` is `null`; (b) `payerParticipantId == null ∧ payerName == "Sam"` ⇒ stored verbatim `"Sam"`; (c) `payerParticipantId == u1` resolvable via `participantNames`/live member ⇒ stored is the **resolved+discriminated label** (NOT the raw `payerName`, even when a `payerName` is also persisted — `payerName` is only a `fallbackName:`); (d) `payerParticipantId == u1` unresolvable + `payerName == "Sam"` ⇒ stored `"Sam (former member)"`.
6. **Resolved-name reaches the UI (P1#1 guard):** a settlement whose `payerParticipantId` is a live same-named member renders the **discriminated** label (`"Ahmed (#…)"`), not the raw `payerName`, through BOTH `LedgerDayCard` and `showLedgerSearchSheet` — proves the widget post-pass didn't fall back to a raw/`Someone` value for a resolvable party.

Existing pumping tests that must stay green (behaviour-preserving): `ledger_screen_overflow_test.dart`, `ledger_screen_same_name_test.dart`, `ledger_back_arrow_rtl_test.dart`, `ledger_day_card_former_member_test.dart`.

## Verification principles (run while writing the spec)

1. **Callsite classification (INBOUND/OUTBOUND/BOTH).** The hoisted values are all **INBOUND (display-only)**: `balances`/`roster`/name-maps/`participants` feed render widgets (hero, roster strip, day cards, search sheet) — none feed a write path. The write paths (add/edit/settle) live on separate screens and read raw names/uids, not these maps. `rosterDisplayNames`/`expensePayerDisplayNames` carry the render-only `(#last4)` discriminator and the ` (former member)` suffix — confirmed INBOUND-only (write paths use `MemberNameResolver.stripDiscriminator`/raw uids elsewhere). Moving them into a derived provider cannot leak a display string into a write.
2. **Every concrete claim vs. code.** Verified: `ledger_screen.dart:102` chip-tap setState; `:175-179` inline `calculateBalances`; `eventBalanceUniverse`/`eventBalancesProvider` at `expense_provider.dart:94-215`; `Event.==` id-only at `event_model.dart:224-229`; `eventDetailProvider` key type == `EventRef`; `event_provider.dart` imports neither `expense_provider` nor `group_provider` (no cycle); l10n keys `ledgerYou/Someone/SomeoneLower/MemberFallback` exist in both ARBs; `LedgerDayCard` wants non-null name-map records (`ledger_day_card.dart:108-110`).
3. **One read-path per write-path.** No write path touched. Read-path: who reads `data.balances` after the move? `myBalance` (hero `You` anchor + settled state), `roster` (per-person chips) — both in `_Body`, both unchanged in logic. Who reads the name maps? `LedgerDayCard` + `showLedgerSearchSheet` — unchanged.
4. **Enumerate fields from the type.** `LedgerView` enumerated against the inline consumers: `participants` (→ count), `balances` (→ myBalance, roster), `eventTotal` (→ trip caption), `rosterDisplayNames` (→ roster), `expensePayerDisplayNames` (→ day card + search), `settlementDisplayNames` (→ day card + search). No inline-computed value that a widget consumes is dropped. `liveCounts`/`displaysByUid` are intermediates consumed only to build the maps above → stay private to the provider.
5. **Spell out the data contract.** `settlementDisplayNames` value is `({String? payerName, String? recipientName})`; `null` ⇔ (participantId == null AND persisted name == null) ⇔ widget substitutes `l10n.ledgerSomeone`/`ledgerSomeoneLower`. Non-null ⇔ resolved-or-persisted string, widget `?? l10n` is a no-op. This reproduces the original branch `payerParticipantId == null ? payerName ?? someone : resolved` exactly.
6. **Arithmetic decomposition.** `calculateBalances` is moved, not altered: same `expenses`, `settlements`, `participants` inputs ⇒ same `List<UserBalance>` (math keyed on participant **id**; `displayName` differences don't affect net/paid/owed). `eventTotal = expenses.fold(+)` is moved verbatim. No aggregate is re-derived from a different slicing.
7. **Adversarial pass on an orthogonal axis.** Fix axis = *when* the work runs (caching). Orthogonal axis = **identity / former-member membership**: the regression risk is that a departed payer or member-gated departed split-recipient (#249 universe) stops rendering with ` (former member)`. Test 2 + Test 4 exercise exactly that — a tombstoned payer and a departed split-recipient must survive the move. Second orthogonal axis = **freshness/staleness**: the `Event.==`-id-only trap (keying by Event) is refuted by keying on `EventRef` + watching `eventDetailProvider`.

## Risks / non-goals

- **Risk:** subtle divergence if the provider's stream snapshot differs from the `expenses`/`settlements` the state passes to `_Body` for the filter pass. Mitigated: both read the same provider instances within one frame (Riverpod intra-frame consistency); they recompute together on a new emission.
- **Risk:** a NEW listener accumulation. The provider is non-`autoDispose` family → one cached `LedgerView` per visited `EventRef`, never freed — identical to the existing `eventExpenses/Settlements` family behaviour. Not the #104 O(G×E) leak (that's the home dashboard pinning group/event leaves; this is a single route-scoped screen). Acceptable; `autoDispose` is a trivial follow-up if the Gate prefers it.
- **Non-goal:** do NOT reuse `eventBalancesProvider` verbatim (issue's ⚠️) — its participant `displayName` is `participantNames[id] ?? memberName`, dropping the former-member-aware `resolveEventScoped`/`format` the ledger needs.
- **Non-goal:** no money-math change, no rules/Functions change, no new global repository.

## Done when

- Filter-independent work hoisted into `ledgerViewProvider`; a chip tap does not re-enter `calculateBalances` (Test 1 green).
- Former-member payer + departed split-recipient still render correctly (Tests 2/4 green).
- `flutter analyze` clean; full ledger test suite + the new tests green; 80% gate holds.
- Gate cleared (no [P1]s) before implementation.

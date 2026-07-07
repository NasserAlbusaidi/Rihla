# #1028 Error/Partial Display Honesty Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Three sibling surfaces still render errored/partial money streams as clean after #997 — the event hub header shows "Nothing to settle yet"/"All settled" (or wrong nets) during a stream-error window, the event settle-up screen silently folds an errored settlements stream into its OUTBOUND basis (and its #773 pre-write revalidation recomputes the same wrong basis), and the hero breakdown sheet ignores `HomeGroupBalance.partial` (hero says "may be incomplete", the sheet it opens says "You're all settled up"). Fix all three plus the one true sibling discovered in scouting: `groupBalancesProvider` silently folds a `groupSettlementsProvider` hard error into the OUTBOUND group basis, invisible to the #244 banner.

**Architecture:** Display-layer honesty fixes only — no allocator, rules, routing, or schema change. Hub: two new `_HubState`s (`unavailable`, `pending`) gated on the #1005 hard-error pattern (`hasError && !hasValue`) across BOTH streams. Settle-up: settlements hard-error joins the existing loud expenses-error branch; the revalidation read gets null-skip parity. Group provider: group-settlements hard error propagates as `AsyncValue.error` (absorbed by already-enumerated watchers). Sheet: `partial` threaded to a per-row caption + the existing incomplete footer, with partial-only kept distinct from unresolved. Zero ARB changes — every string reuses a verified-existing l10n key.

**Tech Stack:** Flutter/Dart, Riverpod 2.x, existing test helpers (`Stream.error` provider overrides — `FakeFirebaseFirestore` never errors streams).

**Issue:** #1028 (`Closes #1028`). Gate category: touches `lib/features/groups/providers/group_balance_provider.dart` (money) — fresh-context Gate review required before implementation.

**Gate outcome (round 1, 2026-07-07):** rubric reviewer 0 P1 / 1 P2 / 3 P3; orthogonal adversary 0 P1 / 0 P2 / 2 P3 — both P1-clean in the same round → PASS. The P2 + actionable P3s are folded into this revision: the hub's transitive members fold via `ledgerViewProvider` added to the members-fail-open follow-up list; the `ledgerViewProvider` out-of-scope justification corrected (recap/trip-receipt/danger-section consumers do NOT error-handle — named in the follow-up); `SkeletonLoader.groupList()` invocation parens in return position; typedef field type `Group` (not `SafarGroup`); pending-skeleton header-scale fit confirmed as a real builder decision, not a copy-paste.

---

## Root cause (one paragraph)

#997 made the home facade honest (`AsyncError` / `partial: true`) and #1024 heals transient denials, but a *surviving* stream error (genuine revocation, or any future terminal error) still reaches these surfaces, and each of them collapses it to "clean": the hub folds both event streams via `valueOrNull ?? const []` and derives its header state from the folded result (`event_command_center.dart:190`, `:197-200`, `:368-377`); `ledgerViewProvider` folds all three source streams (`ledger_view_provider.dart:62-71`) so a settlements-only error yields *wrong nets*, not just false-settled; the event settle-up basis discards an errored settlements stream to `const []` (`settle_up_screen.dart:233-235`) and its pre-write revalidation does the same (`:531-532`) so the #773 cap cannot catch the resulting over-pay; `groupBalancesProvider` folds a group-settlements error to `const []` (`group_balance_provider.dart:197`) where `groupFailedEventIdsProvider` (`:215-232`) structurally cannot flag it; and the breakdown sheet never reads `partial` (`group_balance_breakdown_sheet.dart:74-96`) while `crossGroupHomeBalanceProvider` already ORs it into the hero (`group_balance_provider.dart:1065-1066`).

## Design decisions (with rejected alternatives)

**C1 — hub gates on BOTH streams with the #1005 hard-error pattern (`hasError && !hasValue`), not bare `hasError`.** A settlements-only fresh error makes `ledgerViewProvider` compute nets WITHOUT settlements — wrong money, so gating only expenses is insufficient. `hasError && !hasValue` (home `_GroupRow`, `home_screen.dart:871-880`) keeps a stale-but-valid value rendering after a later error tick — for a passive header, last-known numbers beat "unavailable". Rejected: bare `hasError` (the `LedgerScreen` panel pattern, `ledger_screen.dart:88`) — the panel is the interactive surface with the Reload affordance; the header is passive, and #1005 is the established passive-display pattern. The deliberate divergence (header shows stale numbers while the panel below shows "Couldn't load ledger" + Reload) is documented in a code comment.

**C2 — hub also fixes the loading window (`_HubState.pending`).** Today the first frame(s) after `eventDetailProvider` resolves render "Nothing to settle yet" while the expense stream lags — the same false-clean, one frame wide normally, indefinitely wide under a #997-class wedge. Same `!hasValue` vocabulary; renders a compact skeleton. `unavailable` wins over `pending` when both hold.

**C3 — the collapsed `_CompactAmounts` must be gated too.** With expenses valued and settlements hard-errored, `myLines` is non-empty WRONG nets (C1), and `_EventHeader`'s collapsed row renders them via `if (collapsed && lines.isNotEmpty)` (`event_command_center.dart:462-466`). The gate extends to `state`-awareness: no compact amounts in `unavailable`/`pending`.

**C4 — hub reuses `homeBalanceUnavailable`, no new ARB key.** "Balance unavailable" (`app_en.arb:1317`) fits verbatim; cross-feature key reuse inside this exact file is precedented (`_ErrorState` uses `activityLoadFailedMessage`, `event_command_center.dart:1004`). Rejected: minting `eventBalanceUnavailable` — two ARB files + regenerated localizations for an identical string.

**C5 — settle-up: settlements hard-error joins the loud expenses-error branch; loading gets the skeleton; retry invalidates BOTH providers.** The error view is extracted to a shared helper; its Retry invalidates `eventExpensesProvider` AND `eventSettlementsProvider` (the existing branch invalidates only expenses — a settlements-triggered error could never heal). Stale-valued settlements errors keep rendering (C1 semantics). The `:288-294` comment is updated: the settlements-error arm of the `:295` sheet gate becomes unreachable for `!hasValue` (the gate condition simplifies to `settlementsAsync.hasValue`); the MEMBERS-error fallback (`:306-308`, pinned by `settle_up_screen_test.dart:377-405`) is untouched.

**C6 — `_freshOutstandingForPair` gets null-skip parity.** The #773 pre-write revalidation currently folds an errored/loading settlements read to `const []` (`settle_up_screen.dart:531-532`) — the safety cap recomputes the same wrong basis it exists to guard against. Fix: read `valueOrNull`; `null` (no value at all — loading or hard error) → `return null` (the documented skip-revalidation contract, exactly the expenses leg at `:530`). A legitimately empty settlements list is `[]`, never null — the empty-event case is unaffected. Rejected: blocking the write on a hard-errored read — with C5 the record sheet is unreachable while settlements are hard-errored, so the only residual window is an error tick between sheet-open and write, where skip-and-let-the-sheet-amount-through matches the expenses contract.

**C7 — sibling: `groupBalancesProvider` propagates a group-settlements HARD error as `AsyncValue.error`.** Mirrors the events-leg loudness (`group_balance_provider.dart:148-150`) using the per-event-guard vocabulary (`hasError && !hasValue`, `:178-182`) so stale-valued errors keep serving. Watcher enumeration (all verified in-session 2026-07-07):
- `group_detail_screen.dart:151` — already handles `hasError && !hasValue` (#574 denied-balance bounded retry → surfaced error).
- `group_settle_up_screen.dart:135/:363` — loud `.when` error branch + retry, pinned by `group_settle_up_screen_test.dart:820`.
- `group_settle_up_screen.dart:627` (#719 revalidation), `group_members_section.dart:202`, `group_danger_section.dart:186/:213/:295` — `read(...).valueOrNull` null-safe server-authority fall-throughs (#318/#290/#190: never skip the callable on a null local balance).
- `group_presettle_review_provider.dart:50` — treats `hasError` as settled; fail-open by documented design.
- `group_spending_summary_provider.dart:23` / `group_spending_summary_section.dart:37` — `valueOrNull` fold; an error now renders exactly like loading (both are null). No new lie class.
Rejected: (a) surfacing through the #244 warning-banner channel — `groupFailedEventIdsProvider` is keyed per-event and structurally cannot carry a group-level flag; a new provider is a bigger diff for a softer signal on an OUTBOUND basis. (b) Bare `hasError` — errors the whole in-group balance surface even when stale data exists. (c) A loading guard for group settlements — deliberately NOT added: the provider documents that proceeding on partially-loading inputs prevents a balance-card deadlock (`:187-190`), the loading fold is brief and self-corrects on first snapshot, and tests that don't override `groupSettlementsProvider` would hang.

**C8 — sheet: `partialCount` stays distinct from `unresolvedCount`; only the footer condition unions them.** Routing partial-but-resolved groups into `unresolvedCount` would show `_Loading` — a spinner that never resolves (the facade already returned data). Body selection: `entries.isEmpty` → `unresolvedCount > 0` → `_Loading` (pinned, unchanged); else `partialCount > 0` → footer-only `_RowsList` (itemCount 1: index 0 == entries.length hits the footer branch — pinned by a new test); else `_EmptyBody` ("You're all settled up"). Non-empty entries → `_RowsList` with footer when `unresolvedCount + partialCount > 0`.

**C9 — sheet rows get the per-row caption, and a NEW key.** Footer-only would flag the sheet globally without saying which row is incomplete; the home-row reference (`home_screen.dart:957-974`) is per-row. New `HomeKeys.heroBreakdownRowIncomplete` — NEVER reuse `groupRowBalanceIncomplete`: the sheet overlays the home list, both live in the tree simultaneously, and a shared key breaks `byKey` reads (the documented two-unread-badges trap, `home_keys.dart:54-57`). Strings reuse `homeGroupBalanceIncomplete` ("Incomplete") and `homeBalanceIncompleteNotice` — zero ARB changes across the whole PR.

**Out of scope (follow-ups, do not bundle):**
- Members fail-open on the settle-up bases (`settle_up_screen.dart:213-214`, `group_balance_provider.dart:154-158`, `_freshOutstandingForPair:533-534`) — same shape, but drags the #249 universe semantics and the pinned members-error review-sheet fallback. **Gate R1 rubric [P2]: the hub has the same exposure TRANSITIVELY — `ledgerViewProvider` also folds `groupMembersProvider` (`ledger_view_provider.dart:69-71`), so a members-only hard error still yields wrong hub nets that C1 (expenses+settlements gate) renders as clean. Deferred with the rest of the members class — but the hub is NOT fully honest until the members follow-up lands.** File as a follow-up issue at close-out, listing all four sites.
- `ledgerViewProvider`'s internal folds — the hub gate (C1) stops the header from rendering its wrong nets, and changing the provider's shape touches every ledger consumer. **Gate R1 adversary [P3] correction: its OTHER consumers (`event_recap_provider.dart:19`, `trip_receipt_provider.dart:83`, `event_recap_screen.dart:70`, `event_danger_section.dart:351`) do NOT error-handle the expense/settlement streams — during a stream-error window the recap/receipt surfaces render the same folded wrong nets. Pre-existing, untouched by this PR; named in the follow-up issue so it isn't lost.**
- The hub search sheet fed empty settlements during an error window (`event_command_center.dart:230-235`) — search over empty data yields no results (fail-safe absence, not a money lie).
- The sheet's pre-existing conflation of errored (never-resolving) groups with loading ones in the `_Loading` branch — #997 behavior, pinned, not this PR.

## Verification-principles report (run against code, 2026-07-07)

1. **Callsite classification:** hub header + breakdown sheet are INBOUND (display only). Event settle-up basis is OUTBOUND (feeds `_showRecordPaymentSheet` → `settlementService.addSettlement`, `settle_up_screen.dart:790-806`) — C5/C6 make its error handling *stricter*, never alter computed values on the healthy path. `groupBalancesProvider` is BOTH (group-detail display + group settle-up decompose basis) — C7 only converts a silent-wrong-data state into a loud error; healthy-path data is byte-identical. `computeGroupBalances`, `BalanceCalculator`, and the oracle are untouched.
2. **Concrete claims re-verified in-session:** hub folds `:184-200`, `_resolveState` `:368-377`, `_BalanceBlock` `:548-615`, compact-amounts gate `:462-466`, `_HubState` enum `:359`; `ledgerViewProvider` folds `:62-71`; settle-up fold `:233-235`, sheet gate `:295`, loud branch `:405-431`, revalidation fold `:528-534`; `groupBalancesProvider` events-loud `:148-150`, members fold `:154-158`, per-event guards `:171-182`, settlements fold `:197`, `groupFailedEventIdsProvider` `:215-232`; sheet loop `:74-96`, `_RowsList` `:146-166`, footer `:170-193`; home-row partial caption `home_screen.dart:957-974`; hero partial OR `group_balance_provider.dart:1065-1066`; l10n keys `homeBalanceUnavailable` (`app_en.arb:1317`), `homeBalanceIncompleteNotice` (`:1318`), `homeGroupBalanceIncomplete` (`:1294`), `settleUpCouldNotLoadBalances` (`:799`), `commonRetry` (`:466`).
3. **Read-path per write-path:** no persisted-field change anywhere. The only shape change is the private `_GroupBalanceEntry` record (+`partial`); its sole reader is the sheet's own `_RowsList`/row widget. `groupBalancesProvider`'s new error emission: every watcher enumerated and classified in C7.
4. **Fields enumerated from the type:** `HomeGroupBalance` = `userNet, userPerEventNet, eventCount, partial, fromAggregate` (`group_balance_provider.dart:849-858`) — the sheet reads `userNet` + `partial` only; `fromAggregate` is explicitly display-illegal (doc at `:851`) and stays unread. `_HubState` = `empty, settled, youOwed, youOwe, mixed` (+ new `pending, unavailable`); consumers: `_resolveState`, `_EventHeader.state:394`, `_BalanceBlock:550-586` — all listed in Task 1.
5. **Data contracts spelled out:** exact enum members, exact gate expressions, exact key names (`EventKeys.balanceHeaderUnavailable`, `EventKeys.balanceHeaderPending`, `HomeKeys.heroBreakdownRowIncomplete`), exact l10n keys, exact `_RowsList` param rename (`unresolvedCount` → `incompleteCount`) — in the tasks below.
6. **Arithmetic decomposition:** no number is computed differently anywhere. The fixes only change *which already-computed state renders*. The oracle/`recomputeNet` parity surface is untouched; `partial` remains `failedEventIds.isNotEmpty || groupSettlementsFailed` (`:891`), unchanged.
7. **Orthogonal-axis adversarial pass (self-run):** money-flow axis exposed the wrong-nets-under-settlements-error hazard (→ C1 both-streams gate, C3 compact-amounts gate); time axis exposed the loading-window false-empty (→ C2) and the sheet's spinner-forever hazard (→ C8); identity axis confirmed uid plays no role in any gate; scope axis bounded C7 to hard-error-only with the watcher enumeration and kept members fail-open out. The Gate's fresh reviewers take the next pass.

---

# Task 1: Hub header honest states (fix 1)

**Files:**
- Modify: `lib/features/events/screens/event_command_center.dart` (`:359` enum, `:197-200` state resolution, `:462-466` compact-amounts gate, `:577` `_BalanceBlock` if-chain)
- Modify: `lib/features/events/keys/event_keys.dart` (2 new keys)
- Create: `test/features/events/event_hub_balance_error_states_test.dart`

**Step 1: Write the failing tests.** New file; copy the provider-override harness from `test/features/events/event_command_center_test.dart`'s `_wrap` helper (override `eventDetailProvider`, `eventExpensesProvider`, `eventSettlementsProvider`, `groupMembersProvider`, `sharedPreferencesProvider`), and the bounded-pump idiom from `test/features/home/home_group_row_balance_states_997_test.dart` (`await tester.pump(const Duration(milliseconds: 16))` ×6 — NEVER `pumpAndSettle` while a skeleton/`Stream.empty` is live). Cases:

1. `'expenses stream error → Balance unavailable, never Nothing to settle yet'` — expenses `Stream.error(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'))`, settlements `Stream.value(const [])`. Expect: `find.byKey(EventKeys.balanceHeaderUnavailable)` findsOneWidget; `find.text('Nothing to settle yet')` findsNothing; `find.text('All settled')` findsNothing.
2. `'settlements stream error with valued expenses → unavailable, wrong nets suppressed'` — expenses `Stream.value([expense OMR 5.000 paid by other, split with me])`, settlements `Stream.error(...)`. Expect: `balanceHeaderUnavailable` findsOneWidget; NO `RAmount` inside the header (the wrong 5.000-derived net must not render); `find.byKey(EventKeys.balanceHeader)` still present.
3. `'streams never emit → pending skeleton, never Nothing to settle yet'` — both streams `Stream<...>.empty()` (a broadcast stream that never emits keeps `isLoading`). Expect after bounded pumps: `find.byKey(EventKeys.balanceHeaderPending)` findsOneWidget; `find.text('Nothing to settle yet')` findsNothing.
4. `'healthy streams unchanged'` — both valued, no net → `find.text('All settled')` findsOneWidget (guards the enum insertion against off-by-one regressions).

**Step 2: Run to verify RED.** `flutter test test/features/events/event_hub_balance_error_states_test.dart` — cases 1–3 FAIL (compile error on the missing keys counts as RED for a new key; after adding keys only, they fail on findsNothing).

**Step 3: Implement.**

`event_keys.dart` (next to `balanceHeader`):
```dart
  /// #1028: hub balance header when a source stream is hard-errored.
  static const balanceHeaderUnavailable = Key('event_balance_header_unavailable');

  /// #1028: hub balance header while a source stream has no first value.
  static const balanceHeaderPending = Key('event_balance_header_pending');
```

Enum (`:359`): `enum _HubState { empty, settled, youOwed, youOwe, mixed, pending, unavailable }`

State resolution (replace `:197-200`):
```dart
    // #1028: a hard-errored source stream means view.balances was computed
    // WITHOUT that stream's folds — wrong nets, not just false-settled. Gate
    // BOTH streams with the #1005 hard-error pattern (hasError && !hasValue:
    // a stale-but-valid value keeps rendering; the ledger panel below owns
    // the loud Reload affordance). Same !hasValue vocabulary for the
    // first-value window, which otherwise renders a false "Nothing to
    // settle yet".
    final balanceUnavailable =
        (expensesAsync.hasError && !expensesAsync.hasValue) ||
        (settlementsAsync.hasError && !settlementsAsync.hasValue);
    final balancePending = !balanceUnavailable &&
        ((expensesAsync.isLoading && !expensesAsync.hasValue) ||
            (settlementsAsync.isLoading && !settlementsAsync.hasValue));
    final state = balanceUnavailable
        ? _HubState.unavailable
        : balancePending
        ? _HubState.pending
        : _resolveState(hasExpenses: expenses.isNotEmpty, lines: myLines);
```

Compact-amounts gate (`:462`):
```dart
              if (collapsed &&
                  lines.isNotEmpty &&
                  state != _HubState.unavailable &&
                  state != _HubState.pending)
```
(`_EventHeader` already holds `state`; verify the field is reachable at that expression, else thread it.)

`_BalanceBlock` if-chain — insert BEFORE the `empty || settled` branch (order is load-bearing: `unavailable` with empty lines would otherwise fall to the lines `else` and render an empty column):
```dart
        if (state == _HubState.unavailable)
          Row(
            key: EventKeys.balanceHeaderUnavailable,
            children: [
              Icon(Iconsax.warning_2, size: 16, color: colors.warning),
              SizedBox(width: context.spacing.space8),
              Text(
                context.l10n.homeBalanceUnavailable,
                style: AppTypography.displayOf(
                  context,
                  fontSize: 20,
                  color: colors.textSecondary,
                  height: 1.05,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          )
        else if (state == _HubState.pending)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: KeyedSubtree(
              key: EventKeys.balanceHeaderPending,
              child: SkeletonLoader.trailingBalance(),
            ),
          )
        else if (state == _HubState.empty || state == _HubState.settled)
```
(Use the existing `SkeletonLoader.trailingBalance()` — verify its exact constructor at `lib/shared/widgets/skeleton_loader.dart:317`; if it is sized for a list-row trailing slot and looks wrong at header scale, substitute the file's nearest header-scale skeleton idiom, keeping the key.)

**Step 4: Run to verify GREEN.** Same file → all PASS. Then `flutter test test/features/events/` (the existing hub tests pin the healthy-path states — must stay green untouched).

**Step 5: Commit.** `fix(events): hub balance header renders unavailable/pending instead of false-clean (Refs #1028)`

# Task 2: Settle-up settlements-error basis (fix 2, event screen)

**Files:**
- Modify: `lib/features/ledger/screens/settle_up_screen.dart` (`:231-235`, `:288-309`, `:404-431`, `:528-534`)
- Modify: `test/features/ledger/settle_up_review_suppression_test.dart:267-289` (re-scope — it pins the bug)
- Modify: `test/features/ledger/settle_up_screen_test.dart` (new cases; helper already injects `settlementsStream`)

**Step 1: Re-scope the pinned-bug test + write the failing tests.**
- `settle_up_review_suppression_test.dart:267-289` (`'settlement stream errors fail open against empty settlements'`): rewrite to expect the LOUD path — settlements `Stream.error` → `find.text("Couldn't load balances.")` findsOneWidget, review sheet findsNothing, no settle tiles. Rename to `'settlement stream hard error → loud error view, basis never computed (#1028)'`.
- `settle_up_screen_test.dart`, new cases:
  1. `'settlements hard error → Couldn't load balances + Retry invalidates both streams'` — settlements `Stream.error(...)`: error view present; tap Retry; assert both providers were invalidated (drive scripted overrides that emit data on second subscription → screen recovers to the data branch).
  2. `'settlements loading with valued expenses → skeleton, not a zero-fold basis'` — settlements `Stream.empty()`: `SkeletonLoader` present, no settle tiles, no review sheet.

**Step 2: Run to verify RED.** `flutter test test/features/ledger/settle_up_review_suppression_test.dart test/features/ledger/settle_up_screen_test.dart` — re-scoped + new cases FAIL (data branch renders today).

**Step 3: Implement.**
- Extract the `:406-431` error Column into a private helper `Widget _balancesErrorView(BuildContext context)` whose Retry runs BOTH `ref.invalidate(eventExpensesProvider(eventRef))` and `ref.invalidate(eventSettlementsProvider(eventRef))`; the `expensesAsync.when(error:)` branch delegates to it.
- Top of the `data:` branch (before `:233`):
```dart
          // #1028: a hard-errored settlements stream must not fold to [] —
          // the basis is OUTBOUND (feeds the settlement write) and empty
          // folds resurrect settled debts as over-pay suggestions. Stale-
          // valued errors keep rendering (#1005 hard-error pattern); the
          // first-value window gets the same skeleton as expenses loading.
          if (settlementsAsync.hasError && !settlementsAsync.hasValue) {
            return _balancesErrorView(context);
          }
          if (settlementsAsync.isLoading && !settlementsAsync.hasValue) {
            return SkeletonLoader.groupList();
          }
          final settlements = settlementsAsync.valueOrNull ?? const [];
```
  (verify `SkeletonLoader.groupList`'s exact form at the existing `loading:` branch `:405` and reuse identically.)
- Sheet gate `:295`: `if (settlementsAsync.hasValue) {` — and update the `:288-294` comment: settlements-error is now loud before this point; only the MEMBERS-error fallback (`:306-308`) remains fail-open.
- `_freshOutstandingForPair` (`:531-532`):
```dart
    final settlements =
        ref.read(eventSettlementsProvider(eventRef)).valueOrNull;
    if (event == null || expenses == null || settlements == null) return null;
```
  (fold the null-check into the existing `:530` line; a hard-errored or first-value-less read now SKIPS revalidation — the expenses contract — instead of capping against a basis missing every settlement.)

**Step 4: Run to verify GREEN.** Both files → PASS. Then `flutter test test/features/ledger/` (currency/revalidation/same-name suites must stay green — none inject settlement errors).

**Step 5: Commit.** `fix(ledger): settle-up basis goes loud on settlements hard error instead of folding to empty (Refs #1028)`

# Task 3: Sibling — groupBalancesProvider group-settlements hard error propagates (fix 2, group basis)

**Files:**
- Modify: `lib/features/groups/providers/group_balance_provider.dart` (Step-3 region, `:161` + `:197`)
- Modify: `test/unit/group_balance_provider_test.dart` (new test — NO existing test injects a `groupSettlementsProvider` error; the fold is unpinned)

**Step 1: Write the failing test.** `'group-settlements hard error → groupBalancesProvider errors, never a silently-short basis (#1028)'`: container with events/members/per-event streams valued, `groupSettlementsProvider(gid)` overridden with `Stream.error(FirebaseException(... 'permission-denied'))` → `groupBalancesProvider(gid)` ends in `AsyncError`, not `AsyncData`. Sibling assertion: with `groupSettlementsProvider` emitting data normally, result is byte-identical `AsyncData` (healthy path pinned).

**Step 2: Run to verify RED.** `flutter test test/unit/group_balance_provider_test.dart` — FAILS (emits data with the settlements fold dropped today).

**Step 3: Implement.** After the Step-3 watch (`:161`):
```dart
  final groupSettlementsAsync = ref.watch(groupSettlementsProvider(groupId));
  // #1028: this basis is OUTBOUND (group settle-up decompose). A hard-errored
  // group-settlements stream must be LOUD — folding to [] resurrects cross-
  // event settled debts, and groupFailedEventIdsProvider is per-event keyed
  // so the #244 banner structurally cannot flag it. Stale-valued errors keep
  // serving (per-event-guard vocabulary); loading keeps the documented
  // proceed-on-partial behavior (deadlock note below).
  if (groupSettlementsAsync.hasError && !groupSettlementsAsync.hasValue) {
    return AsyncValue.error(
      groupSettlementsAsync.error!,
      groupSettlementsAsync.stackTrace!,
    );
  }
```
No other line changes (`:197`'s `valueOrNull ?? const []` is now reachable only with a value or stale value).

**Step 4: Run to verify GREEN + watcher suites.** `flutter test test/unit/group_balance_provider_test.dart test/features/groups/` — the group-settle-up loud branch (`group_settle_up_screen_test.dart:820`) and #574 detail-screen tests must stay green (they already handle balance errors). Also `flutter test test/unit/home_balance_partial_244_test.dart` (once-path is a separate code path — must be untouched).

**Step 5: Commit.** `fix(groups): group balance basis goes loud on group-settlements hard error (Refs #1028)`

# Task 4: Breakdown sheet partial honesty (fix 3)

**Files:**
- Modify: `lib/features/home/widgets/group_balance_breakdown_sheet.dart` (loop `:74-96`, `_GroupBalanceEntry` `:18-21`, `_RowsList` `:146-166`, row widget, doc comments `:70-72`/`:140-143`)
- Modify: `lib/features/home/keys/home_keys.dart` (1 new key; widen the `:72-74` comment)
- Modify: `test/features/home/group_balance_breakdown_sheet_997_test.dart` (new cases)

**Step 1: Write the failing tests** (override shape from `home_group_row_balance_states_997_test.dart` — `AsyncData((userNet: ..., userPerEventNet: ..., eventCount: ..., partial: true, fromAggregate: false))`):
1. `'partial group with non-zero net → row + per-row Incomplete caption + footer'` — expect the group's row, `find.byKey(HomeKeys.heroBreakdownRowIncomplete)` findsOneWidget, `find.byKey(HomeKeys.heroBreakdownIncompleteNotice)` findsOneWidget.
2. `'partial group with zero net → footer-only, never all-settled, never a spinner'` — one group, `partial: true`, empty `userNet`: `find.text("You're all settled up")` findsNothing; `find.byType(CircularProgressIndicator)` findsNothing; footer findsOneWidget (pins the `itemCount: 1` empty-entries `_RowsList`).
3. `'partial:false byte-identical'` — non-zero-net `partial: false` group: row present, NO caption, NO footer (guards against a leaky flag).

**Step 2: Run to verify RED.** `flutter test test/features/home/group_balance_breakdown_sheet_997_test.dart` — cases 1–2 FAIL.

**Step 3: Implement.**
- `home_keys.dart`: `static const heroBreakdownRowIncomplete = Key('home_hero_breakdown_row_incomplete');` — comment why it is distinct from `groupRowBalanceIncomplete` (sheet overlays the home list; shared keys break `byKey`). Widen the `heroBreakdownIncompleteNotice` comment from "loading/errored" to "loading/errored/partial".
- Typedef: `typedef _GroupBalanceEntry = ({Group group, List<...> lines, bool partial});` (match the existing field types at `:18-21` exactly — the model class is `Group`, `group_model.dart:11`).
- Loop: track `var partialCount = 0;` after the unresolved `continue`:
```dart
        final balance = balanceAsync.valueOrNull;
        final partial = balance?.partial ?? false;
        if (partial) partialCount++;
        final userNet = balance?.userNet ?? const <String, Decimal>{};
        final lines = nonZeroNetsGccFirst(userNet);
        if (lines.isNotEmpty) {
          entries.add((group: group, lines: lines, partial: partial));
        }
```
- Body selection (C8):
```dart
      body = entries.isEmpty
          ? (unresolvedCount > 0
                ? const _Loading()
                : partialCount > 0
                ? _RowsList(
                    entries: const [],
                    onTapGroup: (groupId) => _openSettleUp(context, groupId),
                    incompleteCount: partialCount,
                  )
                : _EmptyBody(text: context.l10n.heroBreakdownEmpty))
          : _RowsList(
              entries: entries,
              onTapGroup: (groupId) => _openSettleUp(context, groupId),
              incompleteCount: unresolvedCount + partialCount,
            );
```
- `_RowsList`: rename `unresolvedCount` → `incompleteCount` (footer condition `incompleteCount > 0`, unchanged mechanics).
- Row widget: when `entry.partial`, append under the amounts the compact caption (mirror `home_screen.dart:957-974`): `Row(key: HomeKeys.heroBreakdownRowIncomplete, ...)` with `Icon(Iconsax.warning_2, size: 11, color: colors.warning)` + `Text(context.l10n.homeGroupBalanceIncomplete, ... fontSize: 10, color: colors.textSecondary)`.
- Update the `:70-72` loop comment: unresolved (loading/errored) counts AND resolved-but-partial counts both feed the footer; only unresolved may show `_Loading`.

**Step 4: Run to verify GREEN.** File + `flutter test test/features/home/` (`hero_breakdown_navigation_test.dart` pins partial:false behavior — exactly-2-RAmounts, no-row-for-settled, empty state — must stay green untouched).

**Step 5: Commit.** `fix(home): breakdown sheet surfaces partial balances instead of settled-silence (Refs #1028)`

# Task 5: Full verification, PR, close-out

- `flutter analyze` → clean.
- `bash tool/check_theme_purity.sh` → clean (new widget code in 3 lib files — the #615 trap; all colors via `context.colors`, no `.textMuted`).
- `flutter test` full suite → green.
- Branch `fix/1028-error-partial-display-honesty` from `origin/main`; PR body: `Closes #1028` + `Spec: docs/plans/2026-07-07-1028-error-partial-display-honesty.md` + RED evidence pasted per task + the C7 watcher-enumeration table + note that the group-basis sibling (Task 3) extends acceptance box 2 to the group screen (same bug class, discovered in scouting).
- `/automerge <N>` (Gate-category: `group_balance_provider.dart` → fresh review + refuter).
- After merge: file the members-fail-open follow-up issue (out-of-scope note above); comment on #1028 is unnecessary (auto-closes via squash body — verify `Closes #1028` survives in the squash commit message).

## Test matrix (what proves what)

| Concern | Test | State |
|---|---|---|
| Hub error → unavailable, wrong nets suppressed | `event_hub_balance_error_states_test.dart` 1–2 | new, RED-first |
| Hub loading → pending, no false-empty | same, case 3 | new, RED-first |
| Hub healthy path unchanged | same case 4 + existing `event_command_center_test.dart` | new + existing green |
| Settle-up loud on settlements hard error | re-scoped `settle_up_review_suppression_test.dart:267` | re-scoped (pinned the bug) |
| Retry heals both streams; loading → skeleton | `settle_up_screen_test.dart` new cases | new, RED-first |
| Members-error fallback untouched | `settle_up_screen_test.dart:377-405` | existing, must stay green |
| Revalidation skips on valueless settlements | `settle_up_revalidation_test.dart` | existing green (no error case existed; behavior change is error-fold → skip) |
| Group basis loud on group-settlements error | `group_balance_provider_test.dart` new | new, RED-first (fold was unpinned) |
| Group settle-up absorbs the error | `group_settle_up_screen_test.dart:820` | existing, must stay green |
| Once-path unaffected | `home_balance_partial_244_test.dart` | existing, must stay green |
| Sheet partial row + footer / footer-only / partial:false identical | `group_balance_breakdown_sheet_997_test.dart` new trio | new, RED-first |
| Sheet loading/error behavior unchanged | existing `group_balance_breakdown_sheet_997_test.dart` + `hero_breakdown_navigation_test.dart` | existing, must stay green |

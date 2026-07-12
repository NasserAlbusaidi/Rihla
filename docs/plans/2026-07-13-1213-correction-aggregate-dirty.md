# Spec B — #1213: settlement corrections must mark the balance aggregate stale

Issue: #1213 (P2, money/display). Branch: `fix/1213-correction-aggregate-dirty`. Commit body: `Closes #1213`.
Spec ships in PR as `docs/plans/2026-07-13-1213-correction-aggregate-dirty.md`. Client-only change.

## Problem (verified 2026-07-13 against main @2ce0891c)

`ConnectivityNotifier.noteLocalWrite(groupId:)` (`lib/core/providers/connectivity_provider.dart:242-248`)
is the only client path into `balanceAggregateFreshnessProvider.markGroupDirty` (besides
`join_group_screen.dart:163`), and it marks the aggregate dirty UNCONDITIONALLY (connectivity state only
changes when offline). The home facade (`lib/features/groups/providers/group_balance_provider.dart:1046-
1049`) serves the aggregate doc directly whenever `online && !aggregateMayBeStale` — the once-path that
`ledgerRevisionProvider` refreshes is not even watched on that branch.

The settlement RECORD path calls it (`lib/features/ledger/screens/settle_up_screen.dart:897`). The three
CORRECTION paths do not:

1. `_correctSettlement` (event scope) — `settle_up_screen.dart:961-1016`: bumps ledgerRevision only
   (982-984).
2. `_correctLogicalSettleUp` — `lib/features/groups/screens/group_settle_up_screen.dart` (method body
   ~1097-1156): bumps only (1119-1121).
3. `_correctSettlement` (group scope) — `group_settle_up_screen.dart:1165-1213`: neither (its doc comment
   1158-1164 correctly explains why no ledgerRevision bump — group settlements are live-watched by the
   once-path — but that reasoning does NOT cover the aggregate-doc branch).

Result: after a correction callable succeeds, home serves the pre-correction aggregate until the async
`balanceAggregator` trigger rewrites the doc — indefinitely if the trigger errors. The in-group screens
(live streams) already show the reopened debt: home and group disagree about money.

## Fix

Mirror the record path in all three correction methods: after the callable resolves successfully, call
`connectivityNotifier.noteLocalWrite(groupId: widget.groupId);`

Placement and capture rules:
- Capture the notifier BEFORE the `await` (the established #104/#412 idiom — `_correctSettlement` event
  scope and `_correctLogicalSettleUp` already capture `ledgerRevisionNotifier` pre-await; capture
  `ref.read(connectivityProvider.notifier)` alongside it). Group-scope `_correctSettlement` currently
  captures nothing pre-await — it gains ONLY the connectivity-notifier capture (no ledgerRevision capture;
  see non-goals). Do not guard the call on `context.mounted` — the captured-notifier effect must survive
  disposal, same as the record path.
- Call it on the SUCCESS path only (after the `await` returns without throwing), before the snackbar. A
  thrown callable wrote nothing — the aggregate is not stale.
- Site 1: place it next to the existing `shouldBumpLedgerRevision` block (unconditional, not inside the
  `if` — the aggregate is stale regardless of whether event-scope docs landed).
- Site 2: same — unconditional on success, independent of `shouldBumpLedgerRevision`.
- Site 3: add the call; UPDATE the 1158-1164 doc comment to say: no ledgerRevision bump (once-path
  live-watches group settlements) BUT the aggregate must be marked dirty (the online facade branch never
  consults the once-path, `group_balance_provider.dart:1046-1049`).

## Non-goals

- NO ledgerRevision bump added to group-scope `_correctSettlement` (the #104/#233 once-path already
  live-watches `groupSettlementsProvider`; adding a bump is dead weight).
- NO change to the facade, freshness provider, `noteLocalWrite` itself, or the record path.
- NO server change (the balanceAggregator trigger is correct; this is purely the client-side staleness
  bridge).
- NO `noteQueuedWrite` — corrections are ONLINE-ONLY callables (#1129); nothing ever queues.
- NO offline pre-flight gate added to the correction methods (the record path's pre-flight is a UX
  nicety; correction failure copy already covers the offline case — out of scope here).

## Tests (RED first — widget tests)

Line numbers in this spec are landmarks, not gospel — Gate round-2 measured drift of ~10 lines on
several citations (record path ~:905, event correction ~:972-1027, bump ~:993-995); locate by symbol.

**Harness trap (Gate round-1 P1, both reviewers — do NOT copy the existing override blindly):** the
existing settle-up tests override `connectivityProvider` with a BARE
`ConnectivityNotifier(startPeriodicChecks: false)` (`test/features/ledger/settle_up_screen_test.dart`
and `test/features/groups/group_settle_up_screen_test.dart` — no `screens/` segment in test paths). That constructor leaves `_markBalanceAggregateMayBeStale`
null (`connectivity_provider.dart:89-99`), so `noteLocalWrite` → `_markStaleAggregate` →
`?.call(groupId)` is a SILENT NO-OP — only the production provider factory
(`connectivity_provider.dart:30-38`) wires `markGroupDirty`. A freshness assertion on that harness stays
red forever (and there is NO existing `balanceAggregateFreshnessProvider` assertion pattern in the
settle-up tests to copy). The new tests MUST wire the callback explicitly, mirroring the factory:

```dart
connectivityProvider.overrideWith((ref) => ConnectivityNotifier(
  startPeriodicChecks: false,
  markBalanceAggregateMayBeStale:
      ref.read(balanceAggregateFreshnessProvider.notifier).markGroupDirty,
))
```

(Builder verifies the exact constructor parameter name and factory wiring at
`connectivity_provider.dart:30-38/89-99` and the freshness notifier API in
`balance_aggregate_freshness_provider.dart` before writing the override.)

One RED test per site (mocked `firebaseFunctionsServiceProvider`), failing on main:

1. Event-scope correction success → `balanceAggregateFreshnessProvider` contains the groupId.
2. Logical settle-up correction success → contains groupId. Reachability: this callable sits behind
   early-return gates (`logicalSetAffordanceCorrected(tagged)` and the `_correctingSettleUpIds`
   in-flight guard) — the test fixture must present a logical set the affordance considers
   NOT-yet-corrected, or the method returns before the callable fires and the test false-fails.
3. Group-scope correction success → contains groupId.
4. Guard: correction callable THROWS → freshness set unchanged (no false dirty).

Notes: override `sharedPreferencesProvider` in every app-booting test; follow whatever pump/settle
discipline the existing settle-up test files use (their overridden notifier has no periodic timer).

## Acceptance

- [ ] 3 RED tests observed failing on main (paste output), green after; guard test 4 green.
- [ ] Production-code diff is exactly the three call sites (+ pre-await captures) + one comment update;
      test files and the spec doc are the only other changes.
- [ ] `flutter analyze` clean; `test/features/ledger/` + `test/features/groups/` suites green.
- [ ] PR body: `Closes #1213` (also in squash commit body), RED evidence pasted.

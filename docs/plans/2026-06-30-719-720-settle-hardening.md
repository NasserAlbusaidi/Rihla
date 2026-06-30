# Settle-up write-path hardening (#719 + #720) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close the last two buildable slices of epic #200 — (#719) revalidate the directed-pair outstanding against *live* balances immediately before a group settle-up write, forcing review-again if it went stale; and (#720) stop dangling an impossible "settle with a former member" write that the rules reject, surfacing an honest block instead.

**Architecture:** Both are surgical changes to the group settle-up write path (`group_settle_up_screen.dart`). #719 adds one pure, table-tested money helper (`BalanceCalculator.outstandingForPair`) and one fresh-read + revalidate step in `_showRecordPaymentSheet`, before `_recordDecomposedSettlement`. #720 splits the existing `_recordDecomposedSettlement` pre-gate so a non-live counterparty is blocked with a clear message instead of falling through to a group write that `firestore.rules` (`validGroupSettlementBase`, live `memberIds` only) rejects. **No firestore.rules change, no Cloud Functions change, no deploy** — #720's decision is *keep the rule, align the UI*.

**Tech Stack:** Flutter, Riverpod 2.x, `decimal`, `flutter_test`, ARB l10n (`app_en.arb` + `app_ar.arb`).

**Ships as TWO PRs:** PR1 = #719 (`Closes #719`), PR2 = #720 (`Closes #720`, rebased on PR1). Each on its own branch off `main`.

**Out of scope (tracked follow-ups, do NOT bundle):**
- Event-level settle (`settle_up_screen.dart:514`) has the *same* stale gap; #200 Scope 6 is group-scoped. File a follow-up; do not touch here.
- Re-opening the record sheet pre-filled with the fresh amount (vs. a blocking message). Minimal correct fix is block + message; the screen already rebuilds with fresh balances so the user's next tap is fresh.

---

## Context the executor needs

- **Why #718 is gone:** #752 (`26c5cdac`/#754) decomposes a group settle-up into N event settlements + 1 residual group settlement (all sharing `groupSettleUpId`), so the per-event breakdown is already persisted as *real docs*; #755 (`fd413da9`) history (`groupSettlementHistory`, `settle_up_page_body.dart:799`) folds those *persisted* amounts. #718 was closed as delivered.
- **The stale window (#719):** `group_settle_up_screen.dart` watches `groupBalancesProvider`. When the user taps a tile, `suggestedAmount` and the whole `balancesData` snapshot are captured and passed into `_showRecordPaymentSheet` (`:189-210`). While the modal record sheet is open, another device can pay / add an expense; the captured snapshot goes stale. Current validation (`:565`) only caps against the *captured* `suggestedAmount`, and `_recordDecomposedSettlement` (`:685`) decomposes from the *captured* `balancesData.perEventBreakdown`. Nothing re-reads live balances.
- **The former-member contradiction (#720):** `validEventSettlementBase` (`firestore.rules:849-850`) gates parties to `participants()` (may include a departed event-participant, #249). `validGroupSettlementBase` (`firestore.rules:1059-1060`) gates parties to live `groupData(groupId).memberIds`. The decompose pre-gate (`group_settle_up_screen.dart:696-714`) computes `bothLiveMembers` and, when false, falls through to `_recordSettlement` (a single *group* write) — which the rules reject (`permission-denied`). `leaveGroup`/`removeMember` already block exit with non-zero net, so this is defensive, but today it produces a confusing failure.
- **Types:** `GroupBalances` = record `({ Map<String,List<UserBalance>> balances, Map<String,Decimal> totalSpent, int eventCount, Map<String,Map<String,Map<String,Decimal>>> perEventBreakdown, Map<String,String> memberNames, Map<String,String> memberRawNames })` (`group_balance_provider.dart:94`). `UserBalance { String participantId; String? displayName; Decimal totalPaid; Decimal totalOwed; Decimal netBalance; }` — `netBalance` **positive = creditor (owed), negative = debtor (owes)** (`expense_model.dart:410`). `groupBalancesProvider` is a `Provider.family` returning `AsyncValue<GroupBalances>` → use `ref.read(...).valueOrNull`.
- **The optimizer cap (`BalanceCalculator.calculateOptimalSettlements`, `expense_provider.dart:891`):** a directed pair from→to is suggested at most `min(|fromNet|, toNet)` in that currency bucket. `outstandingForPair` is exactly this conservative cap.

---

## PR1 — #719: pre-write stale-amount revalidation

### Task 1: pure money helper `BalanceCalculator.outstandingForPair` (TDD)

**Files:**
- Modify: `lib/features/ledger/providers/expense_provider.dart` (add static to `BalanceCalculator`, near `calculateOptimalSettlements` ~`:891`)
- Test: `test/unit/outstanding_for_pair_test.dart` (new)

**Step 1: Write the failing table-driven test**

```dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

UserBalance _ub(String id, String net) => UserBalance(
      participantId: id,
      totalPaid: Decimal.zero,
      totalOwed: Decimal.zero,
      netBalance: Decimal.parse(net),
    );

void main() {
  group('BalanceCalculator.outstandingForPair', () {
    Decimal call(List<UserBalance> bucket, String from, String to) =>
        BalanceCalculator.outstandingForPair(
          bucket: bucket, fromUserId: from, toUserId: to);

    test('clean: from owes 10, to owed 10 -> cap 10', () {
      expect(call([_ub('a', '-10'), _ub('b', '10')], 'a', 'b'),
          Decimal.parse('10'));
    });
    test('capped by smaller side: from owes 4, to owed 10 -> 4', () {
      expect(call([_ub('a', '-4'), _ub('b', '10')], 'a', 'b'),
          Decimal.parse('4'));
    });
    test('capped by creditor: from owes 10, to owed 3 -> 3', () {
      expect(call([_ub('a', '-10'), _ub('b', '3')], 'a', 'b'),
          Decimal.parse('3'));
    });
    test('stale-shrunk: to now owed only 2 -> 2 (was 10)', () {
      expect(call([_ub('a', '-10'), _ub('b', '2')], 'a', 'b'),
          Decimal.parse('2'));
    });
    test('settled-by-other: to net 0 -> 0', () {
      expect(call([_ub('a', '-10'), _ub('b', '0')], 'a', 'b'), Decimal.zero);
    });
    test('from is no longer a debtor (net >= 0) -> 0', () {
      expect(call([_ub('a', '5'), _ub('b', '10')], 'a', 'b'), Decimal.zero);
    });
    test('to is not a creditor (net < 0) -> 0', () {
      expect(call([_ub('a', '-10'), _ub('b', '-3')], 'a', 'b'), Decimal.zero);
    });
    test('missing party -> treated as net 0 -> 0', () {
      expect(call([_ub('a', '-10')], 'a', 'b'), Decimal.zero);
      expect(call([], 'a', 'b'), Decimal.zero);
    });
    test('OMR 3dp precision preserved', () {
      expect(call([_ub('a', '-2.900'), _ub('b', '2.900')], 'a', 'b'),
          Decimal.parse('2.900'));
    });
  });
}
```

**Step 2: Run — expect FAIL** (`outstandingForPair` undefined)

Run: `flutter test test/unit/outstanding_for_pair_test.dart`
Expected: compile error / FAIL.

**Step 3: Implement the minimal static** (add inside `class BalanceCalculator`)

```dart
/// #719: the current directed-pair outstanding in one currency bucket — how
/// much [fromUserId] can pay [toUserId] without overpaying either side =
/// `min(|fromNet|, toNet)`, clamped to >= 0. Conservative mirror of the
/// per-pair cap in [calculateOptimalSettlements]: never authorizes more than
/// the *current* net allows, regardless of the optimizer's chaining. A party
/// absent from the bucket is treated as net 0 (settled). Pure.
static Decimal outstandingForPair({
  required List<UserBalance> bucket,
  required String fromUserId,
  required String toUserId,
}) {
  Decimal netFor(String uid) {
    for (final b in bucket) {
      if (b.participantId == uid) return b.netBalance;
    }
    return Decimal.zero;
  }

  final fromNet = netFor(fromUserId); // debtor when negative
  final toNet = netFor(toUserId); // creditor when positive
  final payable = fromNet < Decimal.zero ? fromNet.abs() : Decimal.zero;
  final receivable = toNet > Decimal.zero ? toNet : Decimal.zero;
  return payable < receivable ? payable : receivable;
}
```

**Step 4: Run — expect PASS** (`flutter test test/unit/outstanding_for_pair_test.dart`)

**Step 5: Commit** — `test(money): table-test outstandingForPair (#719)` then `feat(money): add BalanceCalculator.outstandingForPair (#719)` (or one commit; keep RED→GREEN visible in history).

---

### Task 2: revalidate before write in `_showRecordPaymentSheet`

**Files:**
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart` — between the `editedAmount > suggestedAmount` check (`:565-576`) and the `_recordDecomposedSettlement` call (`:578`).
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` — new key `settleUpBalanceChangedReviewAgain`.
- Test: `test/features/groups/group_settle_up_revalidation_test.dart` (new widget test) — see Task 3.

**Step 1: Add the l10n key** to `app_en.arb` (next to `settleUpAmountExceedsOutstanding`, `:982`):

```json
  "settleUpBalanceChangedReviewAgain": "Balance changed while you were recording — it's now {amount}. Review and try again.",
  "@settleUpBalanceChangedReviewAgain": {
    "placeholders": { "amount": { "type": "String" } }
  },
```

And the Arabic mirror in `app_ar.arb` (translate; keep the `{amount}` placeholder). Run `flutter gen-l10n` (or it regenerates on build) so `context.l10n.settleUpBalanceChangedReviewAgain(...)` resolves.

**Step 2: Insert the revalidation** in `_showRecordPaymentSheet`, immediately before `final outcome = await _recordDecomposedSettlement(`:

```dart
// #719 (Scope 6 of #200): suggestedAmount + balancesData were captured when the
// tile was tapped; the record sheet may have been open long enough for another
// device to pay or add an expense. Re-read the LIVE balances and revalidate the
// directed-pair outstanding before writing. If it dropped below editedAmount,
// abort and force review-again rather than silently overpaying a stale debt.
// Offline / balances-unavailable -> behave exactly as before (use the captured
// snapshot); this is a safety add-on, never a new offline blocker.
var writeBalances = balancesData;
final fresh = ref.read(groupBalancesProvider(widget.groupId)).valueOrNull;
if (fresh != null) {
  final freshOutstanding = BalanceCalculator.outstandingForPair(
    bucket: fresh.balances[currency] ?? const <UserBalance>[],
    fromUserId: fromUserId,
    toUserId: toUserId,
  );
  if (editedAmount > freshOutstanding) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.settleUpBalanceChangedReviewAgain(
              AppFormatters.formatCurrency(freshOutstanding, currency),
            ),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
    return const _StepOutcome(_StepOutcomeKind.invalid);
  }
  writeBalances = fresh; // decompose from fresh per-event nets too
}
```

Then change the `_recordDecomposedSettlement` call to pass `balancesData: writeBalances` (was `balancesData`).

> Note: `_runSteppedSettle` calls `_showRecordPaymentSheet` per step with the screen-load `balancesData`; the revalidation runs per step too, which is correct (each bucket re-checked against live balances). No change needed there beyond the above.

**Step 3:** `flutter analyze` clean.

**Step 4:** widget test (Task 3) green.

**Step 5: Commit** — `feat(money): revalidate live outstanding before group settle write (#719)`.

---

### Task 3: widget test for the stale-revalidation path

**Files:**
- Test: `test/features/groups/group_settle_up_revalidation_test.dart` (new)

**Approach:** Boot the group settle-up screen with a `groupBalancesProvider` override returning a `GroupBalances` where `a` owes `b` 10 OMR. Use a test harness whose override can emit a *second* value (debt shrunk to 2) — OR, simpler and deterministic: override the provider to return the **already-shrunk** balances (outstanding = 2) while passing `suggestedAmount = 10` into the record flow (simulating the captured-stale value), tap record, confirm with `editedAmount = 10`, and assert:
- the `settleUpBalanceChangedReviewAgain` SnackBar text appears (use a `findRichText`/`textContaining` on the localized amount), and
- **no** settlement was written (mock `settlementServiceProvider` / `groupSettlementServiceProvider` with `mocktail` and `verifyNever(() => ...addSettlement(...))` / `addGroupSettlement(...)`).

Reuse the existing settle-up widget harness (see `test/features/ledger/settle_up_screen_*_test.dart` and any `group_settle_up_*_test.dart`) for boot + provider overrides + `sharedPreferencesProvider` override. End on `pumpAndSettle()` only if no never-settling timer is involved; follow the `pumpRihlaApp` contract.

If the modal-mid-change proves intractable in a widget test, fall back to asserting the pure decision is exercised (Task 1 already covers the math) plus a thinner smoke test that the new branch compiles and the message key exists. Prefer the real widget test.

**Step: Commit** with Task 2 (test + impl together is fine if RED was shown for Task 1's pure helper first).

---

## PR2 — #720: block the impossible former-member group write

### Task 4: split the `_recordDecomposedSettlement` pre-gate (TDD)

**Files:**
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart:696-714`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` — new key `settleUpFormerMemberBlocked`.
- Test: `test/features/groups/group_settle_up_former_member_test.dart` (new) — assert a non-live counterparty blocks with the message and writes nothing.

**Step 1: Add l10n key** `settleUpFormerMemberBlocked` (param `name`):

```json
  "settleUpFormerMemberBlocked": "{name} has left the group, so a group payment can't be recorded with them. Settle inside the relevant event ledger instead.",
  "@settleUpFormerMemberBlocked": {
    "placeholders": { "name": { "type": "String" } }
  },
```

Arabic mirror in `app_ar.arb`.

**Step 2: Replace the pre-gate** (`:696-714`). Current:

```dart
final bothLiveMembers =
    group.memberIds.contains(fromUserId) &&
    group.memberIds.contains(toUserId);
// Fall back to today's atomic single group write (no decompose).
if (!bothLiveMembers || decomposition.perEvent.isEmpty) {
  return _recordSettlement(/* ... */);
}
```

New:

```dart
final bothLiveMembers =
    group.memberIds.contains(fromUserId) &&
    group.memberIds.contains(toUserId);
// #720 (Scope 7 of #200): a group settlement — the single-write fallback below
// AND the residual — is rules-gated to LIVE group.memberIds
// (firestore.rules validGroupSettlementBase). leaveGroup/removeMember already
// block exit with a non-zero net, so a departed member is structurally settled;
// but defend against a non-live counterparty ever reaching here: never attempt
// the doomed write (it fails permission-denied). Block honestly. Decision:
// keep the rule, align the UI ("settle before you leave").
if (!bothLiveMembers) {
  if (context.mounted) {
    final departedName =
        group.memberIds.contains(toUserId) ? fromName : toName;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.settleUpFormerMemberBlocked(departedName)),
        duration: const Duration(seconds: 6),
      ),
    );
  }
  return const _StepOutcome(_StepOutcomeKind.invalid);
}
// bothLiveMembers && no shared-event attribution: legitimate single group
// write (pure cross-event), byte-identical to pre-#752.
if (decomposition.perEvent.isEmpty) {
  return _recordSettlement(/* ...unchanged args... */);
}
```

> The only behavior change: `!bothLiveMembers` now blocks with a message instead of falling through to a `_recordSettlement` that the rules reject. The `bothLiveMembers && perEvent.isEmpty` path is preserved verbatim.

**Step 3: Test** — boot the group settle-up screen with `group.memberIds` excluding `b`, a balance where `a` owes `b`, drive the record flow, assert the `settleUpFormerMemberBlocked` SnackBar appears and `verifyNever` on both settlement services. (If reaching `_recordDecomposedSettlement` with a non-live party via the UI is not naturally reachable — optimizer won't suggest a net-zero departed member — construct the balance so `b` is a non-live creditor, mirroring a legacy/Admin-left member with residual debt.)

**Step 4:** `flutter analyze` clean; run the new test + `flutter test test/features/groups/`.

**Step 5: Commit** — `fix(money): block group settle with a former member instead of a doomed write (#720)`.

---

## Verification & ship checklist (both PRs)

- [ ] `bash tool/check_theme_purity.sh` (new/changed `lib/` widgets — but these changes add no `Color`/`textMuted`, so expected clean).
- [ ] `flutter analyze` clean.
- [ ] `flutter test test/unit/outstanding_for_pair_test.dart test/features/groups/` green.
- [ ] Full `flutter test` green before each PR.
- [ ] PR1 body: `Closes #719`; PR2 body + **commit body**: `Closes #720` (squash-merge auto-closes from the commit message).
- [ ] Follow-up issue filed: event-level settle stale gap (`settle_up_screen.dart:514`).
- [ ] No firestore.rules / functions / deploy touched (confirm `git diff --stat main...HEAD` shows only `lib/`, `test/`, `docs/plans/`, `lib/l10n/`).

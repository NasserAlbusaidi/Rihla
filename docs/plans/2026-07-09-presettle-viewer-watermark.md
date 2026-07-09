# Pre-Settlement Review: Viewer-Scoped Settlement Watermark (#1058)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Stop the "Before you settle" sheet from re-flagging expenses the viewing user has already settled past, while an outstanding currency bucket keeps the #922 bucket-level suppression from applying.

**Architecture:** Add one pure function to the existing display-only detector (`pre_settlement_review.dart`): drop a `ReviewFlag` when the viewer was party to a live settlement in the flag's currency recorded after the expense was created. Wire it as a third filter stage (detect → #922 bucket filter → viewer watermark) at both entry points: the event settle-up screen and the group pre-settle provider. No server, rules, oracle, or schema involvement — every touched path is INBOUND/display-only.

**Tech Stack:** Flutter/Dart, Riverpod 2.x (no codegen), `decimal`, `flutter_test` with stream-override fixtures.

**Branch / worktree:** `fix/presettle-viewer-watermark` in `../Rihla-presettle` (off `main` @ `82471a20`).

**Issue linkage:** PR closes #1058 (`Closes #1058` in the squash commit body, not just the PR description). Refs #898/#922 lineage. #1059 (re-split visibility) is deliberately out of scope — decision-labelled, do not build.

---

## Why (one paragraph)

#922 suppresses flags only when the expense's entire currency bucket nets to zero. Live repro (group "Home", 2026-07-09): all OMR debts between the two real members were settled Jul 2–4; adding two shadow members to the event on Jul 8 re-split a global OMR 37.000 expense 4-ways at read time, making OMR outstanding again — so the sheet re-fires "1 large expense + 1 exact split" on every settle-up entry for a viewer who has already settled past both rows. A fresh joiner, by contrast, SHOULD still see those warnings — hence viewer-scoped, not basis-global.

## Semantics (normative)

A flag is suppressed iff ALL of:
- `viewerUid != null`, and
- there exists a settlement `s` in the **basis** with `s.currency == flag.expense.currency`, and
- viewer is a party: `s.payerParticipantId == viewerUid || s.recipientParticipantId == viewerUid` (creator-only `createdBy` does NOT count — recording on behalf of others is not "your money moved"), and
- `s` is live: `!s.isDeleted`, NOT `s.isMarkedCorrection` (#889 unforgeable server marker — the blessed signal for new derived surfaces), and NOT the target of any marked correction in the basis (a corrected payment is not review evidence), and
- `s.settledAt` is strictly after `flag.expense.createdAt` (tie → keep the flag; fail toward warning).

**Basis (Gate R1 revision):** a settlement suppresses only flags from the review basis it was recorded against — a viewer who settled Event A has NOT reviewed Event B's expenses.

- **Event screen:** that event's settlements (already includes #752 decomposed legs — they are event docs). Unchanged from rev 1.
- **Group provider — two stages:**
  - **Stage A (event-local):** inside the per-event loop, an event's flags are filtered against THAT event's settlements only — identical semantics to the event screen, so a flag suppressed on its own event settle-up is also suppressed at group scope and vice versa (no cross-surface inconsistency).
  - **Stage B (group-engagement):** after the loop, the pooled flags are filtered against only the settlements that prove the viewer went through the GROUP review sheet — group-level docs (from `groupSettlementsProvider`) plus `groupSettleUpId`-tagged decomposed legs (#752). An UNTAGGED event settlement never suppresses another event's flags. Marked-correction rows are also pooled into the Stage B list so a correction whose target sits in a different collection still disarms it (the pure function excludes both).
- A #244 OR-dropped event (hard-errored expense stream) contributes NO settlements to either stage — dropped from the flag basis ⇒ dropped from the watermark basis (fail toward warning).

**Why Stage B exists:** a group settle-up presents the group sheet, which covers every event's flags at that moment; group docs and tagged legs are the durable evidence of that. In the live repro, the viewer's Jul 2–4 OMR settlements are tagged decomposed legs → group-wide suppression applies, so the reported false-fire is fixed at both entry points.

**Known accepted holes (document, don't fix here):**
- `Expense` has `createdAt` only — no edit timestamp exists on the model (verified by enumeration). An expense edited after the viewer's last settlement stays suppressed. #799's `recentlyEdited` trigger is the future home.
- `settledAt`/`createdAt` are client-stamped; cross-device clock skew can mis-order near the boundary. Acceptable for a display-only nudge.
- Legacy note-based corrections (pre-#889, no marker) still count toward the watermark. Marker-based is the contract for new derived surfaces.

## Verified facts the plan relies on (re-checked 2026-07-09 against `main` @ `82471a20`)

- Detector + #922 filter: `lib/features/ledger/services/pre_settlement_review.dart` (imports `split_mode.dart`, `expense_model.dart` only — Task 1 adds the settlement import).
- Event callsite: `lib/features/ledger/screens/settle_up_screen.dart` — `_maybeShowReviewSheet` (~L88), invoked at ~L325 inside a `settlementsAsync.hasValue && groupMembersAsync.hasValue` guard; `settlements` (~L244) and `currentUid` (~L212, from `currentUserIdProvider`) are both in scope at the callsite. File already imports `settlement_model.dart`.
- Group provider: `lib/features/groups/providers/group_presettle_review_provider.dart` — watches per-event `eventSettlementsProvider` for loading-gates only (values currently unused); does NOT yet watch `groupSettlementsProvider` or `currentUserIdProvider`. Both live in `group_balance_provider.dart` (L48, L599) which is already imported.
- `currentUserIdProvider` = `ref.watch(authStateProvider).valueOrNull?.uid` — in an unoverridden test container it resolves to null (AsyncError → `valueOrNull` null), so existing provider tests keep passing; null viewer disables suppression (fail toward warning).
- `Settlement`: nullable `payerParticipantId`/`recipientParticipantId`, `settledAt`, `isDeleted` (default false), `currency` (default `'OMR'`), `scope` ('event'|'group'), `groupSettleUpId`, `correctionOfSettlementId` + `isMarkedCorrection` (non-blank trim check).
- `Expense`: `createdAt`; `lastEditedBy` is a uid with NO timestamp companion.
- Existing tests that pin current behavior (all verified to survive this change unmodified): `test/features/ledger/settle_up_review_suppression_test.dart` (5 tests — the "outstanding → fires" case uses EMPTY settlements, so the watermark is empty there), `test/features/groups/group_settle_up_review_sheet_test.dart` (viewer `uid-alice`, per-event settlements default empty, `groupSettlementsProvider` already overridden to `[]`), `test/features/groups/providers/group_presettle_review_provider_test.dart` (does not override `groupSettlementsProvider`/`currentUserIdProvider` — safe per the null/AsyncError behavior above; Task 3 adds explicit overrides anyway).
- Event-test fixture defaults that make the arithmetic work: `_expense` amount `'10.000'`, payer `alice`, `createdAt DateTime(2026, 5, 16)`; `_settlement` bob→alice, `settledAt DateTime(2026, 5, 17)`; screen viewer is `bob`.
- Provider-test helpers (`group_presettle_review_provider_test.dart`): `_makeEvent({required id, required groupId, participantIds = ['uid-alice','uid-bob']})`, `_makeExpense({required id, required tripId, required amount, payer = 'uid-alice', splitMode})` with `createdAt` hardcoded `DateTime(2026, 1, 1)` and default model currency (OMR); `eventA`/`eventB` are per-test locals, not globals. Widget-test helpers (`group_settle_up_review_sheet_test.dart`): `_makeEvent({required id, participantIds = [...]})` (no groupId param — `_groupId` is baked in), `_makeExpense(..., description = 'Expense', amount = '5.000', currency = 'OMR')` with `createdAt` hardcoded `DateTime(2026, 3, 5)`; both files already import `settlement_model.dart` and `group_balance_provider.dart`.
- `test/features/events/event_tabs_test.dart` also drives the embedded event settle-up review path (asserts the sheet at L300/L305) — it survives unchanged because it overrides `eventSettlementsProvider` to an empty stream (empty watermark basis) with `currentUserIdProvider = 'uid-1'`. Verified L157/L167/L300/L305.
- Six further `GroupSettleUpScreen`-mounting test files (`group_settle_up_{revalidation,correct,decompose,atomic_929,screen,screen_same_name}_test.dart`) all override `groupSettlementsProvider` with value-emitting streams and `currentUserIdProvider`, so the new resolved-gate cannot strand them; Task 4's full-suite run is the backstop.

## Verification-principles report (run while authoring)

1. **Callsite classification:** `suppressFlagsSettledPastByViewer` output feeds `showPreSettlementReviewSheet` (event) and the `GroupPreSettleReview` record consumed only by `group_settle_up_screen.dart`'s sheet trigger — INBOUND both. No write path reads flags. Verified via grep `groupPreSettleReviewProvider|_maybeShowReviewSheet` — consumers are the two screens only.
2. **Concrete claims re-grepped:** provider names/lines, imports, fixture defaults — listed above, all re-checked this session.
3. **Read-path per write-path:** no write path exists (display-only). The new provider watches (`groupSettlementsProvider`, `currentUserIdProvider`) add zero Firestore listeners at the only consumer — `group_settle_up_screen.dart` already watches both.
4. **Fields enumerated from types:** `Expense` and `Settlement` field lists read from the model files (not memory); the absent expense edit-timestamp is a finding of that enumeration.
5. **Data contracts spelled out:** new function signature `List<ReviewFlag> suppressFlagsSettledPastByViewer(List<ReviewFlag> flags, {required List<Settlement> settlements, required String? viewerUid})`; `_maybeShowReviewSheet` gains two trailing optional positional params `List<Settlement> settlements = const []`, `String? viewerUid`.
6. **Arithmetic decomposition:** none introduced — the function compares timestamps; it never sums money.
7. **Orthogonal-axis worked examples in tests:** direction (viewer as recipient), currency (USD settlement vs OMR flag), identity (non-party viewer / fresh joiner), corrections (marked row + its target), time (tie at watermark).

## Rejected alternatives (do not resurrect without new evidence)

- **Basis-global watermark** (any settlement, not viewer-party): silences the sheet for fresh joiners — the audience that needs it most.
- **Per-expense "contribution settled" matching:** an expense's contribution after netting is not well-defined (#922's documented reason for going bucket-level); amount-matching settlements to expenses is a heuristic that breaks on partials/aggregates.
- **`createdBy` counting toward the watermark:** the treasurer who records everyone's payments would self-suppress all warnings.
- **Adding `lastEditedAt` to the expense schema:** read+write schema change (rules, serializer, Gate category) bolted onto a display fix — violates one-PR-one-thing; belongs with #799 if ever.
- **Changing the retroactive re-split semantics:** oracle-parity sacred ground and product-correct for shadow members → #1059 (decision, visibility only).
- **Currency-global group watermark (rev 1, killed by Gate R1):** pooling ALL per-event settlements into one group-wide per-currency watermark lets a viewer's settlement in Event A silence an older, never-reviewed Event B expense — and creates event-vs-group surface inconsistency (the same flag fires on Event B's own settle-up). Replaced by the two-stage basis above.

---

### Task 1: Pure watermark filter + unit tests

**Files:**
- Modify: `lib/features/ledger/services/pre_settlement_review.dart`
- Test: `test/unit/pre_settlement_review_test.dart`

**Step 1: Write the failing tests**

In `test/unit/pre_settlement_review_test.dart`, add the settlement import at the top (after the `expense_model.dart` import):

```dart
import 'package:safar/features/ledger/models/settlement_model.dart';
```

Add a settlement fixture helper after `_exactFlags`:

```dart
Settlement _stl({
  required String id,
  String currency = 'OMR',
  String? payer = 'uid-viewer',
  String? recipient = 'uid-a',
  DateTime? settledAt,
  bool isDeleted = false,
  String? correctionOfSettlementId,
}) => Settlement(
  id: id,
  tripId: 'event-1',
  payerParticipantId: payer,
  recipientParticipantId: recipient,
  amount: Decimal.parse('1.000'),
  settledAt: settledAt ?? DateTime(2026, 6, 10),
  isDeleted: isDeleted,
  currency: currency,
  correctionOfSettlementId: correctionOfSettlementId,
);
```

Add a new top-level group at the end of `main()` (fixture expenses default `createdAt DateTime(2026, 6, 1)` via `_exp`):

```dart
  group('suppressFlagsSettledPastByViewer (#1058 — viewer watermark)', () {
    List<ReviewFlag> flagsFor(Expense e) => [
      ReviewFlag(e, ReviewReason.exactSplit),
    ];

    test('viewer-party settlement newer than the expense suppresses', () {
      final flags = flagsFor(_exp(id: 'a', splitMode: SplitMode.exact));
      expect(
        suppressFlagsSettledPastByViewer(
          flags,
          settlements: [_stl(id: 's1')],
          viewerUid: 'uid-viewer',
        ),
        isEmpty,
      );
    });

    test('viewer as recipient also suppresses', () {
      final flags = flagsFor(_exp(id: 'a', splitMode: SplitMode.exact));
      expect(
        suppressFlagsSettledPastByViewer(
          flags,
          settlements: [
            _stl(id: 's1', payer: 'uid-a', recipient: 'uid-viewer'),
          ],
          viewerUid: 'uid-viewer',
        ),
        isEmpty,
      );
    });

    test('an expense created after the last settlement is kept', () {
      final flags = flagsFor(
        _exp(
          id: 'a',
          splitMode: SplitMode.exact,
          createdAt: DateTime(2026, 6, 15),
        ),
      );
      expect(
        suppressFlagsSettledPastByViewer(
          flags,
          settlements: [_stl(id: 's1')],
          viewerUid: 'uid-viewer',
        ),
        hasLength(1),
      );
    });

    test('a tie (expense created exactly at the watermark) is kept', () {
      final flags = flagsFor(
        _exp(
          id: 'a',
          splitMode: SplitMode.exact,
          createdAt: DateTime(2026, 6, 10),
        ),
      );
      expect(
        suppressFlagsSettledPastByViewer(
          flags,
          settlements: [_stl(id: 's1', settledAt: DateTime(2026, 6, 10))],
          viewerUid: 'uid-viewer',
        ),
        hasLength(1),
      );
    });

    test('a settlement in another currency never suppresses', () {
      final flags = flagsFor(_exp(id: 'a', splitMode: SplitMode.exact));
      expect(
        suppressFlagsSettledPastByViewer(
          flags,
          settlements: [_stl(id: 's1', currency: 'USD')],
          viewerUid: 'uid-viewer',
        ),
        hasLength(1),
      );
    });

    test('a settlement between two other people never suppresses', () {
      final flags = flagsFor(_exp(id: 'a', splitMode: SplitMode.exact));
      expect(
        suppressFlagsSettledPastByViewer(
          flags,
          settlements: [_stl(id: 's1', payer: 'uid-a', recipient: 'uid-b')],
          viewerUid: 'uid-viewer',
        ),
        hasLength(1),
      );
    });

    test('a null viewer uid suppresses nothing', () {
      final flags = flagsFor(_exp(id: 'a', splitMode: SplitMode.exact));
      expect(
        suppressFlagsSettledPastByViewer(
          flags,
          settlements: [_stl(id: 's1')],
          viewerUid: null,
        ),
        hasLength(1),
      );
    });

    test('a soft-deleted settlement never advances the watermark', () {
      final flags = flagsFor(_exp(id: 'a', splitMode: SplitMode.exact));
      expect(
        suppressFlagsSettledPastByViewer(
          flags,
          settlements: [_stl(id: 's1', isDeleted: true)],
          viewerUid: 'uid-viewer',
        ),
        hasLength(1),
      );
    });

    test('a marked correction row never advances the watermark', () {
      final flags = flagsFor(_exp(id: 'a', splitMode: SplitMode.exact));
      expect(
        suppressFlagsSettledPastByViewer(
          flags,
          settlements: [_stl(id: 'corr', correctionOfSettlementId: 'orig')],
          viewerUid: 'uid-viewer',
        ),
        hasLength(1),
      );
    });

    test('the ORIGINAL a correction reverses is excluded too', () {
      final flags = flagsFor(_exp(id: 'a', splitMode: SplitMode.exact));
      expect(
        suppressFlagsSettledPastByViewer(
          flags,
          settlements: [
            _stl(id: 'orig'),
            _stl(
              id: 'corr',
              settledAt: DateTime(2026, 6, 11),
              correctionOfSettlementId: 'orig',
            ),
          ],
          viewerUid: 'uid-viewer',
        ),
        hasLength(1),
      );
    });

    test('suppression is per-currency: OMR settled past, USD flag stays', () {
      final omr = _exp(id: 'omr', splitMode: SplitMode.exact);
      final usd = _exp(id: 'usd', splitMode: SplitMode.exact, currency: 'USD');
      final kept = suppressFlagsSettledPastByViewer(
        [
          ReviewFlag(omr, ReviewReason.exactSplit),
          ReviewFlag(usd, ReviewReason.exactSplit),
        ],
        settlements: [_stl(id: 's1')],
        viewerUid: 'uid-viewer',
      );
      expect(kept.map((f) => f.expense.id), ['usd']);
    });
  });
```

**Step 2: Run tests to verify they fail**

Run: `cd /Users/nasseralbusaidi/Desktop/Personal/Rihla-presettle && flutter test test/unit/pre_settlement_review_test.dart`
Expected: FAIL — compile error, `suppressFlagsSettledPastByViewer` undefined.

**Step 3: Write the implementation**

In `lib/features/ledger/services/pre_settlement_review.dart`, add the import (after the `expense_model.dart` import):

```dart
import '../models/settlement_model.dart';
```

Add after `filterFlagsToOutstandingCurrencies`:

```dart
/// #1058: drop flags the viewer has already settled past. A flag survives
/// unless the viewer was PARTY (payer or recipient — never mere creator) to a
/// live settlement in the flag's currency recorded strictly after the expense
/// was created. Live excludes soft-deleted rows, #889 server-marked correction
/// rows, and the originals those corrections reverse — a corrected payment is
/// not evidence the viewer reviewed the ledger. Null [viewerUid], a tie at the
/// watermark, or a missing basis all fail toward warning (flag kept).
///
/// Timestamps are client-stamped ([Settlement.settledAt] vs
/// [Expense.createdAt]); cross-device clock skew near the boundary is accepted
/// for a display-only nudge. Expenses carry no edit timestamp, so an expense
/// edited after the viewer's last settlement stays suppressed (#799's
/// recentlyEdited trigger is the future home for re-arming). INBOUND-only,
/// like the rest of this file: no money calculation, no I/O.
List<ReviewFlag> suppressFlagsSettledPastByViewer(
  List<ReviewFlag> flags, {
  required List<Settlement> settlements,
  required String? viewerUid,
}) {
  if (viewerUid == null || flags.isEmpty || settlements.isEmpty) return flags;

  final correctedIds = <String>{
    for (final s in settlements)
      if (s.isMarkedCorrection) s.correctionOfSettlementId!,
  };

  final watermarkByCurrency = <String, DateTime>{};
  for (final s in settlements) {
    if (s.isDeleted || s.isMarkedCorrection) continue;
    if (correctedIds.contains(s.id)) continue;
    if (s.payerParticipantId != viewerUid &&
        s.recipientParticipantId != viewerUid) {
      continue;
    }
    final current = watermarkByCurrency[s.currency];
    if (current == null || s.settledAt.isAfter(current)) {
      watermarkByCurrency[s.currency] = s.settledAt;
    }
  }
  if (watermarkByCurrency.isEmpty) return flags;

  return flags.where((f) {
    final watermark = watermarkByCurrency[f.expense.currency];
    return watermark == null || !f.expense.createdAt.isBefore(watermark);
  }).toList();
}
```

**Step 4: Run tests to verify they pass**

Run: `flutter test test/unit/pre_settlement_review_test.dart`
Expected: PASS (all groups, including the pre-existing ones).

**Step 5: Analyze and commit**

Run: `flutter analyze` — expected clean.

```bash
git add lib/features/ledger/services/pre_settlement_review.dart test/unit/pre_settlement_review_test.dart
git commit -m "feat(settle-up): pure viewer settlement-watermark flag filter (#1058)"
```

---

### Task 2: Event settle-up wiring + widget tests

**Files:**
- Modify: `lib/features/ledger/screens/settle_up_screen.dart` (`_maybeShowReviewSheet` ~L88–117 and its callsite ~L325)
- Test: `test/features/ledger/settle_up_review_suppression_test.dart`

**Step 1: Extend the test fixtures**

In `test/features/ledger/settle_up_review_suppression_test.dart`, give `_expense` a `createdAt` override and `_settlement` party/time overrides — change the two helpers to:

```dart
Expense _expense({
  required String id,
  required String description,
  String amount = '10.000',
  String currency = 'OMR',
  SplitMode? splitMode = SplitMode.equally,
  DateTime? createdAt,
}) {
  return Expense(
    id: id,
    tripId: _eventId,
    payerParticipantId: 'alice',
    amount: Decimal.parse(amount),
    scope: ExpenseScope.global,
    splitMode: splitMode,
    currency: currency,
    createdAt: createdAt ?? DateTime(2026, 5, 16),
    description: description,
  );
}
```

(keep every other line of the original `_expense` identical — only the `createdAt` parameter and its use are new)

```dart
Settlement _settlement({
  required String id,
  required String amount,
  String currency = 'OMR',
  String? payer = 'bob',
  String? recipient = 'alice',
  DateTime? settledAt,
}) {
  return Settlement(
    id: id,
    tripId: _eventId,
    payerParticipantId: payer,
    recipientParticipantId: recipient,
    amount: Decimal.parse(amount),
    currency: currency,
    settledAt: settledAt ?? DateTime(2026, 5, 17),
    createdBy: 'bob',
  );
}
```

**Step 2: Write the failing widget tests**

Append inside `main()`:

```dart
  testWidgets(
    'outstanding currency but viewer settled past the flagged expense → '
    'no sheet (#1058)',
    (tester) async {
      final prefs = await _prefs();

      // Partial payment: OMR stays outstanding (alice +3 / bob −3), but the
      // viewer (bob) was party to a settlement NEWER than the flagged expense.
      await tester.pumpWidget(
        _wrap(
          prefs: prefs,
          expenses: Stream.value([
            _expense(
              id: 'omr-exact',
              description: 'Settled-past OMR dinner',
              splitMode: SplitMode.exact,
            ),
          ]),
          settlements: Stream.value([
            _settlement(id: 'partial-omr', amount: '2.000'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
      expect(find.text('Settled-past OMR dinner'), findsNothing);
    },
  );

  testWidgets(
    'an expense NEWER than the viewer\'s last settlement still fires (#1058)',
    (tester) async {
      final prefs = await _prefs();

      await tester.pumpWidget(
        _wrap(
          prefs: prefs,
          expenses: Stream.value([
            _expense(
              id: 'omr-exact-new',
              description: 'Newer OMR dinner',
              splitMode: SplitMode.exact,
              createdAt: DateTime(2026, 5, 18),
            ),
          ]),
          settlements: Stream.value([
            _settlement(id: 'partial-omr', amount: '2.000'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
      expect(find.text('Newer OMR dinner'), findsOneWidget);
    },
  );

  testWidgets(
    'a newer settlement between OTHER parties does not suppress for the '
    'viewer (#1058)',
    (tester) async {
      final prefs = await _prefs();

      await tester.pumpWidget(
        _wrap(
          prefs: prefs,
          expenses: Stream.value([
            _expense(
              id: 'omr-exact',
              description: 'Third-party OMR dinner',
              splitMode: SplitMode.exact,
            ),
          ]),
          settlements: Stream.value([
            _settlement(
              id: 'other-parties',
              amount: '2.000',
              payer: 'alice',
              recipient: 'carol',
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
      expect(find.text('Third-party OMR dinner'), findsOneWidget);
    },
  );
```

**Step 3: Run to verify the first new test fails**

Run: `flutter test test/features/ledger/settle_up_review_suppression_test.dart`
Expected: RED — the `#1058` suppressed-case FAILS (sheet found). The two fires-cases are GUARD tests (green before AND after the wiring — boundary pins, not RED evidence); all 5 pre-existing tests PASS.

**Step 4: Wire the screen**

In `lib/features/ledger/screens/settle_up_screen.dart`, replace `_maybeShowReviewSheet`'s signature and flag computation (keep the post-frame-callback body unchanged):

```dart
  void _maybeShowReviewSheet(
    BuildContext context,
    List<Expense> expenses, [
    Set<String> outstandingCurrencies = const {},
    Set<String> activeParticipantIds = const {},
    List<Settlement> settlements = const [],
    String? viewerUid,
  ]) {
    if (_reviewSheetShown) return;
    final flags = suppressFlagsSettledPastByViewer(
      filterFlagsToOutstandingCurrencies(
        detectReviewWorthyExpenses(
          expenses,
          activeParticipantIds: activeParticipantIds,
        ),
        outstandingCurrencies,
      ),
      settlements: settlements,
      viewerUid: viewerUid,
    );
    if (flags.isEmpty) return;
```

Append to the method's doc comment:

```dart
  /// #1058: flags the viewer already settled past (viewer-party settlement in
  /// the same currency, newer than the expense) are suppressed even while the
  /// currency bucket stays outstanding — see suppressFlagsSettledPastByViewer.
```

Update the callsite (~L325) to pass the two extra arguments:

```dart
            _maybeShowReviewSheet(
              context,
              expenses,
              outstandingCurrencies,
              activeParticipantIds,
              settlements,
              currentUid,
            );
```

**Step 5: Run tests to verify they pass**

Run: `flutter test test/features/ledger/settle_up_review_suppression_test.dart test/features/ledger/settle_up_screen_test.dart`
Expected: PASS (both files — `settle_up_screen_test.dart` exercises the same screen and must stay green).

**Step 6: Analyze and commit**

Run: `flutter analyze` — expected clean.

```bash
git add lib/features/ledger/screens/settle_up_screen.dart test/features/ledger/settle_up_review_suppression_test.dart
git commit -m "feat(settle-up): apply viewer watermark at event settle-up entry (#1058)"
```

---

### Task 3: Group provider wiring + provider/widget tests

**Files:**
- Modify: `lib/features/groups/providers/group_presettle_review_provider.dart`
- Test: `test/features/groups/providers/group_presettle_review_provider_test.dart`
- Test: `test/features/groups/group_settle_up_review_sheet_test.dart`

**Step 1: Extend provider-test overrides and write failing tests**

In `test/features/groups/providers/group_presettle_review_provider_test.dart`:

Add the settlement-model import if absent (`package:safar/features/ledger/models/settlement_model.dart` — it already constructs `Settlement` streams, so it is present; verify).

Extend `_resolvedMoneyOverrides` so every existing test pins the new inputs deterministically:

```dart
List<Override> _resolvedMoneyOverrides(String groupId, List<Event> events) {
  return [
    groupBalancesProvider(
      groupId,
    ).overrideWith((_) => AsyncValue.data(_outstandingBalances)),
    groupSettlementsProvider(
      groupId,
    ).overrideWith((_) => Stream.value(const <Settlement>[])),
    currentUserIdProvider.overrideWithValue(null),
    for (final event in events)
      eventSettlementsProvider((
        groupId: groupId,
        eventId: event.id,
      )).overrideWith((_) => Stream.value(const <Settlement>[])),
  ];
}
```

(`groupSettlementsProvider` and `currentUserIdProvider` come from the already-imported `group_balance_provider.dart`; add the import line only if the file imported it selectively.)

Add a settlement fixture helper near the expense helpers:

```dart
Settlement _viewerSettlement({
  required String id,
  String currency = 'OMR',
  DateTime? settledAt,
  String scope = 'event',
  String? groupSettleUpId,
}) => Settlement(
  id: id,
  tripId: scope == 'group' ? 'group-1' : 'event-a',
  payerParticipantId: 'uid-viewer',
  recipientParticipantId: 'uid-alice',
  amount: Decimal.parse('1.000'),
  settledAt: settledAt ?? DateTime(2026, 6, 10),
  currency: currency,
  scope: scope,
  groupSettleUpId: groupSettleUpId,
);
```

Add new tests inside the existing `group('groupPreSettleReviewProvider')`. `eventA` is a per-test local in this file, and `_makeExpense` requires `amount:` with `createdAt` hardcoded `DateTime(2026, 1, 1)` — so the default June-10 settlement of `_viewerSettlement` is newer. Each new test starts with:

```dart
      final eventA = _makeEvent(
        id: 'event-a',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-viewer'],
      );
```

(the fresh-joiner test uses `['uid-alice', 'uid-joiner']` instead), and uses this expense in the overrides:

```dart
      final flagged = _makeExpense(
        id: 'x',
        tripId: 'event-a',
        amount: '5.000',
        splitMode: SplitMode.exact,
      );
```

```dart
    test('stage A: viewer-party newer EVENT settlement suppresses THAT '
        'event\'s flag (#1058)', () async {
      final eventA = _makeEvent(
        id: 'event-a',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-viewer'],
      );
      final flagged = _makeExpense(
        id: 'x',
        tripId: 'event-a',
        amount: '5.000',
        splitMode: SplitMode.exact,
      );
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(groupId).overrideWith((_) => Stream.value([eventA])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([
              _makeMember(userId: 'uid-alice'),
              _makeMember(userId: 'uid-viewer'),
            ]),
          ),
          groupBalancesProvider(groupId)
              .overrideWith((_) => AsyncValue.data(_outstandingBalances)),
          groupSettlementsProvider(groupId)
              .overrideWith((_) => Stream.value(const <Settlement>[])),
          currentUserIdProvider.overrideWithValue('uid-viewer'),
          eventExpensesProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith((_) => Stream.value([flagged])),
          eventSettlementsProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith((_) => Stream.value([_viewerSettlement(id: 's1')])),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));
      expect(review.resolved, isTrue);
      expect(review.flags, isEmpty);
    });

    test('stage A is event-local: an UNTAGGED settlement in event-a never '
        'suppresses event-b\'s flag (#1058 Gate R1)', () async {
      final eventA = _makeEvent(
        id: 'event-a',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-viewer'],
      );
      final eventB = _makeEvent(
        id: 'event-b',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-viewer'],
      );
      final flaggedB = _makeExpense(
        id: 'b-exact',
        tripId: 'event-b',
        amount: '5.000',
        splitMode: SplitMode.exact,
      );
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(groupId)
              .overrideWith((_) => Stream.value([eventA, eventB])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([
              _makeMember(userId: 'uid-alice'),
              _makeMember(userId: 'uid-viewer'),
            ]),
          ),
          groupBalancesProvider(groupId)
              .overrideWith((_) => AsyncValue.data(_outstandingBalances)),
          groupSettlementsProvider(groupId)
              .overrideWith((_) => Stream.value(const <Settlement>[])),
          currentUserIdProvider.overrideWithValue('uid-viewer'),
          eventExpensesProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith((_) => Stream.value(const <Expense>[])),
          eventSettlementsProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith((_) => Stream.value([_viewerSettlement(id: 's1')])),
          eventExpensesProvider((groupId: groupId, eventId: 'event-b'))
              .overrideWith((_) => Stream.value([flaggedB])),
          eventSettlementsProvider((groupId: groupId, eventId: 'event-b'))
              .overrideWith((_) => Stream.value(const <Settlement>[])),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));
      expect(review.resolved, isTrue);
      expect(review.flags.map((f) => f.expense.id), ['b-exact']);
    });

    test('stage B: a groupSettleUpId-TAGGED leg in event-a suppresses '
        'event-b\'s older flag group-wide (#1058)', () async {
      final eventA = _makeEvent(
        id: 'event-a',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-viewer'],
      );
      final eventB = _makeEvent(
        id: 'event-b',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-viewer'],
      );
      final flaggedB = _makeExpense(
        id: 'b-exact',
        tripId: 'event-b',
        amount: '5.000',
        splitMode: SplitMode.exact,
      );
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(groupId)
              .overrideWith((_) => Stream.value([eventA, eventB])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([
              _makeMember(userId: 'uid-alice'),
              _makeMember(userId: 'uid-viewer'),
            ]),
          ),
          groupBalancesProvider(groupId)
              .overrideWith((_) => AsyncValue.data(_outstandingBalances)),
          groupSettlementsProvider(groupId)
              .overrideWith((_) => Stream.value(const <Settlement>[])),
          currentUserIdProvider.overrideWithValue('uid-viewer'),
          eventExpensesProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith((_) => Stream.value(const <Expense>[])),
          eventSettlementsProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith(
            (_) => Stream.value([
              _viewerSettlement(id: 'leg1', groupSettleUpId: 'gsu-1'),
            ]),
          ),
          eventExpensesProvider((groupId: groupId, eventId: 'event-b'))
              .overrideWith((_) => Stream.value([flaggedB])),
          eventSettlementsProvider((groupId: groupId, eventId: 'event-b'))
              .overrideWith((_) => Stream.value(const <Settlement>[])),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));
      expect(review.resolved, isTrue);
      expect(review.flags, isEmpty);
    });

    test('stage B: viewer-party newer GROUP-level settlement suppresses '
        'group-wide (#1058)', () async {
      final eventA = _makeEvent(
        id: 'event-a',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-viewer'],
      );
      final flagged = _makeExpense(
        id: 'x',
        tripId: 'event-a',
        amount: '5.000',
        splitMode: SplitMode.exact,
      );
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(groupId).overrideWith((_) => Stream.value([eventA])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([
              _makeMember(userId: 'uid-alice'),
              _makeMember(userId: 'uid-viewer'),
            ]),
          ),
          groupBalancesProvider(groupId)
              .overrideWith((_) => AsyncValue.data(_outstandingBalances)),
          groupSettlementsProvider(groupId).overrideWith(
            (_) => Stream.value([_viewerSettlement(id: 'g1', scope: 'group')]),
          ),
          currentUserIdProvider.overrideWithValue('uid-viewer'),
          eventExpensesProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith((_) => Stream.value([flagged])),
          eventSettlementsProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith((_) => Stream.value(const <Settlement>[])),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));
      expect(review.resolved, isTrue);
      expect(review.flags, isEmpty);
    });

    test('a viewer with NO settlements (fresh joiner) still sees flags '
        '(#1058)', () async {
      final eventA = _makeEvent(
        id: 'event-a',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-joiner'],
      );
      final flagged = _makeExpense(
        id: 'x',
        tripId: 'event-a',
        amount: '5.000',
        splitMode: SplitMode.exact,
      );
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(groupId).overrideWith((_) => Stream.value([eventA])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([
              _makeMember(userId: 'uid-alice'),
              _makeMember(userId: 'uid-joiner'),
            ]),
          ),
          groupBalancesProvider(groupId)
              .overrideWith((_) => AsyncValue.data(_outstandingBalances)),
          groupSettlementsProvider(groupId)
              .overrideWith((_) => Stream.value(const <Settlement>[])),
          currentUserIdProvider.overrideWithValue('uid-joiner'),
          eventExpensesProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith((_) => Stream.value([flagged])),
          eventSettlementsProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith(
            (_) => Stream.value([
              Settlement(
                id: 'others',
                tripId: 'event-a',
                payerParticipantId: 'uid-alice',
                recipientParticipantId: 'uid-bob',
                amount: Decimal.parse('1.000'),
                settledAt: DateTime(2026, 6, 10),
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));
      expect(review.resolved, isTrue);
      expect(review.flags, hasLength(1));
    });

    test('unresolved while the group settlement stream is loading (#1058)',
        () async {
      final eventA = _makeEvent(
        id: 'event-a',
        groupId: groupId,
        participantIds: const ['uid-alice', 'uid-viewer'],
      );
      final flagged = _makeExpense(
        id: 'x',
        tripId: 'event-a',
        amount: '5.000',
        splitMode: SplitMode.exact,
      );
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(groupId).overrideWith((_) => Stream.value([eventA])),
          groupMembersProvider(groupId).overrideWith(
            (_) => Stream.value([_makeMember(userId: 'uid-alice')]),
          ),
          groupBalancesProvider(groupId)
              .overrideWith((_) => AsyncValue.data(_outstandingBalances)),
          groupSettlementsProvider(groupId)
              .overrideWith((_) => const Stream<List<Settlement>>.empty()),
          currentUserIdProvider.overrideWithValue('uid-viewer'),
          eventExpensesProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith((_) => Stream.value([flagged])),
          eventSettlementsProvider((groupId: groupId, eventId: 'event-a'))
              .overrideWith((_) => Stream.value(const <Settlement>[])),
        ],
      );
      addTearDown(container.dispose);
      await _pump(container, groupId);

      final review = container.read(groupPreSettleReviewProvider(groupId));
      expect(review.resolved, isFalse);
      expect(review.flags, isEmpty);
    });
```

In `test/features/groups/group_settle_up_review_sheet_test.dart`, extend `_overrides` with an optional group-settlements param:

```dart
  List<Settlement> groupSettlements = const [],
```

and change the `groupSettlementsProvider` override line to use it:

```dart
    groupSettlementsProvider(
      _groupId,
    ).overrideWith((_) => Stream.value(groupSettlements)),
```

Add one end-to-end widget test (viewer is `uid-alice` per the file's overrides; expenses are created `DateTime(2026, 3, 5)`):

```dart
  testWidgets('viewer-party group settlement suppresses re-flagging (#1058)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        _overrides(
          events: [_makeEvent(id: 'event-1')],
          expensesByEvent: {
            'event-1': Stream.value([
              _makeExpense(
                id: 'flagged',
                tripId: 'event-1',
                description: 'Old flagged dinner',
                splitMode: SplitMode.exact,
              ),
            ]),
          },
          groupSettlements: [
            Settlement(
              id: 'g1',
              tripId: _groupId,
              payerParticipantId: 'uid-alice',
              recipientParticipantId: 'uid-bob',
              amount: Decimal.parse('1.000'),
              settledAt: DateTime(2026, 3, 10),
              scope: 'group',
              groupId: _groupId,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
  });
```

(Widget-test helper signatures verified: `_makeEvent` takes no `groupId`; `_makeExpense` has `description`/`amount` defaults and `createdAt` fixed at `DateTime(2026, 3, 5)` — the March-10 group settlement above is newer, and the balances default to `_outstandingBalances`, so only the new watermark can be the reason the sheet stays away.)

**Step 2: Run to verify the new tests fail**

Run: `flutter test test/features/groups/providers/group_presettle_review_provider_test.dart test/features/groups/group_settle_up_review_sheet_test.dart`
Expected: RED — the suppression cases (stage A single-event, stage B tagged-leg, stage B group-doc), the loading-gate case, and the widget case FAIL (flags present / sheet fires / resolved true where false expected). The `untagged-never-suppresses` and `fresh joiner` cases are GUARD tests — green before AND after the wiring; they pin the boundary, they are not RED evidence. Every pre-existing test PASSES.

**Step 3: Wire the provider**

Replace the body of `groupPreSettleReviewProvider` in `lib/features/groups/providers/group_presettle_review_provider.dart`:

```dart
import '../../ledger/models/settlement_model.dart';
```

(add to imports)

```dart
final groupPreSettleReviewProvider =
    Provider.family<GroupPreSettleReview, String>((ref, groupId) {
      final eventsAsync = ref.watch(groupEventsProvider(groupId));
      final membersAsync = ref.watch(groupMembersProvider(groupId));
      final balancesAsync = ref.watch(groupBalancesProvider(groupId));
      // #1058: watermark inputs. Zero new Firestore listeners — the only
      // consumer (group_settle_up_screen.dart) already watches both.
      final groupSettlementsAsync = ref.watch(
        groupSettlementsProvider(groupId),
      );
      final viewerUid = ref.watch(currentUserIdProvider);

      final membersSettled = membersAsync.hasValue || membersAsync.hasError;
      final balancesSettled = balancesAsync.hasValue || balancesAsync.hasError;
      // #1058: a still-loading group-settlement stream reads as "viewer never
      // settled" and would false-fire the one-shot sheet — block resolution,
      // mirroring the per-event settlement gate. A hard error proceeds
      // without those rows (less suppression = fail toward warning).
      final groupSettlementsSettled =
          groupSettlementsAsync.hasValue || groupSettlementsAsync.hasError;
      if (!eventsAsync.hasValue ||
          !membersSettled ||
          !balancesSettled ||
          !groupSettlementsSettled) {
        return (flags: const <ReviewFlag>[], resolved: false);
      }

      final liveMemberIds = <String>{
        for (final m in membersAsync.valueOrNull ?? const <GroupMember>[])
          if (!m.isTombstone) m.userId,
      };

      final flags = <ReviewFlag>[];
      // #1058 stage B basis: ONLY settlements proving the viewer went through
      // the GROUP review sheet — group-level docs plus #752
      // groupSettleUpId-tagged decomposed legs. The group/event ASYMMETRY is
      // intentional (Gate R1): an untagged settlement in Event A proves the
      // viewer passed Event A's sheet, never Event B's — it suppresses only
      // event-locally (stage A below), so a viewer who settled one event
      // still sees another event's unreviewed flags. Marked corrections ride
      // along so cross-collection targets stay disarmed. A #244 OR-dropped
      // event contributes neither flags nor watermark (fail toward warning).
      final groupWideSettlements = <Settlement>[
        ...?groupSettlementsAsync.valueOrNull,
      ];
      var resolved = true;
      for (final event in eventsAsync.valueOrNull ?? const <Event>[]) {
        final eventRef = (groupId: groupId, eventId: event.id);
        final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
        final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
        if (expensesAsync.isLoading && !expensesAsync.hasValue) {
          resolved = false;
          continue;
        }
        if (settlementsAsync.isLoading && !settlementsAsync.hasValue) {
          resolved = false;
          continue;
        }
        if (expensesAsync.hasError && !expensesAsync.hasValue) continue;
        final eventSettlements =
            settlementsAsync.valueOrNull ?? const <Settlement>[];
        groupWideSettlements.addAll(
          eventSettlements.where(
            (s) => s.groupSettleUpId != null || s.isMarkedCorrection,
          ),
        );
        // #1058 stage A: event-local suppression — same semantics as the
        // event settle-up screen, so the two surfaces agree per flag.
        flags.addAll(
          suppressFlagsSettledPastByViewer(
            detectReviewWorthyExpenses(
              expensesAsync.valueOrNull ?? const <Expense>[],
              activeParticipantIds: event.participantIds.toSet().intersection(
                liveMemberIds,
              ),
            ),
            settlements: eventSettlements,
            viewerUid: viewerUid,
          ),
        );
      }
      if (!resolved) return (flags: const <ReviewFlag>[], resolved: false);

      // #1058 stage B: group-engagement suppression across all events.
      // Applies on BOTH exits — settled-past flags stay suppressed even when
      // balances errored and the #922 bucket filter cannot run.
      final visibleFlags = suppressFlagsSettledPastByViewer(
        flags,
        settlements: groupWideSettlements,
        viewerUid: viewerUid,
      );
      if (balancesAsync.hasError) {
        return (flags: List.unmodifiable(visibleFlags), resolved: true);
      }

      final outstandingCurrencies = {
        for (final entry in balancesAsync.valueOrNull!.balances.entries)
          if (entry.value.any((b) => b.netBalance != Decimal.zero)) entry.key,
      };
      return (
        flags: List.unmodifiable(
          filterFlagsToOutstandingCurrencies(
            visibleFlags,
            outstandingCurrencies,
          ),
        ),
        resolved: true,
      );
    });
```

Also update the provider's doc comment: add — `/// #1058: flags the viewer settled past are suppressed in two stages: stage A event-local (that event's settlements — mirrors the event screen), stage B group-engagement (group-level docs + groupSettleUpId-tagged legs, applied group-wide). An untagged event settlement NEVER suppresses another event's flags — intentional asymmetry, Gate R1.` and extend the `[resolved]` sentence to include the group-settlement stream.

**Step 4: Run tests to verify they pass**

Run: `flutter test test/features/groups/providers/group_presettle_review_provider_test.dart test/features/groups/group_settle_up_review_sheet_test.dart`
Expected: PASS — all pre-existing and all new cases.

**Step 5: Analyze and commit**

Run: `flutter analyze` — expected clean.

```bash
git add lib/features/groups/providers/group_presettle_review_provider.dart test/features/groups/providers/group_presettle_review_provider_test.dart test/features/groups/group_settle_up_review_sheet_test.dart
git commit -m "feat(settle-up): viewer watermark at group settle-up entry (#1058)"
```

---

### Task 4: Full verification + PR

**Step 1: Full suite**

Run: `flutter test`
Expected: all green (baseline 3410+ tests).

Run: `flutter analyze`
Expected: clean.

Run: `bash tool/check_theme_purity.sh`
Expected: PASS (no styling was touched; CI-only check, run locally per contract).

**Step 2: Push and open the PR**

```bash
git push -u origin fix/presettle-viewer-watermark
gh pr create \
  --title "fix(settle-up): suppress pre-settle flags the viewer already settled past (#1058)" \
  --body "$(cat <<'PRBODY'
Closes #1058

Spec: docs/plans/2026-07-09-presettle-viewer-watermark.md (Gate-reviewed)

## Summary
- New pure filter `suppressFlagsSettledPastByViewer` in `pre_settlement_review.dart`: drops a review flag when the viewer was party to a live settlement (excl. soft-deleted, #889 marked corrections, and their targets) in the flag's currency newer than the expense.
- Applied at both entry points (detect → #922 bucket filter → viewer watermark). Group scope is TWO-STAGE (Gate R1): stage A event-local (an event's flags vs that event's settlements — mirrors the event screen), stage B group-engagement (group-level docs + groupSettleUpId-tagged legs suppress group-wide). An untagged settlement in one event never silences another event's flags. `resolved` now also gates on the group settlement stream.
- Display-only: no server/rules/oracle/schema change. Fresh joiners still see every warning.

## Test plan
- RED-first unit table (11 cases: direction/currency/identity/correction/time axes).
- Event widget tests: outstanding-but-settled-past suppressed; newer expense fires; third-party settlement fires.
- Group provider tests: event + group settlement watermark, fresh-joiner keeps flags, loading gate; group widget end-to-end case.
- Full suite + analyze + theme purity green.
PRBODY
)"
```

Ensure the final squash commit body carries `Closes #1058` (amend if needed — the PR body alone does not auto-close).

**Step 3: Automerge**

Run `/automerge <PR#>`. Classification note for the reviewer: touches `lib/features/ledger/**` money-display neighborhood — expect Gate-category routing (fresh review + refuter), not exemption.

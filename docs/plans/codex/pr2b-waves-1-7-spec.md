# Task: PR2b Waves 1–7 — Arabic localization of the Ledger surface

## Context

This is a continuation spec for PR2b (Arabic localization of the Ledger surface) on branch `feat/l10n-pr2b-ledger`, Rihla Flutter app (package `safar`). Wave 0 (foundation) is already landed at commit `485b1fe`. The Wave 0 spec is `docs/plans/codex/pr2b-wave-0-spec.md` — read it for tone, conventions, and gate anchors.

**Authoritative sources** (read these first; they have been cleared by 3 rounds of codex spec-gate review at 55756fd, fc9da48, d95bafb):

- Design doc: `docs/plans/2026-05-18-arabic-localization-pr2b-ledger-design.md`
- Implementation plan (wave-by-wave with code skeletons): `docs/plans/2026-05-18-arabic-localization-pr2b-ledger.md`

This spec is a thin wrapper that **enforces commit cadence + the gate-anchored invariants** across all six remaining waves. The implementation plan is the ground truth for which strings to translate, which keys to use, and which RTL fixes apply where. If this spec and the implementation plan ever disagree, **the implementation plan wins** — flag the divergence in your report.

## Goal

Land Waves 1–7 of PR2b as **seven separate atomic commits** on `feat/l10n-pr2b-ledger`, on top of `485b1fe`. Each commit is one wave. After Wave 7 verification passes, **STOP — do NOT push, do NOT open the PR**. The human will review the full branch diff before pushing.

## Pre-flight

- Branch: `feat/l10n-pr2b-ledger`. Confirm with `git rev-parse --abbrev-ref HEAD`.
- Top commit MUST be `485b1fe` (Wave 0). Confirm with `git log --oneline -1`. If anything else is on top, STOP and report.
- Read both authoritative plan docs end-to-end before starting Wave 1.

## Universal invariants (apply to every wave)

These are the same gate-anchored anchors from the Wave 0 spec, restated because this run spans six waves and the temptation to "improve while we're in there" compounds:

- **No money math changes.** Do NOT touch `lib/features/ledger/providers/expense_provider.dart` (`BalanceCalculator`), `lib/core/services/money_serializer.dart`, or `lib/shared/widgets/r_amount.dart`. The OMR-only 3dp bug at `r_amount.dart:84` is a deferred follow-up; leave it. The 4 hardcoded-OMR money bugs listed in the design doc's follow-up section are likewise deferred — do not fix them in this run.
- **No bucket-logic changes.** `ledgerCategoryBucket(String? name)` keeps its body and signature UNCHANGED across all waves. Only display names get localized. The substring-matching brokenness for Firestore expenses (`categoryName: null`) is follow-up #8.
- **No router / security / Functions / firebase_options changes.** Do NOT touch `lib/core/router/app_router.dart`, `security/firestore.rules`, anything under `functions/`, or `lib/firebase_options.dart`.
- **No widget splitting / refactoring.** Even though `expense_editor_body.dart` is 1567 LOC, do NOT split it in this run (follow-up #6). Pure-translation only.
- **No `ledgerCategoryBucket` → `categoryId` refactor.** Follow-up #8.
- **Flutter `^3.10.1`, Riverpod 2.x, `decimal` for money, gen-l10n ARB pipeline.** Do not introduce a different l10n library.
- **Dart conventions per CLAUDE.md:** no hardcoded `Color(0xFF…)` outside `lib/core/theme/tokens/`; no `Navigator.push` / `state.extra`; no `context.goNamed` (path strings only); `RAmount` for money; `DateFormat.MMMd(localeTag)` not `DateFormat('MMM d')`.
- **No new comments in code unless the WHY is non-obvious.** Identifier names carry the WHAT. The implementation plan's docstring examples on helpers (e.g., `expense_scope_display_name.dart`) already shipped in Wave 0 — leave them; do not strip Wave 0 docstrings retroactively.
- **No new dependencies.** No `pubspec.yaml` changes.
- **`pumpAndSettle` after `pumpRihlaApp` is banned** (ConnectivityNotifier Timer hangs). Use `await tester.pump()` + explicit pumps. The helper's signature is `pumpRihlaApp(WidgetTester tester, Widget child, {Locale locale, List<Override> overrides})` — no `settings:` parameter.

## Commit cadence — strict

**One commit per wave.** Conventional message: `feat(l10n): PR2b/wave-N — <scope>`. Use the scope from each wave section below.

**Before each commit, the wave's end-of-wave gate MUST pass** (see "Per-wave verification gate" below). If any check fails, STOP and report — do NOT amend, do NOT skip the failing check, do NOT mass-rebase.

**Between waves:** no force-pushes, no rebases, no commit edits. Each wave appears as a new commit on top of the previous wave. `git log --oneline 485b1fe..HEAD` should show exactly N commits after Wave N.

## Per-wave verification gate

Run at the end of every wave, before the wave's commit:

```bash
flutter analyze                                  # zero new warnings vs main @ edfd385
dart run tool/check_arb_completeness.dart        # exit 0, EN ↔ AR parity
flutter test test/features/ledger/               # wave-relevant widget tests pass
flutter test test/unit/                          # unit suite stays green
```

Plus, after Waves 4, 5, 6, 7, also run the **full suite**:

```bash
flutter test                                     # exit 0, full suite
```

(Skipping the full suite on Waves 1–3 is acceptable to keep loop time tight; the full-suite checks at Waves 4/5/6/7 are non-skippable.)

After each commit, run the **diff-invariant grep** to confirm nothing forbidden was touched in this wave:

```bash
git diff 485b1fe..HEAD --stat | grep -E "expense_provider|money_serializer|r_amount|firestore.rules|app_router|firebase_options|functions/" && echo "FAIL: out-of-scope file touched" || echo "OK: invariants preserved"
```

If `FAIL`, STOP and report.

---

## Wave 1 — Small ledger widgets

Commit message: `feat(l10n): PR2b/wave-1 — small ledger widgets`

Follow the **Widget-translation template** in the implementation plan ("## Conventions used in this plan" → "Widget-translation template (Waves 1-6)"). Apply to each file in the Wave 1 table at plan line 530-545.

**Files (9):**
- `lib/features/ledger/widgets/settlement_row.dart`
- `lib/features/ledger/widgets/settlement_tile.dart` (RTL: L97 `Positioned(left: 20, …)` → `PositionedDirectional(start: 20, …)`)
- `lib/features/ledger/widgets/settlement_summary_card.dart`
- `lib/features/ledger/widgets/recorded_settlements_section.dart`
- `lib/features/ledger/widgets/recent_expenses_section.dart`
- `lib/features/ledger/widgets/ledger_sticky_cta.dart`
- `lib/features/ledger/widgets/ledger_roster_strip.dart`
- `lib/features/ledger/widgets/amount_input_section.dart` (`semanticLabel: 'Backspace'` L88 → `commonSemanticBackspace`; `semanticLabel: 'Decimal point'` L97 → `commonSemanticDecimalPoint`)
- `lib/features/ledger/widgets/receipt_picker_section.dart`

Update tests that assert on the English strings touched. Tests stay English-assertions by default because `pumpRihlaApp` defaults `locale` to `Locale('en')`.

Run the wave verification gate. Commit.

---

## Wave 2 — Hero / list widgets

Commit message: `feat(l10n): PR2b/wave-2 — ledger hero, list, success dialog`

**Files (5):** see plan line 555-562.
- `lib/features/ledger/widgets/ledger_hero_block.dart` (RTL: L136 `EdgeInsets.only(right: 3)` → `EdgeInsetsDirectional.only(end: 3)`)
- `lib/features/ledger/widgets/expense_card.dart`
- `lib/features/ledger/widgets/ledger_day_card.dart`
- `lib/features/ledger/widgets/ledger_category_strip.dart` — replace the Wave 0 minimum compile-fix with the full `context.l10n` consumption path (the bucket name flow is already l10n-aware as of Wave 0; finish any remaining hardcoded strings in this file like `'All · 0'` empty state)
- `lib/features/ledger/widgets/expense_success_dialog.dart` (RTL: L36 `Alignment.topRight` → `AlignmentDirectional.topEnd`)

Run wave gate. Commit.

---

## Wave 3 — Sheets

Commit message: `feat(l10n): PR2b/wave-3 — picker, search, custom split sheets`

**Files (3):** see plan line 570-580.
- `lib/features/ledger/widgets/category_picker_sheet.dart` (RTL: L70 `Alignment.centerLeft` → `AlignmentDirectional.centerStart`; consumes `localizedCategoryName` for category labels)
- `lib/features/ledger/widgets/ledger_search_sheet.dart`
- `lib/features/ledger/widgets/custom_split_sheet.dart` (consumes `splitModeDisplayName` at L505-508)

**Pre-flight for `custom_split_sheet.dart`** (per plan line 577-580):

```bash
grep -rn "'Equally'\|'Shares'\|'Exact'\|'Percent'" test/
```

Enumerate test assertions on these strings and update them to whatever the existing `splitModeDisplayName` helper returns (the design doc Q6 wording shift is mentioned in the plan; if `splitModeDisplayName` already exists and returns its own canonical strings, use those — do NOT introduce new ARB keys unless the test grep reveals they're missing).

Run wave gate. Commit.

---

## Wave 4 — Editor cluster (the big one)

Commit message: `feat(l10n): PR2b/wave-4 — expense editor body + thin shells + scope selector`

**Files (5):** see plan line 590-596.
- `lib/features/ledger/widgets/expense_editor_body.dart` (~42 strings). Specific work:
  - **L201 verb-interpolation refactor:** replace `'Failed to $verb expense: $e'` with `editorFailedToAddExpense(error)` / `editorFailedToUpdateExpense(error)` selected by the existing `isEdit` flag.
  - **L512:** `Alignment.centerLeft` → `AlignmentDirectional.centerStart`
  - **L529:** `Alignment.centerRight` → `AlignmentDirectional.centerEnd`
  - Consumes `splitModeDisplayName` (L1144-1146), `expenseScopeDisplayName` (L1058-1061), `localizedCategoryName` for any category badge rendering.
- `lib/features/ledger/screens/add_expense_screen.dart`
- `lib/features/ledger/screens/edit_expense_screen.dart` (delete snackbar + dialog title; uses `commonDelete` from PR2a and `commonCancel`)
- `lib/features/ledger/widgets/split_scope_selector.dart` (consumes `expenseScopeDisplayName`)
- `lib/features/ledger/widgets/category_selection_step.dart` — L115 `category.name` → `localizedCategoryName(id: category.id, fallbackName: category.name, l10n: context.l10n)`. Plus any chrome strings found by string-grep at implementation time.

**Special handling — `expense_editor_body.dart` `'EVENT DEFAULT'` (per plan line 598-603):**

```bash
grep -n "EVENT DEFAULT" lib/features/ledger/widgets/expense_editor_body.dart
```

Inspect 10 lines around each hit. If rendered via `Text(...)`, translate using the existing `editorEventDefault` ARB key (already in Wave 0). If used as an enum/constant comparison only, leave English. Report which case you found.

**Post-wave grep audit (per plan line 604-607):**

```bash
grep -nE "'[A-Z][a-zA-Z][a-zA-Z ]{2,}'" lib/features/ledger/widgets/expense_editor_body.dart | grep -v "context.l10n\|import \|^[0-9]*:\s*///"
```

Only debug strings, brand strings, or comments should remain. Any user-visible English string is a miss — fix and re-grep before committing.

Run wave gate + full suite. Commit.

---

## Wave 5 — Settle-up cluster

Commit message: `feat(l10n): PR2b/wave-5 — settle-up screen + shared groups widgets`

**Files (6):** see plan line 618-624.
- `lib/features/ledger/screens/settle_up_screen.dart` (~12 strings; SnackBars at L241, L283-307, L319 lose `const`; **L349 RTL:** `Alignment.centerLeft` → `AlignmentDirectional.centerStart`)
- `lib/features/groups/widgets/settle_up_page_body.dart` (15 strings; **L393 RTL:** `EdgeInsets.only(left: 4)` → `EdgeInsetsDirectional.only(start: 4)`. The L466 `DateFormat` was already fixed in Wave 0; leave it.)
- `lib/features/groups/widgets/record_payment_sheet.dart` (11 strings; **L469 RTL:** `Alignment.centerLeft` → `AlignmentDirectional.centerStart`)
- `lib/features/groups/widgets/group_settlement_tile.dart` (1 string)
- `lib/features/groups/widgets/all_settled_state.dart` (2 strings)
- `lib/features/groups/widgets/group_settlement_summary.dart` (2 strings + 1 plural). **L32:** `'$count transfer(s)'` → `context.l10n.settleUpSummaryTransfers(count)` — drop the `'$count '` prefix; the plural value embeds the count via ICU `#`. **L36:** `'… total'` suffix — use `settleUpSummaryTotal` with `{amount}` placeholder if a one-key form fits, else split into `settleUpSummaryTotalSuffix` as a separate `Text`.

**Const SnackBar lint mitigation:**

```bash
flutter analyze lib/features/ledger/screens/settle_up_screen.dart
```

If `prefer_const_constructors` fires on inner widgets after the SnackBars lose their outer `const`, mark those inner widgets `const` individually.

**Cross-feature consequence — deliberate, not a regression:** `lib/features/groups/screens/group_settle_up_screen.dart` will render Arabic via the shared widgets translated in this wave. This is the documented shared-widget cascade from design Q1. Do NOT add new English strings to that screen to "undo" the cascade.

Run wave gate + full suite. Commit.

---

## Wave 6 — Timeline + top-level ledger screen

Commit message: `feat(l10n): PR2b/wave-6 — timeline utils + ledger_screen with plural`

### Task 6.1: `lib/features/ledger/utils/ledger_timeline.dart`

Replace any hardcoded month abbreviation indexing with `DateFormat.MMM(localeTag).format(date)`. Replace `'Today · '` / `'Yesterday · '` literals with `timelineToday` / `timelineYesterday` ARB keys (already in Wave 0). Pass `AppLocalizations` into the util's formatting functions (matches the `expenseScopeDisplayName` / `localizedCategoryName` pattern from Wave 0).

### Task 6.2: `lib/features/ledger/screens/ledger_screen.dart`

~18 strings — empty states, error states, tooltips, plus the plural at L423-426.

**Plural replacement (per plan line 700-715):**

Before:
```dart
final captionParts = <String>[
  ?dateRange,
  '$participantCount '
      '${participantCount == 1 ? 'PERSON' : 'PEOPLE'}',
];
```

After:
```dart
final captionParts = <String>[
  ?dateRange,
  context.l10n.ledgerPeopleCount(participantCount),
];
```

**Empty-state prose at L577, L587-588** (per plan line 720-721): inspect the widget tree first. If the two-line break is intentional visual hierarchy, split into 2 ARB keys; if it's just text-flow, concatenate into one key (`ledgerEmptyStateFirstExpenseBody` already exists from Wave 0 covers the multi-line body). Report which you chose.

Run wave gate + full suite. Commit.

---

## Wave 7 — Tests + final clearance

Commit message: `feat(l10n): PR2b/wave-7 — extend Arabic golden-path with ledger walk`

### Task 7.1: EXTEND `integration_test/golden_path_arabic_test.dart`

Read the existing file end-to-end first; match its conventions (`IntegrationTestWidgetsFlutterBinding`, the `SharedPreferences.setMockInitialValues` seed, `app.main()` boot, `_waitFor` / `_settle` / `_log` helpers). DO NOT use `pumpRihlaApp` — the existing test boots the real app, which is the right pattern.

The existing test stops at the `group_create_screen` without entering data. Extend it to **complete the create-group flow, then navigate into the ledger and assert on at least one Arabic string**.

Use the English sibling test `integration_test/golden_path_test.dart:127-148` as the reference for how to fill `group_name_input` + `group_device_name_input` and tap `group_create_button`. The implementation plan at line 757-817 has a ready-to-adapt code block — use it, but **verify each widget key against the actual key constants in `lib/features/groups/keys/group_keys.dart` and `lib/features/events/keys/`** before pasting. If a key doesn't exist or has a different name, report and stop — do not invent.

**Fallback** (per plan line 821): if the create-group flow proves fragile in `ar`, scope the new assertion down to verifying `group_create_screen` itself renders Arabic copy, or assert on an Arabic Settings/Profile string via deep-link navigation. Report the fallback if you take it.

### Task 7.2: Final clearance

Run, in order, all of the following. STOP on first failure.

```bash
flutter analyze
# zero new warnings vs main @ edfd385

flutter test
# exit 0, full suite, all green

dart run tool/check_arb_completeness.dart
# exit 0

git diff main...HEAD --stat | grep -E "expense_provider|money_serializer|r_amount|firestore.rules|app_router|firebase_options|functions/"
# expected: empty (no out-of-scope file touched across the entire branch)

git log --oneline 485b1fe..HEAD
# expected: exactly 7 lines, one per wave, in order

flutter test integration_test/golden_path_arabic_test.dart -d <sim-id> --dart-define-from-file=config.test.json
# optional during your run if no device is attached — flag as 'pending human-run' in your report
```

### Task 7.3: Commit Wave 7

```bash
git add integration_test/golden_path_arabic_test.dart
git commit -m "feat(l10n): PR2b/wave-7 — extend Arabic golden-path with ledger walk"
```

### Task 7.4: STOP

**Do NOT push.** **Do NOT run `gh pr create`.** **Do NOT amend any earlier commit.**

Report back with:
- `git log --oneline 485b1fe..HEAD` output (must be exactly 7 lines)
- `git diff main...HEAD --stat` summary
- Which optional checks were skipped (e.g., integration test if no device available)
- Any deviations from the implementation plan, with reasons
- Any open questions you hit (e.g., `EVENT DEFAULT` resolution, empty-state 1-key vs 2-key choice, integration test fallback if taken)

The human will review the full branch diff and handle `git push` + `gh pr create`.

---

## Files NOT to touch (universal — applies to all waves)

- `lib/features/ledger/providers/expense_provider.dart` (`BalanceCalculator`)
- `lib/core/services/money_serializer.dart`
- `lib/shared/widgets/r_amount.dart`
- `lib/core/router/app_router.dart`
- `security/firestore.rules`
- `functions/` (Cloud Functions)
- `lib/firebase_options.dart`
- `pubspec.yaml` / `pubspec.lock`
- `lib/features/events/widgets/event_card.dart` and `lib/features/events/widgets/event_details_card.dart` — these have `DateFormat('MMM d')` / `DateFormat('MMM d, yyyy')` callsites but events feature is OUT OF PR2b SCOPE. Leave them.
- Anything under `lib/features/auth/`, `lib/features/onboarding/`, `lib/features/settings/`, `lib/features/profile/`, `lib/features/home/` — PR1 and PR2a already handled these surfaces; further translation work there is out of PR2b scope.

## Out of scope (filed as follow-ups in the design doc)

1. `r_amount.dart:84` — OMR-only 3dp rule
2. `settle_up_screen.dart:221` — group-currency lookup
3. `ledger_hero_block.dart:262` — hardcoded `'OMR'` prefix
4. `expense_editor_body.dart:111` — `_tripCurrency => 'OMR'`
5. `transaction_model.dart` — remove dead `description` field
6. `expense_editor_body.dart` 1567-LOC split
7. `docs/REAL-DEVICE-QA.md` RD-09 — Arabic RTL real-device QA pass
8. `ledgerCategoryBucket` → `categoryId` refactor (Firestore expenses bucket to Other today)

Do not attempt any of these in this run. If you encounter the underlying broken behaviour while translating, leave the existing English-rendering bug in place; the translation is display-only.

---

## If anything seems wrong, STOP and report

The plan was gate-cleared against the codebase at d95bafb. Wave 0 (485b1fe) verified the foundation. If during Waves 1–7 you find:

- A widget key name in `lib/features/*/keys/` that contradicts what the plan references → STOP, report, do not invent
- A line-number reference (`L201`, `L466`, etc.) that no longer matches the actual file (Wave 0 auto-formatter shifted some line numbers in `expense_editor_body.dart` — adjust to actual current line numbers, do NOT assume the plan's numbers are still authoritative)
- An ARB key the plan calls for that doesn't exist in the Wave 0 inventory → grep `lib/l10n/app_en.arb` first; if genuinely missing, add the en+ar pair in the SAME wave commit that introduces the consumer (don't batch a separate "Wave 0.5")
- A test asserting on an English string that the plan didn't anticipate → update the test to the new key's English value, don't skip the translation
- A widget that imports / depends on something in the "Files NOT to touch" list and would require changing that file to translate → STOP, report

Do not improvise around the invariants. The implementation plan is gate-cleared; deviating without flagging is the disaster mode this multi-round gate exists to prevent.

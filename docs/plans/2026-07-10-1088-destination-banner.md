# #1088 — Surface the auto-picked destination at the top of the add-expense editor

> **For Claude:** Delegated implementation (Codex executes; the delegating session re-verifies everything — Codex's sandbox cannot run `flutter test`, so no green/RED claim from Codex is trusted).

**Goal:** In ADD mode, a one-line tappable "Adding to {event} · change" banner sits directly under the editor top bar, so a multi-group user sees (and can redirect) the FAB's auto-picked destination before entering any data. The #900 fast path, `preferred` ranking, `WhereCard`, and `_handleChangeDestination` flow are all untouched.

**Architecture:** New leaf widget `DestinationBanner` (own file, per house style) rendered in `ExpenseEditorBody`'s fixed header column between `ExpenseTopBar` and `OfflineBanner`, gated on `!_isEdit && event != null`. Tap = the existing `_handleChangeDestination` (dirty-form discard confirm → `AddExpenseTargetSheet.show(context, replaceCurrent: true)`). Reuses the existing l10n keys `editorAddingToEvent` / `editorChangeDestination` — NO new ARB strings, no translation churn.

**Tech stack:** Flutter, Riverpod 2.x. Tests mirror the existing editor harnesses: `test/features/ledger/expense_editor_discard_guard_test.dart` (dirty-form discard flow) and `test/features/home/add_expense_fab_navigation_test.dart` (spec §1 test d — the WhereCard change affordance; your banner test is its top-of-screen twin).

**Constraints (project contract — read carefully, several are CI tripwires):**
- Styling ONLY via `context.colors` / `context.spacing` / `AppTypography` — a hardcoded `Color(0xFF…)` or a bare `.textMuted` read fails the CI-only theme-purity gate.
- RTL: `EdgeInsetsDirectional` / `AlignmentDirectional` only.
- A11y (fresh #1067/#1077 work — do not regress): the banner is ONE tap target, min height 44dp, `Semantics(button: true)` with a label covering both the destination and the change affordance.
- Text scale: must stay a single line at 1.5x scale — event name ellipsizes (`Flexible` + `TextOverflow.ellipsis`), the "· change" suffix never wraps (#1083 pattern).
- `Closes #1088` in the COMMIT MESSAGE body.
- `prefer_const_constructors` fails CI — mark const-eligible literals `const`.

---

### Task 1: Failing tests

**Files:**
- Create: `test/features/ledger/destination_banner_1088_test.dart`
- Read first: `test/features/ledger/expense_editor_discard_guard_test.dart` (harness: how the editor is pumped with providers/event), `lib/features/ledger/keys/ledger_keys.dart`

Cases (one shared harness; use `LedgerKeys.editorDestinationBanner` as the finder):
1. `'add mode shows the destination banner under the top bar (#1088)'` — pump the add editor with a resolved event named e.g. `Salalah Trip`; assert the banner exists, renders `Adding to Salalah Trip`, and sits ABOVE the scroll view (e.g. `tester.getTopLeft(banner).dy < tester.getTopLeft(find.byType(SingleChildScrollView)).dy`). Assert the WhereCard section still exists (banner is additive).
2. `'banner tap on a pristine form opens the target picker (#1088)'` — tap the banner; assert `AddExpenseTargetSheet` is shown (mirror how spec §1 test d asserts the change-button flow in `add_expense_fab_navigation_test.dart`; reuse its provider setup for targets).
3. `'banner tap on a dirty form confirms discard first (#1088)'` — enter an amount, tap the banner, assert the discard dialog appears (mirror `expense_editor_discard_guard_test.dart`); cancel keeps the editor.
4. `'edit mode has no banner (#1088)'` — pump edit mode; `findsNothing`.
5. `'banner is one line at 1.5x text scale (#1088)'` — wrap with `MediaQuery(textScaler: TextScaler.linear(1.5))` (or the harness's established pattern — see `test/core/text_scale_policy_test.dart`); assert no overflow errors and the banner `Text` has `maxLines: 1`.
6. `'banner has button semantics naming destination and change (#1088)'` — `tester.ensureSemantics()` (dispose the handle IN the test body, before teardowns — binding verifies handles before `tearDown` runs); assert a semantics node with `button: true` whose label contains the event name.

**Run:** expect FAIL (`LedgerKeys.editorDestinationBanner` doesn't exist yet — this is a compile-error RED, which is acceptable for a feature; note it). Commit: `test(ledger): RED — destination banner spec (#1088)`.

### Task 2: The widget + wiring

**Files:**
- Create: `lib/features/ledger/widgets/expense_editor/destination_banner.dart`
- Modify: `lib/features/ledger/keys/ledger_keys.dart` (add key, match existing naming style: `static const editorDestinationBanner = Key('ledger_editor_destination_banner');`)
- Modify: `lib/features/ledger/widgets/expense_editor_body.dart:876-889` (header column)

**Step 1: The widget** (adjust imports to match `where_card.dart`'s relative-import style):

```dart
import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../events/models/event_model.dart';
import '../../keys/ledger_keys.dart';

/// #1088: add-mode destination disclosure pinned under the top bar. The FAB
/// fast path (#900 §1) auto-picks an event; the only other disclosure
/// (WhereCard) is the last scroll section — below the fold on a phone.
class DestinationBanner extends StatelessWidget {
  const DestinationBanner({
    super.key,
    required this.event,
    required this.onChangeDestination,
  });

  final Event event;
  final VoidCallback onChangeDestination;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.editorAddingToEvent(event.name);
    final change = context.l10n.editorChangeDestination;
    return Semantics(
      button: true,
      label: '$label, $change',
      child: ExcludeSemantics(
        child: InkWell(
          key: LedgerKeys.editorDestinationBanner,
          onTap: onChangeDestination,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: AlignmentDirectional.centerStart,
            padding: EdgeInsetsDirectional.only(
              start: context.spacing.space24,
              end: context.spacing.space24,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.sans(
                      fontSize: 13,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  ' · $change',
                  maxLines: 1,
                  style: AppTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.colors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

If the recent a11y sites (#1077 — see `lib/shared/widgets/section_header.dart` post-merge) use a different Semantics composition (e.g. `MergeSemantics`), mirror THAT pattern instead of the above `Semantics+ExcludeSemantics` — consistency with the fresh sweep wins.

**Step 2: Wiring** in `expense_editor_body.dart` — after `ExpenseTopBar(...)` (line ~888), before `const OfflineBanner()`:

```dart
              if (!_isEdit && event != null)
                DestinationBanner(
                  event: event,
                  onChangeDestination: _handleChangeDestination,
                ),
```

(`event` is the already-resolved local in `build`; while it's null the banner simply isn't there — no placeholder.)

**Step 3:** Run the new test file → green. Then the blast-radius sweep:
- `grep -rn "editorAddingToEvent\|Adding to\|editorChangeDestination" test/` — any test asserting `findsOneWidget` on that string now sees TWO (banner + WhereCard). Fix by scoping the finder (ancestor `WhereCard` / banner key), never by weakening to `findsWidgets`.
- The banner shrinks the scrollable viewport by ~44px in add mode — editor tests that tap below-the-fold elements without scrolling may start missing. Run `flutter test test/features/ledger/ test/features/home/add_expense_fab_navigation_test.dart`; fix any such site with `scrollUntilVisible` (house pattern, see home tests post-#1078).

**Step 4:** `flutter analyze` clean.

**Step 5: Commit:**

```
feat(ledger): destination banner under the add-expense top bar

The FAB fast path auto-picks an event; disclosure lived only in the
last scroll section. One-line "Adding to {event} · change" row, add
mode only, reusing the existing change-destination flow and l10n keys.

Closes #1088
```

### Task 3: Report

Final message: files changed, test names, exact commands run (or not runnable) + output, any existing tests you had to touch and WHY (scoped finder vs behavior change). Do NOT claim green you didn't see. If git metadata was read-only, leave a `git bundle` at the worktree root and say so.

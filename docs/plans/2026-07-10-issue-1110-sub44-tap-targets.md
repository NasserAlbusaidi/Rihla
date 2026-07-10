# Issue #1110 Residual Tap Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise the six empirically confirmed residual tap-target sites to at least 44dp while retaining each control's compact painted dimensions.

**Architecture:** Keep the existing public widget APIs and visual styling. Separate the interaction layer from the painted child for bare `InkWell` controls, and restore Material's padded input region for `TextButton` controls while leaving their 40dp minimum-size styling intact.

**Tech Stack:** Flutter, Dart, `flutter_test`, Material 3, Riverpod test overrides.

## Global Constraints

- Write and run all `#1110` regression tests before changing production widget code; preserve the exact RED output for the PR.
- Every effective hit target must be at least 44dp in both constrained dimensions.
- Preserve the current painted measurements: group-detail pills 42dp high, category pills 42dp high, shares-stepper track 36dp high with 16px icons, and settle-up button styles with `minimumSize: Size(0, 40)`.
- Do not modify `security/firestore.rules`, `functions/**`, or any `**/models/**.dart`; if a required fix reaches one of those paths, stop and write `BLOCKED.md`.
- Do not add raw color literals or unrelated refactors. Run `bash tool/check_theme_purity.sh` because production widget files change.
- The final conventional commit body must contain `Closes #1110`; push `fix/1110-sub44-tap-targets` and create one PR with summary, `Closes #1110`, exact commands/results, and verbatim RED evidence.

---

### Task 1: Add Effective-Hit-Region Regression Coverage

**Files:**
- Modify: `test/features/groups/group_detail_navigation_test.dart`
- Create: `test/features/ledger/expense_editor_category_tap_target_1110_test.dart`
- Modify: `test/features/ledger/custom_split_sheet_test.dart`
- Modify: `test/features/groups/group_settle_up_screen_test.dart`
- Modify: `test/features/groups/settle_up_correction_test.dart`

**Interfaces:**
- Consumes: existing public screen/widget harnesses, `GroupKeys`, and rendered `InkWell`/`TextButton` boxes.
- Produces: seven `#1110` assertions covering New event, Settle up, category chip, shares minus/plus, Record payment, Correct, and Share receipt.

- [ ] **Step 1: Add the two group-detail CTA tests**

```dart
final target = find
    .ancestor(of: find.text('New event'), matching: find.byType(InkWell))
    .first;
expect(
  tester.getSize(target).height,
  greaterThanOrEqualTo(44),
  reason: 'New event effective hit target must be at least 44dp',
);

expect(
  tester.getSize(find.byKey(GroupKeys.settleUpCta)).height,
  greaterThanOrEqualTo(44),
  reason: 'Settle up effective hit target must be at least 44dp',
);
```

- [ ] **Step 2: Add the expense-category chip test**

```dart
final target = find.byType(InkWell).first;
expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
final icon = tester.widget<Icon>(find.descendant(
  of: target,
  matching: find.byType(Icon),
).first);
expect(icon.size, 11);
```

- [ ] **Step 3: Add the shares-stepper test**

```dart
for (final glyph in [Icons.remove, Icons.add]) {
  final target = find
      .ancestor(of: find.byIcon(glyph).first, matching: find.byType(InkWell))
      .first;
  expect(tester.getSize(target), const Size(44, 44));
  expect(tester.widget<Icon>(find.byIcon(glyph).first).size, 16);
}
```

- [ ] **Step 4: Add settle-up TextButton tests**

```dart
final target = find.byKey(GroupKeys.settleUpRecordPaymentButton);
expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
expect(
  tester.widget<TextButton>(target).style!.minimumSize!.resolve({}),
  const Size(0, 40),
);
```

Repeat the same effective-size and retained-minimum-size assertions separately for `GroupKeys.settleUpCorrectButton` and `GroupKeys.settleUpShareReceiptButton`.

Use two tests so the RED run proves each control independently:

```dart
void expectCompactButtonMeetsFloor(WidgetTester tester, Key key) {
  final target = find.byKey(key);
  expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
  expect(
    tester.widget<TextButton>(target).style!.minimumSize!.resolve({}),
    const Size(0, 40),
  );
}

testWidgets('#1110 Correct meets the 44dp floor', (tester) async {
  await tester.pumpWidget(_host(_bodyWithHistory(onCorrect: (_) {})));
  await tester.pumpAndSettle();
  expectCompactButtonMeetsFloor(tester, GroupKeys.settleUpCorrectButton);
});

testWidgets('#1110 Share receipt meets the 44dp floor', (tester) async {
  await tester.pumpWidget(_host(_bodyWithHistory(onCorrect: (_) {})));
  await tester.pumpAndSettle();
  expectCompactButtonMeetsFloor(
    tester,
    GroupKeys.settleUpShareReceiptButton,
  );
});
```

- [ ] **Step 5: Run only the new assertions and verify RED**

Run:

```bash
flutter test \
  test/features/groups/group_detail_navigation_test.dart \
  test/features/ledger/expense_editor_category_tap_target_1110_test.dart \
  test/features/ledger/custom_split_sheet_test.dart \
  test/features/groups/group_settle_up_screen_test.dart \
  test/features/groups/settle_up_correction_test.dart \
  --plain-name '#1110' --reporter expanded
```

Expected: exit 1; failures report 42dp, 36dp, or 40dp effective targets rather than setup errors. Save the output verbatim.

### Task 2: Grow Only the Interaction Layers

**Files:**
- Modify: `lib/features/groups/screens/group_detail_screen.dart`
- Modify: `lib/features/ledger/widgets/expense_editor/category_strip.dart`
- Modify: `lib/features/ledger/widgets/custom_split_sheet_editors.dart`
- Modify: `lib/features/ledger/widgets/custom_split_sheet_mode_selector.dart`
- Modify: `lib/features/groups/widgets/group_settlement_tile.dart`
- Modify: `lib/features/groups/widgets/settle_up_page_body.dart`

**Interfaces:**
- Consumes: the existing callbacks, keys, border radii, colors, padding, and icon sizes unchanged.
- Produces: interactive render boxes at or above 44dp; no callback, persistence, routing, copy, or semantic-contract changes.

- [ ] **Step 1: Separate group-detail hit boxes from 42dp painted pills**

Use a transparent `Material`/`InkWell` interaction layer with a minimum 44dp child and center each 42dp decorated container inside it. The primary control becomes:

```dart
return Material(
  color: Colors.transparent,
  borderRadius: BorderRadius.circular(spacing.radiusMedium),
  child: InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(spacing.radiusMedium),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Center(
            child: Ink(
              height: 42,
              decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(spacing.radiusMedium),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: colors.textOnPrimary),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textOnPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);
```

The secondary control uses the same transparent 44dp interaction layer; its inner 42dp `Ink` keeps `color: colors.cardSoft`, the existing `rule` border, radius, label style, and `GroupKeys.settleUpCta` on the `InkWell`. Using `Ink` retains visible splash feedback above the painted fill.

- [ ] **Step 2: Raise the category strip to 44dp around its 42dp pill**

```dart
return SizedBox(
  height: 44,
  child: ListView.separated(
    padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
    scrollDirection: Axis.horizontal,
    itemCount: sorted.length,
    separatorBuilder: (_, _) => const SizedBox(width: 8),
    itemBuilder: (context, index) {
      final category = sorted[index];
      return _CategoryChip(
        category: category,
        selected: selectedCategoryId == category.id,
        onTap: () => onCategorySelected(category.id),
      );
    },
  ),
);

return InkWell(
  onTap: onTap,
  borderRadius: BorderRadius.circular(999),
  child: Center(
    child: Container(
      height: 42,
      padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 12, 8),
      decoration: BoxDecoration(
        color: selected
            ? context.colors.textPrimary
            : context.colors.cardSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? context.colors.textPrimary : context.colors.rule2,
        ),
        boxShadow: selected ? context.shadows.flat : context.shadows.raised,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: selected
                  ? context.colors.scaffoldBackground.withValues(alpha: 0.18)
                  : context.colors.cardSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              categoryIconForId(category.id),
              size: 11,
              color: selected ? context.colors.scaffoldBackground : color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            displayName,
            style: AppTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected
                  ? context.colors.scaffoldBackground
                  : context.colors.ink2,
            ),
          ),
        ],
      ),
    ),
  ),
);
```

- [ ] **Step 3: Overlay 44dp stepper hit boxes on the 36dp track**

Keep the editor's 124dp width, center the existing 36dp decorated track in a 44dp stack, retain the value's 32dp slot and icon positions, and place each `_StepperButton` in a directional 44-by-44 region. Reduce only the shares row's outer vertical padding from 12dp to 8dp so the row's total height and painted coordinates remain unchanged.

```dart
return SizedBox(
  height: 44,
  child: Stack(
    children: [
      PositionedDirectional(
        start: 0,
        end: 0,
        top: 4,
        bottom: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colors.rule2),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      PositionedDirectional(
        start: 0,
        top: 0,
        bottom: 0,
        width: 44,
        child: _StepperButton(
          icon: Icons.remove,
          enabled: value > 0,
          visualAlignment: AlignmentDirectional.centerStart,
          onTap: () {
            HapticService.selection();
            onChanged((value - 1).clamp(0, 99));
          },
        ),
      ),
      PositionedDirectional(
        start: 36,
        top: 0,
        bottom: 0,
        width: 32,
        child: Center(
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: AppTypography.mono(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
      PositionedDirectional(
        start: 64,
        top: 0,
        bottom: 0,
        width: 44,
        child: _StepperButton(
          icon: Icons.add,
          enabled: value < 99,
          onTap: () {
            HapticService.selection();
            onChanged((value + 1).clamp(0, 99));
          },
        ),
      ),
    ],
  ),
);

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.visualAlignment = Alignment.center,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final AlignmentGeometry visualAlignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Align(
        alignment: visualAlignment,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 16,
            color: enabled ? colors.textPrimary : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
```

In `_ParticipantRow`, use `space8` vertical padding only for `SplitMode.shares` and keep `space12` for all other modes:

```dart
padding: EdgeInsets.symmetric(
  vertical: mode == SplitMode.shares
      ? context.spacing.space8
      : context.spacing.space12,
),
```

- [ ] **Step 4: Restore Material padding for settle-up buttons**

```dart
// Record payment: retain minimumSize/padding/shape.
tapTargetSize: MaterialTapTargetSize.padded,

// Correct and Share receipt: retain minimumSize/padding/foreground.
visualDensity: VisualDensity.standard,
```

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run the Task 1 command again. Expected: exit 0 and all seven `#1110` tests pass.

### Task 3: Verify and Publish the Branch

**Files:**
- Verify all branch changes; do not add generated files or golden updates.

**Interfaces:**
- Consumes: the complete branch diff and the clean baseline.
- Produces: one conventional commit, one pushed branch, and one draft PR.

- [ ] **Step 1: Format and run focused verification**

The installed formatter rewrites unrelated legacy layout in existing files, so preserve their baseline formatting and format only the new standalone test:

```bash
dart format test/features/ledger/expense_editor_category_tap_target_1110_test.dart
```

- [ ] **Step 2: Run all required checks**

```bash
flutter test
flutter analyze
bash tool/check_theme_purity.sh
```

Expected: 0 failures, 0 analysis issues, and theme-purity PASS.

- [ ] **Step 3: Review exact scope and forbidden paths**

```bash
git status --short
git diff --check
git diff --name-only
git diff -- security/firestore.rules functions ':(glob)**/models/**.dart'
```

Expected: no forbidden-file diff, no whitespace errors, and only the planned files.

- [ ] **Step 4: Commit with the required issue-closing body**

```bash
git add \
  docs/plans/2026-07-10-issue-1110-sub44-tap-targets.md \
  test/features/groups/group_detail_navigation_test.dart \
  test/features/ledger/expense_editor_category_tap_target_1110_test.dart \
  test/features/ledger/custom_split_sheet_test.dart \
  test/features/groups/group_settle_up_screen_test.dart \
  test/features/groups/settle_up_correction_test.dart \
  lib/features/groups/screens/group_detail_screen.dart \
  lib/features/ledger/widgets/expense_editor/category_strip.dart \
  lib/features/ledger/widgets/custom_split_sheet_editors.dart \
  lib/features/ledger/widgets/custom_split_sheet_mode_selector.dart \
  lib/features/groups/widgets/group_settlement_tile.dart \
  lib/features/groups/widgets/settle_up_page_body.dart
git commit -m 'fix(a11y): raise residual tap targets to 44dp' \
  -m 'Closes #1110'
```

- [ ] **Step 5: Push and open the PR**

```bash
git push -u origin fix/1110-sub44-tap-targets
gh pr create --draft --base main --head fix/1110-sub44-tap-targets \
  --title 'fix(a11y): raise residual tap targets to 44dp' \
  --body-file /tmp/rihla-pr-1110.md
```

The PR body must include the root cause, concise change summary, `Closes #1110`, the verbatim RED output, and exact focused/full/analyze/theme-purity results.

# Activity UI Consistency Pass Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** One shared activity-row/chrome vocabulary across the four activity surfaces (per-event feed, group timeline, cross-group tab, home RECENTLY) + the approved V2 grain-and-wash backdrop — executing the #490 row half and mockup `docs/design/mockups/activity-ui-polish.html` (all decisions LOCKED 2026-07-04, posted to #490).

**Architecture:** New shared, model-free display primitives under `lib/shared/` (`ActivityRow` + `ActivityGlyph`/`ActivityCategoryIcon`, `ActivityDaySection`, `ActivityFilterStrip`, `CaptionTitleBar`, `PaperBackdrop`, a generic `groupByDay` util). Each feed keeps its own data model (`ActivityLog` / `GroupActivityLog`) and maps to the primitives via a small per-feed adapter — no model unification, no provider changes, no write paths.

**Tech Stack:** Flutter, Riverpod (untouched), existing token system (`context.colors|spacing|shadows|motion`), `RAmount`, `GrainOverlay`, `TapBounce`, `DirectionalIcon`, mocktail/FakeFirebaseFirestore for tests.

---

## Locked decisions (do not relitigate)

| # | Decision | Source |
|---|---|---|
| D-a | Category icon is the canonical row leading; home RECENTLY **drops its avatar** | #490 mockup + issue comment 2026-07-04 |
| D-b | Group context renders as the bordered **tag chip** everywhere (home + cross-group) | mockup §3 |
| D-c | Background = **V2 grain + `paperDeep→paper` wash** on all three routed feeds; V3 cover blend reserved | mockup §4 |
| D-d | Flat card on per-event feed (#866), raised on tappable feeds (#807) — **unchanged** | prior art |
| D-e | Ink-filled active filter pills — **unchanged** (app-wide convention; #490 saffron-chip half stays dropped) | #490 |
| D-f | Day headers show the dot-date everywhere: `TODAY · JUL 4` | mockup §1/§3 |
| D-g | Per-event rows: eventType→glyph (add=saffron receipt-add · edit=neutral receipt-edit · delete=muted receipt-minus), trailing `RAmount`, CREATE/DELETE summary line dropped, audit chip only on UPDATE-with-field-change | mockup §1 |

**Gate status: SKIPPED — named exemption.** No `BalanceCalculator`/`MoneySerializer` change (amounts are consumed as already-parsed `Decimal`s), no `firestore.rules`/Functions, no schema/field-name change, no route-tree or back-guard *semantics* change (back handlers are moved verbatim behind a callback). Every callsite touched is INBOUND/display-only. If any task drifts into those categories, stop and run `/run-the-gate`.

**Verified-against-code claims** (re-run 2026-07-04 after v1.7.3 merged):
- Activity surfaces unchanged since review (last touch `bab1bf17` #867).
- `ExpenseAuditSnap` carries `amount: Decimal` + `currency: String` (`expense_audit_diff.dart`); `diff.after` present for every trigger-written entry, `null` for legacy → row falls back to verb-only.
- Home call site: `home_screen.dart:235` (`ActivityRow(activity:, groupName:, groupId:, onTap:)`).
- Both `activityFilterSettles` (en:1578) and `activityFilterSettlements` (en:1579) exist with identical values in en+ar → unify on `activityFilterSettlements`.
- `radiusSmall: 8` (`spacing_tokens.dart:87`), `TapBounce` (`lib/shared/animations/tap_bounce.dart`), `DirectionalIcon` (`lib/shared/widgets/directional_icon.dart`, **zero** uses in the three feeds today), `SkeletonLoader.expenseList({int count = 5})`, `RAmount({required value, currency='OMR', showCurrency=true, size=16, tone=auto})`.
- **GrainOverlay correction:** `GrainOverlay` = `DecoratedBox` (decoration paints *behind* child). Tab screens paint opaque `Scaffold` backgrounds, so the shell-level `GrainOverlay` in `bottom_nav_shell.dart:102` is covered and effectively invisible. `PaperBackdrop` therefore wraps each screen's **body content** (above the scaffold paint), which makes texture actually visible and is uniform across tab/route entry by construction.
- No activity golden tests exist; `home_golden_test.dart` exists → PR 4 may need a macOS golden regen if it snapshots RECENTLY rows.

**Test gotchas that WILL bite here** (from CLAUDE.md):
- Any widget test ending on an empty/error state (`EmptyStateView`, `_ErrorView`) must `pumpAndSettle()` (flutter_animate ticker) — but `pumpRihlaApp` tests must NOT `pumpAndSettle` (ConnectivityNotifier timer).
- Removing UI (avatar, summary line): grep tests for the removed label/key and **delete** obsolete assertions.
- `bash tool/check_theme_purity.sh` locally before every push — new widget files silently drop justification comments when copied (CI-only check).
- Paginated `ListView.builder` tests: assert a page-2-only row becomes findable; `Text.rich` rows need `find.textContaining(..., findRichText: true)`.

---

## PR sequencing (one concern per PR, each independently green)

1. **PR 1** `feat(shared): activity feed primitives` — new widgets + unit/widget tests, zero screen changes.
2. **PR 2** `feat(activity): per-event feed adopts shared vocabulary` — mockup §1 + P1.
3. **PR 3** `feat(groups): group timeline journal header + shared chrome` — mockup §2 + P2/P4/P7 + skeleton footer.
4. **PR 4** `feat(home): cross-group tab + RECENTLY on shared row` — mockup §3 + D-a/D-b + P3/P6 leftovers.
5. **PR 5** `feat(shared): PaperBackdrop V2 on the three feeds` — mockup §4.

Branch per PR off fresh `main`; PR bodies carry `Refs #490` (PRs 1–4; the #490 row-half checkbox closes only when PR 4 merges — that PR body says `Closes #490` **in the squash commit body too**), `Spec: docs/plans/2026-07-04-activity-ui-consistency.md`. Every PR through `/automerge`, never raw merge.

---

## PR 1 — shared activity primitives

**Files:**
- Create: `lib/shared/widgets/activity_glyph.dart`
- Create: `lib/shared/widgets/activity_row.dart`
- Create: `lib/shared/widgets/activity_day_section.dart`
- Create: `lib/shared/widgets/activity_filter_strip.dart`
- Create: `lib/shared/widgets/caption_title_bar.dart`
- Create: `lib/shared/widgets/paper_backdrop.dart`
- Create: `lib/core/utils/day_grouping.dart`
- Test: `test/shared/activity_primitives_test.dart`, `test/unit/day_grouping_test.dart`

### Task 1.1: `ActivityGlyph` + `ActivityCategoryIcon`

**Step 1: Write the failing test** (`test/shared/activity_primitives_test.dart`)

```dart
testWidgets('ActivityCategoryIcon renders per-glyph icon and radiusSmall tile', (tester) async {
  await tester.pumpWidget(wrapWithTheme(
    const ActivityCategoryIcon(glyph: ActivityGlyph.expenseAdded)));
  expect(find.byIcon(Iconsax.receipt_add), findsOneWidget);
  final box = tester.widget<Container>(find.byType(Container)).decoration! as BoxDecoration;
  expect(box.borderRadius, BorderRadius.circular(8));
});
```

(`wrapWithTheme` = existing helper pattern in `test/helpers/`; reuse, don't reinvent.)

**Step 2:** `flutter test test/shared/activity_primitives_test.dart` → FAIL (no such file).

**Step 3: Implement** `lib/shared/widgets/activity_glyph.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/theme/tokens/domain_aliases.dart';

/// Unified activity-row leading vocabulary (#490 + activity-ui-polish §1).
/// Per-feed adapters map their log models onto these; the icon widget owns
/// the color/glyph table so all four feeds render identically.
enum ActivityGlyph {
  expenseAdded, expenseEdited, expenseDeleted,
  settlement,
  eventCreated, eventDeleted,
  memberJoined, memberLeft,
  generic,
}

class ActivityCategoryIcon extends StatelessWidget {
  const ActivityCategoryIcon({super.key, required this.glyph});
  final ActivityGlyph glyph;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sageSoft = Color.alphaBlend(
      colors.success.withValues(alpha: 0.18), colors.cardSurface);
    final (bg, fg, icon, hasBorder) = switch (glyph) {
      ActivityGlyph.expenseAdded =>
        (colors.saffronSoft, colors.primaryDark, Iconsax.receipt_add, true),
      ActivityGlyph.expenseEdited =>
        (colors.cardSoft, colors.textSecondary, Iconsax.receipt_edit, true),
      ActivityGlyph.expenseDeleted =>
        (colors.cardSoft, colors.textSecondary, Iconsax.receipt_minus, true),
      ActivityGlyph.settlement => (sageSoft, colors.success, Iconsax.wallet_3, false),
      ActivityGlyph.eventCreated =>
        (colors.saffronSoft, colors.primaryDark, Iconsax.calendar_1, true),
      ActivityGlyph.eventDeleted =>
        (colors.cardSoft, colors.textSecondary, Iconsax.calendar_remove, true),
      ActivityGlyph.memberJoined => (colors.cardSoft, colors.cat2, Iconsax.user_add, true),
      ActivityGlyph.memberLeft =>
        (colors.cardSoft, colors.textSecondary, Iconsax.user_minus, true),
      ActivityGlyph.generic =>
        (colors.cardSoft, colors.textSecondary, Iconsax.activity, true),
    };
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(context.spacing.radiusSmall),
        border: hasBorder ? Border.all(color: colors.rule, width: 0.5) : null,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: fg),
    );
  }
}
```

This is the group screen's existing `_CategoryIcon` table (colors verbatim, incl. the sage `alphaBlend` idiom) with two deltas: `radiusSmall` (P6, was literal 10) and the glyph enum instead of raw type strings.

**Step 4:** run test → PASS. **Step 5:** `git commit -m "feat(shared): ActivityGlyph + ActivityCategoryIcon (#490)"`

### Task 1.2: `ActivityRow`

**Step 1: Failing tests** — actor bold + description in one `Text.rich` (findRichText), optional group chip, optional trailing amount widget, optional detail slot, muted variant, onTap plumbed, top-aligned leading (#159 CrossAxisAlignment.start), divider row.

**Step 3: Implement** `lib/shared/widgets/activity_row.dart` — exact contract:

```dart
class ActivityRow extends StatelessWidget {
  const ActivityRow({
    super.key,
    required this.glyph,
    required this.actorName,
    required this.description,
    required this.timestamp,
    this.groupName,          // D-b: renders the bordered tag chip when non-null
    this.trailingAmount,     // caller-built RAmount (keeps per-feed sign/showCurrency semantics)
    this.detail,             // per-event audit chip (ExpenseAuditDetail)
    this.divider = false,
    this.maxLines = 2,       // P8: event feed passes 3
    this.muted = false,      // deleted rows: actor -> textSecondary, trailing in Opacity(.6)
    this.onTap,
  });
  final ActivityGlyph glyph;
  final String actorName;
  final String description;
  final DateTime timestamp;
  final String? groupName;
  final Widget? trailingAmount;
  final Widget? detail;
  final bool divider;
  final int maxLines;
  final bool muted;
  final VoidCallback? onTap;
  ...
}
```

Body reproduces the current `_ActivityRow` anatomy exactly (it is already identical across feeds): vertical padding `space12`, `Row(crossAxisAlignment: start)` → `ActivityCategoryIcon` · `space12` · Expanded(Column: Text.rich(actor w600 `muted ? textSecondary : textPrimary` + ' ' + description textSecondary, maxLines, ellipsis) + `if (detail != null) detail!` + `if (groupName != null)` the chip) · `space12` · trailing Column(end): `if (trailingAmount != null) [muted ? Opacity(opacity: .6, child: trailingAmount!) : trailingAmount!, SizedBox(height: 2)]` + `AppTypography.caption(context, fontSize: 10, letterSpacing: .4, color: textSecondary)` time via `formatRelativeShort(context, timestamp)`. Divider: `space12` gap + 0.5 `rule` line. Wrap everything in `InkWell(onTap: onTap)` only when `onTap != null`.

Group chip (lifted from home `activity_row.dart:77-97`, unchanged styling): `Container(padding: EdgeInsetsDirectional 8/2, cardSoft, radiusPill, rule .5 border, sans 11 w500 textSecondary)` under a `SizedBox(height: space4)`.

**Steps 4–5:** tests PASS → `git commit -m "feat(shared): ActivityRow with per-feed slots (#490)"`

### Task 1.3: `ActivityDaySection` (+ dot-date header)

Contract:

```dart
class ActivityDaySection extends StatelessWidget {
  const ActivityDaySection({
    super.key,
    required this.label,      // "Today" / "Yesterday" / "Mar 22" (pre-localized)
    this.dateSuffix,          // D-f: "JUL 4" — rendered ` · JUL 4` after label
    required this.children,   // ActivityRow widgets (caller sets divider: i < len-1)
    this.raised = true,       // false = flat + rule2 hairline (per-event, #866)
  });
}
```

Header row: `label.toUpperCase()` + optional `' · ' + dateSuffix!.toUpperCase()` in `AppTypography.caption(context, fontSize: 10, w600, textSecondary, letterSpacing: 2)`, then 10-gap + Expanded 0.5 `rule2` line (verbatim from group screen `_DaySection`). Card: `cardSurface`, `BorderRadius.circular(context.spacing.radiusCard)` (**not** radiusLarge — §2 fix), `raised ? boxShadow: context.shadows.raised : border: Border.all(color: rule2)`, horizontal padding `space16`, **`clipBehavior: Clip.antiAlias`** (P5 — ripples stop poking past corners).

Test: flat variant has border + no shadow; raised has shadow + no border; suffix renders `TODAY · JUL 4`; card clips (decoration + clipBehavior asserted).

Commit: `feat(shared): ActivityDaySection — dot-date header, radiusCard, ripple clip`

### Task 1.4: `ActivityFilterStrip`

```dart
class ActivityFilterOption<T> {
  const ActivityFilterOption({required this.value, required this.label, this.key});
  final T value; final String label; final Key? key;
}

class ActivityFilterStrip<T> extends StatelessWidget {
  const ActivityFilterStrip({
    super.key, required this.options, required this.current, required this.onChange,
  });
}
```

Verbatim visual from the two existing `_FilterStrip`/`_Chip` copies (ink-filled active — D-e), with the three unifications baked in: height `context.spacing.space32` (group's token version wins over cross-group's literal), `HapticService.selection()` on every tap (P2), re-tap of active value is a no-op *before* haptic (preserves `group_activity_filter_memo_test.dart`'s #634 guarantee), chip wrapped in `TapBounce` (P7) instead of bare `GestureDetector`.

Test: active chip ink-filled; re-tap active → `onChange` NOT called; keys land on chips.

Commit: `feat(shared): ActivityFilterStrip — haptics, TapBounce, token height`

### Task 1.5: `CaptionTitleBar`

The event feed's `_TopBar` promoted (mockup §2 makes the group screen its second consumer):

```dart
class CaptionTitleBar extends StatelessWidget {
  const CaptionTitleBar({
    super.key, required this.caption, required this.title,
    this.onBack,           // caller keeps its own canPop guard — semantics unchanged
    this.backKey, this.titleKey,
  });
}
```

Layout verbatim from `activity_feed_screen.dart` `_TopBar` (44×44 InkResponse back, caption mono 10/ls2, `AppTypography.displayOf` 22 serif title, 1-line ellipsis) with two deltas: back glyph via **`DirectionalIcon(Iconsax.arrow_left)`** (P3, replaces the hand-rolled RTL ternary) and `HapticService.lightClick()` before `onBack`.

Test: title + caption render; back invokes callback; back button absent when `onBack == null`.

Commit: `feat(shared): CaptionTitleBar (event-feed top bar promoted, DirectionalIcon)`

### Task 1.6: `PaperBackdrop` (V2, D-c)

```dart
class PaperBackdrop extends StatelessWidget {
  const PaperBackdrop({super.key, required this.child, this.washHeight = 240});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(children: [
      PositionedDirectional(
        top: 0, start: 0, end: 0, height: washHeight,
        child: DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [colors.paperDeep, colors.scaffoldBackground],
          ),
        )),
      ),
      Positioned.fill(child: GrainOverlay(child: child)),
    ]);
  }
}
```

Both colors are existing surface tokens; grain reuses the shipped `GrainOverlay` (3.5%). Wraps a screen's **body content** so the texture paints above the opaque scaffold background (see GrainOverlay correction above — this is why the shell-level wrap never showed).

Test: gradient box present with paperDeep→scaffoldBackground; child renders; grain `DecoratedBox` wraps child.

Commit: `feat(shared): PaperBackdrop — grain + paperDeep wash (activity-ui-polish §4 V2)`

### Task 1.7: `groupByDay` util

`lib/core/utils/day_grouping.dart` — generic extraction of the three `_groupByDay` copies, keeping the #634 hoisting (l10n strings + `shortMonthDayFormatter` built once per call, not per log):

```dart
class DayGroup<T> {
  const DayGroup({required this.label, this.dateSuffix, required this.entries});
  final String label; final String? dateSuffix; final List<T> entries;
}

List<DayGroup<T>> groupByDay<T>(
  BuildContext context, List<T> items, DateTime now, DateTime Function(T) timestampOf,
) { ... }
```

Semantics = the group screen's variant (the richest): diff 0 → (`timelineToday`, dateText), 1 → (`timelineYesterday`, dateText), else (dateText, null). Pure-logic unit test in `test/unit/day_grouping_test.dart`: today/yesterday/older bucketing, ordering preserved, suffix only on today/yesterday.

Commit: `feat(core): generic day-grouping util (dot-date, #634 hoisting)`

### Task 1.8: PR 1 wrap-up

- `flutter analyze` clean · `flutter test test/shared/ test/unit/day_grouping_test.dart` green · `bash tool/check_theme_purity.sh` clean · full `flutter test` green.
- Push branch `feat/activity-primitives`, PR body `Refs #490` + `Spec:` line, then `/automerge`.

---

## PR 2 — per-event feed (mockup §1, D-g)

**Files:**
- Modify: `lib/features/activity/screens/activity_feed_screen.dart` (replace `_TopBar`, `_DaySection`, `_ActivityRow`, `_CategoryIcon`, `_groupByDay`)
- Modify: `lib/features/activity/widgets/expense_audit_detail.dart` (narrow to UPDATE-with-field-change)
- Test: `test/features/activity/activity_feed_screen_test.dart`, `test/features/activity/expense_audit_detail_test.dart`

### Task 2.1: glyph adapter (failing test first)

Test: a MONEY/CREATE log renders `Iconsax.receipt_add`; MONEY/UPDATE → `receipt_edit`; MONEY/DELETE → `receipt_minus`; GEAR/DOCS/unknown → `Iconsax.activity` (generic — Phase-39 legacy categories demoted, they no longer get bespoke icons).

Adapter (private, in the screen file):

```dart
ActivityGlyph _glyphFor(ActivityLog log) => switch ((log.category, log.eventType)) {
  ('MONEY', 'CREATE') => ActivityGlyph.expenseAdded,
  ('MONEY', 'UPDATE') => ActivityGlyph.expenseEdited,
  ('MONEY', 'DELETE') => ActivityGlyph.expenseDeleted,
  _ => ActivityGlyph.generic,
};
```

### Task 2.2: row adoption — trailing amount + summary drop

Failing tests first:
- CREATE row shows a trailing `RAmount` (from `diff.after!.amount/currency`, `showCurrency: true`) and does **NOT** show the old `"<description> · <amount>"` summary text.
- DELETE row is muted and shows the trailing amount inside an `Opacity(.6)`.
- UPDATE-with-amount-change keeps the before→after audit chip and has **no** trailing amount (chip already carries both figures — no duplication).
- Legacy log (`metadata: {}` → `diff.after == null`) renders verb-only, no amount, no crash.
- Day header renders `TODAY · <date>` (dot-date, D-f).

Then swap `_buildActivityBody`'s day loop onto `groupByDay` + `ActivityDaySection(raised: false)` (flat — D-d) and `_ActivityRow` onto shared `ActivityRow`:

```dart
final diff = log.category == 'MONEY'
    ? ExpenseAuditDiff.fromMetadata(log.metadata) : const ExpenseAuditDiff();
final showAuditChip = log.eventType == 'UPDATE' && diff.hasFieldChange;
final amount = (!showAuditChip && diff.after != null)
    ? RAmount(value: diff.after!.amount, currency: diff.after!.currency, size: 14)
    : null;
ActivityRow(
  glyph: _glyphFor(log),
  actorName: log.actorName ?? context.l10n.activitySomeone,
  description: localizedEventActivityText(context.l10n, log),
  timestamp: log.createdAt,
  trailingAmount: amount,
  detail: showAuditChip
      ? ExpenseAuditDetail(diff: diff, eventType: log.eventType,
          participantNames: participantNames)
      : null,
  muted: log.eventType == 'DELETE',
  maxLines: 3,           // P8: this feed keeps 3
  divider: i < entries.length - 1,
)
```

`ExpenseAuditDetail` change: `build` returns `SizedBox.shrink()` unless `eventType == 'UPDATE' && diff.hasFieldChange` (the `_summaryRow` branch and its helpers are deleted — grep tests for the summary format and delete those assertions, per the remove-UI rule). Keep the field-change rows exactly as-is.

### Task 2.3: top bar + P1

- `_TopBar` → `CaptionTitleBar(caption: l10n.activityCaption, title: ..., onBack: <verbatim existing canPop-guarded pop>)`.
- `_ErrorView` icon `Iconsax.activity` → `Iconsax.warning_2` (P1); empty state keeps `activity`.

### Task 2.4: wrap-up

Grep the test file for assertions on removed UI (summary lines, old icon). `flutter analyze` + `flutter test test/features/activity/` + theme purity + full suite. Commit(s) `feat(activity): per-event feed — action vocabulary, trailing amounts, dot-date (Refs #490)`, PR + `/automerge`.

---

## PR 3 — group timeline (mockup §2)

**Files:**
- Modify: `lib/features/groups/screens/group_activity_screen.dart`
- Modify: `lib/l10n/app_en.arb` + `app_ar.arb` (delete `activityFilterSettles` after last use is gone)
- Test: `test/features/groups/group_activity_screen_test.dart`, `test/features/groups/group_activity_filter_memo_test.dart`

### Task 3.1: journal top bar

Failing test: serif title = the *group name* via display font + `ACTIVITY` caption present; centered-sans title gone; `GroupKeys.activityBackButton` still works and **cold-entry back still lands on `/group/:gid`** (back-guard semantics preserved — pass the existing `canPop ? pop : go('/group/$groupId')` closure into `CaptionTitleBar.onBack` verbatim; keep `GroupKeys.activityScreenTitle` on the title).

### Task 3.2: shared chrome adoption

- `_FilterStrip`/`_Chip` → `ActivityFilterStrip<_Filter>` with the existing `GroupKeys.activityFilter*` keys; label for settlements switches to `l10n.activityFilterSettlements` (P4). Delete `activityFilterSettles` from both ARBs once `grep -rn activityFilterSettles lib test` is empty. `group_activity_filter_memo_test.dart` must stay green unmodified (re-tap no-op preserved).
- `_DaySection` → `ActivityDaySection(raised: true)` — this silently applies radiusCard (§2) + ripple clip (P5).
- `_ActivityRow` → shared `ActivityRow` with adapter: type→glyph map (verbatim from today's `_CategoryIcon` switch, now returning `ActivityGlyph`), `trailingAmount` = existing `activityAmount(log, currency)` → `RAmount(..., showCurrency: amt.currency != currency)` (unchanged semantics), `onTap` = existing `activityRowTarget` push with the self-target inert guard (#852 — copied verbatim).
- Pagination footer spinner → `SkeletonLoader.expenseList(count: 1)` (#488 parity); the failed-pagination retry `TextButton` stays.
- `_groupByDay` → `groupByDay` util (already dot-dated).
- P1: error view icon → `Iconsax.warning_2` (`GroupKeys.activityErrorView` untouched).

### Task 3.3: wrap-up

Analyze/tests/purity/full suite → commit `feat(groups): group timeline — journal header + shared activity chrome (Refs #490)` → PR → `/automerge`.

---

## PR 4 — cross-group tab + home RECENTLY (mockup §3, D-a, D-b) — `Closes #490`

**Files:**
- Modify: `lib/features/home/screens/cross_group_activity_screen.dart`
- Modify: `lib/features/home/screens/home_screen.dart:235` (RECENTLY rows)
- Delete: `lib/features/home/widgets/activity_row.dart` (home's avatar row)
- Test: `test/features/home/cross_group_activity_screen_test.dart`, `cross_group_activity_search_test.dart`, `activity_row_alignment_test.dart` (re-point at shared row or delete per remove-UI rule), `home_recently_deeplink_test.dart`

### Task 4.1: cross-group adoption

Failing tests: group context renders as chip (not plain text); day header dot-dated; loading-more footer is a skeleton row (not `CircularProgressIndicator`).

- `_DaySection`/`_ActivityRow`/`_CategoryIcon`/`_groupByDay`/`_FilterStrip` → shared primitives. Row adapter: same type→glyph map as PR 3 (extract to `lib/features/activity/utils/activity_display.dart` as `glyphForGroupActivityType(String type)` so PR 3+4 share one copy — move PR 3's private map there in this PR).
- `groupName:` slot = `entry.groupName` (D-b chip). `trailingAmount` keeps this screen's semantics (`showCurrency` always on, per today).
- `_Footer` `isLoadingMore` branch → `SkeletonLoader.expenseList(count: 1)`; partial-failure and search-older branches unchanged.
- Top bar: replace the RTL ternary with `DirectionalIcon(Iconsax.arrow_left)` inside the existing `RIconButton` usage (P3) — `_back` guard untouched.
- `_SearchField` container radius 12 → `BorderRadius.circular(context.spacing.radiusInput)` (P6).

### Task 4.2: home RECENTLY (D-a)

Failing test: RECENTLY row leads with `ActivityCategoryIcon` (e.g. `Iconsax.wallet_3` for a settlement log), **no `RAvatar`**, group chip still present, #852 deep-link tap still fires.

`home_screen.dart:235` → shared `ActivityRow(glyph: glyphForGroupActivityType(entry.log.type), actorName: entry.log.actorName, description: localizedGroupActivityText(...), timestamp: entry.log.timestamp, groupName: entry.groupName, onTap: <existing push, verbatim>)`. Delete `lib/features/home/widgets/activity_row.dart`; grep for its imports/labels in tests — `activity_row_alignment_test.dart` asserted the #159 top-align on the old widget; the shared row has its own alignment test from PR 1, so delete the obsolete file-specific test (don't patch it).

### Task 4.3: wrap-up

If `home_golden_test.dart` covers RECENTLY rows, regenerate goldens locally (macOS) and include them. Analyze/tests/purity/full suite → commit `feat(home): cross-group + RECENTLY on shared activity row (Closes #490)` — **`Closes #490` must be in the squash commit body** → PR → `/automerge`.

---

## PR 5 — PaperBackdrop rollout (mockup §4 V2, D-c)

**Files:**
- Modify: `lib/features/activity/screens/activity_feed_screen.dart` (non-embedded branch only)
- Modify: `lib/features/groups/screens/group_activity_screen.dart`
- Modify: `lib/features/home/screens/cross_group_activity_screen.dart`
- Test: extend the three screen test files

### Task 5.1

Failing test per screen: `find.byType(PaperBackdrop)` + gradient present. Then wrap each `Scaffold` body's content:

```dart
body: SafeArea(child: PaperBackdrop(child: Column(...)))
```

Per-event feed: only in the non-`embedded` branch (`embedded` returns the bare feed — the tabbed event shell owns chrome there, #758; wrapping it would double-texture inside `EventCommandCenter`). Cross-group: wrapping inside the screen body covers **both** the tab and the `/activity` route with one implementation.

### Task 5.2: wrap-up

Analyze/tests/purity/full suite; quick manual pass (`/run` or device) since this is pure visual: light theme, RTL, and dark theme *compiles legibly* (dark is an untuned stub — D5 — so only check nothing becomes unreadable; both tokens have dark values). Commit `feat(shared): V2 grain+wash backdrop on activity feeds` → PR → `/automerge`.

---

## Explicitly out of scope (don't fold in)

- V3 cover-blend header (reserved), any group-detail changes, dark-theme tuning (D5), motion-token migration beyond touched code (D6), `EventCommandCenter`/ledger surfaces, pagination architecture (#422), l10n key additions (none needed — dot separator is punctuation, existing `timelineToday`/`timelineYesterday`/`shortMonthDayFormatter` cover labels).

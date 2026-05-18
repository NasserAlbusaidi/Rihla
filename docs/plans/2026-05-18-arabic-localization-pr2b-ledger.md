# PR2b — Ledger Surface Arabic Localization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Design rationale: `docs/plans/2026-05-18-arabic-localization-pr2b-ledger-design.md`.

**Goal:** Translate the entire Ledger surface to Arabic (~34 files, ~130 new ARB keys) and extend the existing Arabic golden-path integration test with a ledger walk — without altering any money-math, persistence, or bucketing-logic behaviour.

**Architecture:** Display-only translation. ARB keys land en+ar paired (CI completeness lint stays green every commit). Two new helpers (`expense_scope_display_name.dart`, `localized_category_name.dart`); one minimal API change to `ledger_categories.dart` (`ledgerCategoryName` gains `AppLocalizations` param) and one to `formatters.dart` (`formatShortMonthDay` gains `String localeTag`). `ledgerCategoryBucket` substring-matching logic is UNCHANGED — pre-existing brokenness for Firestore expenses stays; behavioural fix is follow-up #8. Each wave is one atomic commit. Codex gate runs against this plan + the design doc BEFORE Wave 0.

**Tech Stack:** Flutter `^3.10.1`, gen-l10n ARB pipeline, Riverpod 2.x, `intl` for date formatting, `mocktail` + `FakeFirebaseFirestore` for tests, `pumpRihlaApp` test helper.

**Pre-flight:**
- Branch: `feat/l10n-pr2b-ledger` (already created off `main` @ edfd385)
- Design doc committed at 657d8b7
- **REQUIRED before Wave 0:** run `/codex` against this plan + the design doc. Apply findings, re-run, stop when verdict has no [P1]s.

---

## Conventions used in this plan

**ARB key writing:** Every new key lands in BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_ar.arb` in the same commit. `tool/check_arb_completeness.dart` (CI) fails if en/ar drift. After editing ARB files, run `flutter gen-l10n` (or `flutter pub get` which triggers gen) — generated bindings land at `lib/l10n/generated/app_localizations*.dart`.

**Consuming a key in Dart:** The `context.l10n` extension lives at `lib/core/extensions/build_context_l10n.dart` — add `import 'package:safar/core/extensions/build_context_l10n.dart';` if not present (codex round 1 catch — earlier draft pointed at the generated file, which is wrong). Replace `'English text'` with `context.l10n.keyName`. For placeholder keys: `context.l10n.editorFailedToAddExpense(errorString)`. For plural keys: `context.l10n.ledgerPeopleCount(participantCount)` — the plural value already embeds the count via `#`, so DO NOT prefix `'$count '` at the callsite.

**RTL fix patterns:**
- `Alignment.centerLeft` → `AlignmentDirectional.centerStart`
- `Alignment.centerRight` → `AlignmentDirectional.centerEnd`
- `Alignment.topRight` → `AlignmentDirectional.topEnd`
- `EdgeInsets.only(left: N)` → `EdgeInsetsDirectional.only(start: N)`
- `EdgeInsets.only(right: N)` → `EdgeInsetsDirectional.only(end: N)`
- `Positioned(left: N, …)` → `PositionedDirectional(start: N, …)`

**Widget-translation template (Waves 1-6):** For each widget file:
1. Grep current strings: `grep -nE "'[A-Z][a-zA-Z][a-zA-Z 0-9',.!?:-]+'" <file>` (and also for any `semanticLabel:`, `tooltip:`, `helperText:`, `hintText:` properties — they hide user-visible strings outside the simple `Text(...)` pattern)
2. Add en+ar ARB pairs to both files for each user-visible string
3. Apply RTL fixes if listed for the file
4. Replace each hardcoded string with `context.l10n.<key>`
5. Update widget tests that assert on the English string (use `pumpRihlaApp(tester, child, locale: ..., overrides: ...)` per the helper's actual signature at `test/helpers/pump_rihla_app.dart:33-38`; tests stay English-assertions by default because the helper's `locale` defaults to `const Locale('en')`)
6. Run `flutter analyze <file>` — must be clean
7. Run the file's widget tests — must pass

**Commit cadence:** One commit per wave. Conventional: `feat(l10n): PR2b/wave-N — <scope>`.

**No `pumpAndSettle` after `pumpRihlaApp`** (ConnectivityNotifier Timer hangs — per `feedback_pump_rihla_app_contracts`). Use `await tester.pump()` + explicit pumps.

---

## Wave 0 — Foundation (no UI changes)

Goal: ARB keys exist; helpers + refactor in place; full app still renders English everywhere.

### Task 0.1: Bulk ARB key addition

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_ar.arb`

**Step 1: Add the ~130 new key pairs to both files**

Use the prefix buckets from the design doc Section "ARB key inventory":
- `ledger*` (~22), `editor*` (~42), `customSplit*` (~10), `categoryPicker*` (~5), `category*` (6 — `categoryFood/Transport/Accommodation/Activities/Shopping/Other`), `settleUp*` (~25), `expenseSuccess*` (~6), `timeline*` (3 — `timelineToday/timelineYesterday/timelineRangeSeparator`), `common*` (5 new — `commonApply/commonRetry/commonBack/commonClose/commonGoHome`).

Plural keys (two in PR2b — first plurals in codebase). Both embed the count INSIDE the value using ICU `#` so callsites stop concatenating `'$count '` separately (codex round 1 catch):

```json
"ledgerPeopleCount": "{count, plural, =1{1 PERSON} other{# PEOPLE}}",
"@ledgerPeopleCount": { "placeholders": { "count": { "type": "int" } } },

"settleUpSummaryTransfers": "{count, plural, =1{1 transfer} other{# transfers}}",
"@settleUpSummaryTransfers": { "placeholders": { "count": { "type": "int" } } }
```

Arabic counterparts in `app_ar.arb`:
```json
"ledgerPeopleCount": "{count, plural, =1{شخص واحد} other{# أشخاص}}",
"settleUpSummaryTransfers": "{count, plural, =1{تحويل واحد} other{# تحويلًا}}"
```

Callsite shape after refactor:
```dart
// ledger_screen.dart — drop the '$participantCount ' prefix
context.l10n.ledgerPeopleCount(participantCount),

// group_settlement_summary.dart:32 — same pattern
label: context.l10n.settleUpSummaryTransfers(transferCount),
```

Verb-interpolation keys (en):
```json
"editorFailedToAddExpense": "Failed to add expense: {error}",
"editorFailedToUpdateExpense": "Failed to update expense: {error}",
"@editorFailedToAddExpense": { "placeholders": { "error": { "type": "String" } } },
"@editorFailedToUpdateExpense": { "placeholders": { "error": { "type": "String" } } }
```

**Per-key source-of-truth:** Each en string mirrors what currently appears in code (see file-list in Waves 1-6 for line refs). When a string spans multiple lines (e.g. empty-state prose at `ledger_screen.dart:587-588`), concatenate into one ARB value.

**Step 2: Run gen-l10n**

Run: `flutter gen-l10n` (or `flutter pub get`)
Expected: `lib/l10n/generated/app_localizations.dart` updated; new method per ARB key added; no errors.

**Step 3: Run ARB completeness check**

Run: `dart run tool/check_arb_completeness.dart`
Expected: `ARB completeness: OK (~235 keys matched)`. Exit 0.

**Step 4: Run analyze**

Run: `flutter analyze`
Expected: zero new warnings (generated file is allowed to have its own).

**Step 5: Commit (held until end of Wave 0)**

Do not commit yet — Wave 0 lands as one commit after Tasks 0.2–0.4.

---

### Task 0.2: Add `expenseScopeDisplayName` helper (TDD)

**Files:**
- Create: `lib/core/utils/expense_scope_display_name.dart`
- Create: `test/unit/expense_scope_display_name_test.dart`

**Step 1: Write the failing test**

```dart
// test/unit/expense_scope_display_name_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/expense_scope_display_name.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('expenseScopeDisplayName', () {
    test('returns English labels for each ExpenseScope', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(expenseScopeDisplayName(ExpenseScope.global,   l10n), 'Equally');
      expect(expenseScopeDisplayName(ExpenseScope.subGroup, l10n), 'Group split');
      expect(expenseScopeDisplayName(ExpenseScope.custom,   l10n), 'Custom');
      expect(expenseScopeDisplayName(ExpenseScope.personal, l10n), 'Personal');
    });

    test('returns Arabic labels — distinct from English, asserts wrong-locale fallback would fail', () async {
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      for (final scope in ExpenseScope.values) {
        expect(expenseScopeDisplayName(scope, ar), isNotEmpty);
        // Distinctness assertion catches a bug where the Arabic delegate
        // accidentally falls back to English (codex round 1 P2 strengthening).
        expect(expenseScopeDisplayName(scope, ar), isNot(expenseScopeDisplayName(scope, en)));
      }
    });
  });
}
```

**Step 2: Verify test fails**

Run: `flutter test test/unit/expense_scope_display_name_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:safar/core/utils/expense_scope_display_name.dart'`.

**Step 3: Implement minimal helper**

```dart
// lib/core/utils/expense_scope_display_name.dart
import '../../features/ledger/models/expense_model.dart';
import '../../l10n/generated/app_localizations.dart';

/// Returns the localized display name for [scope].
///
/// Mirror of [splitModeDisplayName] for [ExpenseScope]. Used in
/// `expense_editor_body.dart` and `split_scope_selector.dart`.
String expenseScopeDisplayName(ExpenseScope scope, AppLocalizations l10n) {
  return switch (scope) {
    ExpenseScope.global   => l10n.editorScopeGlobal,
    ExpenseScope.subGroup => l10n.editorScopeSubGroup,
    ExpenseScope.custom   => l10n.editorScopeCustom,
    ExpenseScope.personal => l10n.editorScopePersonal,
  };
}
```

**Step 4: Verify test passes**

Run: `flutter test test/unit/expense_scope_display_name_test.dart`
Expected: PASS — both groups green.

**Step 5: Hold commit until Wave 0 atomic commit.**

---

### Task 0.3: Add `localizedCategoryName` helper (TDD)

**Files:**
- Create: `lib/features/ledger/utils/localized_category_name.dart`
- Create: `test/unit/localized_category_name_test.dart`

**Step 1: Write the failing test**

```dart
// test/unit/localized_category_name_test.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/utils/localized_category_name.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('localizedCategoryName', () {
    test('returns the English ARB value for each known id', () async {
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(localizedCategoryName(id: 'food',          l10n: en), en.categoryFood);
      expect(localizedCategoryName(id: 'transport',     l10n: en), en.categoryTransport);
      expect(localizedCategoryName(id: 'accommodation', l10n: en), en.categoryAccommodation);
      expect(localizedCategoryName(id: 'activities',    l10n: en), en.categoryActivities);
      expect(localizedCategoryName(id: 'shopping',      l10n: en), en.categoryShopping);
      expect(localizedCategoryName(id: 'other',         l10n: en), en.categoryOther);
    });

    test('returns the Arabic ARB value for each known id — distinct from English', () async {
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      for (final id in const ['food','transport','accommodation','activities','shopping','other']) {
        expect(localizedCategoryName(id: id, l10n: ar), isNotEmpty);
        expect(localizedCategoryName(id: id, l10n: ar), isNot(localizedCategoryName(id: id, l10n: en)));
      }
    });

    test('returns fallbackName when id is null and fallbackName is set', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(localizedCategoryName(id: null, fallbackName: 'Concert tickets', l10n: l10n), 'Concert tickets');
    });

    test('returns fallbackName when id is unknown', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(localizedCategoryName(id: 'wibble', fallbackName: 'Concert tickets', l10n: l10n), 'Concert tickets');
    });

    test('returns categoryOther when both id and fallbackName are missing', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(localizedCategoryName(id: null, fallbackName: null, l10n: l10n), l10n.categoryOther);
    });

    test('returns categoryOther when fallbackName is empty', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(localizedCategoryName(id: 'wibble', fallbackName: '', l10n: l10n), l10n.categoryOther);
    });
  });
}
```

**Step 2: Verify test fails**

Run: `flutter test test/unit/localized_category_name_test.dart`
Expected: FAIL — URI doesn't exist.

**Step 3: Implement helper**

```dart
// lib/features/ledger/utils/localized_category_name.dart
import '../../../l10n/generated/app_localizations.dart';

/// Returns the localized display name for an expense category.
///
/// Lookup precedence:
/// 1. If [id] matches a known default-seed id → ARB key.
/// 2. Else if [fallbackName] is non-empty → return as-typed (custom/legacy).
/// 3. Else → `categoryOther`.
String localizedCategoryName({
  String? id,
  String? fallbackName,
  required AppLocalizations l10n,
}) {
  switch (id) {
    case 'food':          return l10n.categoryFood;
    case 'transport':     return l10n.categoryTransport;
    case 'accommodation': return l10n.categoryAccommodation;
    case 'activities':    return l10n.categoryActivities;
    case 'shopping':      return l10n.categoryShopping;
    case 'other':         return l10n.categoryOther;
  }
  if (fallbackName != null && fallbackName.isNotEmpty) {
    return fallbackName;
  }
  return l10n.categoryOther;
}
```

**Step 4: Verify test passes**

Run: `flutter test test/unit/localized_category_name_test.dart`
Expected: PASS — all 5 tests green.

**Step 5: Hold commit.**

---

### Task 0.4: Add `AppLocalizations` param to `ledgerCategoryName` (TDD, minimal — codex round 1 rescope)

**Files:**
- Modify: `lib/features/ledger/utils/ledger_categories.dart` (signature change to `ledgerCategoryName` only — `ledgerCategoryBucket` is unchanged)
- Modify: `test/unit/ledger_categories_test.dart` (or create if it doesn't exist — grep first)
- Compile-fix callsite patches at `lib/features/ledger/widgets/ledger_category_strip.dart:142` and `lib/features/ledger/widgets/ledger_day_card.dart` (any callsite using the old name-only signature)

**Step 1: Confirm test file location**

Run: `find test -name "ledger_categories_test.dart"`
- If exists: extend it.
- If not: create `test/unit/ledger_categories_test.dart`.

**Step 2: Write/extend failing tests**

```dart
// test/unit/ledger_categories_test.dart (full skeleton — extend existing if present)
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/utils/ledger_categories.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  group('ledgerCategoryName(bucket, l10n) returns localized name', () {
    test('English bucket names match l10n keys 1..6', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(ledgerCategoryName(1, l10n), l10n.ledgerBucketFood);
      expect(ledgerCategoryName(2, l10n), l10n.ledgerBucketLodging);
      expect(ledgerCategoryName(3, l10n), l10n.ledgerBucketTransit);
      expect(ledgerCategoryName(4, l10n), l10n.ledgerBucketGroceries);
      expect(ledgerCategoryName(5, l10n), l10n.ledgerBucketActivities);
      expect(ledgerCategoryName(6, l10n), l10n.ledgerBucketOther);
    });

    test('Arabic bucket names are non-empty AND distinct from English', () async {
      final ar = await AppLocalizations.delegate.load(const Locale('ar'));
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      for (var i = 1; i <= 6; i++) {
        expect(ledgerCategoryName(i, ar), isNotEmpty);
        expect(ledgerCategoryName(i, ar), isNot(ledgerCategoryName(i, en))); // catches wrong-locale fallback
      }
    });

    test('out-of-range bucket falls back to Other', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(ledgerCategoryName(99, l10n), l10n.ledgerBucketOther);
      expect(ledgerCategoryName(0,  l10n), l10n.ledgerBucketOther); // historical bucket-1-based, 0 is invalid
    });
  });

  // ledgerCategoryBucket is NOT refactored in PR2b — see follow-up #8.
  // Existing tests for it (if any) should still pass without modification.
}
```

**Step 3: Verify tests fail**

Run: `flutter test test/unit/ledger_categories_test.dart`
Expected: FAIL — `ledgerCategoryName` currently takes only `int`, and `l10n.ledgerBucket*` getters do not exist yet (Wave 0 Task 0.1 adds those ARB keys; this Task 0.4 runs after Task 0.1).

**Step 4: Modify the implementation (minimal)**

```dart
// lib/features/ledger/utils/ledger_categories.dart
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/tokens/color_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Maps a free-text expense category name onto one of six stable buckets.
///
/// Unchanged from PR2a baseline — substring matching against `name`.
/// Pre-existing bug: Firestore-loaded expenses have `categoryName: null`
/// (`expense_model.dart:185-205` reads only `categoryId`), so every real
/// expense buckets to 6 (Other). Follow-up #8 will switch this to take
/// `categoryId` and direct-map the 6 seed ids.
int ledgerCategoryBucket(String? name) {
  if (name == null) return 6;
  final lower = name.toLowerCase();
  bool any(List<String> needles) => needles.any(lower.contains);
  if (any(const ['food', 'rest', 'din', 'meal'])) return 1;
  if (any(const ['lodg', 'hotel', 'accom', 'stay'])) return 2;
  if (any(const ['trans', 'taxi', 'flight', 'uber', 'train'])) return 3;
  if (any(const ['groc', 'supermark'])) return 4;
  if (any(const ['activ', 'entertain', 'tour', 'ticket'])) return 5;
  return 6;
}

/// Returns the localized display name for a bucket index 1..6.
/// Default branch (any other int) returns the Other label.
String ledgerCategoryName(int bucket, AppLocalizations l10n) => switch (bucket) {
  1 => l10n.ledgerBucketFood,
  2 => l10n.ledgerBucketLodging,
  3 => l10n.ledgerBucketTransit,
  4 => l10n.ledgerBucketGroceries,
  5 => l10n.ledgerBucketActivities,
  _ => l10n.ledgerBucketOther,
};

Color ledgerCategoryColor(AppColorTokens colors, int bucket) => switch (bucket) {
  1 => colors.cat1,
  2 => colors.cat2,
  3 => colors.cat3,
  4 => colors.cat4,
  5 => colors.cat5,
  _ => colors.cat6,
};

IconData ledgerCategoryIcon(int bucket) => switch (bucket) {
  1 => Iconsax.coffee,
  2 => Iconsax.house_2,
  3 => Iconsax.car,
  4 => Iconsax.shopping_cart,
  5 => Iconsax.star,
  _ => Iconsax.box,
};
```

**Step 5: Verify tests pass**

Run: `flutter test test/unit/ledger_categories_test.dart`
Expected: PASS.

**Step 6: Compile-fix all callsites in same Wave 0 commit**

The `ledgerCategoryName(int)` → `ledgerCategoryName(int, AppLocalizations)` signature change breaks every existing callsite. Grep first:

Run: `grep -rn "ledgerCategoryName(" lib/`
Expected callsites: `ledger_category_strip.dart:142`. (`ledger_day_card.dart:195` calls `ledgerCategoryBucket`, NOT `ledgerCategoryName` — leave alone.)

At `ledger_category_strip.dart:142`, change:
```dart
ledgerCategoryName(bucket),  // OLD
ledgerCategoryName(bucket, context.l10n),  // NEW — minimum-change compile patch
```

Wave 2 will fully translate `ledger_category_strip.dart`; this is just the minimum compilation fix.

Run: `flutter analyze`
Expected: clean.

---

### Task 0.5: `formatShortMonthDay` gains a locale param (codex round 1 — P1 #7)

**Files:**
- Modify: `lib/core/utils/formatters.dart` (replace hardcoded `_monthAbbr` list with `intl` `DateFormat.MMMd`)
- Compile-fix every callsite of `formatShortMonthDay` to pass a locale tag

**Step 1: Find every callsite**

Run: `grep -rn "formatShortMonthDay\|AppFormatters\.formatShortMonthDay" lib/ test/`
Expected: `lib/features/ledger/widgets/expense_editor_body.dart:1215` plus any others surfaced by the grep.

**Step 2: Modify `formatters.dart`**

```dart
// lib/core/utils/formatters.dart — replace the existing hardcoded path
import 'package:intl/intl.dart';

// (delete the const _monthAbbr list entirely)

static String formatShortMonthDay(DateTime date, String localeTag) {
  return DateFormat.MMMd(localeTag).format(date);
}
```

**Step 3: Compile-fix every callsite to pass a locale tag**

At each callsite found in Step 1, change `AppFormatters.formatShortMonthDay(date)` to `AppFormatters.formatShortMonthDay(date, Localizations.localeOf(context).toLanguageTag())`. If the callsite has no `BuildContext` in scope, that's a refactor signal — but `expense_editor_body.dart:1215` does have context.

**Step 4: Verify analyze + tests**

Run: `flutter analyze`
Expected: clean.

Run: `flutter test test/`
Expected: existing tests still green; any test asserting on a specific month abbreviation may need a `localeTag` update.

---

### Task 0.6: Localize `DateFormat('MMM d')` callsite in groups widget (codex round 1 — P1 #7 continued)

**File:** `lib/features/groups/widgets/settle_up_page_body.dart`

**Change at L466:**
```dart
// BEFORE
final dateStr = DateFormat('MMM d').format(settlement.settledAt);
// AFTER
final dateStr = DateFormat.MMMd(Localizations.localeOf(context).toLanguageTag()).format(settlement.settledAt);
```

Verify with `flutter analyze`. (Wave 5 fully translates this widget; this is a Wave 0 compile-fix to avoid leaving an English-baked DateFormat call after the formatters refactor.)

Alternative if a broader audit during implementation finds many `DateFormat('MMM d')` callsites: introduce a `localizedShortMonthDay(BuildContext, DateTime)` helper in `formatters.dart` so callsites stay one-line.

---

**Step 7: Commit Wave 0**

```bash
git add lib/l10n/app_en.arb \
        lib/l10n/app_ar.arb \
        lib/l10n/generated/ \
        lib/core/utils/expense_scope_display_name.dart \
        lib/core/utils/formatters.dart \
        lib/features/ledger/utils/localized_category_name.dart \
        lib/features/ledger/utils/ledger_categories.dart \
        lib/features/ledger/widgets/ledger_category_strip.dart \
        lib/features/ledger/widgets/expense_editor_body.dart \
        lib/features/groups/widgets/settle_up_page_body.dart \
        test/unit/expense_scope_display_name_test.dart \
        test/unit/localized_category_name_test.dart \
        test/unit/ledger_categories_test.dart
git commit -m "feat(l10n): PR2b/wave-0 — ARB keys, helpers, l10n-ready ledger_categories + formatters"
```

Expected: commit succeeds. `git status` clean afterward.

---

## Waves 1-6 — Widget translation (apply the template)

For every file in Waves 1-6, apply the **Widget-translation template** at the top of this plan. Each wave is ONE commit at the end.

### Wave 1 — Small ledger widgets

Commit: `feat(l10n): PR2b/wave-1 — small ledger widgets`

| File | Strings | RTL fixes (specific) |
|---|---|---|
| `lib/features/ledger/widgets/settlement_row.dart` | 1 | — |
| `lib/features/ledger/widgets/settlement_tile.dart` | 1 | **L97**: `Positioned(left: 20, …)` → `PositionedDirectional(start: 20, …)` |
| `lib/features/ledger/widgets/settlement_summary_card.dart` | 4 | — (gradient `topLeft → bottomRight` at L38-39 is decorative; leave) |
| `lib/features/ledger/widgets/recorded_settlements_section.dart` | 2 | — |
| `lib/features/ledger/widgets/recent_expenses_section.dart` | 3 | — |
| `lib/features/ledger/widgets/ledger_sticky_cta.dart` | 2 | — |
| `lib/features/ledger/widgets/ledger_roster_strip.dart` | 2 | — |
| `lib/features/ledger/widgets/amount_input_section.dart` | 4 | Includes `semanticLabel: 'Backspace'` at L88 and `semanticLabel: 'Decimal point'` at L97 — translate via `commonSemanticBackspace` / `commonSemanticDecimalPoint` ARB keys. (codex round 1 catch) |
| `lib/features/ledger/widgets/receipt_picker_section.dart` | 5 | — |

**End-of-wave checks:**
- `flutter analyze` → clean
- `flutter test test/features/ledger/` → all green (note: `test/features/ledger/widgets/` does not exist as a separate directory — tests live directly under `test/features/ledger/`)
- `dart run tool/check_arb_completeness.dart` → exit 0

---

### Wave 2 — Hero/list widgets

Commit: `feat(l10n): PR2b/wave-2 — ledger hero, list, success dialog`

| File | Strings | RTL fixes / helper consumption |
|---|---|---|
| `lib/features/ledger/widgets/ledger_hero_block.dart` | 4 | **L136**: `EdgeInsets.only(right: 3)` → `EdgeInsetsDirectional.only(end: 3)` |
| `lib/features/ledger/widgets/expense_card.dart` | 5 | — |
| `lib/features/ledger/widgets/ledger_day_card.dart` | 5 | — |
| `lib/features/ledger/widgets/ledger_category_strip.dart` | 0 net (was patched in Wave 0) | Replace temporary callsite with proper `context.l10n` consumption. Renders Arabic via `ledgerCategoryName(bucket, context.l10n)` |
| `lib/features/ledger/widgets/expense_success_dialog.dart` | 6 | **L36**: `Alignment.topRight` → `AlignmentDirectional.topEnd` |

**End-of-wave checks:** same as Wave 1.

---

### Wave 3 — Sheets

Commit: `feat(l10n): PR2b/wave-3 — picker, search, custom split sheets`

| File | Strings | RTL fixes / helper consumption |
|---|---|---|
| `lib/features/ledger/widgets/category_picker_sheet.dart` | 7 | **L70**: `Alignment.centerLeft` → `AlignmentDirectional.centerStart`. Consumes `localizedCategoryName` for category labels. |
| `lib/features/ledger/widgets/ledger_search_sheet.dart` | 9 | — |
| `lib/features/ledger/widgets/custom_split_sheet.dart` | 14 | Consumes `splitModeDisplayName` at L505-508. **Wording shift:** `'Equally'` → `'Equal'` (per design Q6). Pre-flight grep `test/` for assertions on `'Equally'`. |

**Pre-flight (before changing `custom_split_sheet.dart`):**

Run: `grep -rn "'Equally'\\|'Shares'\\|'Exact'\\|'Percent'" test/`
Expected: enumerate any tests asserting on these strings. Update them to match `splitModeDisplayName`'s actual return values (`'Equal'`, `'Shares'`, `'Exact amounts'`, `'Percent'`).

**End-of-wave checks:** same as Wave 1.

---

### Wave 4 — Editor cluster (the big one)

Commit: `feat(l10n): PR2b/wave-4 — expense editor body + thin shells + scope selector`

| File | Strings | RTL fixes / helper consumption / refactor |
|---|---|---|
| `lib/features/ledger/widgets/expense_editor_body.dart` | ~42 | **L201:** verb-interpolation refactor — replace `'Failed to $verb expense: $e'` with `editorFailedToAddExpense(error)` / `editorFailedToUpdateExpense(error)` selected at the callsite by the existing `isEdit` flag. **L512:** `Alignment.centerLeft` → `AlignmentDirectional.centerStart`. **L529:** `Alignment.centerRight` → `AlignmentDirectional.centerEnd`. Consumes `splitModeDisplayName` (L1144-1146), `expenseScopeDisplayName` (L1058-1061), `localizedCategoryName` for any category badge rendering. |
| `lib/features/ledger/screens/add_expense_screen.dart` | 2 | — |
| `lib/features/ledger/screens/edit_expense_screen.dart` | 11 | Includes delete snackbar + dialog title; uses `commonDelete` (PR2a key) and `commonCancel` for the inline `AlertDialog` at L222-235 of editor body via the dialog wrapper here. |
| `lib/features/ledger/widgets/split_scope_selector.dart` | 9 | Consumes `expenseScopeDisplayName` for scope labels. |
| `lib/features/ledger/widgets/category_selection_step.dart` | 2 | Lives in Wave 4 (NOT Wave 1, despite the earlier table — codex round 2 ambiguity fix). L115 renders `category.name` directly — replace with `localizedCategoryName(id: category.id, fallbackName: category.name, l10n: context.l10n)`. Plus any chrome strings (title/subtitle) found by string-grep at implementation time. |

**Special handling — `expense_editor_body.dart:1004` `'EVENT DEFAULT'`:**
Open question per design — verify whether this is user-facing badge or internal sentinel before translating. Grep render path:

Run: `grep -n "EVENT DEFAULT" lib/features/ledger/widgets/expense_editor_body.dart`
Inspect the surrounding 10 lines. If rendered via `Text(...)`, translate as `editorEventDefault`. If used as an enum/constant comparison only, leave English.

**Post-wave grep audit (R1 mitigation):**

Run: `grep -nE "'[A-Z][a-zA-Z][a-zA-Z ]{2,}'" lib/features/ledger/widgets/expense_editor_body.dart | grep -v "context.l10n\|import \|^[0-9]*:\\s*///"`
Expected: only debug strings, brand strings, or comments returned. Any remaining user-visible English string is a miss — fix and re-grep.

**End-of-wave checks:** same as Wave 1, plus `flutter test test/features/ledger/` (broader).

---

### Wave 5 — Settle-up cluster

Commit: `feat(l10n): PR2b/wave-5 — settle-up screen + shared groups widgets`

| File | Strings | RTL fixes / notes |
|---|---|---|
| `lib/features/ledger/screens/settle_up_screen.dart` | ~12 | SnackBars at L241, L283-307, L319 — drop `const` after localization. **L349 RTL:** `Alignment.centerLeft` → `AlignmentDirectional.centerStart` (codex round 1 catch). |
| `lib/features/groups/widgets/settle_up_page_body.dart` | 15 | **L393 RTL:** `EdgeInsets.only(left: 4)` → `EdgeInsetsDirectional.only(start: 4)`. L466 `DateFormat('MMM d')` already fixed in Wave 0 Task 0.6. |
| `lib/features/groups/widgets/record_payment_sheet.dart` | 11 | **L469 RTL:** `Alignment.centerLeft` → `AlignmentDirectional.centerStart`. |
| `lib/features/groups/widgets/group_settlement_tile.dart` | 1 | — |
| `lib/features/groups/widgets/all_settled_state.dart` | 2 | — |
| `lib/features/groups/widgets/group_settlement_summary.dart` | **2 strings + 1 plural** (codex round 1 correction — original "0" was wrong) | L32: `'$count transfer(s)'` → `context.l10n.settleUpSummaryTransfers(count)`. L36: `'... total'` suffix → either `settleUpSummaryTotal` with `{amount}` placeholder, or split into `settleUpSummaryTotalSuffix` (returned as a separate `Text` next to the formatted amount). |

**Const SnackBar lint mitigation (R5):**

After translating the SnackBars in `settle_up_screen.dart`, run:

Run: `flutter analyze lib/features/ledger/screens/settle_up_screen.dart`
Expected: clean. If `prefer_const_constructors` fires on inner widgets, mark those as `const` individually (only the outer SnackBar loses const-ness).

**Cross-feature consequence (R9):**

`lib/features/groups/screens/group_settle_up_screen.dart` will render Arabic via the shared widgets. Verify by booting the app in Arabic and navigating to Groups → group → Settle up:

Run: `flutter run -d <android-device> --dart-define-from-file=config.json`
Expected: Group settle-up renders Arabic copy. This is intentional, not a regression.

**End-of-wave checks:**
- `flutter analyze` → clean
- `flutter test test/features/ledger/ test/features/groups/widgets/` → all green
- `dart run tool/check_arb_completeness.dart` → exit 0

---

### Wave 6 — Timeline + top-level ledger screen

Commit: `feat(l10n): PR2b/wave-6 — timeline utils + ledger_screen with plural`

#### Task 6.1: Translate `ledger_timeline.dart`

**File:** `lib/features/ledger/utils/ledger_timeline.dart`

**Step 1: Replace month abbreviations with `intl` DateFormat**

```dart
// Pseudocode — actual replacement at the existing 'Jan'..'Dec' constants
import 'package:intl/intl.dart';

String monthAbbreviation(DateTime date, String localeTag) {
  return DateFormat.MMM(localeTag).format(date);
}
```

Callsites that previously indexed `'Jan'..'Dec'` switch to calling `monthAbbreviation(date, Localizations.localeOf(context).toLanguageTag())` from the consuming widget. The util becomes a small wrapper that takes a localeTag rather than indexing.

**Step 2: Replace `'Today · '` and `'Yesterday · '` with ARB**

These need a `BuildContext` to access `context.l10n`. Either:
- Move the formatting to consuming widgets (push l10n out of the util), OR
- Pass `AppLocalizations` into the util's formatting functions.

**Recommended (matches existing helper pattern):** Pass `AppLocalizations` as parameter.

```dart
String dayLabel(DateTime date, DateTime now, AppLocalizations l10n) {
  if (_isSameDay(date, now)) return l10n.timelineToday;
  if (_isSameDay(date, now.subtract(const Duration(days: 1)))) return l10n.timelineYesterday;
  // … existing fallback (formatted date)
}
```

**Step 3: Run analyze + tests**

Run: `flutter analyze lib/features/ledger/utils/ledger_timeline.dart`
Expected: clean.

Run: `flutter test test/features/ledger/`
Expected: all green (some tests may need locale tag updates).

#### Task 6.2: Translate `ledger_screen.dart`

**File:** `lib/features/ledger/screens/ledger_screen.dart`

**Strings to translate:** ~18 — empty states, error states, tooltips, plus the plural at **L426**.

**Step 1: Plural replacement at L423-426** (codex round 1 catch — count was being dropped in the original draft)

Before (actual code, L423-426):
```dart
final captionParts = <String>[
  ?dateRange,
  '$participantCount '
      '${participantCount == 1 ? 'PERSON' : 'PEOPLE'}',
];
```

After — drop the `'$participantCount '` prefix since the plural value already embeds `#`:
```dart
final captionParts = <String>[
  ?dateRange,
  context.l10n.ledgerPeopleCount(participantCount),
];
```

The generated `AppLocalizations.ledgerPeopleCount(int count)` returns `"1 PERSON"` / `"3 PEOPLE"` / `"شخص واحد"` / `"3 أشخاص"` depending on locale and count. The ICU `#` token inside the plural value is the count.

**Step 2: Translate remaining strings + handle empty-state prose carefully (open question)**

`L577,587-588` empty-state prose is multi-sentence. Concatenate the lines into one ARB value (`ledgerEmptyStateFirstExpense`) and replace both Text widgets with a single localized Text or split into 2 keys if the visual hierarchy requires it. **Inspect the widget tree before translating** to choose 1-key vs 2-key.

**Step 3: Verify the plural renders correctly in both locales**

Boot the app in English with `participantCount = 1` and `participantCount = 3`; verify "PERSON" / "PEOPLE". Repeat in Arabic; verify "شخص" / "أشخاص".

**End-of-wave checks:** same as Wave 1.

---

## Wave 7 — Tests + gate clearance

Commit: `feat(l10n): PR2b/wave-7 — extend Arabic golden-path with ledger walk + final clearance`

### Task 7.1: EXTEND the existing `integration_test/golden_path_arabic_test.dart` (codex round 1 — P1 #5 + #8)

**Key facts the original draft got wrong:**
- The Arabic golden-path test ALREADY EXISTS at `integration_test/golden_path_arabic_test.dart` (PR1 Task 11 shipped — my original "does not exist" claim was a directory miss; the file lives under Flutter's `integration_test/` runner, not `test/integration/`).
- `pumpRihlaApp` does NOT have a `settings:` parameter. Its actual signature at `test/helpers/pump_rihla_app.dart:33-38` is `pumpRihlaApp(WidgetTester tester, Widget child, {Locale locale, List<Override> overrides})`. It is also NOT router-aware (the helper's doc comment says so).
- The existing integration test does NOT use `pumpRihlaApp`. It boots the real app via `app.main()` after seeding `SharedPreferences.setMockInitialValues({SettingsService.languageKey: 'ar'})` — that's the right pattern for end-to-end ledger navigation.

**File:** Modify `integration_test/golden_path_arabic_test.dart` (add a ledger walk; don't create new).

**Step 1: Read the existing file to understand its conventions**

Run: `cat integration_test/golden_path_arabic_test.dart`
Expected: Sees `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`, the SharedPreferences seed in `setUp`, `app.main()` invocation, `_waitFor` / `_settle` / `_log` helpers. Match those conventions.

**Step 2: Extend the existing test with the full create-group → ledger walk (codex round 3 fix)**

**Current state of the Arabic integration test:** `integration_test/golden_path_arabic_test.dart:39-173` stops at `Key('group_create_screen')` without entering a name or tapping the create button. The Arabic test does NOT actually create a group today. PR2b's extension must complete the create-group flow first, then navigate into the ledger.

**Reference for the full create-group flow:** see the English sibling test `integration_test/golden_path_test.dart:127-148`, which fills `group_name_input` and `group_device_name_input` then taps `group_create_button`. PR2b's extension mirrors that pattern.

After the existing assertion on `group_create_screen` (around L172), continue:

```dart
// PR2b extension — load Arabic delegate once for assertion strings.
// SynchronousFuture via the generated delegate; safe with binding init.
final l10n = await AppLocalizations.delegate.load(const Locale('ar'));

// Complete the create-group flow that the existing test only opened.
// Keys come from lib/features/groups/keys/group_keys.dart.
await tester.enterText(
  find.byKey(const Key('group_name_input')),
  'رحلة الاختبار',
);
await _settle(tester);
await tester.enterText(
  find.byKey(const Key('group_device_name_input')),
  'مختبِر',
);
await _settle(tester);
await tester.tap(find.byKey(const Key('group_create_button')));
await _settle(tester);

// After create, the app navigates to the group's detail/events screen.
// Find and tap into the group's first event ledger. Adjust the predicate
// to match the actual key/text rendered after group creation lands —
// likely a Key('event_card') or similar from features/events/keys/.
await _waitFor(
  tester,
  label: 'group_detail_after_create',
  predicate: () =>
      find.byKey(const Key('group_screen')).evaluate().isNotEmpty ||
      find.byType(EventListTile).evaluate().isNotEmpty,
);

// Tap the first event to enter the ledger. If no default event auto-creates,
// the test will need to walk through event creation first — verify against
// the actual app flow at implementation time. The Arabic plan ships even if
// this step needs an extra create-event tap; the goal is just to land in
// the ledger and assert one Arabic string.
final eventFinder = find.byKey(const Key('event_card')).first;
if (eventFinder.evaluate().isNotEmpty) {
  await tester.tap(eventFinder);
  await _settle(tester);
}

// Wait for the ledger empty-state to render and assert an Arabic string.
await _waitFor(
  tester,
  label: 'arabic-ledger-empty-state',
  predicate: () =>
      find.text(l10n.ledgerEmptyStateTitle).evaluate().isNotEmpty ||
      find.text(l10n.ledgerEmptyStateFirstExpenseBody).evaluate().isNotEmpty,
);

expect(
  find.text(l10n.ledgerEmptyStateTitle).evaluate().isNotEmpty ||
      find.text(l10n.ledgerEmptyStateFirstExpenseBody).evaluate().isNotEmpty,
  isTrue,
  reason: 'Ledger should render at least one Arabic string in ar locale',
);

_log('--- PR2b LEDGER WALK PASSED (locale=ar) ---');
```

**Important:** the exact widget keys (`group_screen`, `event_card`, `EventListTile`) are placeholders — confirm against `lib/features/groups/keys/` and `lib/features/events/keys/` at implementation time. The plan-level test text `'رحلة الاختبار'` ('Test journey') and `'مختبِر'` ('Tester') are example Arabic strings; final wording is a small implementation detail.

**Concrete fallback if the create-group flow in `ar` proves fragile:** scope the assertion down to verifying the `group_create_screen` itself renders Arabic copy. Add an Arabic-locale assertion on whatever PR2b/PR3 translates on that screen (or if it stays English in PR2b scope, then assert against an Arabic Settings/Profile string via deep-link or another navigation path that doesn't require new data). The fallback is acceptance-grade if the create-group flow keeps breaking but the Arabic localization is otherwise demonstrably wired.

**Step 3: Run the integration test (separate runner from `test/`)**

Run: `flutter test integration_test/golden_path_arabic_test.dart -d <sim-id> --dart-define-from-file=config.test.json`

(Optional during development) Start Firebase emulator first if the test depends on seeded backend:
```
firebase emulators:start --only auth,firestore,functions
```

Expected: PASS. If GoogleFonts async fails the test zone, follow the existing test's pattern — it already runs against `app.main()` and has handled font loading historically.

### Task 7.2: Final clearance

**Step 1: Full analyze**

Run: `flutter analyze`
Expected: zero new warnings vs baseline at `main` @ edfd385.

**Step 2: Full test suite**

Run: `flutter test`
Expected: exit 0; all green.

**Step 3: ARB completeness**

Run: `dart run tool/check_arb_completeness.dart`
Expected: `ARB completeness: OK (~235 keys matched)`.

**Step 4: Diff invariants — no untouched files were changed**

Run: `git diff main...HEAD --stat | grep -E "expense_provider|money_serializer|r_amount|firestore.rules|app_router|firebase_options|functions/"`
Expected: empty output. If any of these files appear → STOP, investigate, revert before commit.

**Step 5: Commit Wave 7**

```bash
git add integration_test/golden_path_arabic_test.dart
git commit -m "feat(l10n): PR2b/wave-7 — extend Arabic golden-path with ledger walk"
```

### Task 7.3: Open PR

**Step 1: Push branch**

Run: `git push -u origin feat/l10n-pr2b-ledger`

**Step 2: Create PR**

```bash
gh pr create --title "feat(l10n): PR2b — Ledger surface Arabic translation" --body "$(cat <<'EOF'
## Summary
- Translate the entire Ledger surface to Arabic (~34 files, ~130 new ARB keys)
- Add `AppLocalizations` param to `ledgerCategoryName` so the filter strip's bucket labels render in Arabic. **`ledgerCategoryBucket` substring-matching unchanged**; pre-existing brokenness for Firestore expenses (categoryName is null) deferred to follow-up #8.
- Ship the first Arabic golden-path integration test (closes PR1 Task 11 debt)

Design doc: `docs/plans/2026-05-18-arabic-localization-pr2b-ledger-design.md`
Implementation plan: `docs/plans/2026-05-18-arabic-localization-pr2b-ledger.md`

## Out of scope (filed as follow-ups, not fixed here)
1. `r_amount.dart:84` — extend 3dp rule to {OMR, KWD, BHD}
2. `settle_up_screen.dart:221` — group-currency lookup
3. `ledger_hero_block.dart:262` — replace hardcoded `'OMR'` prefix
4. `expense_editor_body.dart:111` — replace `_tripCurrency => 'OMR'`
5. `transaction_model.dart` — remove dead `description` field
6. `expense_editor_body.dart` — split the 1567-LOC widget
7. `docs/REAL-DEVICE-QA.md` RD-09 — Arabic RTL real-device QA pass

## Side effect (deliberate)
`groups/group_settle_up_screen.dart` renders Arabic earlier than rest of Groups surface — shared-widget cascade, documented in design Q1.

## Codex gate
Cleared on the design doc + this plan before Wave 0 implementation. No [P1] findings.

## Test plan
- [ ] `flutter analyze` clean
- [ ] `flutter test` exit 0
- [ ] `dart run tool/check_arb_completeness.dart` exit 0
- [ ] Extended `integration_test/golden_path_arabic_test.dart` passes (run via `flutter test integration_test/...`, not under `test/`)
- [ ] Coverage ≥80%
- [ ] No diff in BalanceCalculator / MoneySerializer / RAmount / app_router / firestore.rules / Cloud Functions
EOF
)"
```

---

## Plan complete and saved to `docs/plans/2026-05-18-arabic-localization-pr2b-ledger.md`.

**Next: REQUIRED codex gate run BEFORE Wave 0.**

```bash
# Run from the branch
/codex
# Point it at: docs/plans/2026-05-18-arabic-localization-pr2b-ledger-design.md
#            + docs/plans/2026-05-18-arabic-localization-pr2b-ledger.md
# Apply findings, re-run, stop when no [P1]s.
```

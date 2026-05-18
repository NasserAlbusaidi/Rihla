# PR2b — Ledger Surface Arabic Localization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Design rationale: `docs/plans/2026-05-18-arabic-localization-pr2b-ledger-design.md`.

**Goal:** Translate the entire Ledger surface to Arabic (33 files, ~126 new ARB keys), unify the two category-naming systems, and ship a new Arabic golden-path integration test — without altering any money-math or persistence behaviour.

**Architecture:** Display-only translation. ARB keys land en+ar paired (CI completeness lint stays green every commit). Three new helpers at `lib/core/utils/` and `lib/features/ledger/utils/`; one small refactor of `ledger_categories.dart` (substring → exact-match). Each wave is one atomic commit. Codex gate runs against this plan + the design doc BEFORE Wave 0.

**Tech Stack:** Flutter `^3.10.1`, gen-l10n ARB pipeline, Riverpod 2.x, `intl` for date formatting, `mocktail` + `FakeFirebaseFirestore` for tests, `pumpRihlaApp` test helper.

**Pre-flight:**
- Branch: `feat/l10n-pr2b-ledger` (already created off `main` @ edfd385)
- Design doc committed at 657d8b7
- **REQUIRED before Wave 0:** run `/codex` against this plan + the design doc. Apply findings, re-run, stop when verdict has no [P1]s.

---

## Conventions used in this plan

**ARB key writing:** Every new key lands in BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_ar.arb` in the same commit. `tool/check_arb_completeness.dart` (CI) fails if en/ar drift. After editing ARB files, run `flutter gen-l10n` (or `flutter pub get` which triggers gen) — generated bindings land at `lib/l10n/generated/app_localizations*.dart`.

**Consuming a key in Dart:** Add `import 'package:safar/l10n/generated/app_localizations.dart';` if not present (most files already have `context.l10n` extension available via a different import — grep the file first). Replace `'English text'` with `context.l10n.keyName`. For placeholder keys: `context.l10n.editorFailedToAddExpense(errorString)`.

**RTL fix patterns:**
- `Alignment.centerLeft` → `AlignmentDirectional.centerStart`
- `Alignment.centerRight` → `AlignmentDirectional.centerEnd`
- `Alignment.topRight` → `AlignmentDirectional.topEnd`
- `EdgeInsets.only(left: N)` → `EdgeInsetsDirectional.only(start: N)`
- `EdgeInsets.only(right: N)` → `EdgeInsetsDirectional.only(end: N)`
- `Positioned(left: N, …)` → `PositionedDirectional(start: N, …)`

**Widget-translation template (Waves 1-6):** For each widget file:
1. Grep current strings: `grep -nE "'[A-Z][a-zA-Z][a-zA-Z 0-9',.!?:-]+'" <file>`
2. Add en+ar ARB pairs to both files for each user-visible string
3. Apply RTL fixes if listed for the file
4. Replace each hardcoded string with `context.l10n.<key>`
5. Update widget tests that assert on the English string (use `pumpRihlaApp` with default locale = en; tests stay English-assertions because PR2a's harness uses en by default)
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

**Step 1: Add the ~126 new key pairs to both files**

Use the prefix buckets from the design doc Section "ARB key inventory":
- `ledger*` (~22), `editor*` (~42), `customSplit*` (~10), `categoryPicker*` (~5), `category*` (6 — `categoryFood/Transport/Accommodation/Activities/Shopping/Other`), `settleUp*` (~25), `expenseSuccess*` (~6), `timeline*` (3 — `timelineToday/timelineYesterday/timelineRangeSeparator`), `common*` (5 new — `commonApply/commonRetry/commonBack/commonClose/commonGoHome`).

Plural key (first in codebase):
```json
"ledgerPeopleCount": "{count, plural, =1{PERSON} other{PEOPLE}}",
"@ledgerPeopleCount": { "placeholders": { "count": { "type": "int" } } }
```

Arabic counterpart in `app_ar.arb`:
```json
"ledgerPeopleCount": "{count, plural, =1{شخص} other{أشخاص}}"
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
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/utils/expense_scope_display_name.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_ar.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

void main() {
  group('expenseScopeDisplayName', () {
    test('returns English labels for each ExpenseScope', () {
      final l10n = AppLocalizationsEn();
      expect(expenseScopeDisplayName(ExpenseScope.global,   l10n), 'Equally');
      expect(expenseScopeDisplayName(ExpenseScope.subGroup, l10n), 'Group split');
      expect(expenseScopeDisplayName(ExpenseScope.custom,   l10n), 'Custom');
      expect(expenseScopeDisplayName(ExpenseScope.personal, l10n), 'Personal');
    });

    test('returns Arabic labels for each ExpenseScope', () {
      final l10n = AppLocalizationsAr();
      for (final scope in ExpenseScope.values) {
        expect(expenseScopeDisplayName(scope, l10n), isNotEmpty);
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
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/utils/localized_category_name.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

void main() {
  group('localizedCategoryName', () {
    final l10n = AppLocalizationsEn();

    test('returns Arabic-key value for each known id', () {
      for (final id in const ['food','transport','accommodation','activities','shopping','other']) {
        expect(localizedCategoryName(id: id, l10n: l10n), isNotEmpty);
      }
    });

    test('returns fallbackName when id is null and fallbackName is set', () {
      expect(
        localizedCategoryName(id: null, fallbackName: 'Concert tickets', l10n: l10n),
        'Concert tickets',
      );
    });

    test('returns fallbackName when id is unknown', () {
      expect(
        localizedCategoryName(id: 'wibble', fallbackName: 'Concert tickets', l10n: l10n),
        'Concert tickets',
      );
    });

    test('returns categoryOther when both id and fallbackName are missing', () {
      expect(
        localizedCategoryName(id: null, fallbackName: null, l10n: l10n),
        l10n.categoryOther,
      );
    });

    test('returns categoryOther when fallbackName is empty', () {
      expect(
        localizedCategoryName(id: 'wibble', fallbackName: '', l10n: l10n),
        l10n.categoryOther,
      );
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

### Task 0.4: Refactor `ledger_categories.dart` (TDD)

**Files:**
- Modify: `lib/features/ledger/utils/ledger_categories.dart`
- Modify: `test/unit/ledger_categories_test.dart` (or create if it doesn't exist — grep first)

**Step 1: Confirm test file location**

Run: `find test -name "ledger_categories_test.dart"`
- If exists: extend it.
- If not: create `test/unit/ledger_categories_test.dart`.

**Step 2: Write/extend failing tests**

```dart
// test/unit/ledger_categories_test.dart (full skeleton — extend existing if present)
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/ledger/utils/ledger_categories.dart';
import 'package:safar/l10n/generated/app_localizations_ar.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

void main() {
  group('ledgerCategoryBucket — exact-match against seed names', () {
    test('exact seed names return their bucket', () {
      expect(ledgerCategoryBucket('Food & Dining'),   0);
      expect(ledgerCategoryBucket('Transport'),       1);
      expect(ledgerCategoryBucket('Accommodation'),   2);
      expect(ledgerCategoryBucket('Activities'),      3);
      expect(ledgerCategoryBucket('Shopping'),        4);
      expect(ledgerCategoryBucket('Other'),           5);
    });

    test('case/whitespace variants still bucket correctly', () {
      expect(ledgerCategoryBucket('food & dining'),     0);
      expect(ledgerCategoryBucket('  Transport  '),     1);
      expect(ledgerCategoryBucket('ACCOMMODATION'),     2);
    });

    test('unknown names bucket to Other (5)', () {
      expect(ledgerCategoryBucket('Concert tickets'),   5);
      expect(ledgerCategoryBucket('سفر'),               5);  // Arabic free text
      expect(ledgerCategoryBucket(null),                5);
      expect(ledgerCategoryBucket(''),                  5);
    });
  });

  group('ledgerCategoryName(bucket, l10n) returns localized name', () {
    test('English bucket names', () {
      final l10n = AppLocalizationsEn();
      expect(ledgerCategoryName(0, l10n), l10n.categoryFood);
      expect(ledgerCategoryName(1, l10n), l10n.categoryTransport);
      expect(ledgerCategoryName(2, l10n), l10n.categoryAccommodation);
      expect(ledgerCategoryName(3, l10n), l10n.categoryActivities);
      expect(ledgerCategoryName(4, l10n), l10n.categoryShopping);
      expect(ledgerCategoryName(5, l10n), l10n.categoryOther);
    });

    test('Arabic bucket names are non-empty', () {
      final l10n = AppLocalizationsAr();
      for (var i = 0; i < 6; i++) {
        expect(ledgerCategoryName(i, l10n), isNotEmpty);
      }
    });

    test('out-of-range bucket falls back to Other', () {
      final l10n = AppLocalizationsEn();
      expect(ledgerCategoryName(99, l10n), l10n.categoryOther);
    });
  });
}
```

**Step 3: Verify tests fail**

Run: `flutter test test/unit/ledger_categories_test.dart`
Expected: FAIL — `ledgerCategoryName` signature mismatch (currently takes only `int`); exact-match tests fail because current impl is substring-based and matches loosely.

**Step 4: Refactor the implementation**

```dart
// lib/features/ledger/utils/ledger_categories.dart
import '../../../l10n/generated/app_localizations.dart';

/// Stable seed-name → bucket index mapping. Mirrors the 6 default categories
/// seeded in `category_provider.dart`. Case-insensitive trim match.
const _seedNameToBucket = <String, int>{
  'food & dining': 0,
  'transport':     1,
  'accommodation': 2,
  'activities':    3,
  'shopping':      4,
  'other':         5,
};

/// Maps a free-text expense category name onto one of six stable buckets.
///
/// Exact-match (case-insensitive, trimmed) against the 6 seed names. Unknown
/// names bucket to 5 (Other) — including Arabic free-text since the dead
/// custom-CRUD pre-PR2b never produced Arabic seed names.
int ledgerCategoryBucket(String? name) {
  if (name == null) return 5;
  return _seedNameToBucket[name.trim().toLowerCase()] ?? 5;
}

/// Returns the localized display name for a bucket index.
String ledgerCategoryName(int bucket, AppLocalizations l10n) => switch (bucket) {
  0 => l10n.categoryFood,
  1 => l10n.categoryTransport,
  2 => l10n.categoryAccommodation,
  3 => l10n.categoryActivities,
  4 => l10n.categoryShopping,
  _ => l10n.categoryOther,
};
```

**Step 5: Verify tests pass**

Run: `flutter test test/unit/ledger_categories_test.dart`
Expected: PASS — all groups green.

**Step 6: Verify callsites still compile**

The `ledgerCategoryName(bucket, l10n)` signature change breaks existing callsite at `lib/features/ledger/widgets/ledger_category_strip.dart:142`. That callsite gets fixed in Wave 2 (the strip widget). Until then, the file won't compile.

Workaround for clean Wave 0 commit: temporarily patch the callsite to pass `context.l10n`:

```dart
// lib/features/ledger/widgets/ledger_category_strip.dart:142 — temporary, finalised in Wave 2
ledgerCategoryName(bucket, context.l10n),
```

Wave 2 will fully translate this widget; this is just the minimum compilation fix.

Run: `flutter analyze`
Expected: clean.

**Step 7: Commit Wave 0**

```bash
git add lib/l10n/app_en.arb \
        lib/l10n/app_ar.arb \
        lib/l10n/generated/ \
        lib/core/utils/expense_scope_display_name.dart \
        lib/features/ledger/utils/localized_category_name.dart \
        lib/features/ledger/utils/ledger_categories.dart \
        lib/features/ledger/widgets/ledger_category_strip.dart \
        test/unit/expense_scope_display_name_test.dart \
        test/unit/localized_category_name_test.dart \
        test/unit/ledger_categories_test.dart
git commit -m "feat(l10n): PR2b/wave-0 — ARB keys, helpers, ledger_categories refactor"
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
| `lib/features/ledger/widgets/category_selection_step.dart` | 1 | — |
| `lib/features/ledger/widgets/amount_input_section.dart` | 2 | — |
| `lib/features/ledger/widgets/receipt_picker_section.dart` | 5 | — |

**End-of-wave checks:**
- `flutter analyze` → clean
- `flutter test test/features/ledger/widgets/` → all green
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
| `lib/features/ledger/screens/settle_up_screen.dart` | ~12 | SnackBars at L241, L283-307, L319 — drop `const` after localization. |
| `lib/features/groups/widgets/settle_up_page_body.dart` | 15 | **L393**: `EdgeInsets.only(left: 4)` → `EdgeInsetsDirectional.only(start: 4)`. |
| `lib/features/groups/widgets/record_payment_sheet.dart` | 11 | **L469**: `Alignment.centerLeft` → `AlignmentDirectional.centerStart`. |
| `lib/features/groups/widgets/group_settlement_tile.dart` | 1 | — |
| `lib/features/groups/widgets/all_settled_state.dart` | 2 | — |
| `lib/features/groups/widgets/group_settlement_summary.dart` | 0 | RTL audit only — no string changes; confirm via grep. |

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

**Step 1: Plural replacement at L426**

Before:
```dart
Text('${participantCount == 1 ? 'PERSON' : 'PEOPLE'}')
```

After:
```dart
Text(context.l10n.ledgerPeopleCount(participantCount))
```

The generated `AppLocalizations.ledgerPeopleCount(int count)` method handles the plural form selection.

**Step 2: Translate remaining strings + handle empty-state prose carefully (open question)**

`L577,587-588` empty-state prose is multi-sentence. Concatenate the lines into one ARB value (`ledgerEmptyStateFirstExpense`) and replace both Text widgets with a single localized Text or split into 2 keys if the visual hierarchy requires it. **Inspect the widget tree before translating** to choose 1-key vs 2-key.

**Step 3: Verify the plural renders correctly in both locales**

Boot the app in English with `participantCount = 1` and `participantCount = 3`; verify "PERSON" / "PEOPLE". Repeat in Arabic; verify "شخص" / "أشخاص".

**End-of-wave checks:** same as Wave 1.

---

## Wave 7 — Tests + gate clearance

Commit: `feat(l10n): PR2b/wave-7 — Arabic golden-path integration test + final clearance`

### Task 7.1: New integration test

**File:** Create `test/integration/locale_arabic_ledger_test.dart`

**Step 1: Write the test**

```dart
// test/integration/locale_arabic_ledger_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// + Riverpod, mocktail, FakeFirebaseFirestore imports as in existing integration tests
// + import pumpRihlaApp helper
// + import AppLocalizationsAr for expected-string assertions

void main() {
  // Pattern: tester.runAsync wraps the test to allow GoogleFonts async load
  testWidgets('Arabic locale walks ledger end-to-end', (tester) async {
    await tester.runAsync(() async {
      // Boot with languageCode: 'ar' via pumpRihlaApp settings override
      await pumpRihlaApp(tester, settings: AppSettings(languageCode: 'ar'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Navigate Home → group → event → ledger
      // (use ledgerKeys.* / event keys to tap into the flow)

      // Assert at least one Arabic ledger string is visible
      expect(find.text(AppLocalizationsAr().ledgerEmptyStateTitle), findsOneWidget);
      // OR (if data is seeded): assert plural rendering
      // expect(find.text(AppLocalizationsAr().ledgerPeopleCount(2)), findsOneWidget);

      // Tap "Settle up"
      // Assert at least one Arabic settle-up string visible
    });
  });
}
```

**Step 2: Run integration test**

Run: `flutter test test/integration/locale_arabic_ledger_test.dart`
Expected: PASS. If GoogleFonts async fails the test zone, the `tester.runAsync` wrapper catches it (R7 mitigation).

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
git add test/integration/locale_arabic_ledger_test.dart
git commit -m "feat(l10n): PR2b/wave-7 — Arabic golden-path integration test"
```

### Task 7.3: Open PR

**Step 1: Push branch**

Run: `git push -u origin feat/l10n-pr2b-ledger`

**Step 2: Create PR**

```bash
gh pr create --title "feat(l10n): PR2b — Ledger surface Arabic translation" --body "$(cat <<'EOF'
## Summary
- Translate the entire Ledger surface to Arabic (33 files, ~126 new ARB keys)
- Unify the two category-naming systems (substring → exact-match) — fixes silent Arabic-bucketing bug
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
- [ ] New `test/integration/locale_arabic_ledger_test.dart` passes
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

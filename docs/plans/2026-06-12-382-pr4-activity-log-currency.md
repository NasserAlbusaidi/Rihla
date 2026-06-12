# #382 PR-4 — Activity-Log Currency Metadata Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Group-settlement activity logs stamp the settlement's bucket currency into `metadata.currency`; the two amount-displaying feed readers prefer it and fall back to `group.currency` for legacy rows. Display-only; no backfill.

**Architecture:** One client-side writer change (`group_settle_up_screen.dart` already has the bucket `currency` in scope since PR-1/PR-3 — it goes into the settlement doc and the description but is dropped from the activity metadata), one shared validating reader helper in `activity_display.dart`, two row-widget callers. No model change (`GroupActivityLog.metadata` is already `Map<String, dynamic>` passed through verbatim).

**Tech Stack:** Flutter/Dart, Riverpod, existing test fakes (`_RecordingGroupActivityService`, seeded `GroupActivityLog` factories).

**Branch/worktree:** `git worktree add ../Rihla-382-pr4 -b feat/382-pr4-activity-log-currency origin/main` (concurrent-session rule).

---

## Verified ground truth (re-grep before trusting; all against origin/main @ b12a3f00)

**Spec-verification item from the epic — RESOLVED: this PR is client-only, NOT functions-category, no deploy.**
- #248 PR2 locked the **event-scoped** `groups/{gid}/events/{eid}/activity_logs` subcollection (server-only via `expenseAuditLogger`; those docs already carry `currency` in before/after snapshots and `expense_audit_detail.dart` already reads it). Different collection — out of scope.
- The feed readers here read the **group-scoped** `groups/{gid}/activity` collection, which is client-writable: `security/firestore.rules:827` `validGroupActivityCreate` requires `metadata is map` (`:845`) with **no key whitelist inside metadata** → a new `metadata.currency` key passes the deployed rules unchanged. No rules edit.
- Complete writer set of group `activity` docs (grepped `logGroupEvent` callers in `lib/` + `metadata` writers in `functions/src` callables):
  | Writer | type | metadata | amount? |
  |---|---|---|---|
  | `group_settle_up_screen.dart` `_recordSettlement` (logGroupEvent at ~:474, metadata at ~:481 on main) | `group_settlement` | `{amount, recipientId}` | **YES — only one** |
  | `join_group_screen.dart:151` | `member_joined` | `{groupId}` | no |
  | `create_event_screen.dart:155` | `event_created` | `{eventId, eventName}` | no |
  | `event_danger_section.dart:239` | `event_deleted` | `{eventId, eventName}` | no |
  | server `leaveGroup.ts:127` | `member_left` | `{}` | no |
  | server `removeMember.ts:176` | `member_left` | `{memberAction, memberName}` | no |

**Callsite classification (principle 1):**
- OUTBOUND (feeds a write): `group_settle_up_screen.dart` metadata map — the only write-path change.
- INBOUND (display only): `group_activity_screen.dart` `_ActivityRow` (`metadata['amount']` at :427, currency threaded from `:120` `groupAsync.valueOrNull?.currency ?? 'OMR'`); `cross_group_activity_screen.dart` `_ActivityRow` (`:326` coerce, RAmount `:391` with `entry.currency`).
- NOT readers of amount: `lib/features/home/widgets/activity_row.dart` (renders no amount — unaffected); `localizedGroupActivityText` (`group_settlement` → fixed l10n string, no amount/currency embedded — unaffected).
- `dashboard_providers.dart:62` (`currency: group.currency` into `CrossGroupActivityEntry`) **stays unchanged**: it supplies the per-group *fallback*; the preference lives in the row that consumes `entry.currency`. Changing the entry's meaning would silently retag every non-settlement row too.

**Read-path per write-path (principle 3):** `metadata.currency` written by settle-up → read by the two `_ActivityRow`s via the new helper. Nobody else reads `metadata` keys besides `eventName`/`memberName`/`memberAction`/`amount` (grepped).

**Why now:** since PR-1/PR-3, `_recordSettlement` records the settlement doc with the **bucket** currency (`addGroupSettlement(currency: currency)` :453) and formats the description with it (:480), but the activity metadata drops it — a foreign-currency settlement (possible post-PR-6 rules relax; == group.currency for all prod data today) would render in the feed at the wrong precision/label.

**Boundary validation:** `metadata` is client-writable by any group member → the helper accepts `metadata['currency']` only if it is a `String` in `MoneySerializer.supportedCurrencies`; anything else (absent, junk string, num) falls back. Display-only fail-safe, mirrors `_coerceAmount`'s tolerance.

**Display contract for the group feed:** both RAmounts in `group_activity_screen.dart`'s `_ActivityRow` are `showCurrency: false` (bare numbers). A foreign-currency amount with no label is ambiguous money display, so the main 14px RAmount flips to `showCurrency: rowCurrency != currency` — the exact `showCurrency: !sameCurrency` idiom already shipped in `lib/features/activity/widgets/expense_audit_detail.dart:119`. The small 11px sage duplicate stays unlabeled. The cross-group feed RAmount already shows the code unconditionally — only its `currency` value changes.

---

### Task 1: Worktree + baseline

**Step 1:** `git worktree add ../Rihla-382-pr4 -b feat/382-pr4-activity-log-currency origin/main && cd ../Rihla-382-pr4 && cp ../Rihla/config.json . 2>/dev/null; flutter pub get`

**Step 2:** Baseline: `flutter test test/unit/activity_display_test.dart test/features/groups/group_settle_up_screen_test.dart test/features/groups/group_activity_screen_test.dart test/features/home/cross_group_activity_screen_test.dart`
Expected: all PASS.

---

### Task 2: `activityAmountCurrency` helper (TDD)

**Files:**
- Modify: `lib/features/activity/utils/activity_display.dart`
- Test: `test/unit/activity_display_test.dart` (has a `_groupLog` factory taking `metadata` already)

**Step 1: Write the failing tests** — append inside the existing `group('activity display helpers', …)`:

```dart
group('activityAmountCurrency (#382 PR-4)', () {
  test('prefers a supported metadata currency over the fallback', () {
    final log = _groupLog(
      type: 'group_settlement',
      metadata: const {'amount': '7.75', 'currency': 'USD'},
    );
    expect(activityAmountCurrency(log, 'OMR'), 'USD');
  });

  test('falls back when the key is absent (legacy rows)', () {
    final log = _groupLog(
      type: 'group_settlement',
      metadata: const {'amount': '7.750'},
    );
    expect(activityAmountCurrency(log, 'OMR'), 'OMR');
  });

  test('falls back on unsupported or non-string values (client-forgeable map)', () {
    for (final junk in [Object(), 'NOPE', '', 3, 'omr']) {
      final log = _groupLog(
        type: 'group_settlement',
        metadata: {'amount': '1', 'currency': junk},
      );
      expect(activityAmountCurrency(log, 'AED'), 'AED', reason: '$junk');
    }
  });
});
```

**Step 2: Run** `flutter test test/unit/activity_display_test.dart`
Expected: FAIL — `activityAmountCurrency` undefined.

**Step 3: Implement** in `activity_display.dart` (add `import '../../../core/services/money_serializer.dart';`):

```dart
/// Currency for an amount-bearing group-activity row (#382 PR-4).
///
/// Settlement logs stamp `metadata.currency` with the bucket currency the
/// settlement was recorded in; legacy rows lack the key. The metadata map is
/// client-written by any member, so an unsupported value also falls back to
/// the group currency rather than driving display precision.
String activityAmountCurrency(GroupActivityLog log, String fallback) {
  final raw = log.metadata['currency'];
  if (raw is String && MoneySerializer.supportedCurrencies.contains(raw)) {
    return raw;
  }
  return fallback;
}
```

**Step 4: Run** the same test file. Expected: PASS.

**Step 5: Commit** `feat(activity): currency-preferring helper for amount-bearing activity rows (#382 PR-4)`

---

### Task 3: Writer — stamp the bucket currency (TDD)

**Files:**
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart` (metadata map, ~:481)
- Test: `test/features/groups/group_settle_up_screen_test.dart:704`

**Step 1: Make the existing exact-map assertion expect the new key** (this IS the failing test — exact map equality):

```dart
expect(activityService.logCalls.single.metadata, {
  'amount': '7.75',
  'recipientId': 'uid-alice',
  'currency': 'OMR',
});
```

**Step 2: Run** `flutter test test/features/groups/group_settle_up_screen_test.dart`
Expected: FAIL — actual map lacks `currency`.

**Step 3: Implement** — in `_recordSettlement`, the `currency` param (bucket currency) is already in scope:

```dart
metadata: {
  'amount': amount.toString(),
  'recipientId': toUserId,
  'currency': currency,
},
```

**Step 4: Run** the file. Expected: PASS (the #412 offline test asserts only counts — verify nothing else reddens).

**Step 5: Commit** `feat(groups): stamp settlement bucket currency into activity metadata (#382 PR-4)`

---

### Task 4: Reader — group activity feed (TDD)

**Files:**
- Modify: `lib/features/groups/screens/group_activity_screen.dart` (`_ActivityRow.build`, RAmounts at ~:475/:484)
- Test: `test/features/groups/group_activity_screen_test.dart` (seeds raw maps incl. `'metadata'`; group fixture currency is whatever `groupDetailProvider` override carries — reuse the file's existing seeding pattern)

**Step 1: Write the failing test** — seed a `group_settlement` log with `metadata: {'amount': '12.50', 'currency': 'USD'}` in an OMR group, pump, then:

```dart
final amounts = tester.widgetList<RAmount>(find.byType(RAmount)).toList();
expect(amounts.first.currency, 'USD');
expect(amounts.first.showCurrency, isTrue); // foreign → labeled
```

And a legacy-row regression in the same test or a sibling: a settlement log **without** `metadata.currency` renders `currency == 'OMR'` (group currency) with `showCurrency == false`.

**Step 2: Run** `flutter test test/features/groups/group_activity_screen_test.dart`
Expected: FAIL — currency is `'OMR'`/`showCurrency` false for the USD row.

**Step 3: Implement** in `_ActivityRow.build` (import `activity_display.dart` is already there for `localizedGroupActivityText`):

```dart
final rowCurrency = activityAmountCurrency(log, currency);
```

- main 14px RAmount: `currency: rowCurrency, showCurrency: rowCurrency != currency` (the `expense_audit_detail.dart:119` idiom)
- 11px sage RAmount: `currency: rowCurrency` (keeps `showCurrency: false`)

**Step 4: Run** the file. Expected: PASS.

**Step 5: Commit** `feat(groups): activity rows prefer per-log settlement currency (#382 PR-4)`

---

### Task 5: Reader — cross-group activity feed (TDD)

**Files:**
- Modify: `lib/features/home/screens/cross_group_activity_screen.dart` (`_ActivityRow.build`, RAmount ~:391)
- Test: `test/features/home/cross_group_activity_screen_test.dart` (has `_makeEntry(log, name, gid, currency: …)` + RAmount widgetList probes at :226/:258 to mirror)

**Step 1: Write the failing test** — entry with `currency: 'OMR'` (group fallback) whose log carries `metadata: {'amount': '20.25', 'currency': 'USD'}`:

```dart
expect(amounts.single.currency, 'USD');
```

Plus legacy-row regression: log without `metadata.currency` → `amounts.single.currency == entry.currency`. (The existing :250-262 test already proves the entry-currency path; keep it green.)

**Step 2: Run** `flutter test test/features/home/cross_group_activity_screen_test.dart`
Expected: FAIL — renders `'OMR'`.

**Step 3: Implement** — `cross_group_activity_screen.dart` already imports `activity_display.dart`:

```dart
RAmount(
  value: amount,
  currency: activityAmountCurrency(log, entry.currency),
  size: 14,
)
```

**Step 4: Run** the file. Expected: PASS.

**Step 5: Commit** `feat(home): cross-group activity rows prefer per-log settlement currency (#382 PR-4)`

---

### Task 6: Verify + ship

**Step 1:** `flutter analyze` — must be clean.
**Step 2:** `flutter test` — full suite green (80% coverage gate).
**Step 3:** PR with body `Refs #382` (partial delivery of the epic — `Refs` in the **squash commit message** too, not just the body), title `feat(activity): per-log settlement currency in group feeds (#382 PR-4)`. Body carries `Spec: docs/plans/2026-06-12-382-pr4-activity-log-currency.md` + pasted RED outputs (automerge RED-evidence check).
**Step 4:** `/automerge <N>` — classifier will land Gate-category (schema), review + refuter must clear.

---

## Out of scope (do not bundle)

- No backfill of legacy activity docs (epic: display-only).
- No rules change (`metadata is map` already admits the key); no functions change; **no deploy**.
- No consolidation of the duplicated `_coerceAmount` helpers (tangential refactor).
- Event-scoped `activity_logs` audit feed (already currency-aware).
- Richer per-currency feed display (PR-5).

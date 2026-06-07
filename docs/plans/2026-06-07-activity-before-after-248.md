# Activity Feed Renders Expense Audit Before/After — Implementation Plan (#248 — PR 3 of 5)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> **Spec:** Client-only render of the `metadata.before/after` that PR 2's `expenseAuditLogger` trigger writes. `Refs #248` (does NOT close it).
> **Gate:** NOT a Gate category — display-only / INBOUND money, no `BalanceCalculator`/`MoneySerializer` *math* change, no `firestore.rules`, no Cloud Functions, no routing, no schema field-name change. (`MoneySerializer.fromSubunits` is reused as a read-only converter, not modified.) The 7 verification principles are run below; no fresh-context Opus Gate required.
> **Depends on:** PR 2 (#339) at **runtime** (the trigger must be live to populate `metadata`), NOT at code level. PR 3 renders a frozen contract and branches off `main` independently (no file overlap with PR 2 — PR 2 touches `functions/**`, `firestore.rules`, `expense_service.dart`, `activity_service.dart`; PR 3 touches the activity-feed UI). Safe to merge before or after PR 2 because every render path degrades gracefully on absent/empty metadata (legacy entries carry `metadata: {}`).

**Goal:** Under each MONEY activity row, render the money before/after the `expenseAuditLogger` trigger recorded so a reader can see *what* changed, not just *that* something changed. CREATE/DELETE show a `<description> · <amount>` summary; UPDATE shows a `before → after` line per changed field (description, amount, payer).

**Architecture:** A pure parser (`ExpenseAuditDiff.fromMetadata`) turns the trigger's `metadata` map into two optional typed snapshots (`before`/`after`) + per-field change flags, defensively (any malformed/legacy shape → null side → renders nothing). A presentational widget (`ExpenseAuditDetail`) renders the snapshots, resolving `payerParticipantId → name` via the event's `participantNames` map (already in screen context). The feed screen threads `participantNames` from `eventDetailProvider` down to each row and mounts the detail under the existing verb line for MONEY rows.

**Tech Stack:** Flutter/Dart, `decimal`, `MoneySerializer.fromSubunits` (read-only), `RAmount` (money display widget), ARB l10n (`generate: true`), `flutter_test`.

---

## The contract PR 3 renders (frozen — verified against PR 2 code in `../Rihla-248-pr2`)

`expenseAuditLogger.ts` writes, on every CREATE/UPDATE/soft-DELETE of an expense:

```
metadata = {
  expenseId: string,
  before: moneySnap | null,   // null on CREATE (and legacy entries have NO metadata.before)
  after:  moneySnap,          // present on CREATE / UPDATE / DELETE
}
moneySnap(d) = {
  amountFils: number,               // raw subunits (scale per currency)
  currency: string,                 // ISO 4217; default 'OMR'
  payerParticipantId: string | null,
  description: string | null,
  isDeleted: boolean,
}
```
Row identity: `category: 'MONEY'`, `eventType: 'CREATE' | 'UPDATE' | 'DELETE'`. The verb line is already rendered today via `localizedEventActivityText` (`activity_display.dart`) → `activityEventMoney{Created,Updated,Deleted}`. **PR 3 adds only the detail line(s) below it.**

**Backward-compat is the load-bearing requirement:** pre-PR-2 entries (and the test seeds) carry `metadata: {}`. `fromMetadata({})` → `before == null && after == null` → `hasDetail == false` → the widget renders `SizedBox.shrink()` and the row looks exactly as it does today. No crash, no blank box.

---

## Load-bearing design decisions

### D1 — Pure parse layer, defensive, separate from the widget
`ExpenseAuditDiff` / `ExpenseAuditSnap` live in `utils/expense_audit_diff.dart` with no Flutter import, so parsing + change-detection is unit-testable without pumping. `ExpenseAuditSnap.tryParse(raw)` returns `null` unless `raw` is a `Map` with a numeric `amountFils` **and** a non-empty `String currency` — so legacy `{}`, the old client-writer's metadata shape, and any forged/partial map all degrade to "no detail". `amountFils` accepts `num` (`.toInt()`) — Firestore returns `int`, but a JSON-roundtripped double must not throw.

### D2 — `after` is the render gate; `before` drives the diff
- `hasDetail == after != null`. The trigger always writes `after` (even on DELETE — it's the snapshot of the now-deleted doc), so any trigger-written row renders something; only legacy/empty rows render nothing.
- `before == null` ⇒ CREATE (or legacy) ⇒ no `→` diff possible ⇒ summary line.
- Change flags (`amountChanged`/`descriptionChanged`/`payerChanged`) require **both** sides present; `Decimal ==` compares value (not identity), `String?` compares directly.

### D3 — Render shape by `eventType`
| eventType | before | render |
|---|---|---|
| CREATE | null | one summary line: `<description> · <amount(after)>` |
| UPDATE + ≥1 field changed | present | one `before → after` line **per changed field** (description, amount, payer) |
| UPDATE + no tracked field changed (e.g. split-only edit) | present | fall back to summary line of `after` (the row isn't bare) |
| DELETE | present | summary line of `after`, **muted** (whole detail at 0.6 opacity) |

"No tracked field changed" is real: the trigger's `contentChanged` also fires on `categoryId`/`splitMode`/`splitDistribution`, which `moneySnap` does not carry — so an UPDATE can have `before.moneySnap == after.moneySnap`. Falling back to the `after` summary keeps the row informative.

### D4 — Payer name resolution via the event `participantNames` map (uid→name)
`payerParticipantId` is a uid (OMR-only name-based members; `Event.participantNames` is `Map<String,String>` keyed by uid, `event_model.dart:69`). Resolve `participantNames[id] ?? l10n.activitySomeone`. A departed/unknown payer → localized "Someone" (never the raw uid). The screen already watches `eventDetailProvider(eventRef)` and has the event in the `data:` branch — thread `event.participantNames` down to the rows (no new provider/read).

### D5 — Reuse `RAmount`, never re-format money by hand
Amounts render through `RAmount(value: MoneySerializer.fromSubunits(amountFils, currency), currency: currency)`. `MoneySerializer.fromSubunits` is the canonical subunit→`Decimal` converter (scale per currency, incl. OMR=1000 / JPY=1) and `RAmount` is the canonical display (3dp OMR, code prefix, tabular, forced-LTR for Arabic). On an amount **change** line, render `before` with currency code and `after` **without** the code when currencies match (the mockup's `OMR 10.500 → 12.500`); show both codes only on a currency change. No `toStringAsFixed`, no `double`.

### D6 — Only MONEY rows get audit detail
`_ActivityRow` computes `diff` only when `log.category == 'MONEY'`; GEAR/DOCS (legacy, effectively dead post-Phase-39 but still switched in the icon) get `const ExpenseAuditDiff()` (empty) → no detail. Keeps the change scoped to the expense audit surface.

### D7 — Directional layout (RTL)
The `before → after` sequence is a `Row` (mirrors automatically under RTL). The arrow glyph flips with `Directionality.of(context) == TextDirection.rtl ? Iconsax.arrow_left : Iconsax.arrow_right` — the exact pattern already in this file's `_TopBar` (`activity_feed_screen.dart:214`). `RAmount` already forces LTR internally for the numerals.

---

## Verification principles (run against this spec — reported out loud)

1. **Callsite classification (INBOUND/OUTBOUND/BOTH).** The new code is **INBOUND only** — it *reads* `log.metadata` (written server-side by the trigger) and displays it. There is no write path: PR 3 adds no `.set`/`.update`, touches no service, persists nothing. `MoneySerializer.fromSubunits` is a read-only converter. So the "display-formatted string gets persisted" failure mode is structurally impossible here.
2. **Concrete claims re-verified against code (this session):** metadata shape from PR 2's actual `expenseAuditLogger.ts` `moneySnap` (`../Rihla-248-pr2`, lines 85–91 + 171–174) ✓; `Event.participantNames: Map<String,String>` (`event_model.dart:69`) ✓; `ActivityLog.metadata: Map<String,dynamic>` + `category`/`eventType` (`activity_log_model.dart:7-9,75`) ✓; verb mapping `localizedEventActivityText` (`activity_display.dart`) unchanged ✓; `MoneySerializer.fromSubunits(int,String)→Decimal` (`money_serializer.dart:30`) ✓; `RAmount(value:Decimal,currency:String,showCurrency:bool)` (`r_amount.dart:36-45`) ✓; `activitySomeone` exists (`app_en.arb:1035`) ✓; legacy seed uses `metadata: {}` (`activity_feed_screen_test.dart:82`) ✓.
3. **Read-path per write-path.** N/A inbound — but the inverse check matters: *who writes what PR 3 reads?* Only `expenseAuditLogger` (PR 2) and legacy entries. Both are covered: trigger entries render the diff; legacy `{}` render nothing (D2). No other producer writes `metadata.before/after` on a MONEY event row.
4. **Fields enumerated from the type.** `moneySnap` keys (from PR 2 code): `amountFils, currency, payerParticipantId, description, isDeleted`. PR 3 renders `amountFils`(→amount), `currency`, `payerParticipantId`(→name), `description`. `isDeleted` is **not** rendered (the DELETE verb + muted styling already convey deletion; `isDeleted` inside `after` would always be `true` on a DELETE row and `false` otherwise — redundant). Documented so a later reader doesn't think it was forgotten.
5. **Data contracts (exact).** `ExpenseAuditDiff.fromMetadata(Map<String,dynamic>) → {before: ExpenseAuditSnap?, after: ExpenseAuditSnap?}`. `ExpenseAuditSnap = {Decimal amount, String currency, String? payerParticipantId, String? description}`. Widget props: `ExpenseAuditDetail({required ExpenseAuditDiff diff, required String eventType, required Map<String,String> participantNames})`. New ARB key: `activityAuditPayerLabel` (en "Payer", ar "الدافع").
6. **Arithmetic decomposition.** N/A — no balance math, no allocator, no `splitDistribution`, no sum claim. `amountFils` is converted 1:1 to a display `Decimal` via the existing serializer and shown; nothing is summed or split.
7. **Adversarial pass on an orthogonal axis (robustness / malformed input).** The fix is on the *display* axis; the adversarial cases exercise **malformed/hostile metadata** (a forged or legacy entry reaching the reader): (a) `metadata: {}` → renders nothing (no blank box, no throw); (b) `after` present but `amountFils` missing/string → `tryParse` null → nothing; (c) `before` a non-map (e.g. a string) → `tryParse` null → treated as CREATE-style summary, no throw; (d) `payerParticipantId` not in `participantNames` (departed member) → localized "Someone", not a raw uid; (e) huge/negative `amountFils` → `RAmount` renders it (display-safe; negatives are rules-blocked upstream and not PR 3's concern). Same-axis (money math) is deliberately not the example because no math exists here (principle 6).

---

## Tasks

> TDD throughout. `flutter test <file>`; `flutter analyze` clean before any commit. Atomic commits, all `Refs #248`. Branch `feat/248-pr3-activity-before-after` off `main` (worktree `../Rihla-248-pr3`).

### Task 1: Pure diff/parse layer — `ExpenseAuditDiff`
**Files:** create `lib/features/activity/utils/expense_audit_diff.dart`; test `test/unit/expense_audit_diff_test.dart`.
RED → GREEN cases: CREATE (`before` null, `after` present, `hasDetail`, `!hasFieldChange`); UPDATE amount/description/payer each flips exactly its flag; `amountFils:10500,currency:'OMR'` → `amount == Decimal.parse('10.5')` (scale 1000); `num` double coercion; legacy `{}` → `!hasDetail`; `after` missing `amountFils` → `!hasDetail`; `before` a String → `before == null`, treated as create-summary.
**Commit:** `feat(activity): ExpenseAuditDiff parses trigger before/after metadata (#248)`.

### Task 2: Presentational widget — `ExpenseAuditDetail`
**Files:** create `lib/features/activity/widgets/expense_audit_detail.dart`; test `test/features/activity/expense_audit_detail_test.dart`.
RED → GREEN cases (pump with `AppTheme` + `AppLocalizations`, single `pump` — no ticker): UPDATE amount-change renders both `10.500` and `12.500` (findRichText); UPDATE description-change renders both texts; UPDATE payer-change resolves `participantNames` to names; CREATE renders description + amount, no arrow; DELETE renders muted (`Opacity` ≤ 0.6 present) summary; UPDATE with equal money snaps → summary fallback; `!hasDetail` → `SizedBox.shrink` (nothing rendered). Add `activityAuditPayerLabel` to `app_en.arb` + `app_ar.arb`; run `flutter gen-l10n`.
**Commit:** `feat(activity): ExpenseAuditDetail renders money before/after (#248)`.

### Task 3: Wire into the feed — thread `participantNames`, mount the detail
**Files:** modify `lib/features/activity/screens/activity_feed_screen.dart`; extend `test/features/activity/activity_feed_screen_test.dart`.
Thread `event.participantNames` from the `data:(event)` builder → `_buildActivityBody` → `_DaySection` → `_ActivityRow`. In `_ActivityRow`, compute `diff` for MONEY rows and mount `ExpenseAuditDetail` inside the Expanded column, below the verb `Text.rich`. Integration test: seed a `MONEY/UPDATE` log with `metadata.before/after` amounts; assert both render (findRichText); assert a legacy `metadata:{}` row still renders the verb and no detail (no regression — existing tests stay green).
**Commit:** `feat(activity): mount expense audit before/after under MONEY rows (#248)`.

### Task 4: Full suite green + analyze + PR
1. `flutter analyze` → clean. 2. `flutter test` → green (esp. `test/features/activity/`, `test/unit/activity*`). 3. Open PR `Refs #248` (NOT `Closes`), `Spec:` → this file, paste RED→GREEN evidence (#329). `/automerge` (classifier: activity UI is **not** a denylist path → Gate-exempt → native auto-merge on green `readiness`).

## Done checklist (PR 3)
- [ ] `ExpenseAuditDiff.fromMetadata` parses before/after defensively; legacy `{}` → no detail; malformed → no throw.
- [ ] CREATE/DELETE summary line; UPDATE per-changed-field `before → after`; split-only UPDATE → after summary.
- [ ] Amounts via `RAmount` + `MoneySerializer.fromSubunits` (no hand-formatting); currency code shown once when unchanged.
- [ ] Payer ids resolve to names via `participantNames`, "Someone" when unknown; RTL arrow flips.
- [ ] Only MONEY rows render detail; GEAR/DOCS unaffected.
- [ ] No write path / no money math / no rules / no schema change (INBOUND-only).
- [ ] `flutter analyze` clean; full Dart suite green; RED→GREEN pasted in PR; `Refs #248` + `Spec:` line.

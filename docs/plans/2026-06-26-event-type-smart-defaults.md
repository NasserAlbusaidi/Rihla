# Design: Event-type smart defaults (the "personalization of events" revival)

Date: 2026-06-26
Status: DESIGN / DRAFT (pre-implementation — fresh-context reviewed; ready for `writing-plans`)
Mode: office-hours (builder)
Author: Nasser + Claude

## Origin

Pre-1.0 idea, cut for scope in Phase 39: per-event-type **modules** (camping → gear
claim-list, travel → logistics for rooms/cars, etc.). The cut was correct. This doc
revives the *intent* — making an event feel tailored to its type — without rebuilding
the module machinery that died.

## What the code actually says today (verified 2026-06-26)

- **`EventType` is alive and persisted** on every event: `trip / camping / travel /
  nightDayOut / custom` (`event_model.dart:9-14`, written `:163`, read `:126`). Create
  flow shows 4 type chips since #489 (`event_type_config.dart` `selectableTypes`). The
  signal exists end-to-end and is **currently used for nothing but an icon + accent**.
- **`EventModules` is a phantom** — `ledger` is the only surviving module and nothing
  reads its value (#246, owner decision 2026-06-19: keep vestigial). The module *slot*
  in schema + rules exists but is empty. We are **not** filling it; this design needs
  no module.
- **Money is already solved.** Communal spend → one expense, equal split (correct).
  Individual spend → itemized split, which shipped (#203/#605). The grocery-vs-coffee
  behavior proves the user already picks the right tool per situation. **There is no
  splitting problem to fix.**
- **Categories: two systems that disagree, and a latent bug between them.**
  - Picker (`category_provider.dart` `_defaultCategories`): 6 fixed `ExpenseCategory`
    with ids `{food, transport, accommodation, activities, shopping, other}`, each with
    its own `name`/`icon`/`color`. Selected in `_CategoryStrip`
    (`expense_editor_body.dart:1351`), persisted as **`categoryId` only**.
  - **Only `categoryId` is persisted.** `expense_model.dart` `toFirestore` explicitly
    excludes `categoryName`/`categoryIcon` as "legacy join artifacts"; `fromFirestore`
    reads only `categoryId`. `categoryName` is a read-time field that is **always null**
    on the Firebase path.
  - Bucket display (`ledger_categories.dart:12-22`): a SEPARATE layer mapping category
    **name → one of 6 buckets by substring** `{Food, Lodging, Transit, Groceries,
    Activities, Other}`.
  - **LATENT BUG (this design fixes it):** the ledger reads `expense.categoryName`
    (`ledger_category_strip.dart:28`, `ledger_screen.dart:272`, `ledger_day_card.dart:209`)
    and feeds it to `ledgerCategoryBucket`. Because `categoryName` never persists, it is
    null for every live expense → `ledgerCategoryBucket(null) == Other`. So **every
    expense currently renders as "Other"** in the ledger category strip / filter /
    day-card coloring; the Food/Lodging/Transit/Groceries/Activities buckets are dead
    for all real data. (The bucket helpers are used ONLY in those 3 ledger files — NOT
    in the hero, NOT in recap; `EventRecap` has no category dimension at all.)
- **Soft, context-derived defaults are already an established pattern**: add-expense
  derives "last-used-in-event → group default" for currency (`add_expense_screen.dart:156-175`,
  #382 PR-6), and the default split mode is already soft — seeded from
  `settingsProvider.defaultSplitMode` at `expense_editor_body.dart:238`. The editor takes
  `eventId` (string), not an `Event`; the live `Event` comes from `eventDetailProvider`
  in `build()` (`:652`) as `valueOrNull` (null while loading) — so reading `event.type`
  needs no new plumbing, but per-type logic **must define a null-event fallback**.

## The reframe + governing principle

"Personalization of events" for a money app = **the event type pre-tunes the existing
ledger**, not a new surface beside it.

> Personalization should make the first expense *faster*, not make the event feel
> *bigger*. Soft defaults: preselect/suggest, never force or block. Change copy and
> ordering, not money rules. Reuse ledger/settle-up/recap/activity/invite as-is. No new
> Firestore collections.

(Principle converged independently by Nasser, Claude, and Codex.)

## v1 scope (decided)

1. **Reconcile the two category systems into one id-driven taxonomy (also fixes the
   latent "everything → Other" bug).** Build a single client-side
   `categoryId → {display name (l10n), icon, color}` table — the picker's
   `_defaultCategories` already holds id→name/icon/color, so reuse it as the source of
   truth. Make the ledger strip/filter/day-card key off the persisted **`categoryId`**
   instead of the always-null `categoryName`. Unknown or null `categoryId` → Other
   (the real fallback; the old substring matcher is inert because `categoryName` is null
   for every row). Retain all 6 existing ids unchanged so legacy expenses keep their
   category. **This slice is independently valuable as a bug fix** and could ship as its
   own PR.

2. **Expand the built-in category set** from 6 to a curated ~10–11 (proposal below),
   no CRUD, no storage, still hardcoded client-side. Covers the real gaps (groceries
   distinct from dining, drinks, fuel, fees) including better camping/travel coverage.

3. **Per-type category ordering** — `EventTypeConfig` gains a per-type priority order
   over the (expanded) categories. Camping leads Groceries/Fuel/Food; night-out leads
   Food/Drinks/Tickets; travel leads Accommodation/Transport/Activities. Unlisted
   categories append in default order; **`event == null` (still loading) → default order**.

4. **Per-type recap noun/tone** — same math, different label ("Trip total" / "Outing
   total" / "Camping total"). Recap is a pure projection (`event_recap.dart`), so this
   is copy only. (NOT a category breakdown — recap has no category dimension.)

5. **Per-type empty-state copy** — the ledger empty state speaks the event's language.

### Deliberately NOT auto-selecting a split mode per type (safety refinement)

The originating insight was "camping = equal, night-out = itemized." The *safe* way to
honor it is to let per-type config **prioritize / surface** the likely split affordance
— never to auto-select it. Auto-defaulting night-out to `exact`/itemized would persist
an incomplete split if the user doesn't then assign items. So in v1 the default split
mode stays `equally` / the user setting (unchanged write-path). "Lead with itemized" is
a fast-follow at most, and stays a pre-selection the user confirms.

## Proposed expanded category set (to confirm)

Core (keep, do not rename — legacy `categoryId`s): Food & Dining, Transport,
Accommodation, Activities, Shopping, Other.
Add: **Groceries** (camping case; also closes the picker/bucket gap), **Drinks**
(night out), **Fuel** (camping / road trip), **Fees** (campsite fee, visas, service
charges), **Tickets** (events/entertainment — or fold into Activities).

Color constraint (resolved below): the theme has exactly `cat1..cat6`, so >6 categories
needs either new `cat7+` tokens or a defined color-reuse map. Decide the final count
against that.

## EventTypeConfig additions (the per-type "profile")

Extend the existing static config (`event_type_config.dart`) — already holds
icon/label/color/description:
- `List<String> categoryOrder` — category ids in priority order (null-event → default).
- recap noun (l10n key).
- empty-state copy (l10n key).
- (later, optional) quick-add name chips that pre-fill the expense name and map to a
  real categoryId — deferred from v1 unless ordering proves insufficient.

## Out of scope / explicitly deferred (with why — do not re-litigate without new evidence)

- **User-created categories** — a real CRUD feature: new group-level storage + new
  `firestore.rules` validation + reworking the bucket layer so customs don't collapse
  to "Other". Orthogonal to event type and reverses the "faster not bigger" principle
  (makes the user do the personalization work). Revisit ONLY if expanded built-ins prove
  insufficient. (Chosen against 2026-06-26: "Expand built-ins + per-type order".)
- **Bring/buy planning list** — a real coordination job, but a new Firestore surface
  with a thin money connection (the buy-list collapses to one expense anyway). Closest
  thing to the cut modules. Separate validated bet.
- **Capability modules (gear claim, rooms/cars logistics)** — stay cut (Phase 39).
  Unvalidated, 0 users. Do not reintroduce.

## Gate assessment — Gate-EXEMPT (both blocking unknowns resolved)

v1 changes copy, ordering, and category VALUES — no money math, no new schema fields,
no routing. Both prior unknowns resolved toward exempt:

1. **`firestore.rules` does NOT constrain `categoryId`.** It is validated only as free
   text: `validFreeText(d.categoryId)` (create, `firestore.rules:553`), diff-gated
   re-validate on update (`:566-567`), `nullableString` (`:610`). New short ids
   (`groceries`, `drinks`, `fuel`…) pass trivially → **adding category ids touches no
   rules.**
2. **Color tokens are exactly `cat1..cat6`** (`color_tokens.dart` fields `:221-236`,
   light `:303-308`, dark `:365-370`, copyWith, lerp). >6 categories needs `cat7+`
   (field + light + dark + copyWith + lerp — all inside `lib/core/theme/tokens/`, exempt
   from the hardcoded-`Color()` ban) OR a color-reuse map. Either is a token-dir edit,
   not a Gate trigger.

`categoryId` is OUTBOUND (feeds a write), but expanding its *value domain* is not a
schema/field-name change and passes the existing rules. No v1 item touches
`BalanceCalculator`/`MoneySerializer`/routing. → **Skip the Gate; just build.** (If a
later slice wires the split default per type, re-evaluate that one piece.)

## Test impact (deliberate updates, not surprises)

- `test/features/ledger/category_provider_test.dart:15-20` pins `hasLength(6)` + the
  exact id list + every `isDefault` → updated in Slice 2.
- `test/unit/ledger_categories_test.dart` pins the 6 bucket names + out-of-range→Other →
  touched in Slice 1 (bucket scheme → id-driven).
- Slice 1 needs a NEW regression test asserting the real baseline (a persisted
  `categoryId='food'` currently renders "Other") and the fix (renders "Food").
- After adding `cat7+` tokens, run `bash tool/check_theme_purity.sh` (CI-only step).

## Open questions

- Final category set + per-type priority order per type (confirm the lists).
- `cat7+` new tokens vs color-reuse map for the expanded set.

## Next step

`superpowers:writing-plans` → slice it:
- Slice 1: id-driven taxonomy reconciliation (fixes "everything → Other") — pure
  refactor + bug fix, pinned by a regression test. Independently shippable.
- Slice 2: expanded category set + tokens/l10n + updated category_provider_test.
- Slice 3: per-type ordering + recap noun + empty-state copy (with null-event fallback).

## What I noticed

- You cut these for scope and *still* think it was right — then asked anyway. Correct
  instinct: revisit the intent, distrust the original implementation.
- The grocery-vs-coffee story did the design work. "I bought everything and logged 24
  OMR shared by all" vs "each homie ordered their own → itemized" is the whole spec for
  why money needs no fix and what the type signal is actually for.
- You reached for custom categories the moment categories came up. Real want, but the
  expensive user-effort version. Parked, not dismissed.

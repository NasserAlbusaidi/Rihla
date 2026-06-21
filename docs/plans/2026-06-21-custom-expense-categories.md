# Custom Expense Categories (Creator-Managed) — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL when picked up: `superpowers:executing-plans` to implement task-by-task.
>
> **STATUS: DEFERRED / FUTURE FEATURE.** Tracked in [#638](https://github.com/NasserAlbusaidi/Rihla/issues/638). Not scheduled. This doc captures the design and surface map so a future session can pick it up cold. **Do not start coding from this doc as-is** — it is pre-Gate. Two things must happen first (see § Before You Build).

**Goal:** Let a group creator define custom expense categories (name + icon + color) in addition to the built-in defaults, persisted per group, and render them consistently everywhere a category shows.

**Architecture:** Persist category *definitions* in a `groups/{gid}/categories` subcollection. Collapse the two category systems that exist today (hardcoded input set + keyword-bucket display set) into one **definition-resolved** path: display resolves icon/color/name by the expense's `categoryId`, falling back to the existing keyword bucket only for unresolvable/legacy ids. Built-in defaults stay virtual (merged in the provider, not written per group). Custom = name + pick-from-fixed-icon-set + pick-from-fixed-color-palette (bounded, theme-safe — never arbitrary icons or raw hex).

**Tech Stack:** Flutter, Riverpod 2.x (no codegen), Firestore (subcollection + rules), `decimal` not relevant (categories don't touch money). No new Cloud Functions.

---

## Why this is a real project (and why it was deferred)

Categories are **cosmetic in a splitter** — `balanceAggregator.ts` explicitly treats `categoryId` edits as not moving money. So the payoff is organizational polish, not correctness. The cost is disproportionate because the feature forces us to finally **merge two category systems that don't agree today**. Recorded rejected/cheaper alternatives:

- **A — Stay hardcoded (status quo).** Zero work. The fallback if this is never prioritized.
- **B — Free-typed inline label.** Store an arbitrary `categoryId` string on the expense, no persisted definition. Cheap, but renders as grey "Other" (no icon/color), no reuse, not localized. "Tags lite."
- **Cheap win, independent of this plan:** the **input set and display buckets are misaligned today** (input `shopping`/`activities` vs display buckets `Groceries`/`Activities`). Realigning the 6 hardcoded categories to the 6 display buckets is a one-PR fix that gives most of the "feels limiting" relief without any of this. Consider doing that first regardless.

This plan is **Option C — full creator-managed custom set.**

---

## Current state (verified 2026-06-21 against `main`)

Two category systems coexist:

1. **Input set** — `lib/features/ledger/providers/category_provider.dart`: `tripCategoriesProvider` is `StreamProvider.family<List<ExpenseCategory>, String>` that just `Stream.value(_defaultCategories)` — 6 hardcoded (`food, transport, accommodation, activities, shopping, other`). Comment: *"Custom categories via the legacy backend have been removed."* The `.family<…, tripId>` signature is **already shaped for a per-group source** — picking this up means making it actually read Firestore.
   - **Only one consumer:** `lib/features/ledger/widgets/expense_editor_body.dart:650` (the editor `_CategoryStrip`).

2. **Display set** — `lib/features/ledger/utils/ledger_categories.dart`: `ledgerCategoryBucket(name)` keyword-matches *any* string into 6 fixed buckets → `ledgerCategoryName` (l10n), `ledgerCategoryColor` (tokens `cat1..cat6`), `ledgerCategoryIcon` (Iconsax). Keys off `expense.categoryName` (a legacy read-time join field), **not** `categoryId`.
   - **Consumers:** `ledger_day_card.dart:199,372,382`; `ledger_category_strip.dart:28,156,162`; `ledger_screen.dart:272` (the category **filter**).

3. **Localization bridge** — `lib/features/ledger/utils/localized_category_name.dart`: maps the 6 known ids → l10n keys, falls through to raw `fallbackName`. Consumers: `expense_editor_body.dart:1408`, `expense_success_dialog.dart:223`, `ledger_search_sheet.dart:436,449`.

**Model** — `lib/features/ledger/models/expense_category_model.dart`: `ExpenseCategory{id, tripId, name, icon, color(hex), isDefault, createdAt}` with snake_case `fromJson`/`toJson` (`trip_id`, `is_default`) — **legacy Supabase-era artifacts**. `iconData` switch handles only `gas/food/gear/lodging/transport/other`. `resolveColor` parses the hex `color` with a `tokens.success` fallback.

**Storage / rules** — the expense doc stores `categoryId` as **free-text** (`firestore.rules`: `validExpenseFreeText` → `validFreeText(d.categoryId)`, ≤280, plus `nullableString` in `validExpenseBase`). **No whitelist — the DB has never been the constraint.** `expense.categoryName/categoryIcon` are excluded from `toFirestore` (read-time join only).

**No server triggers** consume category. **No `groups/{gid}/categories`** collection exists.

---

## Before You Build (mandatory, in order)

1. **Brainstorm the open decisions** (`superpowers:brainstorming`) — resolve every item in § Open Decisions. They change the schema and the rules; do not guess.
2. **Run the Gate** (`/run-the-gate`) on the resolved spec — this is **Gate-category** (new subcollection + `firestore.rules` + a model/schema field with read- and write-paths). Apply P1s, re-run with a fresh subagent each round until 0 P1.
3. Then expand the leaf tasks below into bite-sized TDD steps and execute.

PRs land via `/automerge` → routes to the **gated** path (touches `security/firestore.rules` + `**/models/**.dart`). Rules change → **`deploy-ceremony`** after the PR1 merge (advances `backend-deployed` tag). No client-compat gating — no real users yet.

---

## Open Decisions (resolve in brainstorming — each shapes schema/rules)

1. **Color storage: token-index vs hex.** Recommend a **palette index** (e.g. `colorIndex: 0..N` into an expanded `colors.catN` set) over the legacy hex `color` field — stays theme-aware (dark/light) and avoids any temptation to surface raw hex. Existing `resolveColor(hex)` becomes `resolveColorIndex(tokens, i)`. Decide the palette size (today only `cat1..cat6` tokens exist — adding customs likely needs more tokens in `color_tokens.dart`).
2. **Icon set.** Custom categories pick from a **fixed enumerated icon set** (store an `iconKey` string, map to Iconsax in code — never arbitrary). Decide the set (~12–16 icons). Today `iconData` only knows 6 keys; expand the map.
3. **Authz: creator-only vs any member.** "The creator creates more" → recommend **creator-only** create/edit/delete to start (mirror the member-create CREATOR branch: `groupData(groupId).createdBy == request.auth.uid`). Leave a hook for a future `categoryEditPolicy` (mirror the `ledgerEditPolicy` pattern). Decide.
4. **Defaults: virtual vs seeded.** Recommend **virtual** — the provider merges 6 built-in defaults + custom docs; don't write 6 docs into every new group (avoids a createGroup write-path change + keeps defaults localized by id). Custom docs render their stored name verbatim (free-text, not localized — user's own words). Decide.
5. **Delete semantics.** Categories are referenced by historical expenses → **soft-delete** (`isDeleted`/`deletedAt`), never hard-delete (consistent with the soft-delete invariant). A soft-deleted category still resolves for old expenses but drops out of the picker. Decide whether deleted categories are reassignable.
6. **Management UI home.** Likely Group Settings → Manage (where member management lives). Confirm the exact route/screen.
7. **Filter migration.** `ledger_screen.dart:272` filters by **bucket** today. New world filters by `categoryId`. Confirm the filter chip strip (`ledger_category_strip.dart`) drives off resolved definitions, not buckets.

---

## Architecture: the resolver is the spine

The single most important design move: introduce one resolver and route **every** display site through it.

```
categoryResolverProvider(groupId) -> CategoryResolver
  - merges: 6 built-in defaults (virtual, l10n by id) + group custom docs (streamed)
  - resolve(categoryId) -> ResolvedCategory{ displayName, icon, color }  (theme-resolved at call site)
  - fallback when categoryId is null / unknown / soft-deleted:
        keyword bucket (ledgerCategoryBucket) on the legacy name  ← KEEP as safety net
```

`ledger_categories.dart` (keyword bucketing) is **demoted to the fallback path**, not deleted — it still handles legacy expenses whose `categoryId` predates definitions or points at a removed custom category. This preserves WYSIWYG/no-blank-rows for old data.

---

## Suggested slicing (multi-PR — keep each independently revertable)

### PR1 — Persistence + rules (BACKEND, Gate + deploy-ceremony)
- New `lib/features/ledger/models/expense_category.dart` (rewrite; drop snake_case Supabase artifacts; fields per Open Decisions 1–2,5): `id, groupId, name, iconKey, colorIndex, isDefault, isDeleted, deletedAt, createdAt, createdBy`. `toFirestore`/`fromFirestore` (camelCase, Firestore-boundary only).
- `security/firestore.rules`: new `match /groups/{groupId}/categories/{categoryId}` block. Mirror the `members` block pattern (`isGroupMember` read; creator-gated create/update per Decision 3; soft-delete-only update path; `hasOnly([...])` key allowlist; `isValidDisplayName`/`validFreeText` on name; bounded `iconKey`/`colorIndex`).
- TDD: emulator tests under `functions/` rules-publish-readiness style **and** Dart model round-trip tests. Tests: creator can create; non-creator create denied; oversized name denied; out-of-range colorIndex denied; soft-delete allowed, hard-delete denied; unknown key denied.
- **Deploy:** `deploy-ceremony` after merge (rules only; no functions).

### PR2 — Resolver unification (CLIENT-ONLY)
- New `categoryResolverProvider(groupId)` + `CategoryResolver` + `ResolvedCategory`.
- Make `tripCategoriesProvider` read the subcollection (merge defaults + custom) instead of `Stream.value`.
- Rewire all display consumers to the resolver with bucket fallback: `ledger_day_card.dart`, `ledger_category_strip.dart`, `ledger_screen.dart` filter, `expense_success_dialog.dart`, `ledger_search_sheet.dart`.
- TDD: resolver returns custom def for a known id; returns l10n default for a built-in id; falls back to keyword bucket for unknown/soft-deleted id; filter matches by categoryId.

### PR3 — Creator management UI (CLIENT-ONLY)
- Manage-categories screen (Group Settings → Manage), gated to creator: list defaults (read-only) + custom (edit/soft-delete), "Add category" with name field + icon picker (fixed set) + color picker (fixed palette).
- Offline: it's a plain Firestore write; the strip streams from the SDK offline cache. If any UI step gates on the write completing, respect the **#412 server-ack trap** (`awaitServerAck` / `noteQueuedWrite`) — don't await the raw `set` future.
- TDD: widget tests for add/edit/soft-delete; non-creator sees read-only; RTL/AR label check.

### PR4 — Editor integration polish (CLIENT-ONLY)
- `_CategoryStrip` in `expense_editor_body.dart` shows defaults + customs from the resolver; selecting a custom writes its `categoryId`.
- Remove now-dead reliance on `expense.categoryName` for the editor chip display.
- TDD: picking a custom category persists its `categoryId`; ledger row + success dialog render the custom name/icon/color (proves the round-trip through the resolver).

---

## Out of scope (do not fold in)

- Category rename **cascade** to historical expenses (none needed — display resolves live by id; `categoryName` is a dead join field).
- Per-expense multi-category / tags.
- Spending-by-category analytics (separate; categories must be definition-resolved first — this plan is the prerequisite).
- Realigning the 6 hardcoded defaults to the display buckets — that's the cheaper standalone fix (§ Why), ship it independently.

## Landmines (project-specific)

- **Theme purity CI** (`tool/check_theme_purity.sh`, CI-only): no hardcoded `Color(0xFF…)` in `lib/` outside tokens. Store `colorIndex` and resolve via `context.colors`; if you must parse a persisted hex, that's data not a literal but prefer the index. New widgets need the justification comments — copying a styled block silently drops them (cost #615).
- **Soft-delete invariant** — categories referenced by expenses must soft-delete, never hard-delete.
- **`fake_cloud_firestore`** cursor clause order if the category list paginates (cursor-then-limit). Unlikely to matter at category counts.
- **No new global repository** — extend `FirestoreRepository` / an existing ledger service for category CRUD.
- **`tripCategoriesProvider` rename** — it's mis-named (`trip` is legacy). Consider renaming to `groupCategoriesProvider` in PR2; grep the single editor consumer.

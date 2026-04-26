# Phase 39: Strip to Shippable v1 — Context

**Created:** 2026-04-26
**Source:** Direct decision from app owner — "I want to make this app shippable" by stripping feature bloat.

## Intent

Reduce the surface area of Rihla to the smallest set of features that delivers the core value statement:

> Groups persist across events and accumulate financial history — friends settle up across trips, not just within one.

Anything outside of that loop is bloat to remove. This phase deletes — it does not refactor. The goal is fewer files, fewer collections, fewer dependencies, fewer screens. After this phase, the app is shippable as v1.

## What Stays (the shippable v1 surface)

- **auth** — anonymous Firebase auth
- **groups** — create, join via invite code, member management, group-level balances
- **events** — create events inside a group from templates
- **ledger** — expenses (incl. receipts via StorageGateway), splits, settle-up, settlement history
- **home** — dashboard listing groups
- **activity** — group activity feed (settle-up history is the only activity people care about)
- **settings** — preferences, theme toggle, profile

## What Gets Cut (the six feature areas)

### 1. memories
- **Delete:** `lib/features/memories/` (entire directory)
- **Firestore:** `trip_memories` collection
- **Storage:** `trip-memories` bucket
- **SQLite:** any memories tables / migrations
- **Cloud Functions:** memories-related callables added in Phase 38 (`listMemoriesWithUrls`)
- **Routes:** `/event/:eid/memories`, `/event/:eid/memories/:memId`, `FullScreenPhoto` overlay
- **CommandCenter:** memories module card; `TripModules.memories` flag
- **Why:** photo storage is Instagram-lite; heavy Firebase Storage cost, unclear retention, not why anyone joins a group expense app. Highest bloat-to-value ratio.

### 2. vault
- **Delete:** `lib/features/vault/` (entire directory)
- **Firestore:** `documents` collection
- **Storage:** `trip-documents` bucket
- **SQLite:** `documents` table + related migrations
- **Cloud Functions:** documents-related callables added in Phase 38 (`listDocumentsWithUrls`)
- **Routes:** `/event/:eid/vault`
- **CommandCenter:** vault module card; `TripModules.docs` flag
- **Why:** users use Apple/Google Files for documents. Competing with the OS is a losing fight.

### 3. logistics
- **Delete:** `lib/features/logistics/` (entire directory)
- **Firestore:** logistics collection (if separate; otherwise nested fields on event)
- **Routes:** `/event/:eid/logistics`
- **CommandCenter:** logistics module card; `TripModules.logistics` flag
- **Why:** notes-field-pretending-to-be-a-module. Not a module.

### 4. onboarding
- **Delete:** `lib/features/onboarding/` (entire directory)
- **SharedPreferences:** `onboardingCompleteProvider` flag
- **Routes:** `/onboarding` route + redirect logic in `app_router.dart`
- **Why:** friction before value. Empty home screen teaches the app better than a 3-page intro.

### 5. gear
- **Delete:** `lib/features/gear/` (entire directory)
- **Firestore:** gear_items collection
- **SQLite:** `gear_items` table + related migrations
- **Routes:** `/event/:eid/gear`
- **CommandCenter:** gear module card; `TripModules.gear` flag
- **Why:** checklist feature creep. If users want a packing list, they'll write a note in the app or use any of a hundred packing-list apps.

### 6. multi-currency + Thawani payments
- **Delete:** `thawani_payment` package from `pubspec.yaml` (and `pubspec.lock`)
- **Delete:** all FX/conversion code paths in expense and balance providers
- **Schema:** `base_currency` field on `trips` (Firestore + SQLite); `currency` field on expenses if separate from app default
- **UI:** currency picker in trip creation, currency override in expense add/edit, FX rate display
- **Why:** Rihla is an OMR group ledger. Live FX rates and a payment processor MVP add complexity for a use case (international group spending) that no current user has asked for. "Mark as settled" replaces the payment processor.

## What Stays Despite the Cut

- **StorageGateway** (built in Phase 38) — still has purpose: receipts for ledger expenses
- **Receipts** — part of ledger, kept; they ride on StorageGateway
- **Decimal package** — financial precision still required for OMR
- **Activity feed** — kept, scoped to settle-up events (not the broader "activity log" originally envisioned)

## Suggested Wave Order (planner can refine)

1. **Wave 1 — Make features unreachable.** Kill GoRouter routes, remove module cards from `CommandCenter`, prune `TripModules` field. App still compiles; deleted features cannot be navigated to.
2. **Wave 2 — Delete Flutter source.** `rm -rf lib/features/{memories,vault,logistics,gear,onboarding}` + matching `test/features/*` directories. Run `flutter analyze` and chase the import errors.
3. **Wave 3 — Prune cross-feature references.** Services, providers, models, and shared widgets that reference deleted features. Prune unused fields (`TripModules.memories` etc.) and migrations.
4. **Wave 4 — Drop infra & deps.** Drop Firestore collections, remove Storage buckets (`trip-documents`, `trip-memories`), drop SQLite tables and bump schema version, remove `thawani_payment` from `pubspec.yaml`, tighten Storage and Firestore security rules to deny removed paths, remove Phase 38 Cloud Functions for memories/vault.
5. **Wave 5 — Verify.** `flutter analyze` clean, `flutter test` green, smoke-test the surviving golden path (auth → create group → invite → join → create event → add expense → settle up).

## Risk & Reversibility

- **Destructive.** Deletes ~5 feature directories, drops collections/buckets/tables, removes a package dependency, removes Cloud Functions.
- **Reversible.** All git-reversible. Pre-ship — no production user data to migrate.
- **Confirm before mass-delete.** Each wave should be its own commit. The user has already approved the cut list at intent level; the executor should still pause before destructive ops in Wave 4 (Storage bucket deletion is the only non-git-reversible action).

## Non-Goals

- **Not a refactor.** Don't rewrite surviving code. Don't reorganize `shared/widgets/`. Don't touch theme tokens. Don't modify ledger logic.
- **Not a v2 release plan.** This phase makes v1 shippable. Marketing, app store listings, screenshots — separate work.
- **Not a feature freeze beyond this list.** Future phases can re-add anything; the bar is "user explicitly asked for it after using v1."

## Acceptance

Phase 39 is done when:

1. The five feature directories no longer exist on disk.
2. `pubspec.yaml` has no `thawani_payment` line; `flutter pub get` succeeds.
3. `flutter analyze` reports zero issues.
4. `flutter test` reports zero failures.
5. A manual smoke test of the surviving flow on a clean device install completes without error.
6. Firestore rules and Storage rules deny access to all removed paths.
7. The CommandCenter for an event shows only Ledger (and Activity if kept at event level).

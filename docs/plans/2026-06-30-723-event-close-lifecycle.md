# Event Close Lifecycle (#723, Slice 5 of #202) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an explicit, admin-triggered "Close trip" lifecycle to events — once closed, an event's *spending* is read-only (no new/edited/deleted expenses) while *settlements stay live* — backed by `firestore.rules`, with a reopen escape hatch.

**Architecture:** Mirror the established soft-delete pattern (`isDeleted`+`deletedAt`) with a parallel **`isClosed`(bool) + `closedAt`(timestamp) + `closedBy`(uid)** triple on the event doc. The bool is the load-bearing, immediately-readable gate (offline-safe, unlike a pending serverTimestamp); `closedAt`/`closedBy` are display metadata. Enforcement is a **new `eventNotClosed` rules predicate wired ONLY into the two expense-write rules** — settlements keep the untouched shared `eventAllowsClientWrites` helper so they remain writable after close. Close/reopen are two new admin-gated event-update rule paths producing a clean 3-key diff. Zero balance-math change: no provider, the oracle, or `recomputeNet` reads the close fields.

**Tech Stack:** Flutter/Dart, Riverpod 2.x, Firestore (offline persistence), `firestore.rules` v2, Jest + `@firebase/rules-unit-testing` under the emulator (Java 21), `flutter_test`.

**Issue:** #723 · Parent epic #202 · Gate-category (schema field read+write path + `firestore.rules`) · model:opus-4.8.

---

## Design decisions (locked, with rejected alternatives)

- **`isClosed` is a NEW bool field, NOT a reuse of `isDeleted`.** A closed event stays visible in lists and still contributes its expenses/settlements to every balance. Soft-delete filters the event out entirely. Independent semantics → independent fields. *(Rejects the mapping-agent's "reuse isDeleted" suggestion.)*
- **The close-gate is a SEPARATE predicate, not added to `eventAllowsClientWrites`.** That shared helper gates expense create/update **and** settlement create (rules L635/L691/L791). Adding `closedAt==null` there would freeze settlements too, violating the epic's "settlements must still update after closeout." Instead add `eventNotClosed(groupId,eventId)` and wire it into **only** `validExpenseCreate`/`validExpenseUpdate`. *(Rejects the agent's "remove `eventAllowsClientWrites` from settlement create" — that would wrongly let settlements write on a soft-deleted event, dropping the group-not-deleted + event-not-deleted guards.)*
- **Read-only scope = expense writes only.** Closing blocks expense create/edit/soft-delete. It does **NOT** block event meta edits (rename/dates/description/participants) or event soft-delete. Rationale: "spending frozen" is the money guarantee; cosmetic meta edits don't touch money, and gating the light/admin event-update paths on closed-state would also trap soft-delete. Broader meta-freeze is a deliberate **non-goal** for this slice (smaller change + follow-up). *(Surfaced explicitly so the Gate sees it's intentional.)*
- **Reopen is included** (admin-only). An irreversible "Close" is a UX trap; the rules cost is one extra update path. Slice 5's recap is live-computed (no snapshot yet), so reopen→edit→reclose is trivially clean. The `spendingSnapshot` freeze that makes reopen non-trivial is **Slice 6 (#202 epic), out of scope here.**
- **Close is allowed with outstanding balances.** That is the point — freeze spending, settle later. No settled-ness gate on close. (Mockup: "4 people still owe. Settlements stay live after close.")
- **Admin = event creator OR group creator**, via `EventPermissions.isEventAdmin` (client) mirroring `requesterIsEventAdmin()` (rules). Same authority as event soft-delete today.
- **No new `EventCloseout` screen.** Slices 1–3 already shipped `event_recap_screen.dart` at `/group/:gid/event/:eid/recap`. Slice 5 only adds the lifecycle + read-only banner; recap reachability is unchanged (still gated on has-expenses). *(Rejects the agent's "route to a separate EventCloseout screen" — that conflates with already-shipped slices.)*
- **No money-math change.** `group_balance_provider`, `event_recap_provider`, `ledger_view_provider`, the TS oracle, and `recomputeNet` read none of the close fields. Verified. The Gate must confirm this stays true.

## Exact data contracts

**Close write** (`EventService.closeEvent`, partial `.update`):
```dart
{ 'isClosed': true, 'closedAt': FieldValue.serverTimestamp(), 'closedBy': uid, 'updatedAt': FieldValue.serverTimestamp() }
```
**Reopen write** (`EventService.reopenEvent`, partial `.update`):
```dart
{ 'isClosed': false, 'closedAt': null, 'closedBy': null, 'updatedAt': FieldValue.serverTimestamp() }
```
**Rules `eventNotClosed(groupId, eventId)`** (absent-key-guarded; reuses the already-fetched `eventData` get → no extra billed read):
```
(!('isClosed' in eventData(groupId, eventId)) || eventData(groupId, eventId).isClosed == false)
```
**Rules close diff:** `affectedKeys().hasOnly(['isClosed','closedAt','closedBy','updatedAt'])` · before `isClosed==false` (absent-guarded) · after `isClosed==true && closedAt is timestamp && closedBy==request.auth.uid`.
**Rules reopen diff:** same `hasOnly` · before `isClosed==true` · after `isClosed==false && closedAt==null && closedBy==null`.
**`validEventBase` additions:** `(!('isClosed' in data) || data.isClosed is bool)` · `(!('closedAt' in data) || data.closedAt==null || data.closedAt is timestamp)` · `(!('closedBy' in data) || data.closedBy==null || data.closedBy is string)`.
**`validEventCreate`:** whitelist `+= 'isClosed','closedAt','closedBy'`; require (absent-guarded) `isClosed==false`, `closedAt==null`, `closedBy==null`.

---

## Phase A — Model fields (tree stays green; no behavior change)

### Task A1: Add close fields to the Event model

**Files:**
- Modify: `lib/features/events/models/event_model.dart`
- Test: `test/features/events/models/event_model_test.dart`

**Step 1 — Write failing tests** (append to the existing round-trip groups): isClosed/closedAt/closedBy parse from Firestore (Timestamp + null), serialize in `toFirestoreMap` (bool / Timestamp / string), `copyWith` overrides each independently while preserving immutables, default `isClosed==false`/`closedAt==null`/`closedBy==null` when keys absent (TOTAL-PARSE), and `deletedAt`/`isDeleted` unaffected by close fields.

**Step 2 — Run, expect RED:** `flutter test test/features/events/models/event_model_test.dart` → fails (named params/fields don't exist).

**Step 3 — Implement** in `event_model.dart`:
- Add fields after `description` (L90): `final bool isClosed;`, `final DateTime? closedAt;`, `final String? closedBy;`
- Constructor: `this.isClosed = false, this.closedAt, this.closedBy,`
- `fromDoc`: `isClosed: data['isClosed'] == true,` · `closedAt: dateOrNull(data['closedAt']),` · `closedBy: data['closedBy'] is String ? data['closedBy'] as String : null,`
- `toFirestoreMap`: `'isClosed': isClosed,` · `'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,` · `'closedBy': closedBy,`
- `copyWith`: add params `bool? isClosed, DateTime? closedAt, String? closedBy,` → `isClosed: isClosed ?? this.isClosed,` etc. **Note:** `copyWith` cannot null-out `closedAt`/`closedBy` with the `?? this` idiom; reopen goes through the service partial-update, not `copyWith`, so this is fine. Document it inline.

**Step 4 — Run, expect GREEN.** **Step 5 — Commit:** `feat(events): add isClosed/closedAt/closedBy fields to Event model (#723)`

---

## Phase B — Firestore rules (deployable; tree green)

### Task B1: Add `eventNotClosed` predicate + wire into expense rules

**Files:** Modify `security/firestore.rules`

**Step 1 — Write failing rules tests** in `functions/test/firestore-rules-publish-readiness.test.ts` (extend the events/expenses block):
- closed event (`isClosed:true,closedAt:<ts>,closedBy:<uid>`) → participant create expense → `assertFails`.
- closed event → participant update existing expense (amount) → `assertFails`.
- closed event → participant soft-delete expense → `assertFails`.
- **closed event → group member create SETTLEMENT → `assertSucceeds`** (the coupling-trap regression — the single most important test here).
- open event (`isClosed:false`) → create expense → `assertSucceeds` (no regression).

**Step 2 — Run, expect RED:** `cd functions && npm run test:emulator -- firestore-rules-publish-readiness.test.ts` (the runner forwards args — verified in `tool/run_firebase_emulator_tests.sh:15-17`; the CLAUDE.md "never forwards args" note is stale). Expect the settlement test PASS-by-accident but the expense-block tests FAIL (writes still permitted).

**Step 3 — Implement:** add helper after `eventAllowsClientWrites` (L177):
```
function eventNotClosed(groupId, eventId) {
  return !('isClosed' in eventData(groupId, eventId))
    || eventData(groupId, eventId).isClosed == false;
}
```
In `validExpenseCreate` (after L635) and `validExpenseUpdate` (after L691) add `&& eventNotClosed(groupId, eventId)`. **Do NOT touch `validEventSettlementCreate` (L791)** — settlements stay on `eventAllowsClientWrites`.

**Step 4 — Run, expect GREEN** (all five). **Step 5 — Commit:** `feat(rules): block expense writes on closed events; settlements stay live (#723)`

### Task B2: Add close/reopen update paths + schema validation

**Files:** Modify `security/firestore.rules`

**Step 1 — Write failing rules tests:**
- admin (event creator) close: update `{isClosed:true,closedAt:<ts>,closedBy:<self>,updatedAt:<ts>}` → `assertSucceeds`.
- group creator close on an event they didn't create → `assertSucceeds`.
- non-admin participant close → `assertFails`.
- close with `closedBy != auth.uid` → `assertFails`.
- close bundling an extra key (e.g. `name`) → `assertFails` (diff `hasOnly`).
- admin reopen (`isClosed:false,closedAt:null,closedBy:null,updatedAt`) on a closed event → `assertSucceeds`.
- non-admin reopen → `assertFails`.
- light update (rename) on a closed event → `assertSucceeds` (meta edits stay allowed — documents the scope decision).
- **admin close on an event with a DEPARTED participant** (an event `participantIds` entry absent from current `group.memberIds`, #249) → `assertSucceeds` (regression guard for the [P2] fix — proves close does NOT re-run `participantIds.hasOnly(groupMembers())`).
- reopen on a never-closed (no `isClosed` key) event → `assertFails` ([P3] guard).
- create event with `isClosed:false,closedAt:null,closedBy:null` → `assertSucceeds`; create with `isClosed:true` → `assertFails`.

**Step 2 — Run, expect RED.**

**Step 3 — Implement** (events match block):
- `validEventBase` (after L427): add the three absent-guarded type checks (see Data contracts).
- `validEventCreate` whitelist (L433-449): add `'isClosed','closedAt','closedBy'`; after L453 add absent-guarded `isClosed==false` / `closedAt==null` / `closedBy==null`.
- Add `validEventCloseUpdate()` — **deliberately does NOT call `validEventUpdateCommon`/`validEventBase`** (Gate [P2]): re-running the base re-asserts `participantIds.hasOnly(groupMembers())` (L416), which would **permanently block closing any event with a departed participant (#249)** — the exact post-trip closeout case. The `diff().hasOnly([...4 keys])` already pins groupId/createdBy/type/createdAt/name/participants immutable, so the base re-check is both redundant and harmful. Mirrors `validSoftDelete` (L651-665), which diff-gates without re-validating the base.
  ```
  requesterIsEventAdmin()
    && eventAllowsClientWrites(groupId, eventId)
    && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['isClosed','closedAt','closedBy','updatedAt'])
    && (!('isClosed' in resource.data) || resource.data.isClosed == false)
    && request.resource.data.isClosed == true
    && request.resource.data.closedAt is timestamp
    && request.resource.data.closedBy == request.auth.uid
    && request.resource.data.updatedAt is timestamp
  ```
- Add `validEventReopenUpdate()` — same no-base rationale; reopen before-check **requires the key present** (Gate [P3]) so a never-closed/legacy doc cleanly denies the reopen path without a missing-key eval error.
  ```
  requesterIsEventAdmin()
    && eventAllowsClientWrites(groupId, eventId)
    && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['isClosed','closedAt','closedBy','updatedAt'])
    && ('isClosed' in resource.data) && resource.data.isClosed == true
    && request.resource.data.isClosed == false
    && request.resource.data.closedAt == null
    && request.resource.data.closedBy == null
    && request.resource.data.updatedAt is timestamp
  ```
- Update `allow update` (L512): `if validEventLightUpdate() || validEventAdminUpdate() || validEventCloseUpdate() || validEventReopenUpdate();`

**Step 4 — Run, expect GREEN** (B1+B2 suites). **Step 5 — Commit:** `feat(rules): admin close/reopen event update paths + schema (#723)`

---

## Phase C — EventService close/reopen

### Task C1: `closeEvent` / `reopenEvent`

**Files:** Modify `lib/features/events/services/event_service.dart` · Test `test/features/events/services/event_service_test.dart` (already exists, ~4.9k — append; mirror its `FakeFirebaseFirestore` style).

**Step 1 — Failing tests:** `closeEvent` writes `isClosed:true` + `closedBy` + non-null `closedAt`-or-pending + `updatedAt`; `reopenEvent` writes `isClosed:false` + nulls. (FakeFirebaseFirestore resolves serverTimestamp immediately — assert the bool + closedBy.)

**Step 2 — RED.** **Step 3 — Implement** mirroring `deleteEvent` (L180-201), partial `.update`:
```dart
Future<void> closeEvent({required String groupId, required String eventId, required String closedBy}) async { ... update({'isClosed': true, 'closedAt': FieldValue.serverTimestamp(), 'closedBy': closedBy, 'updatedAt': FieldValue.serverTimestamp()}); }
Future<void> reopenEvent({required String groupId, required String eventId}) async { ... update({'isClosed': false, 'closedAt': null, 'closedBy': null, 'updatedAt': FieldValue.serverTimestamp()}); }
```
Wrap in `try/on FirebaseException` like siblings.

**Step 4 — GREEN.** **Step 5 — Commit:** `feat(events): EventService closeEvent/reopenEvent (#723)`

---

## Phase D — UI: close/reopen action, closed banner, read-only gating, l10n

### Task D1: l10n keys (en + ar)
**Files:** `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`. Keys (final names verified against existing convention at edit time): `eventCloseTripAction`, `eventReopenAction`, `eventClosedBannerBy` (placeholder `{name}`), `eventClosedBannerNoDate`, `eventCloseConfirmTitle`, `eventCloseConfirmBody`, `eventCloseConfirmCta`, `eventReadOnlyAddBlocked`, `eventReopenConfirmTitle`/`Body`/`Cta`. Run `flutter gen-l10n` (note `lib/l10n/generated` is git-tracked → regenerate, commit). **Commit:** `feat(l10n): event close/reopen + read-only copy (#723)`

### Task D2: Close/Reopen admin action
**Files:** `lib/features/events/widgets/event_danger_section.dart` (already admin-gated, L48). Add a tile **above** the delete tile (~L75): if `event.isClosed` → "Reopen" tile (→ confirm → `eventServiceProvider.reopenEvent`); else → "Close trip" tile (→ confirm dialog explaining frozen-spending/settle-later/reopen-able → `closeEvent(closedBy: currentUid)`). Race the ack via `awaitServerAck` + `connectivity.noteQueuedWrite()` per #412 (mirror how `deleteEvent` is invoked in this section). Widget test: admin sees Close; tapping confirms→service called; closed event shows Reopen. **Commit.**

### Task D3: Closed banner on the event hub
**Files:** `lib/features/events/screens/event_command_center.dart` (after `_CoverHeader`, before `OfflineBanner` in the sliver stack). Render when `event.isClosed`: a lock-pill banner "🔒 Closed by {name} · spending frozen" (resolve `closedBy`→name via `participantNames`/member resolver; fall back to `eventClosedBannerNoDate` when name/date unresolved). Mirror `OfflineBanner` structure (`lib/shared/widgets/offline_banner.dart`). Theme-pure (`context.colors`). Widget test: banner shows iff closed. **Run `bash tool/check_theme_purity.sh`.** **Commit.**

### Task D4: Disable expense affordances when closed
**Files & exact gates** (pass `isClosed` down the tree; do not have each leaf re-watch):
- `event_command_center.dart`: `_BalanceHero` "Add expense" (L400-418) → `onPressed: null` + dim; `_AddFirstExpenseCard` (L978/L995, gated in `_RecentExpensesSection` ~L238) → card `onTap: null` + dim.
- `ledger_screen.dart` `_Body` (~L394): compute `addExpenseEnabled = !event.isClosed`, pass to `LedgerStickyCta`. **Settle button gate is left untouched** (decouple — coupling risk flagged at ledger_screen.dart:394-402).
- `ledger_sticky_cta.dart` (L78-100): add `addExpenseEnabled` param; `_PrimaryCta` `onTap: enabled?onTap:null` + `Opacity` (mirror `_SecondaryCta` L113).
- `ledger_day_card.dart` `_ExpenseRow` (L217-292): pass `isClosed`; `onTap: isClosed ? null : onTap` (tap-to-edit disabled).

Widget tests: closed event → Add buttons disabled, expense rows non-tappable, **Settle-up button still enabled**. **Commit.**

### Task D5: Navigation gates on add/edit screens
**Files:** `add_expense_screen.dart` (before rendering `ExpenseEditorBody` ~L169) and `edit_expense_screen.dart` (extend the existing `canEdit` gate ~L70-97 with `&& !event.isClosed`): if `event.isClosed`, render a read-only/blocked state (reuse the existing `_ErrorScaffold`/`canEdit`-denied path with `eventReadOnlyAddBlocked` copy) instead of the editor. Belt-and-suspenders behind the rules. Widget tests for both. **Commit.**

---

## Phase E — Verify, PR, deploy

- `flutter analyze` clean · `bash tool/check_theme_purity.sh` clean · `flutter test` (model/service/widget) green · rules suite green under emulator.
- PR body: `Closes #723`, `Spec: docs/plans/2026-06-30-723-event-close-lifecycle.md`, RED evidence pasted for the settlement-stays-live rules test, security checklist.
- Gate-category PR → `/automerge` will route to fresh-Opus review. After merge: **deploy-ceremony** (rules deploy; `tool/pending_deploy.sh` → deploy → advance `backend-deployed` tag → `docs/DEPLOY-LEDGER.md`). No client-compat gating (no users).

## Test matrix (acceptance #723 + epic)
| Case | Layer | Assert |
|---|---|---|
| closed event, expense create | rules + widget | denied / Add disabled |
| closed event, expense edit/delete | rules + widget | denied / row non-tappable, editor blocked |
| **closed event, settlement create** | rules + widget | **allowed / Settle-up enabled** |
| non-admin close/reopen | rules | denied |
| admin close (event creator & group creator) | rules + widget | allowed |
| close bundling extra key | rules | denied |
| reopen restores writability | rules + widget | expense create allowed again |
| model round-trip closed fields | unit | parse/serialize/copyWith |
| balances unchanged by close | unit | closed event still contributes (no provider reads close fields) |
| banner copy en + ar/RTL | widget | renders both |

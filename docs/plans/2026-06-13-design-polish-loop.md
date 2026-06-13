# Design-Polish Loop — runbook

**Created:** 2026-06-13
**Owner of state:** GitHub PR/issue state (not this file). This file is the static operating manual; "what's done" is read from `gh` each iteration.
**Driven by:** `/loop` (self-paced). Each wake-up does **one unit** end-to-end, then reschedules.

## Why this loop exists

Today's whole-app UI audit (`docs/design/mockups/app-ui-audit-2026-06-13.html`) filed issues **#485–#490**. This loop ships the **Gate-exempt, test-backed** subset autonomously and **hands the rest to the human** with reasons. It does not invent scope.

## Hard guardrails (read every iteration)

1. **Gate-exempt only.** Never autonomously implement a unit that touches `BalanceCalculator`/`MoneySerializer`, `security/firestore.rules`, `functions/**`, routing (`app_router.dart`/deep-links/back-guards), or a schema/field-name with both a read- and write-path. Those are **FLAG** units below — surface them, do not build them.
2. **Read before edit.** Issue bodies carry `:line` refs that were correct when filed. Re-`Read`/`grep` the file in the moment before editing — code wins over the issue text.
3. **Bug fix = RED first.** A unit tagged *bug* ships a failing regression test that fails for the right reason BEFORE the fix. Paste the failing output into the PR.
4. **One PR, one concern.** Each unit is its own branch + PR off fresh `origin/main`. No bundling, no opportunistic cleanup.
5. **`flutter analyze` clean + relevant tests green** before opening any PR. If analyze or tests can't be made green, **STOP and report** — don't open a broken PR.
6. **AUTO units** route through `/automerge` (Gate-exempt → native auto-merge on green `readiness`). **HOLD units** open a PR with the mockup reference but **do NOT enable auto-merge** — they need a human visual glance because CI has no golden gate. **FLAG units** are not built.
7. **Idempotency.** Before building a unit, `gh pr list --state all --search "<issue#>"` and read the issue's task-list checkboxes. If the unit already has a PR (open or merged) or its box is ticked, skip it.
8. **Partial-delivery merge hygiene.** Multi-box issues (#488, #490): each PR uses `Refs #N` in the **commit body** (squash auto-closes from the commit message) and ticks its box; only the PR that completes the last *non-flagged* box uses `Closes #N`. #490 keeps two flagged boxes → it stays OPEN re-scoped.

## Per-iteration procedure

1. `git fetch origin` and determine the next un-shipped unit from the ordered list (idempotency check, guardrail 7).
2. If it's a **FLAG** unit or the AUTO batch is exhausted → **STOP**, post the checkpoint summary (below), do not reschedule.
3. `git worktree add ../Rihla-<tag> origin/main` (isolation — main working dir stays put holding this runbook). Work there.
4. Re-read the target file(s). For a *bug* unit, write the RED test, run it, confirm it fails for the right reason.
5. Implement minimally to the mockup section cited. `flutter analyze`. Run the relevant test dir.
6. Commit (conventional, `Refs #N`/`Closes #N` per guardrail 8), push, open the PR (body: what/why, mockup ref, RED output for bugs, test plan).
7. **AUTO** → `/automerge <PR#>`. **HOLD** → leave PR open, no auto-merge; note "visual review needed (no golden gate in CI)".
8. `git worktree remove ../Rihla-<tag>` (after push; the branch lives on origin).
9. Reschedule the next iteration. Stop at the AUTO→HOLD boundary for a human checkpoint.

---

## AUTO batch — ship autonomously (TDD → PR → /automerge)

Order = P2 correctness/honesty first, then the cohesive #488 state-sweep.

### 1. `488-bug` — activity load errors masquerade as "No activity yet" *(bug, P2)*
- **File:** `lib/features/groups/screens/group_activity_screen.dart` — `_loadPage` (`~:104`) wraps the fetch in `catch (_)` and only clears `_isLoadingMore`; a first-load network failure renders the "No activity yet" empty state (`~:145`). A failed page-2 fetch silently stops paginating.
- **Fix:** distinct error state (`EmptyStateView` + Retry) ≠ empty. Track a load-failed flag.
- **RED first:** widget test — first-load fetch throws → screen shows the error/Retry affordance, NOT "No activity yet". Confirm it fails for the right reason before the fix.
- **Mockup:** `app-ui-audit-2026-06-13.html` §A4. **Closes-keyword:** `Refs #488` (lead box).

### 2. `487` — identity hero never reflects backup state *(P2, display-only)*
- **File:** `lib/features/settings/screens/profile_screen.dart:405` renders `l10n.profileAnonymousTraveller` unconditionally. Providers already exist: `isDurableUserProvider`/`googleAccountProvider`/`linkedEmailProvider` (watched ~`:880-883`).
- **Fix:** hero status chip — amber "⚠ Not backed up" (anon) / sage "✓ Backed up · email|Google" (durable). When anon, a single "Back up this account" card stating the stakes. Group recovery/restore entries under one labelled block; delete stays in its danger zone.
- **Tests:** widget tests on the state branches (durable → "Backed up"; anon → "Not backed up" + back-up card). Styling follows the mockup.
- **Mockup:** §A3. **Closes #487.**

### 3. `488-a` — cross-group Activity loads to a blank screen *(P3)*
- `lib/features/activity/screens/cross_group_activity_screen.dart:~69` returns `SizedBox.shrink()` while loading. → `SkeletonLoader` + `EmptyStateView` (loading/empty/error). Test the error/empty branches. `Refs #488`.

### 4. `488-b` — create-event bare spinner + naked Text error *(P3)*
- `lib/features/events/screens/create_event_screen.dart:~227` `CircularProgressIndicator`; error branch `~:228` is a naked `Text`. → layout-matched skeleton + `EmptyStateView` error. Test branches. `Refs #488`.

### 5. `488-c` — profile stats em-dashes, no loading/error state *(P3)*
- `profile_screen.dart` stats render `—` with no explicit loading/error. → explicit states. Test. `Refs #488`.

### 6. `488-d` — group-detail events section renders nothing while loading *(P3)*
- `lib/features/groups/screens/group_detail_screen.dart:~256` `SizedBox.shrink()` under already-painted chrome. → skeleton. Test. `Refs #488`.

### 7. `488-e` — event-activity uses three loading treatments on one screen *(P3)*
- Unify shimmer/nothing/bare-spinner to one (`SkeletonLoader`). Test. **`Closes #488`** (last non-flagged box).

**→ CHECKPOINT after unit 7.** Post summary, await human for HOLD + FLAG.

---

## HOLD batch — implement + open PR, NO auto-merge (human visual review; CI has no golden gate)

### 8. `490-a` — one avatar widget (`RAvatar`) everywhere
- 4+ impls for one person: `RAvatar`, `_Avatar` (editor + split sheet), `_MiniAvatar`, stock `CircleAvatar` in the payer dropdown. → `RAvatar` everywhere (DEC-3: one stable color per person). `Refs #490`, tick box. §A6.

### 9. `490-b` — one `ActivityRow` + saffron selected chip
- Rows rendered 3 ways (home shared `ActivityRow`, cross-group `_ActivityRow`, per-event `_ActivityRow`). Cross-group selected filter chip uses near-black `textPrimary` instead of brand `primary` (`cross_group_activity_screen.dart:~243`). → one shared `ActivityRow` + saffron chip. `Refs #490`, tick box.

### 10. `490-c` — one header primitive, one back button, one height
- Heights drift 36/44/48; 5 different back-button widgets. **Biggest blast radius** — touches many screens + shifts goldens. → one header primitive + one back button + one height. `Refs #490`, tick box. Do last, smallest sensible diff.

---

## FLAG — do NOT build; surface to the human with the reason

- **#485** — split-editor IA collapse. Exempt alone, but the issue says land it **with #242** (Gated, per-person numbers) so the editor isn't restructured twice. → needs the #242 spec + Gate together.
- **#486** — "one balance truth." Issue itself says **run the fresh-context Gate** (routing-adjacent + balance display), AND it collides with the **locked #382 multi-currency UI overhaul** (`382-multi-currency-overhaul.html`) on the same group-detail/balance surfaces. → sequencing decision + Gate.
- **#489** — fold the type-picker. **Routing** change (folds `/create-event/:type`, `app_router.dart:~294`; deep links must resolve cold). → Gate required.
- **#490-d** — payment method collected but discarded (`record_payment_sheet.dart` `_MethodChip` → `RecordPaymentResult.method`, never persisted). "Persist" = settlement schema/write change = **Gate-category**; "remove" = product call. → human decides persist-vs-remove.
- **#490-e** — group-settings "Defaults" card inert (`group_settings_screen.dart:203-212`, hardcoded "Equally"/"Weekly"). "Wire" = feature; "remove" = product call. → human decides.

## Checkpoint summary template (post when stopping)

```
Design-polish loop — AUTO batch complete (or stopped at <unit>).
Shipped (auto-merge enabled, merging on green): <PR#s + titles>
Open for your visual review (HOLD, no auto-merge): <PR#s>
Awaiting your call (FLAG): #485 (couple w/ #242), #486 (Gate + #382 collision),
  #489 (routing Gate), #490-d (payment persist/remove), #490-e (defaults wire/remove).
#469 (account-deletion identity P1) remains deferred to a dedicated session.
```

# A+ Grade Sprint — from the first-impressions review to 2.0

**Tracking issue: #818.**

**Context.** An external-style first-impressions review graded the app C+ overall ("a B+ app
wearing a C+ first hour"), with two would-quit blockers. Every material claim was verified
against main @ `f688ae27` (includes History PR2 #815 / PR3 #816). One blocker (expenses
missing from Activity) is already fixed on main. This plan takes the rest to an A-grade app,
with the A+ ceiling reserved for 2.0 (real dark pass + one headline feature).

**Constraints in force.**
- No production release until 2.0 → sequencing is by leverage, not release pressure.
  Server/rules changes deploy freely (no-real-users rule).
- Each Gate-category item below ships its own spec → `/run-the-gate` → PR → `/automerge`.
  This document is the map, not the Gate spec.
- Dark mode decision (locked): stopgap default-to-light now; real dark pass is a 2.0
  design round (canvas-first).

**Grade math** (review dimensions → sprint target):

| Dimension | Review | After sprint | Gap to A+ |
|---|---|---|---|
| First-run | C | A | — (gate removal + identity polish) |
| Core task | B– | A | — (settlement direction + headline) |
| Navigation | C | A– | naming IA is taste-capped |
| Copy | B | A | — |
| Visual | B+ | A– | real dark pass (2.0) |

Honest note: "A+" is not reachable by polish alone. The review's ceiling arguments are the
dark stub and the missing-features list. This sprint gets to A–/A; 2.0 (dark pass + one
roadmap feature) gets the +.

---

## Decision 0 — the anon-create gate (LOCKED 2026-07-03: REMOVE)

The review's #1 would-quit: "Not now" on the durable-credential sheet silently aborts group
creation (`create_group_screen.dart:151`). This is the #441 policy, not a bug. Enforcement
is three-layered: `firestore.rules` `isDurableSignIn()` (gates group + inviteCode creation),
`group_provider.dart:201` (`stageGroup` throws `DurableCredentialRequiredException`), and
the client gate call site.

**Decision: remove the create gate.** Reasoning, recorded for the future re-litigator:

1. **The invariant it protects no longer holds.** Rules comment: "money data must never be
   born under a discardable anonymous UID." But #648 un-gated join + expenses — an anonymous
   user can already join a group and accumulate real money history on a discardable UID.
   The gate now only guarantees *creators* are durable.
2. **Creator durability is real but narrow** (claim approvals, member management orphaned if
   the creator's phone dies; the group itself survives server-side and members keep using it).
3. **The cost lands at the worst moment** — the first meaningful action, before any value is
   demonstrated. Classic commitment-before-value onboarding failure; the review called it
   would-quit-class.
4. **Post-hoc nudges already exist and stay**: amber not-backed-up pill, #285 backup nudge,
   profile CTA — all reuse the same sheet with honest optional semantics.
5. **Cheapest possible time to flip**: no users until 2.0; the policy is reversible.

---

## Wave 1 — Copy honesty & tiny fixes (Gate-exempt except 1.3; parallel PRs, no dependencies)

- **1.1 Settle-up headline contradiction.** `settleUpTransfersHeadline`
  ("3 transfers,\neveryone's even.") shows while transfers are *outstanding*
  (`settle_up_page_body.dart:434-436`) and reads identical to the settled state
  (`settleUpEveryoneEvenHeadline`). Recopy to forward-looking ("3 transfers\nuntil
  everyone's even."). Zero-state unchanged. ARB (en+ar) + any test pinning the old string.
- **1.2 Jargon sweep.** `editorShadowProfile` "Shadow Profile" → user language
  ("Hasn't joined yet" or similar, verified against the surface); `activityEventMoney*`
  "money entry" → "expense"; `activityFilterSettles` "Settles" → "Settlements".
  ARB-only (en+ar) + test fixtures (fixtures lag label changes).
- **1.3 404 screen.** `app_router.dart:487-491` is a bare centered `Text` with the raw
  route path — the screen a shared-link user hits. Replace with `EmptyStateView` + friendly
  copy + "Go home" button (`context.go(AppRoutes.home)`); demote the path to a small caption.
  Router file → Gate-category by path; the diff is a leaf errorBuilder, `/automerge`
  classifies.
- **1.4 Dark-mode stopgap.** Default `AppThemeMode.system` → `light` at
  `app_settings_model.dart:34` AND `settings_service.dart:32-35` (all fallbacks must move
  together; persisted explicit choices unaffected). Pin the new default with a test whose
  comment cites the DESIGN.md §13 stub. Real dark pass → 2.0 (Wave 6).

## Wave 2 — Execute Decision 0 (Gate-category: rules + money-adjacent; deploy ceremony)

- **2.1 Remove the anon-create gate:**
  - `security/firestore.rules`: relax `isDurableSignIn()` call sites (group + inviteCode
    create — both together; enumerate call sites at spec time, don't trust this doc).
  - `group_provider.dart:201`: drop the `stageGroup` anon guard.
  - `create_group_screen.dart:141-151`: drop the `ensure()` call; clean up only what this
    change orphans (e.g. `PendingGateIntent.create` if it becomes dead).
  - Add the *replacement* nudge moment: non-blocking, after first successful group create
    (NOT a modal ambush). Mind the #411 snackbar-action trap if a snackbar carries an action.
  - Emulator rules tests updated (anon create now allowed); widget tests for the ungated
    flow; deploy ceremony after merge.
  - The durable sheet, conflict-switch machinery, and swap gates (#647/#661) are untouched —
    they guard restores, not creates.

## Wave 3 — Money-feed truth (Gate-category: data-shape, write+read path)

- **3.1 Settlement direction in activity feeds.** Two verified defects:
  `activity_display.dart:42` maps every `group_settlement` to the generic "recorded a
  settlement" (discarding the directional description the write path composes), and
  `group_activity_screen.dart:568-575` renders a hardcoded `sign: true, tone:
  AmountTone.sage` — permanent green "+" regardless of direction.
  - Write path: stamp `fromName`/`toName` (and uids) into settlement log metadata at every
    settlement write site (enumerate at spec time: group settle-up `logGroupEvent`, event
    settle-up, decomposed #752 writes).
  - Read path: directional phrase ("Ali paid Sarah 5.000"); amount neutral or
    viewer-relative — no unconditional green +.
  - Guarded reads (metadata is client-forgeable, rules check only `is map` — follow the
    #808 PR2 `_metadataString` pattern). Legacy rows without the keys keep today's generic
    fallback.
  - Coordinate with #814 (server-half metadata hardening, in flight in another session) —
    rebase over it; do not race it on `firestore.rules`.
- **3.2 Add-expense discard guard.** No `PopScope` anywhere in `add_expense_screen.dart`;
  itemized split can hold a full typed receipt. Dirty-check + confirm on X/system-back.
  Back-guard → Gate-category. Respect the routing landmines: no blanket `canPop: false`
  (Android predictive back); nested route so pop semantics per the #243 notes.

## Wave 4 — First-run identity polish (Gate-exempt, copy/UI only)

- **4.1 The "?" avatar.** Fresh install → `RAvatar(name: deviceName)` renders "?"
  (`home_screen.dart:477`). Smallest honest fix: a one-time "Set your name" affordance on
  the home header opening the existing edit-name sheet. NOT an onboarding route/flow
  (contract: onboarding stays deleted).
- **4.2 Restore CTA framing.** `homeRestoreWithGoogle` / `homeRestoreWithEmail` confuse
  fresh installs ("Restore what?"). Prefix with a "Been here before?" caption or collapse
  to one "Restore an existing account" link. Copy-only; the CTAs are already tap-gated
  (#804) — visibility is not a safety boundary and must not become one.
- **4.3 Guest explainer.** One caption near the backup pill explaining the guest model
  ("You're using a guest account — it lives on this phone until you link it"). Copy-only.
- **4.4 Initials-selector false affordance.** Confirmed presentation-only by design
  (`edit_name_bottom_sheet.dart:14-16`) — user "picks" an initials style, nothing persists.
  Restyle as a static preview (cheapest honest state, same class as the #802 sweep).

## Wave 5 — Navigation & naming (decision-labelled; needs product sign-off)

- **5.1 "Activity" triple-meaning.** Bottom tab (`homeBottomNavActivity`), per-group screen,
  per-event tab — same word, three feeds. Proposal: rename the bottom tab to **"History"**
  (matches the #808 epic language and its search); per-group and per-event keep "Activity".
  ARB + test fixtures. Decision-labelled — naming is taste; don't build without sign-off.
- **5.2 Bell affordance.** `home_screen.dart:483-487` pushes top-level `/activity` — the
  tab bar disappears, and a bell reads as "notifications" but opens a feed. Proposal: drive
  the Activity/History *tab* selection instead of pushing the route (BottomNavShell is
  provider-driven, not GoRouter-driven). Mind the dual-mode screen contract
  (`CrossGroupActivityScreen` showBack; never `PopScope(canPop:false)` — the #666 trap).
  Nav behavior change → treat as Gate-category routing.
- **5.3 Export entry point from settle-up.** Trip Receipt export exists on Recap (#704
  merged; issue stays open for the group-scoped pack). Add a link from the settle-up
  surface. Entry-point-only; verify surfaces at implementation.

## Wave 6 — the 2.0 ledger (each its own epic; decision-labelled; NOT this sprint)

- Real dark pass: canvas-first design round → dark token tuning → goldens.
- Receipt photo attach (v1 = attach only, no OCR) — decision.
- Friends / per-person view across groups — decision.
- Notifications inbox — decision.
- Global search beyond history (PR3 #816 covers history search).

---

## Definition of done — the re-grade gate

After Waves 1–5 land: run a **fresh-context reviewer** (zero session history, same
first-impressions rubric, latest debug build) and re-grade. Sprint passes when:

- [ ] Zero would-quit findings.
- [ ] Every dimension ≥ B+; overall ≥ A–.
- [ ] No new false affordances introduced (the reviewer checks for them explicitly).

The A+ re-grade happens at 2.0, after the dark pass and at least one Wave-6 feature.

## Process checklist (every wave)

- [ ] Gate-category items get a spec + `/run-the-gate` before code.
- [ ] Bug-class items ship a failing test first (RED evidence in PR).
- [ ] All PRs through `/automerge`; no raw merges.
- [ ] Rules/Functions changes → deploy ceremony after merge.
- [ ] `bash tool/check_theme_purity.sh` before pushing any new/changed widget.
- [ ] Partial deliveries: `Refs #818` in the COMMIT MESSAGE, not just the PR body
  (squash-merge auto-close trap).

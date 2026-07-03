# Remove the anon-create gate (#818 Wave 2, Decision 0)

**Spec status:** v3 — GATE-APPROVED. Round 1: 1 P1 / 1 P2 / 3 P3 (applied in v2). Round 2:
0 P1 / 3 P2 / 3 P3 (stop condition; all findings folded in below). **Tracking:** #818
(partial — `Refs #818`).

**MANDATORY PRE-STEP (Gate r2 P2):** #814/#820 has MERGED — origin/main now carries
`validActivityMetadata` in `security/firestore.rules`. Branch from CURRENT origin/main
(not any older snapshot) and assert `grep -c validActivityMetadata security/firestore.rules`
returns 2 BOTH before and after the rules edit — a count of 0 means you are editing a
stale tree (the #812 failure mode); stop and re-fetch.

## Intent

Anonymous users can currently not create groups: the #441 durable-credential gate blocks
the first valuable write behind a "Link Google" modal whose "Not now" silently aborts
creation. Decision 0 (locked 2026-07-03, rationale in
`docs/plans/2026-07-03-a-plus-grade-sprint.md`): remove the create gate entirely.
Post-#648 an anonymous user can already join groups and add expenses on a discardable UID
("gate creation, not participation" — `joinGroupByInviteCode.ts:35-40`), so the gate no
longer protects its founding invariant; it only guarantees creator durability, at the
worst UX moment in the app.

After this change: an anonymous user creates groups like a durable user, **with one
carve-out — add-people-BY-NAME (shadow members) stays durable-only** (see §Shadow
carve-out): the `addShadowMember` callable hard-rejects anonymous callers and that server
policy is NOT changing in this PR. Anonymous creators grow their group via the invite
code (join is already un-gated).

The existing non-blocking home nudge (#285 `AccountBackupNudge`) becomes the primary
link-your-account prompt — it already renders for ANY anonymous, non-dismissed user
(`lib/features/home/widgets/account_backup_nudge.dart:32-36`), so the user who just
created their first group sees it on returning home. **No new nudge UI is built.**

## Enforcement surface (verified against code, 2026-07-03, worktree @ cb650d68)

Three layers, all must move together:

1. **Rules** — `security/firestore.rules`:
   - `isDurableSignIn()` helper, line 16 (comment lines 14-15).
   - Call site A: `validGroupCreate()` — the `&& isDurableSignIn()` conjunct (~line 298).
   - Call site B: `match /inviteCodes/{code}` `allow create` — the `&& isDurableSignIn()`
     conjunct (~line 239). Group + inviteCode are written in ONE client batch
     (`stageGroup` batches only these two — `group_provider.dart:219-246`; the chained
     member/event writes at :277-301 are governed by `isGroupMember`, not durability),
     so A and B must be relaxed together or the batch still fails.
   - After both call sites are removed the helper is dead → delete helper + its comment.
     (Grep confirms exactly 2 call sites + 1 definition; no other references.)
2. **Client service guard** — `lib/features/groups/providers/group_provider.dart`:
   - `stageGroup` lines ~198-202: `if (_isCurrentUserAnonymous) throw const
     DurableCredentialRequiredException();` + the `#441: gate BEFORE batch staging`
     comment + the doc-comment sentence promising the throw (lines ~184-187).
   - `_isCurrentUserAnonymous` getter (line 112): its only group_provider use is line 200
     → delete the getter with the guard, AND (Gate r2 P2) the `_isAnonymousOverride`
     field (~line 66) + the `isAnonymous` ctor param on `GroupService.withFirestore`
     (~line 92) that feed it — leaving them strands an `unused_field` (analyze failure)
     and a vacuous test seam. `stageGroup` becomes anonymity-blind. (The same-named
     getter in `notification_service.dart:87` is UNRELATED — FCM suppression —
     untouched.)
3. **Client screen** — `lib/features/groups/screens/create_group_screen.dart`:
   - `_createGroup()` lines ~138-151: the `durableCredentialGateProvider.ensure(...)`
     call, its `PendingGateIntent.create(...)` argument, and the `if (!gateOk ||
     !mounted) return;` — remove. The `on DurableCredentialRequiredException` catch
     (~line 229) becomes unreachable → remove that catch clause only. Gate r2 P3
     completions: the now-dangling imports at line 21 (gate provider) AND line 22
     (`durable_credential_exception.dart`) go with it; the catch body's
     `context.l10n.durableCredentialRequired` (~line 235) was that l10n key's sole use —
     grep, and if sole, remove the key (en+ar+gen-l10n); the stale comment at ~lines
     183-185 ("its DurableCredentialRequiredException is caught below — it MUST stay
     inside this try") must be rewritten (the try still matters for the
     not-authenticated throw; the named exception is gone).

## Shadow carve-out — the newly-reachable `addShadowMember` branch (Gate r1 P1)

`functions/src/callables/addShadowMember.ts:54-59` throws `permission-denied` for
`sign_in_provider === 'anonymous'`. Today that branch is unreachable (creators are always
durable); after this change an anonymous creator reaches it from three client surfaces.
The callable's reject **stays** (defense in depth; un-gating the claim/merge engine is a
separate decision). Instead, the three client surfaces gate the affordance on
`isDurableUserProvider` (`lib/features/auth/providers/auth_provider.dart`):

1. **Create-screen chips** — `create_group_screen.dart:420-424` currently passes
   `enabled: ref.watch(connectivityProvider) == ConnectivityStatus.online`. New contract:
   `enabled: online && durable`. `ShadowMemberChipsField`
   (`lib/features/groups/widgets/shadow_member_chips_field.dart`) gains an optional
   `String? disabledHint`; its footer line (currently
   `enabled ? l10n.groupCreatorBody : l10n.createGroupShadowOfflineHint`, lines ~138-140)
   becomes `enabled ? groupCreatorBody : (disabledHint ?? createGroupShadowOfflineHint)`.
   The caller passes `disabledHint: !durable ? l10n.shadowAddRequiresLink : null` — the
   anon hint wins over the offline hint when both apply.
2. **Group-detail #807 shortcut** — `group_detail_screen.dart:257-266`: extend both
   ternaries' condition from `currentUid != null && group.createdBy == currentUid` to
   `… && durable` (affordance hidden for an anonymous creator, mirroring how non-creators
   see none).
3. **Group-settings members section** — `group_members_section.dart:49-55`: extend
   `isCurrentUserCreator` gating with `&& durable` the same way. The section's #807
   explanatory footer gains the anon-creator case: when the current user IS the creator
   but NOT durable, show `shadowAddRequiresLink` instead of the non-creator explanation.
   (How `durable` reaches this widget — new ctor param or `ref.watch` — implementer's
   choice; it is a ConsumerWidget-adjacent surface, keep it consistent with the file.)

New ARB key (en+ar+gen-l10n): `shadowAddRequiresLink` = "Link your account to add people
by name — anyone can still join with the invite code." One key, reused on surfaces 1
and 3.

(Gate r2 P3, accepted transient:) `isDurableUserProvider` reads
`authUserChangesProvider.valueOrNull`, which is null for a frame or two at boot — a
durable creator may momentarily see the affordance hidden / the link hint. Cosmetic,
self-healing, no data impact; do NOT add loading-state special-casing (treating unknown
as durable would flash an affordance that then errors for anon users — the safe default
is the current one).

Also: the callable's comment ("the CREATOR adds it and is always durable
(validGroupCreate requires a durable sign-in)", `addShadowMember.ts:51-53`) becomes false
— update the comment to name the new reality (client gates the affordance; this reject is
the server backstop). Comment-only; no behavior change, no Functions redeploy required
beyond the ceremony already planned.

`_seedShadowMembers` (`create_group_screen.dart:263-271`) needs no change: with the chips
field disabled for anon, `_shadowNames` stays empty and it early-returns.

## Orphans — what this change kills, and the retention boundary

- `lib/features/auth/providers/durable_credential_gate_provider.dart`: the create screen
  is its ONLY lib/ consumer → the file is dead. **Delete it**, plus (compile-forced,
  named per Gate r1): `test/unit/durable_credential_gate_test.dart` (its direct unit
  test) and the dangling import at `create_group_screen.dart:21`.
- **RETAIN unchanged** (follow-up cleanup issue, NOT this PR):
  `pending_gate_intent.dart`, `gate_intent_replay.dart` (+ its `main.dart:214` call),
  `create_group_screen._consumePendingGateIntent()` prefill, and the durable sheet's
  `intent` parameter / conflict-switch persist path (persists only when `intent != null`
  — `durable_credential_sheet.dart:152-158` — and no caller passes one anymore, so it is
  unreachable-but-inert). Rationale: interwoven with the #647/#661 swap-safety
  neighborhood; a "cleanup" diff there is exactly the change class that has caused
  data-loss regressions. One PR does one thing.
- `DurableCredentialRequiredException` (`durable_credential_exception.dart`): loses its
  only thrower. Grep at implementation; if the only remaining references are the deleted
  catch + deleted tests, delete the class too, else retain with a stale-free comment.

## The sheet and its copy stay — with one honesty fix

`durable_credential_sheet.dart` remains live from `profile_screen.dart:549,1189` and
`account_backup_nudge.dart:115`. Its copy ("Keep your money safe / Link Google so they
can't be lost with this device" / "Not now") was dishonest as a hard gate but is honest
as an optional nudge — no copy change needed. Two doc touch-ups in this PR:

- `lib/l10n/app_en.arb` `@durableGateNotNow` description (~line 2411) says "Aborts the
  pending create/join; the gate re-asks on the next attempt" — stale after removal.
  Reword to dismiss-only semantics. (Description-only: no generated-content diff beyond
  the ARB; gen-l10n run confirms.)
- `account_backup_nudge.dart` header comment claims "Post-gate (#441 PR2) a dashboard
  user is normally already durable, so this only fires for legacy pre-gate anon shells"
  — stale; post-#818 anonymous dashboards are the normal first-run state and this nudge
  is the primary backup prompt. Update the comment.

## Tests (RED first, then flip)

1. **Rules (emulator)** — `functions/test/firestore-rules-publish-readiness.test.ts`
   lines ~288-325 pin the denial: "anonymous provider cannot create a group (even
   valid-shaped)" and "anonymous provider cannot create the group + inviteCode batch".
   INVERT both to assert SUCCESS (same valid-shaped payloads, expectation flipped;
   rename accordingly, keep the #818 rationale in a comment). Run
   `cd functions && npm run test:emulator -- firestore-rules-publish-readiness.test.ts`
   BEFORE touching rules → both fail (RED, paste output into PR). Then edit rules →
   GREEN. (Never bare `npm test` — hangs without emulator.)
2. **Service guard** — (Gate r2 P2) `test/unit/group_service_durable_gate_test.dart` is
   built entirely on the `isAnonymous` ctor seam being deleted → delete the file
   WHOLESALE (its four pins become vacuous once `stageGroup` is anonymity-blind; the
   not-authenticated throw stays pinned in `test/unit/group_service_test.dart:265`,
   untouched). The RED-first inverse pin moves to the WIDGET layer instead: the new
   §Tests.3 create-flow test (anon user taps Create → `stageGroup` invoked, no sheet)
   is the anon-can-create regression pin — run it before the client changes for RED.
3. **Screen wiring** — `test/features/groups/durable_gate_wiring_test.dart`: the create
   pins (sheet-declined-aborts-create) are obsolete → replaced by one widget test
   pinning the new behavior: anonymous user taps Create → `stageGroup` invoked, NO sheet.
   Its `group('join')` block (join never consults the gate, :258-277; join-failure →
   `groupJoinFailed` snackbar, :279-295 — the ONLY test of that snackbar) must SURVIVE:
   relocate it into `test/features/groups/create_join_group_test.dart` (Gate r1 P2 — do
   not delete join coverage with the create tests).
   `create_group_offline_412_test.dart` and `create_group_shadow_members_test.dart`
   override `durableCredentialGateProvider` to auto-pass — drop those overrides
   (compile-forced by the provider deletion). (Gate r2 P2) Dropping the override is NOT
   enough for `create_group_shadow_members_test.dart`: its online tests type into the
   chips field expecting it ENABLED, and under the new `enabled: online && durable`
   contract `isDurableUserProvider` resolves false in a bare harness (null user →
   `valueOrNull` null). Add a durable-user override (`isDurableUserProvider`
   overridden true, or a non-anonymous `authUserChangesProvider`) to every test that
   exercises chips-enabled behavior; same check for any other test that types into
   `shadowMemberInput`.
4. **Shadow carve-out (RED first)** — new widget pins:
   - anon user on create screen, online → chips field disabled + `shadowAddRequiresLink`
     hint visible (RED today: field is enabled).
   - anon creator on group detail → no `groupAddMemberAction` affordance (RED today).
   - durable creator → both affordances unchanged (guard against over-hiding).
5. **Full suite**: `flutter analyze` clean, `flutter test`, plus the emulator rules
   file above. No goldens affected.

## Explicit non-changes (Gate reviewer: verify these hold)

- `joinGroupByInviteCode.ts` — untouched (#648 already un-gated; its "do NOT re-harden"
  comment stands).
- `addShadowMember.ts` behavior — untouched (comment-only edit); the anon reject is the
  server backstop for the client carve-out.
- Swap gates `outgoingShellProvablyEmpty`, conflict-switch, restart chokepoint —
  untouched. This PR touches CREATE flow only; no restore/swap surface.
- `MoneySerializer` / `BalanceCalculator` / oracle parity — untouched (no money math).
- The durable sheet's Google-link flow itself — untouched.
- No new nudge UI; #285 nudge covers the moment by existing behavior.

## Deploy

Rules-only backend behavior change (the Functions edit is comment-only). After merge:
`deploy-ceremony` (pending-delta check, deploy, `backend-deployed` tag advance, ledger
row). **Coordination (Gate r2 P2 — now a hard requirement, not a conditional):** #814's
rules hardening HAS merged to origin/main (`validActivityMetadata` present). This branch
MUST be cut from current origin/main and the pre-step grep-count assertion (top of this
spec) must pass; the emulator suite must run against the rules file that contains BOTH
changes.

## Acceptance

- [ ] Anonymous fresh install → Create Group → group created, NO modal, share prompt as
      today; home shows the #285 nudge afterwards.
- [ ] Rules emulator: anon single-doc group create AND group+inviteCode batch succeed
      (valid-shaped); all other create-shape validation unchanged (bad shapes still
      denied for anon AND durable).
- [ ] Anon creator: by-name add affordances disabled/hidden with the link hint; no
      `addShadowMember` call is reachable; durable creator affordances unchanged.
- [ ] `isDurableSignIn` has zero references in the repo.
- [ ] Gate provider file + its unit test + wiring test deleted; join pins relocated and
      green; no lib/ reference to `durableCredentialGateProvider` remains.
- [ ] RED evidence for test flips pasted in PR body; `Refs #818` in commit body.

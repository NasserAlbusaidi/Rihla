# Production Readiness

Last verified: 2026-06-01 (`release/android-public-hardening-2026-06-01`)

This checklist tracks the remaining launch gates for the Firebase project
`rihla-safar` and the mobile apps. Treat checked items as verified from the
commands listed here, not as permanent guarantees.

Run the consolidated read-only audit:

```bash
RIHLA_SKIP_IOS_QA=yes RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh
```

For a single wake-up handoff that prints the current commit, Android QA
artifact hashes, Firebase deploy command, release audit command, and open
blocker links, run:

```bash
bash tool/print_release_wakeup_handoff.sh rihla-safar
```

For the prompt-to-artifact map of this release-hardening branch, see
`docs/RELEASE-HARDENING-AUDIT.md`.

For a full iOS + Android release, omit `RIHLA_SKIP_IOS_QA=yes` and replace the
iOS `Deferred ...` matrix cells with passing physical-device evidence.

Current branch status: local code gates pass for the hardening branch, but the
consolidated release audit does not pass yet. On 2026-06-01, the audit passed
Functions install/audit/build, emulator tests, Flutter analyzer, theme purity,
navigation smoke tests, full Flutter coverage (88.3% raw line coverage), and
the Android release AAB build (56.5 MB). It failed on external release state:
Firebase production is still behind the branch, Android real-device QA is still
incomplete, and `RIHLA_RELEASE_APPROVED_SHA` does not match the target commit.
v1.3 launches Android-only on Google Play; iOS is soft-deferred to follow
within weeks of Android Production. The remaining release gates are backend
deploy/re-audit, Android-only physical-device QA (`docs/REAL-DEVICE-QA.md` with
`RIHLA_SKIP_IOS_QA=yes`), and final commit-bound CI release-confirmation repo
variables.

GitHub also runs `.github/workflows/readiness_check.yml` on `main` pushes and
pull requests. That workflow covers the local non-deploy gates only; it does not
replace the Firebase production-state check or physical-device QA.

Check the current `main` readiness workflow in GitHub Actions before release;
this document intentionally does not pin a run ID because every doc-only push
starts a new run.

## Verified

- [x] Android release bundle builds locally.
  - Command: `flutter build appbundle --release --obfuscate --split-debug-info=./build/app/outputs/symbols --dart-define-from-file=config.json --android-skip-build-dependency-validation`
  - Latest PR #39 hardening result (2026-05-20): `build/app/outputs/bundle/release/app-release.aab` at 58.5 MB
  - Current commit and artifact SHA-256s for Android QA handoff: `bash tool/print_android_qa_handoff.sh`
- [x] Static analysis is clean with infos enabled as non-fatal.
  - Command: `flutter analyze --no-fatal-infos`
- [x] Non-golden Flutter test suite passes with raw coverage over the 80% gate.
  - Command: `flutter test --coverage test/architecture test/core test/features test/helpers test/integration test/shared test/unit test/widget_test.dart`
  - Result: 1303 passed, 3 skipped (verified 2026-05-20 on `codex/release-hardening-1-0`)
  - Coverage: 80.6% raw line coverage
  - Note: CI and `tool/check_release_readiness.sh` both enforce 80% raw line coverage.
- [x] Navigation smoke tests cover the shippable route tree and invite links.
  - Command: `flutter test test/unit/app_router_test.dart test/helpers/navigation_test.dart test/unit/deep_link_service_test.dart test/unit/auth_link_hosting_files_test.dart test/features/activity/activity_feed_screen_test.dart test/features/groups/qr_invite_sheet_test.dart test/features/groups/group_detail_navigation_test.dart test/features/events/event_command_center_test.dart test/features/ledger/ledger_roster_strip_overflow_test.dart`
  - Result: 69 passed
  - Coverage: splash redirects to `/home`, `/join/:code` stays addressable on fresh installs, onboarding is not in the production route tree, invite links use Firebase Hosting, normalize legacy lowercase codes before sharing, and accept browser-normalized trailing slashes, account-recovery browser fallback links use the `rihla://auth-link` app scheme, both Firebase default Hosting domains are checked by the production-state verifier, production code avoids imperative `Navigator.push`, `state.extra`, and named GoRouter calls, GroupDetail create-event/settle-up/settings/activity entry points route to expected destinations, event hub module cards, expense hero, and settings button route to ledger/activity/settings, Ledger settings/search/add/settle-up/edit entry points route to expected destinations, and direct-entry nested back navigation covers group settings, group settle-up, group activity, create-event, typed create-event, event hub, event activity, ledger, activity, settings, add, edit, and settle-up.
- [x] Account-recovery success routes are restoration-safe.
  - Command: `flutter test test/features/auth/link_email_screen_test.dart test/features/auth/recover_screen_test.dart`
  - Result: 12 passed
  - Coverage: link-email and restore flows carry the normalized email in the route query instead of GoRouter `extra`; direct `/profile/link-email` and `/recover` entry back buttons route to `/profile` and `/home`; `rg -n "state\\.extra|extra: email" lib test` has no matches.
- [x] Direct route close/back controls are guarded.
  - Command: `flutter test test/features/groups/create_join_group_test.dart --plain-name "direct create close routes home when there is no stack to pop"`, `flutter test test/features/groups/create_join_group_test.dart --plain-name "direct invite close routes home when there is no stack to pop"`, `flutter test test/features/profile/profile_screen_test.dart --plain-name "direct profile back button routes home when showBack is true"`, and `flutter test test/features/group_detail_screen_test.dart --plain-name "direct entry back button routes home when no stack exists"`
  - Result: 4 focused tests passed
  - Coverage: `/create-group`, `/join/:code`, `/profile`, and `/group/:gid` no longer pop or no-op on the last GoRouter page when opened as direct entry routes. Full-suite route-backed tests also cover direct-entry back controls for group settings, group activity, event hub, event activity, event settings, and ledger.
- [x] Recovery completion drains pending writes before replacing the anonymous UID.
  - Command: `flutter test test/unit/auth_email_link_bootstrap_test.dart test/unit/auth_recovery_service_test.dart`
  - Result: 26 passed
  - Coverage: recovery deep links dispatch by persisted operation kind from warm link streams, cold-start initial URLs, and hosted-page custom-scheme fallbacks; `completeRecovery()` waits for pending Firestore writes with a timeout, signs out the transient anonymous UID, then signs in with the email link.
- [x] Local macOS golden tests pass.
  - Command: `flutter test test/goldens/ --tags golden`
  - Result: 8 passed
- [x] Firebase emulator/rules tests pass under Java 21.
  - Command: `npm --prefix functions run test:emulator`
  - Latest result (2026-05-20): 5 suites passed, 105 tests passed
  - Note: raw `npm --prefix functions test` expects the Firestore emulator to already be running; use `test:emulator` for the normal local/CI backend gate. The script delegates to `tool/run_firebase_emulator_tests.sh`, which defaults to isolated Auth/Firestore ports `19099`/`18080` so local services on Firebase's default emulator ports do not break the gate.
  - Note: Homebrew Java 21 may be installed even when `/usr/libexec/java_home -v 21` still resolves to Java 17; prefer the explicit `brew --prefix openjdk@21` path above.
- [x] Firestore production database exists for `rihla-safar`.
  - Database: `(default)`, Native mode, location `nam5`
- [x] Firebase Hosting invite/auth link files are deployed on both default domains.
  - Evidence: production-state audit verifies `/join/<code>` invite fallback,
    Apple App Site Association `/join/*` entries, Digital Asset Links matching
    `com.safar.safar`, and the auth continue page containing
    `rihla://auth-link` on both `rihla-safar.web.app` and
    `rihla-safar.firebaseapp.com`.
- [x] Production Functions dependency audit has no known vulnerabilities at low-or-higher severity.
  - Command: `npm --prefix functions audit --omit=dev --audit-level=low`
- [x] App Check client and callable enforcement are wired in the repo.
  - Evidence: `lib/core/config/firebase_config.dart` activates debug providers outside release builds and Play Integrity/App Attest with DeviceCheck fallback for release builds.
  - Evidence: `functions/src/callables/joinGroupByInviteCode.ts` sets `enforceAppCheck: true`.
  - Evidence: `tool/check_release_readiness.sh` fails if callable App Check enforcement is removed.
  - Evidence: `tool/check_release_readiness.sh` also requires `RIHLA_CONFIRM_APP_CHECK_READY=yes` so Console enrolment stays an explicit release assertion.
- [x] `deleteAccount` runs with `enforceAppCheck: false` **by design** — accepted posture, not a regression.
  - Evidence: `functions/src/callables/deleteAccount.ts` sets `{ enforceAppCheck: false }` (vs `true` on `joinGroupByInviteCode` and `cleanupAnonUidArtifacts`).
  - Rationale: GDPR right-to-erasure must succeed on attestation-failing devices (Play Integrity failure / no Play Services / MDM). Hard App Check enforcement previously **blocked** erasure — see #73; it was deliberately softened to verify-if-present.
  - Why it stays safe: the callable takes **no input** (`assertNoInput`), is **self-scoped** (uid from `request.auth` only), is idempotent, and is rate-limited by `enforceDeletionRateLimit` (5 attempts/hour/UID) — the compensating control. Do **not** re-enable App Check on this callable without reopening #73.
- [x] Join callable display-name validation matches the Firestore rules contract.
  - Evidence: `functions/src/callables/joinGroupByInviteCode.ts` rejects over-32-character names and control characters before Admin SDK writes.
  - Evidence: `functions/test/callables/joinGroupByInviteCode.test.ts` covers missing-name fallback, over-length rejection, and control-character rejection.
- [x] Join callable repairs and rejects malformed membership edge cases.
  - Evidence: `joinGroupByInviteCode` creates a missing `groups/{groupId}/members/{uid}` doc when `memberIds` already contains the caller.
  - Evidence: `joinGroupByInviteCode` rejects malformed `memberIds` before writing a member document.
- [x] Join screen preserves server rate-limit feedback.
  - Evidence: `test/features/groups/create_join_group_test.dart` covers `resource-exhausted` failures showing `Too many attempts. Try again later.` instead of the generic connection error.
- [x] Profile display-name edits use the same Firestore-compatible validation.
  - Evidence: `lib/features/settings/widgets/edit_name_bottom_sheet.dart` uses `validateDisplayName()` and `normalizeDisplayName()`.
  - Evidence: `test/features/profile/profile_screen_test.dart` rejects a 33-character profile name and leaves the persisted setting unchanged.
- [x] Device-name persistence cannot carry invalid names into later backend writes.
  - Evidence: `SettingsNotifier.setDeviceName()` rejects invalid non-empty names, normalizes valid names before saving, and avoids propagating empty names to Firestore.
  - Evidence: `SettingsService.loadSettings()` drops invalid legacy persisted names instead of surfacing them to create/join flows.
- [x] Firebase project upgraded to Blaze plan.
  - Evidence: Cloud Functions are deployed (see below), which requires `cloudbuild.googleapis.com` and `artifactregistry.googleapis.com` — both gated on Blaze.
- [x] Historical Firebase production-state audit passed for v1.2.0+15.
  - Command: `bash tool/check_firebase_prod_state.sh rihla-safar`
  - Historical result (2026-05-15): 12 checks PASS, exit 0. Re-verified 2026-05-16 after v1.2.0+15 functions deploy.
  - Current branch result (2026-05-20, PR #39): FAIL until the branch backend is deployed. Firestore indexes and Hosting passed; Firestore rules differ from production, and the deployed Functions list is missing `deleteAccount`.
- [x] Historical v1.2.0+15 Firebase Functions were deployed in production.
  - Historical evidence: production-state audit confirmed expected functions were deployed (`joinGroupByInviteCode`, `cleanupAnonUidArtifacts`, account-deletion cascade, FCM token cleanup) for the v1.2.0+15 backend snapshot.
  - v1.2.0+15 changes: `joinGroupByInviteCode` now fans the joiner into existing event `participantIds` server-side (Gap 1); new `cleanupAnonUidArtifacts` callable scrubs FCM tokens + joinAttempts for the abandoned anon UID after email-link recovery (Gap 3, fire-and-forget — failures land in Sentry breadcrumbs).
  - v1.0 hardening branch: `cleanupAnonUidArtifacts` now requires a 15-minute one-time `recoveryCleanupIntents/{oldUid}` secret created by the retiring anon UID before sign-out, so recovered users cannot migrate arbitrary visible anon UIDs.
  - Current branch note: production is missing `deleteAccount`; this checkbox is historical evidence only, not proof that the current branch Functions are deployed.
  - Backfill: `tool/backfill_join_event_sync.js` was run against `rihla-safar` on 2026-05-16 to reconcile historical event participant discrepancies.
- [x] Historical v1.2.0+15 Firestore production rules matched `security/firestore.rules`.
  - Historical evidence: production-state audit diffed the active v1.2.0+15 ruleset against the repo and reported PASS.
  - Current branch note: production does not yet contain the new `recoveryCleanupIntents/{oldUid}` rules or the latest former-member display-name validation; this checkbox remains historical, not proof that the current branch is deployed.
- [x] Firestore production indexes match `firestore.indexes.json`.
  - Evidence: production-state audit confirms index set matches the repo config; legacy `gear_items` index removed.
- [x] Firebase App Check Console enrolment is verified.
  - Evidence: Android app enrolled with Play Integrity; iOS app enrolled with App Attest (with DeviceCheck fallback). Enforced `joinGroupByInviteCode` callable is live in production.
  - Re-verify path: Firebase Console → App Check → confirm enforcement is ON for Cloud Functions and that both platform apps show "Enforced".
- [x] Icon font is subset-safe and icon tree-shaking stays on in release builds (#636).
  - Evidence: every iconsax usage in `lib/` is a `static const IconData` reference, so Flutter's `--tree-shake-icons` (on by default for `flutter build`) subsets the ~1.3MB iconsax font down to only the glyphs actually used. No `--no-tree-shake-icons` flag exists anywhere in the build/CI scripts.
  - Guard: `test/unit/tree_shake_icons_guard_test.dart` scans `.github/workflows/*.yml` and `tool/*.sh` (incl. `release_android.yml`, `check_release_readiness.sh`, `print_android_qa_handoff.sh`) and fails if any `flutter build` path passes `--no-tree-shake-icons`.
  - Text fonts: Flutter does not tree-shake text fonts, so the Arabic wordmark no longer declares the full Reem Kufi variable face. `pubspec.yaml` uses `assets/fonts/ReemKufi-RihlaWordmark.ttf` (about 11KB) under the `Rihla Arabic Display` family, and `test/unit/bundled_fonts_test.dart` fails if the full `ReemKufi-Variable.ttf` returns.

## Blockers

- [ ] Firebase production state is not aligned with this branch yet.
  - Gate command:
    ```bash
    bash tool/check_firebase_prod_state.sh rihla-safar
    ```
  - Latest gate result (2026-06-01, `release/android-public-hardening-2026-06-01`):
    Firestore database and both Hosting domains passed. Firestore indexes
    failed because production lacks the `deleteGroupAttempts.expiresAt` TTL
    field override. Firestore rules failed because production is missing the
    current delete-group write locks, soft-delete rules, and split-distribution
    participant-key validation. Functions failed because production is missing
    `deleteGroup`.
  - Required action: deploy Firestore rules/indexes, Functions, and Hosting,
    then rerun the gate before setting `RIHLA_BACKEND_RELEASE_READY=yes`.
  - **Backend deploy (2026-07-04, `c47bf943`) — DEPLOYED to prod, prod-state PASS.**
    The "Latest gate result (2026-06-01…)" above is stale. As of the latest
    2026-07-04 deploy ceremony the `backend-deployed` tag is `c47bf943`; prod
    matches `main` for all deployable backend surface (`tool/pending_deploy.sh`
    exits clean — nothing pending).
    Latest delta: **#892 (Closes #783)** — notification delivery markers now
    carry a 90-day `expiresAt` and `firestore.indexes.json` enables TTL for
    `notificationDeliveries.expiresAt`, so idempotency markers stop growing
    without bound while preserving same-key single-send behavior.
    Prior delta: **#891 (Closes #831)** — event-scoped settle-up writes a
    client `event_settlement` group-activity row; `firestore.rules` allow-lists
    that exact client type while keeping Admin-only `expense_*` forged out.
    Prior delta: **#882 (Closes #872)** — server oracle weighted allocation now
    sends rounding remainder to the alphabetically-last positive-weight
    recipient, never a 0-share/0-percent participant, matching the client.
    Prior delta: **#875 (Closes #825, Refs #885)** — pending gate intent cleanup;
    deploy-relevant backend surface is comment/test/docs only around
    `joinGroupByInviteCode` plus client token behavior, with no runtime
    rules/index/function-set change.
    Prior delta: **#874 (#876, deployed 2026-07-04 `68cd3d89`)** — offline group
    creation is atomic: one founding `WriteBatch` plus after-state create rules
    for the group, creator member, invite code, and seeded event. See the
    DEPLOY-LEDGER `68cd3d89` row for the full record.
    Prior delta: **#830 (Refs #818 Wave 3.1)** — settlement direction in
    activity feeds, rules half: `validActivityMetadata` gains 5 absent-or-typed
    string clauses (`recipientId` promoted to typed; the new direction keys
    `fromUserId`/`toUserId`/`fromName`/`toName`). Pure tightening — type
    allow-list, `hasOnly` list, and 16-key cap untouched; rules suite 202/202 at
    deploy time. See the DEPLOY-LEDGER `abee70e8` row for the full record.
    Prior delta: **#826 (Refs #818 Wave 2, Decision 0)** — anon-create gate
    removed. `firestore.rules` loses `isDurableSignIn()` (helper + its only two
    conjuncts: `validGroupCreate`, `inviteCodes` create) — anonymous users can
    now create groups + invite codes (join was already un-gated, #648).
    `addShadowMember` keeps its anon reject as the server backstop for the
    client-side shadow carve-out. Rules-only server delta (functions updated in
    place, none created/deleted); rules suite 201/201 at deploy time. See the
    DEPLOY-LEDGER `18b1d3e7` row for the full record.
    Prior delta: **#814 (#820, deployed 2026-07-03 `35785be4`)** — value-domain floor for client-writable
    group-activity metadata, **rules-only**. `validGroupActivityCreate` gains
    `validActivityMetadata(md)`: `amountFils` absent-or-int ≥ 0 (rejects
    NaN/Infinity/doubles/negatives), `currency` absent-or-`validCurrency`
    allow-list, legacy `amount` absent-or-string, `eventName`/`memberName`/
    `memberAction` absent-or-string, `size() <= 16`; ids/unknown keys stay
    opaque. Single-reference `map.get(key, default)` pattern in the standalone
    `/activity` create block (no 1000-expr pressure). Client display half
    shipped in #815/#816; Admin-SDK writers (`expense_*` fan-in, `member_left`
    callables) bypass rules — unaffected. Functions/indexes had zero content
    delta vs `07864871`; the 28 functions redeployed in place. Rules suite
    201/201 at deploy time.
    Prior delta: **#810 (Refs #808 PR1, deployed 2026-07-03 `07864871`)** — expense fan-in to the group activity
    feed. `expenseAuditLogger` also writes `expense_added`/`expense_edited`/
    `expense_deleted` entries to `groups/{gid}/activity` in the exact
    `GroupActivityLog` client shape (idempotent `.set` on `event.id`, verb-phrase
    description, ISO-string timestamp, metadata = ids + money scalars only);
    `firestore.rules` `validGroupActivityCreate` swaps `type is string` for the
    4-type client allow-list (`event_created`/`event_deleted`/`group_settlement`/
    `member_joined` — `member_left` + `expense_*` are Admin-SDK-only, closing a
    forgery hole); `groupActivityWriteRateMonitor` skips `expense_*` creates
    (T1 already counted the underlying expense; safe only because of the
    allow-list). Oracle/#366 aggregate untouched. Rules 193/193, trigger 17/17,
    monitor 12/12, full emulator suite green.
    Prior delta: **#793 + #794 (Closes #245, deployed 2026-07-02 `bcb27382`)** —
    shadow event fan-in via shared `eventFanIn.ts` (Functions-only) + client
    auto-seed default ledger event (see DEPLOY-LEDGER row for detail; this doc
    missed that ceremony's update — the ledger did not).
    Prior delta: **#780 (Refs #179)** — notification idempotency + claim-decision
    routing hardening. **Cloud Functions only** (no rules/index/function-set change).
    `fcmSender.sendToUids` gains an optional `dedupeKey`; when set, a
    `claimDeliveryMarker` transaction creates `notificationDeliveries/{sha256(key)}`
    (admin-SDK only, client default-deny) and skips the send if it already exists,
    collapsing Eventarc retry redeliveries of the SAME CloudEvent to one buzz. The
    5 Eventarc notification triggers thread a key = type-prefix + doc ids + the
    stable CloudEvent `event.id` (distinct events each still notify; #752 decomposed
    per-event settlements keep distinct ids; no cross-trigger sha collision).
    Claim-decision payload adds `decision`/`inviteCode`/`routeability`
    (`member`/`pre_join`, from live `memberIds`) so a declined already-member routes
    to `/group/:gid`, not a `/join/<code>` they can't use. Client half
    (`notification_service.dart` claim routing, `group_settings_screen` back-nav →
    `/home` fallback) shipped on `main` (not deploy-relevant). Merge-time Gate:
    fresh-context diff review 0 P1 + independent refuter REFUTED:false. **28**
    functions updated in place (none created/deleted); full Functions + Flutter
    suites green.
    Prior delta: **#766 (#767)** — freeze spending snapshot at close (Slice 6 of
    #202). `firestore.rules` `validEventCloseToggle` gains a 5th diff key
    `spendingSnapshot` + a `spendingSnapshotBounded` opaque guard (`is map &&
    size() <= 16`) after the cheap diff gate; the blob is opaque display-only,
    written on close and DELETEd on reopen, never read by the oracle/any Function.
    Rules-only — all **28** functions updated in place.
    Prior delta: **#723 (#763)** — event close lifecycle (Slice 5 of #202).
    `firestore.rules` adds `eventAcceptsExpenseWrites` which **REPLACES**
    `eventAllowsClientWrites` in the TWO expense write paths only (folds
    `isDeleted`-absent/false + `isClosed==false` into the SAME `eventData()`
    `.get(key,default)` reference, so a closed event freezes expense
    create/edit/soft-delete with no extra `get()` against the 1000-expression
    ceiling); settlements keep the untouched `eventAllowsClientWrites` and **stay
    writable after close** (the epic contract). `validEventCloseToggle` deliberately
    skips `validEventBase` so re-validating `participantIds.hasOnly(groupMembers())`
    can't block closing an event with a departed participant #249. Schema-only model
    add (`Event.isClosed/closedAt/closedBy`) with **zero money-math change**.
    Prior delta: **#752 PR1 (#754)** — decompose a group-level settle-up into
    per-event settlement writes. `firestore.rules` **additive/permissive**: optional
    `groupSettleUpId` link on settlements (guarded `!('groupSettleUpId' in data) ||
    … is string` — `validSettlementCore` runs on EVERY create, a direct access on the
    absent key would deny every keyless settle-up) + added to the event- and
    group-settlement `hasOnly` allow-lists; `validEventSettlementCreate` writer gate
    relaxed `isEventParticipant`→`isGroupMember` (counterparties STILL gated to event
    participants) so a decomposed group settle-up + #595 settle-on-behalf are accepted
    — nothing previously-allowed becomes denied. Server oracle UNTOUCHED (already folds
    event settlements per-event + group settlements globally by collection path →
    byte-for-byte aggregate parity). Rules + `functions/test/` only — no function
    add/remove/logic change (all **28** updated in place). Client decompose half
    shipped on `main`; the corrections flow is PR2 (#753 → #755, client-only, no deploy).
    Prior delta: **#714 (#714, Closes #710)** — claimShadow **per-shadow locking**
    (the #710 follow-up to #558's parity backstop): per-shadow claim reservations
    with a `claiming` transient state, lock-token verification, mutation markers +
    compare-release, and a new scheduled `claimShadowLockReaper` (27 → **28
    functions**) that resolves an abandoned claim lock; freezes Admin/rules write
    paths during claim / account-deletion identity rewrites; protects pre-join
    claimants from account deletion; extends claim/delete re-key to itemized
    `splitExplanation` + recursive activity metadata. **Two new COLLECTION_GROUP
    index overrides** (`claimRequests.requesterUid`, `claimShadowLocks.claimerUid`)
    deployed WITH the functions — `deleteAccount`'s collectionGroup scrub queries
    depend on them. Functions + rules + indexes. (The deploy also fixed a `ttl`
    absent-vs-`false` false-fail in `tool/check_firebase_prod_state.sh`'s index
    normalizer — a tooling fix, not a backend-surface change.)
    Prior delta: **#558 (#711)** — close two TOCTOU holes in `claimShadowEngine`'s
    post-commit parity backstop: a mode/scope-gated lingering-shadow-reference scan
    (`snapshotReferencesShadow`, reading field-for-field the oracle's identity set)
    so a torn uuid→uid claim cascade is detected instead of throwing post-commit
    (no rollback) / silently blessing the torn state on idempotent retry. Confined
    to `claimShadow.ts` — **27 functions unchanged** (`claimShadow` is engine-only,
    never a deployed function; updated in place, none created/deleted).
    Prior delta: **#673 (#673)** — a malformed (timestamp-less) deleteGroup lock
    self-clears instead of wedging a group's deletion forever, and
    `deleteGroupLockReaper` can now reap it · **#672 (#672)** `leaveGroup` /
    `removeMember` honor the delete-quiesce marker inside a fresh transaction so
    membership can't mutate during an in-flight group delete · **#676 (#676)**
    comment-only doc refresh (no logic change). **27 functions unchanged**
    (updated in place, none created/deleted). Prior delta: **#528 (#588)** — `firestore.rules` `positiveInt` caps
    `amountFils ≤ 2^53−1` (`Number.MAX_SAFE_INTEGER`; backstops the int64↔JS-number
    divergence, client `MoneySerializer.fitsSafeSubunits` guards the normal path) ·
    **#525 (#582)** `balanceReconciler` cursor-paginates ALL live groups (was
    skipping legacy field-absent ones) · **#526 (#583)** `writeRateMonitor` stops
    double-counting expenses · **#565 (#585)** `claimRequestNotifier` also notifies
    the **requester** on the creator's decide (rules + functions; **27 functions
    unchanged**). Prior delta: **#560 (#563)** — new `claimRequestNotifier` FCM
    `onDocumentWritten` trigger pushing the group creator when a placeholder-claim
    request arrives (26 → **27 functions**; the #278 PR9 discoverability tail).
    Prior delta: #278
    claim/merge backend (PR6 #556 `mergeUidMapKey` SUM helper · PR7
    #557 `claimShadow` re-key engine + shared `batchWriter`/`mapReKey`/`recomputeNet`
    extraction · PR8 #559 the 4 request/approve callables + `claimRequests` rules
    block + raw `claimShadow` de-exported · PR9 #561 `listUnclaimedShadows`
    discovery) — 5 new callables CREATED (21 → 26 functions; `claimShadow` is
    engine-only, never deployed). Epic #278 CLOSED.
    `docs/DEPLOY-LEDGER.md` is the authoritative per-deploy history; shipped
    across the 2026-06-07…12 deploys:
    - **#270** (`cc8c84e`) — server allocators (`groupNetBalance.ts`
      `allocateShares`/`allocateExact`/`allocatePercent`) gain the
      negative-value→equal-split guard, mirroring the client byte-for-byte.
    - **#318** (`6af0594`) — `removeMember` Cloud callable (created in prod) +
      `firestore.rules` drop of `validCreatorRemoveMember` /
      `removesExactlyOneExistingMember`.
    - **#294** (`ef64797`) — `deleteAccount.ts` + `cleanupAnonUidArtifacts.ts`
      locate member docs by the `userId` field.
    - **#275** (`f105862`) — `cleanupAnonUidArtifacts` per-group cascade migrated
      off the 500-write transaction cliff to a chunked `BatchWriter`.
    - **#248 PR 1** (`a9ef95a`, #337) — expense `lastEditedBy` field rule pins
      (`==auth.uid`; presence-gated create / diff-gated update; `validSoftDelete`
      carries it).
    - **#248 PR 2** (`b53433d`, #339) — new `expenseAuditLogger` `onDocumentWritten`
      trigger (server-owned expense CREATE/UPDATE/soft-DELETE audit log → event
      `activity_logs`); `validActivityCreate` removed so event `activity_logs` is
      server-only (a client can no longer forge an audit entry). 13 functions now.
    - **#248 PR 4** (`786c2f1`, #343) — `validExpenseUpdate` opens expense
      edit/soft-delete to **any event participant** (drops `requesterIsRecordCreator()`)
      and makes the `lastEditedBy == auth.uid` pin **mandatory** on every update
      (was diff-gated) so the audit trigger can never mis-attribute an edit to the
      creator. Rules-only; 13 functions unchanged.
    - **#261 PR-0b** (`5eaacf7`, #371) — mixed-currency balance-gate guard:
      `groupNetBalance.ts recomputeNet` returns a `currencies` set (expense-fold
      only, function-scope, `toUpperCase()`-normalized) and `deleteGroup` /
      `leaveGroup` / `removeMember` refuse `failed-precondition` when it holds
      more than one currency, **before** the `isZero()` gate — closing the
      `+10 OMR / −10 USD` fake-zero delete/leave/remove money-loss path.
      Functions-only; 13 functions unchanged.
    - **#261 PR-1** (`edd6421`, #374) — `firestore.rules` make `group.currency`
      authoritative + immutable: `currencyMatchesGroup` pins expense create
      (unconditional) / update (diff-gated) / event-settlement-create currency to
      the owning group's currency, and `validCreatorMetadataUpdate` drops
      `currency` from its allow-list (settable only at create). Client
      `updateGroup(currency:)` param removed. Rules-only; 13 functions unchanged.
      Historical Model A enforcement: later #382 PRs moved write paths to
      supported explicit currency codes and relaxed money-doc equality to
      `validCurrency`, so non-OMR writes no longer fail solely for differing
      from the group default.
    - **#279** (`b9163a1d`, #388) — server-authoritative display-name collision
      guard in `joinGroupByInviteCode`: a brand-new joiner whose
      `trim().toLowerCase()` name matches an existing member is rejected
      `already-exists` (→ client l10n `groupJoinNameTaken`). Gated on `didJoin` so
      the #53 heal-path / idempotent re-join are exempt; the collision does not
      burn the 5/hr join throttle. Functions-only; 13 functions unchanged.
    - **#366 PR1** (`7370b307`, #421) — server-maintained per-group balance
      aggregate (`groups/{gid}/aggregates/balance`): 4 new diff-gated
      `onDocumentWritten` triggers + daily `balanceReconciler`, all over the
      shared `recomputeNet` oracle; rules add a client-write-denied
      `aggregates` block. Display-cache only. 18 functions now.
    - **#441 PR2** (`20689860`, #444) — the durable-credential gate, server
      side: `isDurableSignIn()` (`sign_in_provider != 'anonymous'`) on
      `validGroupCreate` + `inviteCodes` create, and an anonymous-provider
      `permission-denied` reject in `joinGroupByInviteCode` (pre-throttle, no
      `joinAttempts` burn; closes the #197 anon-rotation bypass for join).
      `recoveryCleanupIntents` deliberately stays anon-writable until PR5.
      Rules + one function updated; 18 functions unchanged.
    - **#441 PR5** (`c009b700`, #450) — the cross-UID merge engine DELETED from
      prod: `cleanupAnonUidArtifacts` callable removed (`deploy --force`, 18 → **17
      functions**), `recoveryCleanupIntents` rules block + `validCleanupIntent` +
      TTL dropped (fails closed). Epic #441 CLOSED.
    - **#461** (`fdf8460b`) — security: scoped npm `overrides` pin of
      `@grpc/grpc-js` to `^1.14.4` under `google-gax` (GHSA-5375-pq7m-f5r2),
      re-bundled into prod Functions. Deps-only; functions logic / rules / indexes
      unchanged; 17 functions. Phase 1 of the v1.5.0 release.
    - **#382 PR-2** (`8acb7fdf`, #467) — server balance oracle bucketed per
      currency: `groupNetBalance.ts` `foldEventNet`/`recomputeNet` return
      per-currency `net`/`perEventNet` (expenses AND settlements bucket by their
      own per-doc currency); `deleteGroup`/`leaveGroup`/`removeMember` drop the
      `currencies.size>1` refusal → require **zero in every currency bucket** (no
      FX). `balanceAggregator` Shim #2 flattens the sole bucket → v1 aggregate doc
      byte-identical; `balanceReconciler` untouched. Functions-only; 17 functions
      unchanged. Backward-compatible — single-currency behavior is identical;
      later #382 PRs relaxed the uniformity constraint and made per-bucket
      paths reachable. Mirrors the merged client PR-1; #382 epic stayed open
      at this point in the rollout.
    - **#382 PR-3** (`b12a3f00`, #471) — aggregate doc v2: `balanceAggregator`
      drops Shim #2 and writes `schemaVersion: 2` per-currency milli maps
      (`netMilliByCurrency` `{ccy:{uid:int}}` + `perEventNetMilliByCurrency`
      `{eid:{ccy:{uid:int}}}`, eventId-major); `degraded` is byte-cap-only;
      `balanceReconciler` fingerprint re-keyed to the v2 fields (first sweep =
      v1→v2 backfill); dead `RecomputeResult.currencies` deleted. Client half
      (v2 decoder, facade serves mixed docs, Shim #1 dropped, bucket-key
      cross-group fold) merged in the same PR; v1-pinned clients decode v2 docs
      as null → once-path fallback. Functions-only; 17 functions unchanged.
      #382 epic stays open (PR-4 activity-log currency / PR-5 stepped settle /
      PR-6 rules relaxation remain).
    - **#519 + #529** (`80932c51`, #543) — deleteGroup lock lifecycle. #529 drops
      `canClearObservedLock` so an invocation clears only the lock it created — a
      concurrent caller can no longer wipe a peer's live lock. #519 adds the new
      hourly `deleteGroupLockReaper` scheduled fn (19 → **20 functions**) that
      resumes the shared `finalizeGroupDeletion` core for stale
      `deletingInProgress` locks; money-safe because it never bumps
      `deleteLockedAt` (the balance gate runs before any mutation). Bundled #544
      (`caa23852`): `form-data 2.5.6` + `protobufjs 7.6.4` audit pins (deps-only,
      fixes the readiness `npm audit` gate). Functions-only; rules/indexes
      unchanged.
    - This clears the prior pending-deploy debt; the pinned checkbox above stays
      OPEN until the full *release* ceremony (a recorded prod-state PASS vs the
      release SHA), which is a higher bar than this backend deploy.
- [ ] Real-device QA is not complete (Android-only for v1.2).
  - Runbook: `docs/REAL-DEVICE-QA.md`
  - Gate command (v1.2 Android-only):
    ```bash
    RIHLA_SKIP_IOS_QA=yes bash tool/check_real_device_qa_gate.sh
    ```
  - Latest gate result (2026-06-01, `release/android-public-hardening-2026-06-01`):
    no physical Android device detected; matrix iOS cells filled with
    `Deferred — v1.2 Android-only`; Android cells and evidence still empty for
    RD-01..RD-09.
  - v1.2.0+15 carry-over: post-launch bugs found on +14 (group-detail back button, event settlement names, `currentUserIdProvider` reactivity, App Check on join callable, join-event-sync, anon-UID cleanup) are all resolved on `main` and documented in `docs/REAL-DEVICE-QA.md` § "Resolved on fix/post-launch-qa-v1.2".
  - Required Android matrix (RD-01..09):
    - Create group, join group by invite code, delete group.
    - Two-device ledger identity (two Android devices in one group; one pays an expense and each device shows the correct payer/ower identity).
    - Android expense entry keyboard exposes decimal input for OMR amounts.
    - Offline and reconnect: create/read flows recover without false permanent offline state.
    - Notification opt-in and opt-out: token is written on enable and removed on disable.
    - Arabic RTL golden path.
  - iOS re-activation: when iOS ships, unset `RIHLA_SKIP_IOS_QA` and replace `Deferred ...` cells with `Pass ...` and concrete iOS evidence.
- [ ] Android release workflow external confirmations must be re-confirmed for the target commit.
  - `.github/workflows/release_android.yml` now refuses to upload unless `RIHLA_BACKEND_RELEASE_READY`, `RIHLA_APP_CHECK_READY`, and `RIHLA_REAL_DEVICE_QA_READY` repository variables are all set to `yes`.
  - It also requires `RIHLA_RELEASE_APPROVED_SHA` to match the exact commit being uploaded, so stale `yes` variables from a previous release cannot authorize a newer tag.
  - The upload job now refuses non-`v*` refs and refuses tag commits that are
    not contained in `origin/main`, so manual dispatches must target a release
    tag on the protected branch history.
  - Latest gate result (2026-06-01, `release/android-public-hardening-2026-06-01`):
    `RIHLA_BACKEND_RELEASE_READY`, `RIHLA_APP_CHECK_READY`, and
    `RIHLA_REAL_DEVICE_QA_READY` were `yes`, but
    `RIHLA_RELEASE_APPROVED_SHA=f03a89a15b03f9c873bdfa08158a31357c869061`
    did not match target commit
    `51f358e727a58ec260b0783c54535becd568b3cb`.
  - Reconfirm or reset these variables only after the production-state audit,
    App Check Console enrolment, and physical-device QA matrix pass for the
    final target commit.
- [x] GitHub release governance is configured.
  - Gate command:
    ```bash
    bash tool/check_github_release_governance.sh
    ```
  - Latest gate result (2026-05-20): main branch protection is configured
    with the strict `readiness` status check and admin enforcement. The gate
    still fails intentionally until `RIHLA_BACKEND_RELEASE_READY=yes`,
    `RIHLA_REAL_DEVICE_QA_READY=yes`, and `RIHLA_RELEASE_APPROVED_SHA` match
    the final target commit after #40/#41 pass.

## External Actions

These actions cannot be completed from this repo and remain before release:

0. Print the current wake-up handoff:
   ```bash
   bash tool/print_release_wakeup_handoff.sh rihla-safar
   ```
1. After branch testing/review is accepted and Firebase deploy approval is
   explicit, deploy the branch backend from a clean worktree and verify
   production state. Production Firebase must match this branch before the
   final real-device QA evidence is recorded; otherwise the matrix proves the
   wrong backend:
   ```bash
   bash tool/print_firebase_deploy_handoff.sh rihla-safar
   RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes RIHLA_FIREBASE_DEPLOY_APPROVED_SHA="$(git rev-parse HEAD)" bash tool/deploy_firebase_backend.sh rihla-safar
   bash tool/check_firebase_prod_state.sh rihla-safar
   ```
   Do not continue until the production-state check exits 0 for the target
   commit.
2. Connect two physical Android devices, complete the `docs/REAL-DEVICE-QA.md`
   matrix (RD-01..09) with concrete Android evidence against the verified
   production Firebase backend, then rerun the gate until it exits 0:
   ```bash
   RIHLA_SKIP_IOS_QA=yes bash tool/check_real_device_qa_gate.sh
   ```
   iOS cells stay marked `Deferred — v1.2 Android-only` until iOS ships.
3. After RD-QA is recorded and the backend re-audit passes for the target
   commit, set the three Android release-workflow repository variables to
   `yes`:
   `RIHLA_BACKEND_RELEASE_READY`, `RIHLA_APP_CHECK_READY`,
   `RIHLA_REAL_DEVICE_QA_READY`.
4. Set `RIHLA_RELEASE_APPROVED_SHA` to the full commit SHA that will be tagged
   and uploaded. The release workflow refuses to upload to Play until the three
   readiness variables are `yes`, the approved SHA matches `GITHUB_SHA`, the
   workflow is running from a `v*` tag, and the tag commit is contained in
   `origin/main`.
5. Confirm `main` branch protection is still enabled and still requires the
   strict `Readiness Check / readiness` status before merging release branches.
6. Re-run the full audit before promoting the Play Store track:
   ```bash
   RIHLA_SKIP_IOS_QA=yes RIHLA_CONFIRM_APP_CHECK_READY=yes bash tool/check_release_readiness.sh
   ```
   `tool/release.sh` runs this same audit after creating the release commit and
   before creating/pushing the tag. If the audit fails, fix the failed gate
   before tagging that commit.

Historical external actions completed on or before 2026-05-16:

- Upgraded `rihla-safar` to Blaze plan.
- Deployed Firestore rules, indexes, Functions, and Hosting via
  `tool/deploy_firebase_backend.sh`.
- Enrolled Firebase App Check (Play Integrity for Android, App Attest /
  DeviceCheck fallback for iOS).
- Re-ran `bash tool/check_firebase_prod_state.sh rihla-safar` — 12 checks
  PASS for the v1.2.0+15 backend snapshot.
- 2026-05-16: deployed v1.2.0+15 functions (`joinGroupByInviteCode` event
  fan-out + new `cleanupAnonUidArtifacts` callable); ran
  `tool/backfill_join_event_sync.js` against `rihla-safar`; tagged
  `v1.2.0-b15` and triggered Android Release workflow to Play "first" track.

## Follow-ups for v1.2.0+16

- **Orphan anon-UID reconciliation.** Five orphan anon UIDs in production
  have downstream references (`memberIds` / `participantIds` /
  `groups/{gid}/members/{uid}` docs) and cannot be safely auto-pruned by
  the fire-and-forget `cleanupAnonUidArtifacts` callable. Build a
  server-side reconciliation tool (or expand the callable to traverse
  references) before the next batch of recoveries lands. No inspection or
  reconciliation tool exists in the repo yet — build one before relying on it.
- **Complete the Android RD-QA matrix.** RD-01..09 cells in
  `docs/REAL-DEVICE-QA.md` are still empty; gate command above will block
  the next release tag until they're filled with concrete evidence.

## Deployment Commands

The initial production deploy is complete. Use these commands for subsequent
backend changes.

Before deploying, run the read-only production-state check to understand
current drift:

```bash
bash tool/print_firebase_deploy_handoff.sh rihla-safar
bash tool/check_firebase_prod_state.sh rihla-safar
```

If this branch includes backend changes, rule/function mismatches are expected
before deployment. After deployment, the command should report PASS and exit 0
against the currently deployed backend.

Redeploy backend after a rules / indexes / Functions / Hosting change:

```bash
RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes RIHLA_FIREBASE_DEPLOY_APPROVED_SHA="$(git rev-parse HEAD)" bash tool/deploy_firebase_backend.sh rihla-safar
```

The script installs Functions dependencies from the lockfile, audits production
dependencies at low severity, builds Functions, rechecks the clean worktree and
approved SHA, deploys Firestore rules/indexes, Functions, and Hosting, then runs
`tool/check_firebase_prod_state.sh`.

Equivalent manual deploy command:

```bash
npx --yes firebase-tools@15.8.0 deploy \
  --force \
  --project rihla-safar \
  --only firestore:rules,firestore:indexes,functions,hosting
```

### Updating the Play Store listing

Listing assets (icon, feature graphic, screenshots, title, descriptions) are
managed via `fastlane supply` and live under `fastlane/metadata/android/en-US/`.
Listing edits are **decoupled from the AAB release pipeline** — they don't
touch the binary, don't trigger an AAB re-review, and are safe to push while
an Android Release workflow is in flight.

```bash
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"   # Homebrew Ruby 3.x required
bundle install

# Edit fastlane/metadata/android/en-US/<file>, then:
bundle exec fastlane android icon        # icon + feature graphic only
bundle exec fastlane android listing     # icon + screenshots + text (full)
bundle exec fastlane android pull        # re-sync local repo from live Play
```

The service-account key at `secrets/play-key.json` (gitignored) is the same
JSON used by CI as `GOOGLE_PLAY_JSON_KEY`.

Then confirm production state:

```bash
npx --yes firebase-tools@15.8.0 functions:list --project rihla-safar
npx --yes firebase-tools@15.8.0 firestore:indexes --project rihla-safar --database '(default)'
```

For Firestore rules, fetch the active release through the Firebase Rules API and
diff it against `security/firestore.rules`.

## Promoting the Play Store track (`first` → production)

**Chosen path: manual promotion in Play Console.** The release pipeline
(`release_android.yml`, `fastlane/Fastfile` `TRACK = "first"`) intentionally
uploads to the closed **`first`** track only — there is **no** automated
production-track step. Going public stays a deliberate human gate. (Issue #129.)

Promotion reuses the **exact AAB already tested on `first`** — no rebuild, no new
version code. The CI readiness gates (`RIHLA_BACKEND_RELEASE_READY`,
`RIHLA_APP_CHECK_READY`, `RIHLA_REAL_DEVICE_QA_READY`, matching
`RIHLA_RELEASE_APPROVED_SHA`) already passed when that build was uploaded to
`first`, so they are not re-asserted at promotion time.

Before promoting:

1. Let the `first` build soak until it's demonstrably stable: crash-free
   sessions > 99%, **zero** open P0 Sentry issues for that version code.
2. Confirm the version code you intend to promote is the one that passed
   real-device QA (`docs/REAL-DEVICE-QA.md`).

Promote:

3. Play Console → **Production** → **Create new release** → **Add from library**
   (or **Promote release** from the `first` track) → select the tested build.
   This carries the same AAB + version code into production.
4. Roll out in stages: **5% → 25% → 100%**, watching Android vitals / Sentry
   between each step. Halt and use the Play Console rollback/halt control if
   crash rate spikes.
5. Release notes are entered manually in the Production release (CI uploads none
   — see `fastlane/README.md`).

If a production build must be built fresh instead of promoting the tested
artifact, it needs a **fresh version code** (bump past the live `first` build in
`pubspec.yaml`) and a full re-run of the readiness gates — promotion of the
already-tested AAB is preferred precisely to avoid shipping an unverified binary.

Revisit automating a `production` track in CI (gated by a separate
`RIHLA_PRODUCTION_RELEASE_READY` repo variable) only once the manual cadence is
well understood; until then manual promotion is the safer default for a
single-maintainer launch.

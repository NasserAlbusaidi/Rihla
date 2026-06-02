# Changelog

All notable changes to Rihla are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.1] — 2026-06-02

Post-launch hardening release — no new features. Server-trust boundary,
money-safety, and soft-delete invariants are tightened, plus a home-screen
performance fix. The public `1.3.0+18` client deletes groups client-side; this
build routes deletion through a server callable, so the backend was deployed
ahead of this release.

### Changed
- **Group deletion is now server-authoritative.** A `deleteGroup` Cloud callable
  refuses while any balance is unsettled and soft-deletes the group and its
  events in one server transaction, replacing the former client-side batch
  delete. (#190)
- **Home skips balance aggregation for groups with no active events**, dropping
  redundant Firestore listeners on the home screen.

### Fixed
- **Exact-split never emits a negative owed.** Renormalization at the rounding
  boundary closes the residual onto the alphabetically-last recipient that can
  absorb it without going negative. (#195)
- **Hardened Firestore soft-delete write locks** and cleaned up stale
  `deleteGroup` retry locks so a failed attempt can't strand a group. (#205)
- **Server-side validation of `splitDistribution` participant keys.** (#191)
- **Create-event UID guard** keeps events attributed to the correct actor.

## [1.3.0] — 2026-05-31

**First public production release on Google Play.** Earlier `1.2.0+12 … +16`
builds were closed-test / alpha-track only; this is the first time the app and
its backend reach production users. Everything below merged to `main` after the
closed-test `1.2.0+16` cut. Two subsystems described in those earlier entries are
gone by 1.3.0: the hand-rolled SQLite cache (removed, #50) and first-launch
onboarding (archived out of the route tree, #56).

### Added
- **Arabic localization + full RTL.** Complete Arabic translation across
  settings, profile, ledger, groups, and activity, with RTL-aware layout,
  mirrored navigation glyphs, and a language toggle. Amount entry stays LTR.
  (#34–#38)

### Changed
- **Currency notation unified to ISO codes — code-first, every locale.** Amounts
  render with the ISO currency code rather than a glyph (Geist Mono ships no
  Arabic glyphs); the symbol path is retired. (#144)
- **Brand fonts bundled as native app assets.** Geist / Geist Mono / Instrument
  Serif ship inside the binary instead of being fetched from the Google Fonts CDN
  at runtime — no first-paint network dependency. (#103)
- **Deep links and legal pages standardized on `rihla-safar.web.app`.** The dead
  bare `rihla.app` host was dropped everywhere — link parser, profile QR, App
  Links, iOS entitlements, and the privacy/terms/delete-data URLs. (#130)
- **`deleteAccount` App Check posture made explicit.** The deletion callable
  verifies App Check if present but does not hard-enforce it, so GDPR erasure
  still succeeds on attestation-failing devices; it stays safe via no-input,
  self-scoped, idempotent, rate-limited controls. (#73, #132)

### Fixed
- **Ledger split count and per-person share are correct by scope.** Global /
  equal-split expenses no longer display "split 0 ways"; each scope computes the
  right participant count and share. (#125)
- **Partial account deletion is surfaced with a guaranteed retry** instead of
  silently leaving a half-deleted account. (#46, #77)
- **Join rejects soft-deleted groups** rather than attaching to a tombstoned
  group. (#78)
- **RTL and display polish.** Back-arrow glyphs mirror in Arabic on ledger /
  create-event / settle-up; the GROUPS header gap was widened so the RTL
  call-to-action no longer collides with the first balance; two design-review
  passes resolved RTL, localization, and money-display defects. (#126, #161,
  #148, #150–#163)
- **Settled-balance bar renders intentionally**, and the redundant settle-up
  avatar ring was dropped. (#146, #147)
- **Event settle-up no longer fails with `PERMISSION_DENIED`.** The
  event-settlement Firestore rule now permits and validates the
  `payerName`/`recipientName` the client writes, mirroring the group-settlement
  rule — this also unblocks deleting groups that carry event debts. (#185)

### Removed
- **Hand-rolled SQLite cache.** `safar_cache.db`, `LocalDatabase`, `sqflite`, and
  the UID-change cache-wipe listener are gone — the Firestore SDK's own offline
  persistence now serves offline reads and replays queued writes. (#50)
- **Large dead-code purge.** Receipts/OCR, the three-step add-expense flow, the
  legacy transaction ledger, settle-up orphans, the previous home-dashboard
  cluster, orphaned group / profile / shared widgets, activity shims, trip
  back-compat, the animations barrel, dead constants, an orphaned SVG, and unused
  dependencies were all deleted. (#81–#96)

### Security
- **Cross-UID isolation of the Firestore on-device cache.** A cold-start
  `CacheUidBarrier`, a `FirestoreCacheGate`, and a restart-based isolation
  controller stop one anonymous session's cached data from leaking into the next
  after account recovery. (#45, #68)
- **`deletionAttempts.expiresAt` TTL reconciled** as a Firestore field override,
  so rate-limit records self-expire. (#131)
- Production **Functions dependency audit** clean at low-or-higher severity; an
  ESLint flat config was added and wired into CI. (#55, #64)

### Performance
- **Event activity feed paginated.** The previously unbounded activity-log stream
  is replaced with cursor-based pagination — 50-item pages with infinite scroll.
  (#109)
- **Home dashboard.** Cross-group owed/owes folded into a single
  `CrossGroupBalance` pass, the settings subscription narrowed with `.select`,
  and a redundant per-event `ref.watch` dropped. (#107, #108, #110, #112)

### Internal
- **Key decisions recorded as ADRs** — settlement-name resolution, additive
  event-participant adds, and Western numerals in Arabic text. (#48, #57, #145)
- Play Store listing copy replaced with verified English + Arabic text (no
  unverified feature claims). (#141)

## [1.2.0+16] — 2026-05-17

Account deletion + ledger identity polish. Closes two of the largest
remaining post-launch gaps: users can self-delete accounts end-to-end,
and dormant anon UIDs (post-recovery, post-uninstall) no longer surface
as cryptic strings in the ledger.

### Added
- **Server-side account deletion.** Profile → Account → Delete now
  triggers a Cloud Function that cascades auth removal, Firestore
  tombstones, and FCM token cleanup. Sentry breadcrumbs redact email
  PII on the failure path.
- **Former-member rendering.** Dormant anon-UID creators, payers,
  and settlement counterparties resolve to `former member` across the
  ledger, expense card, settlement row, and settle-up surfaces.
  Pure client-side resolver — no schema changes, no Firestore writes;
  `firestore.rules` reject any persisted `former member` suffix to
  prevent leakage.

### Changed
- **Coverage gate ratcheted back to 80%.** Auth/profile/settings test
  backlog cleared (recover-pending screen now covered).
- **CLAUDE.md split.** Operating Contract is now the top section;
  REFERENCE is lookup. `docs/SPEC-VERIFICATION.md` extracted with the
  full worked examples behind the verification rules.

### Removed
- **Orphaned `TripCacheRepository`** — dead since the trip→event
  rename; deleted with its tests.

## [1.2.0+15] — 2026-05-16

Post-launch QA hardening. Two new server-side capabilities address data
integrity issues surfaced after the +12 Play ship.

### Added
- **Server-side event fan-out on join.** `joinGroupByInviteCode` now
  appends the joining UID to existing event `participantIds` and snapshots
  their display name into `participantNames` — joiners no longer have to
  be manually re-added per event by the creator.
- **`cleanupAnonUidArtifacts` callable.** Fire-and-forget post-recovery
  cleanup: scrubs FCM tokens, `joinAttempts`, and other anon-UID-keyed
  docs left over from the abandoned anonymous session. Failures surface
  as Sentry breadcrumbs. Some UIDs with downstream references in
  `memberIds` / `participantIds` still require a future server-side
  reconciliation pass (queued for +16).
- **Backfill tooling.** `tool/backfill_join_event_sync.js` reconciles
  historical event participant discrepancies; run against `rihla-safar`
  on 2026-05-16.

## [1.2.0+14] — 2026-05-16

Post-launch QA fixes for bugs reported on the +12/+13 Play tracks.

### Fixed
- **GroupDetailScreen back button** no longer fails to pop when opened
  via direct route entry.
- **Event settlement names** correctly resolve display names instead of
  showing "Someone paid Someone".
- **`currentUserIdProvider` reactivity.** Provider now follows Firebase
  Auth UID swaps (regression introduced in +12 broke account-recovery
  flows downstream of the provider).
- **App Check re-enabled** on the `joinGroupByInviteCode` callable
  (accidentally disabled in +13).

## [1.2.0+13] — 2026-05-16

Re-cut to clear a Play upload-rejected version code (+12 succeeded on
build but Play rejected the upload; +13 was burned by another upload
failure — Play registers AAB version codes even on failed uploads).

## [1.2.0] — 2026-05-14 (Play build 1.2.0+12)

First Play Store upload (closed-test / alpha track). Adds account recovery, hardens backend rules,
ships the Sprint 1/2 UI surfaces, and finishes pre-launch polish.

### Added
- **Account recovery (email-link).** Link an email from Profile, receive a
  one-tap sign-in link, restore from the Home banner on a new device.
  Server-driven UID swap wipes the local SQLite cache so old anonymous data
  cannot leak across sessions.
- **In-app account deletion.** Profile → Account → Delete account triggers
  the server-side cascade (auth user, Firestore, FCM tokens, optional
  re-auth gate). Sentry breadcrumbs redact email PII.
- **Sign-out tile.** Linked users can sign out from the current device
  without dropping their data.
- **First-launch onboarding.** Restored 3-page intro with edge-to-edge
  saffron gradient and inline page dots.
- **Group + profile QR sheets** for fast invite/share.
- **Custom split editor** in Add/Edit Expense — shares, exact, percent.
- **Ledger search sheet.**
- **Sprint 2 picker sheets** — base currency, language, default split mode.
- **Deep links.** `rihla-safar.web.app/join/<code>` opens the join-group flow.
- **Legal pages** hosted at `rihla-safar.web.app/privacy`, `/terms`, `/delete-data`.

### Changed
- **Group join** moved to a callable backend (atomic, validated, RLS-safe).
- **Display-name validation** unified across client and Firestore rules
  (length, unicode classes, profanity filter shared via one validator).
- **Event mutations** governed by a C-Hierarchy policy: creator + invited
  roles only, enforced in rules.
- **Add/Edit Expense** unified onto a single editor body and re-skinned to
  match the saffron wireframes.
- **Bottom nav** font tokenized; legacy widgets retired.
- **Storage client surface retired** — no more direct Storage SDK use.

### Fixed
- **ProfileScreen `canPop` crash** when the screen built inside
  `BottomNavShell` before the GoRouter match list was populated. Replaced
  the runtime probe with an explicit `showBack` constructor parameter.
- **Add Expense amount hero** no longer paints a filled background over
  the gradient.
- **Onboarding dots** no longer eat the body padding on short screens.
- **Picker sheets** scroll correctly on short viewports.
- **Auth** continue URL pinned to the Firebase Hosting domain;
  `oobCode` scrubbed from logs.

### Security
- **Append-only settlements.** Settlement rows can no longer be edited or
  deleted; corrections create a new offsetting row.
- **`createdBy` ownership** required on expenses + settlements; rules
  reject writes that lie about the author.
- **Functions deps.** `protobufjs` bumped to clear `npm audit` advisories.

### Internal
- Raw line coverage gate temporarily lowered from 80% → 70% while the
  auth / profile / settings test suites catch up. See TODO in
  `release_android.yml` and `readiness_check.yml`.
- Removed the legacy GSD planning framework from the repo.

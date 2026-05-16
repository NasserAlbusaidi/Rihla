# Changelog

All notable changes to Rihla are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

First Play Store release. Adds account recovery, hardens backend rules,
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
- **Deep links.** `rihla.app/join/<code>` opens the join-group flow.
- **Legal pages** hosted at `rihla.app/privacy`, `/terms`, `/delete-data`.

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

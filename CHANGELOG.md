# Changelog

All notable changes to Rihla are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.7.1] — 2026-07-01

Closed-track validation build for the event-driven connectivity fix, plus the
current post-1.7.0 money-trust work already merged to `main`.

### Added
- **Trip receipt proof packs (#704/#776/#778).** Event recaps can export CSV and
  PDF proof packs for tester review.
- **Shareable recap and settle-up handoff work (#202/#367/#717/#721/#722/#723).**
  Recaps gained richer money summaries, a shareable PNG card, close-state
  spending snapshots, clearer settle-up CTAs, and numberless WhatsApp payment
  notifications.

### Changed
- **Settle-up stale-amount revalidation (#719/#773).** Event and group settle-up
  writes now revalidate the amount immediately before commit so stale screens
  cannot submit outdated balances.

### Fixed
- **Offline replay balance freshness (#633/#777).** Connectivity now treats
  pending writes and balance aggregate freshness as separate barriers, keeping
  home balance reads on the once-path until server aggregates catch up after
  offline replay or join fanout.

## [1.7.0] — 2026-06-29

Ledger and money-trust release. Group settle-ups now decompose into per-event
settlements so cross-event and group balances reconcile exactly; the split
editor is one card; and invite attribution survives Play Store installs. The
decomposed settle-up Firestore rules are already live in production (`26c5cdac`)
— no further backend deploy is required for this client.

### Added
- **Android install-referrer invite attribution (#724).** Joining via a Play
  Store install link now attributes the invite on first launch, even when the
  app is installed before the deep link is opened.

### Changed
- **Group settle-ups decompose into per-event writes (#752/#753).** Settling a
  group balance writes one settlement per underlying event and corrects them
  atomically, so per-event and group views stay consistent.
- **One unified Split card (#485).** The ledger split editor collapses its three
  sections and the duplicate payer picker into a single card.
- **Per-event-type recap copy (#689).** Event recap nouns and empty-state copy
  now match the event type.
- **Cleaner join screen (#293).** The display-name field starts blank, the
  invite-code field filters to the valid alphabet, and the form auto-submits
  once.

### Fixed
- **Faster expense sync (#632).** Expense snapshot ticks deserialize only the
  documents that changed instead of the whole collection.
- **Hardened cold boot (#724/#741).** Cold-start steps are isolated so an early
  failure can't disable account recovery.

## [1.6.3] — 2026-06-27

Performance, ledger-category correctness, and offline-UX patch, plus backend
claimShadow hardening already live in production (`18306fc6`). No schema or
client-breaking changes.

### Added
- **Event-type smart defaults (#689).** Ledger categories are now driven by an
  id-based catalog (10 built-ins) and ordered by the event's type, so the most
  likely categories surface first.

### Changed
- **Faster ledger and event screens.** Per-expense owed shares are memoized
  instead of re-allocated per visible row (#629); `EventCommandCenter` shares a
  single balance pass (#631); filter-independent roster/hero/timeline no longer
  rebuild on every category-chip tap (#628); net-by-currency is pivoted once per
  build (#630).
- **Faster cold boot (#635).** Eager notification sync is deferred off the
  first-frame turn.
- **Smaller app bundle (#636).** Arabic wordmark font is subset and icon
  tree-shaking is guarded on for release builds.

### Fixed
- **Ledger categories displayed correctly (#689/#694).** Category display and
  search read the never-persisted `categoryName`, bucketing every expense as
  "Other"; both now resolve through `categoryId`.
- **Create-group name validation (#680).** The "Name can't be empty." error no
  longer lingers after a valid name is typed.
- **Offline event-settings Save (#682).** Saving event settings while offline now
  shows distinct "will sync" feedback instead of appearing to hang.
- **Group callable failures (#649).** Failed group/shadow callables now surface a
  clear message instead of failing silently.
- **Backend: claimShadow parity + per-shadow locking (#558/#710).** Post-commit
  parity no longer throws after a TOCTOU `participantIds` edit, and concurrent
  claim approvals are isolated per shadow. Deployed to production.

## [1.6.2] — 2026-06-25

Offline-hardening and account-safety patch. Tightens behaviour when the app is
offline or restoring an account, makes group deletion self-healing on the server,
and fixes a back-navigation dead-end. Backend (#672/#673) deployed to the
production Firebase project (`9caab3e0`).

### Fixed
- **Account-switch group-orphan guard (#662).** Switching a populated anonymous
  session to a Google account now blocks the irreversible swap unless the outgoing
  session is provably empty, closing the third cross-UID swap path that could
  orphan a user's joined groups.
- **Offline event-settings writes (#670).** Editing an event's settings while
  offline stages the write and replays it on reconnect instead of hanging.
- **Offline account restore (#671).** Restoring an account no longer blocks on
  FCM-token cleanup when the device is offline.
- **Self-healing group-delete locks (#672/#673).** `leaveGroup` and `removeMember`
  now defer safely to an in-flight group delete, and a malformed (timestamp-less)
  delete lock clears itself instead of blocking deletion forever.
- **Exact-split currency (#674).** Editing an exact (itemized) split now requires
  an explicit currency, keeping each expense's currency consistent.
- **Activity back navigation (#666).** Cold-starting directly into the activity
  screen and pressing back now returns to home instead of dead-ending.

## [1.6.1] — 2026-06-24

Anonymous-join release. Lets anonymous users join groups (creating a group still
requires a durable account) and finishes the cross-UID swap-honesty work. Backend
(#648) deployed to the production Firebase project (`6dcf05e6`).

### Changed
- **Anonymous users can join groups (#648).** Joining by invite code and adding
  expenses no longer requires a durable (email/Google) account; creating a group
  or an invite code still does.

### Fixed
- **Honest cross-UID swap copy (#647).** Account-restore conflict messaging no
  longer implies a swap will happen when the outgoing session isn't empty
  (EN + AR), with a regression test pinning the no-swap path.

## [1.6.0] — 2026-06-22

Itemized-split and group-identity feature release, plus a broad performance and
offline-resilience pass. Backend deployed to the production Firebase project.

### Added
- **Itemized split with bill-level adjustments (#203/#605).** Split an expense by
  line items, then apply service charge, tax, tip, and discount — all reduced
  client-side to an exact, whole-subunit split.
- **Group trip stamps (#287).** Pick a glyph and ink colour to give each group a
  distinct identity at create time and from settings.
- **On-demand event recap (#202).** A per-event summary of total spent with a
  per-currency, per-person breakdown.
- **Settle on behalf of others (#595).** Any group member can record a payment
  between two other people.

### Changed
- **One balance truth on group detail (#486).** Net balance is computed once and
  shown in a single place; the people list shows others only.
- **Performance pass (#622/#623/#626/#627/#634/#640).** Cached themes, memoized
  split-preview and activity-feed work, repaint boundaries on scroll surfaces, and
  a narrowed connectivity read to cut rebuilds.

### Fixed
- **Reject ambiguous European-format amounts (#530).** A pasted `1.234,56` is now
  rejected instead of being silently truncated.
- **Honest partial-payment copy (#587).** Settle-up no longer claims to "close out
  the balance" on a partial payment; it shows what remains.
- **Whole-subunit equal splits (#596).** Equal splits that divide to a sub-subunit
  quotient quantize correctly, keeping balances whole.

## [1.5.1] — 2026-06-18

Shadow-members & claim/merge release. Adds placeholder ("shadow") members so a
group isn't a group-of-one before friends install the app, lets a joiner claim a
shadow's spot and inherit its balance (creator-approved), extends multi-currency
to mixed-currency groups, and ships settlement corrections plus a wave of
offline-staging, loading-state, and notification fixes. Backend deployed to the
production Firebase project.

### Added
- **Shadow members & claim/merge (#278).** Add members by name at create or in
  group settings — placeholders hold their share until a real person joins. A
  joiner who enters the invite code can **claim** an unclaimed shadow; the group
  creator approves, and the joiner inherits that shadow's balance instead of
  starting from zero. Includes the creator-side claim-approval card (#573) and a
  push notification to the creator when a claim request arrives (#560).
- **Settlement corrections (#283).** Fix a mistaken settlement with an offsetting
  reverse entry; corrections are labelled distinctly in payment history (#567).
- **Pre-settlement review sheet (#204).** Flags unusual expenses before you
  settle up, per-currency.
- **Notification deep-links (#179).** Expense-, event-, and settlement-created
  pushes now open the exact entry; added expense- and event-created notifiers.

### Changed
- **Mixed-currency groups (#382).** Balances bucket per currency, so a group can
  hold expenses in more than one currency without nonsensical cross-currency sums.
- **UI consolidation & loading states (#488/#490).** Shared `RAvatar` /
  `RIconButton`, skeleton loaders and real error states across activity, profile,
  events, and group screens; removed inert Defaults rows and the discarded
  payment-method picker.
- **Identity-honest delete dialog (#469).** Deleting an anonymous session no
  longer reads as deleting a durable linked account.

### Fixed
- **Offline staging.** `createGroup` (#520) and `createEvent` (#516) stage and
  race the server ack, so offline no longer shows a false error or hangs the
  spinner.
- **Home balance hero (#570).** A single unreadable group degrades to a per-group
  partial instead of blanking the whole hero.
- **Group detail (#574).** Bounded retry rides out the transient permission-denied
  on a freshly-created group's subcollection listeners.
- **Roster strip (#569).** Long multi-currency balance chips shrink instead of
  overflowing.
- **Ledger robustness.** 0-decimal currency input keeps its separator (#523);
  one bad-currency or malformed doc can't error the whole ledger/list (#537/#532).
- **Recovery & notifications.** Force-refresh the ID token after the email link
  (#522); re-register the FCM token on an in-place anon→durable link (#480);
  localize push copy (#483); the toggle no longer reads a confident ON in
  silent-failure states (#482).
- **Security & data integrity.** Member doc id bound to uid to block forged
  duplicate member docs (#548); an anon-shell delete can no longer silently spare
  a durable account (#549); `deleteGroup` lock lifecycle hardened with a
  stale-lock reaper (#519/#529).

## [1.5.0] — 2026-06-11

Account-recovery release. Replaces the cross-UID merge engine with durable
Google credentials, lays the multi-currency foundation (one currency per group),
and moves home balances onto a server-maintained aggregate. Backend deployed to
the production Firebase project. **Device QA of the durable-credential flows
(RD-10–RD-13) gates the Production promotion.**

### Added
- **Durable account recovery (#441).** Link a Google account to your anonymous
  session and restore it on a new device — same account, same UID, no merge.
  Includes a credential gate before your first create/join, a conflict-switch
  flow when an account is already in use, and recovery intent that survives the
  app restart. A slim email-link fallback remains for accounts without Google.
- **Multi-currency foundation — Model A (#261).** Each group has its own
  currency, chosen at creation and immutable thereafter; amounts display in the
  group's currency throughout. (Mixed-currency-per-group remains a post-1.0
  feature.)
- **Server-maintained balance aggregate (#366).** Home reads a per-group balance
  doc kept up to date by Cloud Functions, cutting home from O(group×event) reads
  to O(group).
- **Record a payment you received (#282).** Creditors — not just debtors — can
  log a settlement.
- **Open expense editing with an audit trail (#248).** Any event participant can
  edit or remove an expense; every change is server-audit-logged and shown as
  "added by … · edited by …".
- **Friendlier notifications and invites.** A soft in-app rationale before the OS
  push prompt (#352); a WhatsApp-direct invite CTA on the group QR sheet (#354);
  a one-time email-backup nudge for anonymous accounts (#285).

### Changed
- **Offline writes are clearer (#357, #412).** A "Saved — will sync" state and an
  offline banner on the expense editor and settle-up screens; UI no longer waits
  on a server ack that can't arrive offline.
- **Server-authoritative group membership (#290, #318).** Leaving a group and
  removing a member are gated server-side on a zero balance, closing
  offline-orphaned-debt paths.
- **Design unification.** Spacing, radius, and component styling consolidated
  onto the design-system tokens across every screen.

### Fixed
- Action snackbars no longer hang open without dismissing (#411).
- iOS share sheet and inbound deep links fixed (#308, #369).
- Numerous balance-conservation and allocator-parity fixes keeping the client and
  server money math byte-for-byte aligned (#270 and others).
- Security: patched a high-severity `@grpc/grpc-js` advisory in the Cloud
  Functions runtime (#461).

## [1.4.0] — 2026-06-05

Feature + hardening release. Adds push notifications and ships a cluster of
money-correctness and balance-conservation fixes ahead of the public launch.
Locks 1.0 to OMR-only. Verified against the production Firebase backend with a
full physical-device QA pass (RD-01–RD-09).

### Added
- **Push notifications (#53).** You're now notified when someone joins your
  group or records a settlement. Includes the FCM consumer (foreground display,
  background handler, deep-link routing into the relevant group/event) and
  locale-aware notification copy persisted per recipient.
- **Server-side write-rate monitoring (#198).** Per-actor write-rate detection
  triggers flag abnormal bursts across events, group settlements, and activity.

### Changed
- **1.0 is OMR-only (#61).** The orphaned currency picker is removed; every
  money write path is OMR for this release. Multi-currency aggregation is a
  post-1.0 feature.
- **Home balances are computed one-shot (#104).** Eliminates an O(G×E) Firestore
  listener leak from the always-mounted home dashboard.
- **Faster cold start (#105).** The first frame no longer waits on the
  restored-session token refresh.
- Dropped the `shimmer` dependency; skeleton loaders now run on `skeletonizer`
  (#111). Removed the dead onboarding screen (#56).

### Fixed
- **Expense attribution and split previews (#247).** Removed an incorrect
  restriction on who an expense could be attributed to; the split preview now
  reflects what will actually be saved.
- **Departed members stay in the balance books (#249).** A member removed from a
  group no longer drops their owed share, so balances conserve on both client
  and the server `deleteGroup` recompute.
- **Exact splits are validated before save (#250).** Saving is blocked when an
  exact split no longer sums to the expense amount; every split-allocation
  fallback now emits telemetry.
- **Incomplete settle-up is surfaced (#244).** Group settle-up warns when its
  balance set is incomplete instead of silently optimising a partial picture.
- **Allocator and currency safety (#220).** The share/percent allocator is
  guarded against negative entries, and settlement reads are fenced against an
  unsupported currency.
- **Same-named members are disambiguated in settle-up (#196, #263).** Members
  who share a display name are distinguished in the settle-up list and on the
  transfer tiles.
- **Group activity pagination (#183).** Activity now pages correctly past the
  first page (cursor applied before the limit).

## [1.3.2] — 2026-06-02

Hotfix release. Fixes a critical data-loss bug affecting anonymous accounts,
shipped alongside a server-side account-recovery fix deployed the same day.

### Fixed
- **Anonymous sessions are no longer wiped on a transient auth error.** A
  restored anonymous session whose ID token failed to verify (e.g. a transient
  Firebase `internal-error`) was treated as corruption and replaced with a fresh
  anonymous UID, orphaning all of the user's groups, events, and expenses under
  the old UID. The restored session is now always kept; a token-check failure
  never signs out or mints a new UID. (#213)
- **Account recovery no longer splits balances across a dead UID** (server-side,
  deployed 2026-06-02 — applies to all clients). The email-link recovery cascade
  now migrates the full expense/settlement ledger from the retiring anonymous
  UID to the recovered account, so a recovered user no longer appears as two
  people. (#216)

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

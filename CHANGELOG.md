# Changelog

All notable changes to Rihla are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.9.3] — 2026-07-17

Rihla 1.9.3 ships the post-audit hardening sweep: crash fixes around
navigation, safer account restore, clearer offline signals in settle-up,
and the new store-review ask.

### Added

- Rihla now asks for a store review right after a settle-up completes — at
  most once every two weeks, only when the platform review flow is available,
  and never on QA builds (#1263).
- Groups now cap at 50 members on invite-code joins — matching the existing
  add-by-name bound — with a clear “group is full” message in English and
  Arabic, and without counting a full group against the join rate limit
  (#1282).

### Fixed

- Completing a join no longer crashes if you navigate away mid-join, and
  approving or declining a claim no longer crashes after navigation
  (#1275, #1276).
- Sharing a settle-up to WhatsApp no longer silently consumes the
  store-review prompt’s two-week cooldown (#1277).
- The group settle-up screen now shows the offline banner immediately on
  entry — before the payment form — since recording a settlement needs a
  connection (#1255).
- Restoring an account while recent changes are still syncing now aborts
  safely with a “still syncing — try again” message instead of risking those
  queued changes in the account swap (#1281).

### Internal

- Mac-independent iOS release path: match-based CI signing and a
  release_ios.yml workflow that builds and uploads to TestFlight on version
  tags (#1268, #1269).
- Accessibility guideline assertions (tap targets, labels, text contrast)
  now cover the five core screens in English and Arabic (#1283); two real
  violations found were filed as #1287/#1288.

## [1.9.2] — 2026-07-16

Rihla 1.9.2 brings Android to parity with the iOS 1.9.1 (37) build and ships
the accumulated navigation, Arabic-text, and settle-up fixes to both stores.

### Added

- The group activity feed now discloses when a roster change re-splits
  expenses, as a server-authored entry showing who was added or removed and
  which expenses were affected (#1059, #1245).

### Changed

- The public website now offers both stores — App Store buttons and smart
  banners across the landing, SEO, and invite pages — alongside the Falaj
  bilingual feature graphic, social preview cards on invite links, and
  on-page SEO fixes (#1260, #1261, #1262, #1264).

### Fixed

- Opening an event you no longer have access to — from a deep link, a stale
  notification, or a sibling surface — now shows a proper no-access state
  instead of a broken screen (#1237, #1239, #1244).
- A deep link or notification tap no longer silently discards an in-progress
  expense draft (#1240).
- User names render correctly inside Arabic and mixed-direction money
  sentences, and display names reject invisible directional characters that
  could be used to spoof names or amounts (#1216, #1242, #1243).
- The date picker keeps Western digits under the Arabic locale (#1241).
- Settle-up breakdown labels no longer collide, and emoji names no longer
  split mid-character (#1204, #1217, #1238).
- Saving an expense edit with no actual changes no longer touches
  connectivity state (#1236).

### Internal

- Eight oversized screen files split into sibling widget files, bringing
  every source file back under the 800-line cap (#965).
- Bumped `websocket-driver` to 0.7.5, clearing a critical npm audit finding
  that blocked CI (#1265).

## [1.9.1] — 2026-07-13

Rihla 1.9.1 adds clearer settle-up choices and more flexible itemized
discounts, while tightening navigation, money calculations, Arabic dates, and
membership integrity.

> **iOS build 1.9.1 (37)** — rebuilt 2026-07-15 for App Review with Sign in
> with Apple as a parallel link/restore provider (Hide My Email supported) and
> delete-time Apple token revocation per guideline 5.1.1(v) (#1256, #1258).
> This build also carries the fixes listed under 1.9.2; Android reaches parity
> in 1.9.2.

### Added

- Group creators can choose whether to simplify debts for each group. Keep it
  on for the fewest suggested transfers, or turn it off to show direct
  debtor-to-creditor payments (#363).
- Itemized discounts can now be assigned to selected people instead of always
  being shared proportionally across the full group (#605).

### Changed

- Android now asks for a second Back press before exiting from Home, while
  direct links and deeper routes return through the app correctly after the
  navigation upgrade (#1188, #1192).
- Settle-up amounts use the shared money typography, and trailing controls in
  group creation, Preferences, Theme, and expense details align consistently
  in both English and Arabic (#1182, #1184, #1193, #1194, #1201).
- The public website received a mobile, RTL, accessibility, and motion polish
  pass.

### Fixed

- Arabic dates keep localized month names while displaying Western digits
  consistently throughout the app (#1215).
- Correcting a settlement now refreshes cached group balances immediately,
  and proportional itemized adjustments no longer risk integer overflow on
  large values (#1213, #1206).
- Rejoining, leaving, deleting, and removing members now handle legacy member
  records, temporary membership locks, and pending name claims consistently;
  unexpected removal failures also show translated copy and reach Sentry
  (#1160, #1209, #1210, #1211, #1212).
- Group activity writes now reject malformed or unbounded timestamps and
  descriptions, and the server balance calculation ignores an empty payer ID
  instead of creating a phantom participant (#1218, #1205).

### Internal

- Cloud Functions CI now enforces coverage thresholds and 90% diff coverage
  for changed backend lines (#1189).
- The iOS TestFlight lane uploads Dart symbols and dSYMs to Sentry after a
  successful upload, improving production crash symbolication (#950).

## [1.9.0] — 2026-07-12

Rihla 1.9.0 is a correctness-and-integrity release. It hardens what happens when people leave a group — balances, permissions, notifications, and history all stay consistent — makes recording settlements safer with a single transactional, deduplicated server path, and scrubs every trace of a deleted account from a group's history. It also lands a broad accessibility pass and RTL/visual polish.

### Added

- Group creation now appears as the first entry in every group's activity/history feed; for groups created offline the entry is added on reconnect, correctly stamped with the original creation time (#1018).
- The add-expense screen shows a one-line "Adding to {event} · change" banner under the top bar, so it's always clear which event a new expense will land in (#1088).

### Changed

- Rewrote 20 English UI labels from Title Case to sentence case across home, events, groups, and expenses for a more natural, consistent look (#1046).
- Before adding a shadow (name-only) member, the add-person sheet now warns that this will re-split existing events' costs — including already-closed events — so you know what changes before confirming (#1059).
- Simplified the event-screen header into a cleaner single column, dropping redundant labels and making the balance amount the focal point (#1057).
- Money amounts now render consistently across the expense success screen, pre-settlement review, and ledger balance chips (#1041).
- Recap and picker-sheet loading states now show a layout-matched skeleton instead of a bare spinner (#1041).
- Unified section headers and adopted the shared header-fade motion token across group settings, and added the offline banner to the activity screen (#1047).
- Removed a redundant repeated "settled" message and made relative timestamps (e.g. "2 hours ago") lowercase for cleaner activity copy (#1068, #1069).

### Fixed

Departure & membership integrity

- Leaving or removing a member now locks the group during the departure check, so a race between two simultaneous departures can no longer both pass a stale zero-balance check (#1144).
- Leaving a group is now refused if it would strand shared history that only that person's balance ties together, preventing a departure from silently corrupting group balances (#1144).
- Expenses and settlements can no longer be created against someone who has already left the group (#1144).
- Removed or departed "ghost" members can no longer be newly added to expenses, events, or the group roster (#1144).
- Only current group members can add or edit expenses in that group's ledgers — someone who has left or been removed can no longer write to a ledger they no longer belong to (#1131).
- A group creator who has since left can no longer rename the group, change its stamp, delete it, remove members, or approve name-claim requests — creator powers now require current membership (#1132).
- If the person who created a group leaves, another current member automatically becomes the admin (#1138).
- People who leave a group (or are removed) stop receiving that group's push notifications (#1141).
- Activity-history entries are now written together with the underlying change, so a blocked or denied edit no longer leaves a phantom history entry (#1140).
- Member pickers, settle-up pairing, and history views now consistently exclude departed/ghost members, matching the new server-side rules (#1149).
- Creating a new event no longer auto-selects deleted-account placeholder members as participants, avoiding a submit error (#1159).

Settlement correctness

- Recording a settlement now goes through a single server-side transactional callable that caps the amount at what's actually still outstanding between the two people, closing a window where a client-side race could over-record or double-record (#1129).
- Settlement records now get deterministic, content-derived IDs (scope, parties, currency, amount, time-window) instead of random ones, so the same settlement can't accidentally be written twice (#1130, #1093).
- The Settle Up screen now blocks recording a payment while your balances are still loading or converging, preventing you from settling against a stale number (#1106).
- Pre-settle-up warnings no longer reappear for amounts you've already settled past — the review screen remembers what you've seen and only flags genuinely new changes (#1058).

Privacy & account deletion

- Deleting your account now scrubs your user ID from every event's "closed by" record and from frozen spending-summary data, so no personally identifying trace of you lingers in a group's history (#1133).
- Account deletion now re-checks group memberships right before finishing, catching a group you joined or were added to mid-deletion so it gets scrubbed too (#1099).
- If you rejoin a group after deleting your account (or a claim is approved during deletion), your prior and new balances are now correctly combined instead of one silently overwriting the other (#1099).

Ledger & expenses

- Entering a zero or invalid amount when adding an expense or recording a payment now shows a clear error on the amount field, moves focus there, and announces it for screen readers (#1080).
- Editing one field of an expense (like category or description) no longer silently reverts other fields you'd already changed and saved (#1092).
- Group balance labels now clearly state who owes whom for each event instead of an ambiguous number (#1107).
- The event-deletion warning now shows your group's real current balances instead of stale or incorrect figures (#1101).
- You can now clear an event's description after it's been set (#1103).
- Fixed timeline dates that could be mislabeled "Yesterday" for something added earlier today, depending on your timezone (#1097).
- Event start/end dates no longer shift by a day depending on your device's timezone (#1098).
- Fixed a crash that could occur when closing the "add adjustment" sheet in the itemized split editor with a blank amount (#1053).
- Fixed a mis-tap hazard where the add-expense button could overlap the settle-up controls, and a home-screen balance row that was partly hidden behind the floating action button (#1086).

Auth & session

- If your account is deleted mid-session (e.g. from another device), the app now recognizes the deletion after restart and cleanly resets you to a fresh anonymous session instead of getting stuck (#1100).
- Restoring or switching accounts on a reinstalled or empty-cache device no longer risks silently deleting the account you're switching away from — the app double-checks with the server that it's truly empty first (#1091).
- Signing out now waits for and confirms any unsaved changes have synced (letting you discard them if they can't), and deregisters that device's push notifications before switching accounts (#1094, #1095).
- A display name changed while offline now reliably syncs to your groups once you're back online (#1102).
- Fixed a race where rapidly toggling push notifications off could leave a stale token registered; opting out now also clears notifications already delivered to the device (#1096, #1104).

Accessibility

- Tap targets across the app (category and split-mode chips, group settlement rows, custom split editors, group detail actions, Create Group's top-bar button, and more) are now at least 44dp (#1120, #1114, #1085, #1048).
- Screen-reader users get correct semantics and labels on chip/tab selections and navigation back buttons, and navigation elements now meet color-contrast requirements (#1067, #1075).
- Text no longer overlaps, wraps oddly, or gets cut off at larger text sizes — app text scaling is capped at 1.5x, and Home/Profile screens were hardened to stay readable (#1064, #1074, #1083).
- Error and destructive buttons (like deleting a group or expense) now use a dedicated high-contrast text color in dark mode (#1042).

RTL & visual polish

- Fixed the back button on eight screens showing a mismatched glyph for Arabic users — it now mirrors as a single consistent icon in both languages (#1167, #1171).
- Fixed Arabic payer/payee names in settlement captions merging together and reversing order, in both RTL and LTR locales (#1073, #1066, #1113).
- Fixed padding around two expense-editor elements that stayed physically left/right instead of mirroring in Arabic (#1041).
- Restored consistent typography on the event settings title and a ledger empty-state caption (#1050, #1041).
- Fixed iOS status-bar icons staying the wrong color when the system switches between light and dark mode live (#1052, #1051).
- Fixed the payer→payee flow arrow in the expense audit detail so it also mirrors for Arabic, matching the back-button fix (#1173).
- Removed a decorative em-dash on the ledger's "You" roster anchor that could be mistaken for an empty-state placeholder (#1169).

Avatars, activity, search & home

- A person's avatar color is now stable and no longer changes when their display name is edited or the app switches between English and Arabic (#1168).
- Search no longer flashes a false "No matches" message while results are still loading (#1108).
- Pull-to-refresh works again on the History screen when it's showing an empty state (#1063).
- On the home screen, the bottom of your list no longer gets clipped while scrolling, and the floating add button now reads as lighter and more "floating" (#1166).
- Dismissing the invite share-sheet after creating a group now takes you straight into the new group instead of stranding you on the creation form, where tapping Create again could make a duplicate group (#1087).
- The "add person by name" sheet now shows an inline error instead of silently doing nothing when the entered name is invalid (#1065).

### Internal

- iOS platform bring-up: expense and settlement push notifications can now wake the app in the background and show a proper banner and sound when they arrive while the app is open (#1055, #941). Hardened the account-deletion cascade against a maliciously malformed group snapshot that could otherwise have permanently blocked a deletion request (#1133).
- Retired the legacy `eventId==groupId` sentinel on group-settlement documents (server-side only; documents are now identified by collection path + groupId/scope, old docs still decode via the retained fallback — no behavior change) (#71).

## [1.8.2] — 2026-07-07

Patch release for the 1.8 line. It collects the post-1.8.1 home, History,
search, and group-balance honesty fixes that landed on `main`; production
backend state is already aligned, so no backend deploy is bundled with this
client release.

### Added
- **Scroll-under header treatment reaches Profile, Home, and History
  (#1011/#1020/#1039).** Fixed headers now gain the shared scroll-edge hairline
  instead of letting list rows visually bleed underneath.

### Changed
- **Search starts with useful scope guidance (#1023)** and updates the mounted
  field when a new `q` deep link arrives (#1027/#1033).
- **Release tooling now follows the protected-branch path (#985/#1002).** The
  helper opens a release PR, waits for the squash merge, and tags the landed
  `main` commit so Play upload validation sees the release on `origin/main`.

### Fixed
- **Home and group balance surfaces stay honest during partial/error states
  (#997/#1005/#1017/#1028/#1031/#1034/#1037).** Loading placeholders no longer
  show false settled text, stale group listeners are fenced, and spending/balance
  summaries surface hard failures instead of quietly flattening them.
- **Activity day buckets use the viewer's local calendar date (#1007/#1036).**
  UTC Firestore timestamps created after local midnight now remain under
  `TODAY` instead of slipping into `YESTERDAY`.
- **Home polish fixes (#1014/#1019).** The unread-dot top-bar glyphs stay
  centered, and the set-name chip copy fits the compact header.
- **Join-group CTA stays above the keyboard (#1015).**
- **Semantics and inactive controls read correctly (#1004/#1026/#1032).**

## [1.8.1] — 2026-07-07

Hotfix release for the 1.8.0 line. It contains everything merged after
`v1.8.0` through PR #999; later work belongs to the next release.

### Added
- **iOS release plumbing (#986/#987/#988/#989).** The app now carries the Rihla
  display name, an app-level privacy manifest, refreshed CocoaPods lockfile,
  native Google Sign-In URL scheme configuration, and a manual-restart fallback
  for the iOS cache-isolation overlay.

### Changed
- **Restore identity self-heals the local profile name (#990/#995).** After a
  verified restore, the device name is seeded from the signed-in member's own
  group member document when needed.
- **Home top bar keeps the wordmark visually centered (#994).** The title uses a
  Stack overlay instead of inheriting leftover row spacing from the actions.

### Fixed
- **Ledger roster chips show each member's own standing (#998/#1000).** The
  strip no longer negates a member's net and mislabels multi-person balances.
- **Smart-forward navigation preserves the group Back path (#996/#999).** Event
  and search jumps now push the `/group/:gid` ancestor before the destination so
  Back returns to the group overview.

## [1.8.0] — 2026-07-06

The Falaj release: the rebrand completed in-app last cycle now reaches the
launcher icon, Play listing, and marketing site, joined by global search, a
hardened claim flow for placeholder members, and a money-correctness pass on
group settle-up. All backend changes in this range are deployed
(`backend-deployed` → `1fa502b9`).

### Added
- **Global search (#900/#924).** `/search` spans groups and events from home.
- **One-tap expense entry + IA pass (#917).** Persistent FAB fast path,
  smart-forward rows, balance-hero breakdown sheet, and event-module route
  consolidation.
- **Readable crash reports (#933/#979).** Release builds upload Dart debug
  symbols to Sentry (with a retained CI artifact), and a central scrubber
  strips PII from every event before it leaves the device (#974).

### Changed
- **Falaj rebrand, outward-facing:** launcher + Play icons (#961), store
  listing captions/frames/feature graphic with AR-native screenshots (#970),
  marketing-site re-skin (#962), and an Android cold-launch splash that
  follows the scaffold ground (#957).
- **Claim decisions are the durable identity boundary (#963).** Adding people
  by name stays lightweight; identity hardens at creator-approved claim time
  (anonymous shadow sandbox, D6-R).
- **Settlement corrections are recorder-or-party only (#972),** and the
  Correct affordance is hidden for everyone else.
- "View activity" is now "View history" everywhere (#966/#971); interactive
  list rows gained merged semantics and button roles and the avatar stack is
  RTL-safe (#967/#975); 115 dead translation keys pruned (#969/#976); the
  expense editor split into focused leaf widgets (#965/#978).

### Fixed
- **Group settle-up writes all decomposed legs atomically (#929/#939)** — one
  WriteBatch capped at 9 legs, so a rules rejection persists nothing.
- **One malformed money doc can no longer blank the ledger, home, or feeds
  (#928/#943)** — total-parse money factories fence bad docs while mirroring
  the balance oracle.
- Pre-settlement review skips already-settled currency buckets (#922);
  mixed-currency explainer copy is currency-agnostic (#919); the delete-group
  sheet drops the false 30-day retention promise (#927); settle-up headline
  styling no longer synthesizes italics (#958); QR invite modules stay
  scan-dark in both themes (#954); the EditName sheet clears the system nav
  bar (#959).

## [1.7.4] — 2026-07-05

Production promotion of the 1.7.x line. Production users are on 1.7.0, so this
build gathers **everything shipped to the closed "first" track since 1.7.0** into
one release: the History/activity unification across every feed, the tabbed event
command screen, group spending insights, the pre-settlement review safety net,
trip-receipt exports, the first-run/account honesty pass, and a batch of money-,
offline-, and accessibility-correctness fixes. All backend changes are already
live in production (`backend-deployed` → `474da89b`) — no further backend deploy
is required for this client.

### Added
- **History as a first-class surface across every feed
  (#808/#810/#815/#816/#849/#852/#865/#881/#883/#886/#887/#891).** Expenses and
  settlements fan into the group activity feed, the History tab paginates and
  searches, a shared row vocabulary drives all four feeds (home RECENTLY,
  cross-group, group timeline, per-event), and every row deep-links to the group,
  event, expense, or settlement it describes.
- **Default ledger event for new groups (#245/#793/#794).** Creating a group
  seeds one ledger event named after the group, and server-side shadow-member
  fan-in keeps added-by-name members in existing event split rosters.
- **Persistent Add Expense FAB (#364/#796).** A fast add-expense action with a
  flattened open-event picker and a one-event direct path.
- **Tabbed event command screen (#758/#788).** Event detail hosts Expenses,
  Settle up, Activity, and closed-event Recap in one surface with a pinned
  balance header.
- **Group spending summary (#180/#797).** Per-currency spend insights across top
  events, categories, payers, and consumers.
- **Trip receipt proof packs (#704/#776/#778) and a shareable recap card (#722).**
  Event recaps export CSV and PDF proof packs and a shareable PNG summary, and
  settle-up can open the receipt/export path directly (#836).
- **Labelled open-event recap entry (#811/#880).** The recap entry is a clear
  labelled action instead of a tooltip-only glyph.
- **Add-people account nudge (#847).** The disabled add-people field points toward
  account linking instead of looking inert.
- **Numberless WhatsApp settle-up notify (#367/#762)** and clearer event-vs-group
  settle CTAs and scope notes (#717/#721).

### Changed
- **Pre-settlement review safety net (#204/#786/#798).** Event and group settle-up
  flag departed-payer expenses and show the same review sheet across every
  affected event before payment is recorded.
- **Settle-up stale-amount revalidation (#719/#773).** Settle-up writes
  revalidate the amount immediately before commit so a stale screen cannot submit
  an outdated balance.
- **Itemized is a first-class split option (#790/#791)** and **a category is
  required at expense creation (#204/#787)**; legacy edits stay editable without
  forced backfill.
- **Split editor honesty (#853/#856/#869).** Exact and Percent editors seed from
  the equal baseline, and the equal-split preview shows the same allocator shares
  that get saved.
- **First-run and account honesty pass (#834/#839/#842/#843/#851).** Guest,
  set-name, restore, offline-bootstrap, and email-bootstrap states use copy that
  matches what the app can actually prove.
- **Theme and localization polish (#821/#835/#845/#857/#858/#890).** Light theme
  is the default until the dark pass ships, the bottom tab reads History, Arabic
  activity text drops gendered-verb leaks and gains script-specific
  caption/display tokens, and the backup card promises Google-only recovery to
  match the sheet.
- **Refreshed activity presentation (#490/#867/#888).** The four feeds share a V2
  grain-and-wash backdrop, and event-feed day cards are flat with a hairline
  instead of a misleading raised affordance.

### Fixed
- **Offline group creation is atomic (#874/#876).** A group and its seeded event
  are founded in one WriteBatch, so an offline create can no longer leave an
  empty-shell group.
- **Offline replay balance freshness (#633/#777).** Pending-write replay and
  balance-aggregate freshness are separate barriers, keeping home balance reads
  correct after offline replay or join fan-out.
- **Weighted-split rounding never lands on a zero-share participant (#872/#882),**
  on both the client allocator and the server oracle.
- **Notification correctness (#179/#780/#783/#892).** Retry deliveries no longer
  double-send, claim taps route safely, and idempotency markers now expire on a
  90-day TTL.
- **Expense-editor trust (#829/#859/#863).** The editor guards discarded edits,
  shows human-readable save errors, and surfaces queued-write replay rejections.
- **False-affordance and accessibility cleanup
  (#802/#804/#846/#848/#850/#862/#871/#884).** Dead or misleading controls were
  removed or relabelled, the History bell carries its unread state, settlement
  transfer arrows are RTL-safe, the profile QR sheet is gone, and the amount
  input and command-center nav buttons are screen-reader named with unfragmented
  amount output.
- **Router and backend restore hardening (#813/#823/#826).** The reverted History
  fan-in function was restored, unknown routes land on a friendly 404, and
  anonymous users can create groups after the removed durable-create gate.
- **Closed-event receipt access (#708/#782)** and **event polish follow-ups
  (#789/#792).**

### Backend
- **Settlement-correction foundation (#889/#893).** A machine-readable
  `correctionOfSettlementId` marker plus Admin-only `correctSettlement` /
  `correctLogicalSettleUp` callables landed server-side to support future in-app
  settlement corrections. The balance oracle is unchanged — the marker is
  oracle-invisible — and the change is already live in production.

## [1.7.3] — 2026-07-04

Closed-track first-impressions and History hardening release. Activity now works
as a real History surface, first-run/account copy is more honest, and the split
editor's visible math matches the saved allocator. Backend changes through
`abee70e8` are already live in production.

### Added
- **History feed expansion (#808/#810/#815/#816/#849/#865).** Expenses now fan
  into the group Activity feed, the History tab paginates and searches rows, and
  History entries deep-link to the group, event, expense, or settlement they
  describe.
- **Standalone settle-up receipt entry (#836).** Settle-up can now expose the
  recap/export path directly when a receipt is available.
- **Add-people account nudge (#847).** The disabled add-people field now points
  users toward account linking instead of looking inert.

### Changed
- **First-run and account honesty pass (#834/#839/#842/#843/#851).** Guest,
  set-name, restore, offline bootstrap, and email-bootstrap states now use copy
  that matches what the app can actually prove.
- **Theme and localization polish (#835/#845/#857/#858).** Activity is renamed
  to History in the bottom tab, Arabic activity text avoids gendered verb leaks,
  Arabic typography gets script-specific caption/display tokens, and settle-copy
  wording is more precise.
- **Light-theme default until dark mode is complete (#821).** The app now stays
  on the supported light presentation instead of exposing unfinished dark-mode
  surfaces.

### Fixed
- **Activity and settlement correctness (#820/#830/#867).** Client-writable
  group-activity metadata has a server-side value-domain floor, settlement
  direction is visible in activity rows, and event-feed day cards no longer show
  a misleading raised-but-inert affordance.
- **Expense-editor trust fixes (#829/#853/#856/#859/#863/#869).** The editor now
  guards against discarded edits, shows human-readable save errors, surfaces
  queued-write replay rejections, seeds Exact/Percent editors from the equal
  baseline, and shows the same allocator shares used for saved equal splits.
- **False-affordance and accessibility cleanup (#802/#804/#846/#848/#850/#862).**
  Dead controls and misleading affordances were removed or relabelled, the
  History bell carries its unread state, settlement transfer arrows are RTL-safe,
  the profile QR sheet was removed, and amount screen-reader output is
  unfragmented.
- **Router and backend restore hardening (#813/#823/#826).** The reverted History
  fan-in function was restored, unknown routes now land on a friendly 404, and
  anonymous users can create groups after the removed durable-create gate.

## [1.7.2] — 2026-07-02

Closed-track activation and trip-command release. New groups now start with a
ledger event, expenses can be added from the home shell, event work happens in a
single tabbed screen, and the settlement review safety net now covers both event
and group settle-up. Backend changes through `bcb27382` are already live in
production.

### Added
- **Default ledger event for new groups (#245/#793/#794).** Creating a group now
  seeds one ledger event named after the group, and server-side shadow-member
  fan-in keeps added-by-name members available in existing event split rosters.
- **Persistent Add Expense FAB (#364/#796).** Groups and Activity tabs now show a
  fast add-expense action with a flattened open-event picker and a one-event
  direct path.
- **Tabbed event command screen (#758/#788).** Event detail now hosts Expenses,
  Settle up, Activity, and closed-event Recap in one tabbed surface with a pinned
  balance header.
- **Group spending summary (#180/#797).** Group detail now shows per-currency
  spend insights across top events, categories, payers, and consumers.

### Changed
- **Pre-settlement review expansion (#204/#786/#798).** Event settle-up now flags
  departed-payer expenses, and group settle-up shows the same review sheet across
  all affected events before payment is recorded.
- **Itemized split discoverability (#790/#791).** Itemized is now a first-class
  split option on the Split card instead of being buried inside the custom split
  sheet.
- **Expense category required at creation (#204/#787).** New expenses must pick a
  category before saving; legacy edits remain editable without forced backfill.

### Fixed
- **Notification retry idempotency and claim routing (#179/#780).** Eventarc
  retry deliveries no longer double-send supported notifications, and claim
  decision taps route safely for member and pre-join cases.
- **Closed-event receipt access (#708/#782).** The closed-event banner now links
  directly to the Trip Receipt export surface when there is something to export.
- **Event polish follow-ups (#789/#792).** Embedded event panels reserve FAB
  clearance, no-description ledger rows fall back to category names, and live
  multi-day trips show a localized day badge.

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

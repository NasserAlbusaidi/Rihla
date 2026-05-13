# "Coming Soon" Implementations — Plan

**Status:** All Sprints shipped — every "Coming soon" snack burned down (T3.J, T3.K, T3.L, T4.N)
**Branch:** `worktree-plan-coming-soon` (based on `feat/settings-pickers-sprint-2` @ e0942d9)
**Last updated:** 2026-05-13

## Goal

Burn down the "Coming soon" SnackBar surfaces shipped across the app. Each surface is a visible-but-non-functional affordance — together they undermine perceived polish and Play Store readiness. We resolve them tier by tier, starting with the ones that reuse libraries already in `pubspec.yaml`.

## Inventory

14 surfaces across 4 files.

| # | Surface | Location | Snack copy |
|---|---|---|---|
| 1 | Group invite Share icon | `lib/features/groups/widgets/group_info_section.dart:289` | "Invite sharing coming soon" |
| 2 | Profile header Share icon | `lib/features/settings/screens/profile_screen.dart:155` | "Share coming soon" |
| 3 | Ledger cover Search icon | `lib/features/ledger/screens/ledger_screen.dart:214` | "Search coming soon" |
| 4 | Settings → Help center | `profile_screen.dart:583` | "Help center soon" |
| 5 | Settings → Terms & privacy | `profile_screen.dart:603` | "Terms & privacy soon" |
| 6 | Settings → Send feedback | `profile_screen.dart:593` | "Feedback flow soon" |
| 7 | Settings → Currency | `profile_screen.dart:540` | "Currency picker soon" |
| 8 | Settings → Language | `profile_screen.dart:546` | "Language picker soon" |
| 9 | Settings → Default split | `profile_screen.dart:555` | "Split preferences soon" |
| 10 | Profile gear icon (no-canPop branch) | `profile_screen.dart:136` | "Settings coming soon" |
| 11 | Group invite QR icon | `group_info_section.dart:278` | "QR invite coming soon" |
| 12 | Profile QR chip | `profile_screen.dart:280` | "QR sharing coming soon" |
| 13 | Profile → Buy me a coffee | `profile_support_section.dart:62` | "Coming soon" |
| 14 | CustomSplitSheet → Shares/Exact/Percent | `custom_split_sheet.dart:165` | "{mode} splits are coming soon." |

## Existing infrastructure (reuse)

- `share_plus: ^10.1.4` — already in pubspec; used in `create_group_screen.dart:527`.
- `url_launcher: ^6.3.2` — already in pubspec.
- `package_info_plus: ^8.2.1` — already in pubspec; useful for feedback subject prefill.
- `AppSettings` (`lib/core/models/app_settings_model.dart`) — already has `languageCode`, `currencyCode`; missing `defaultSplitMode`.
- `SettingsNotifier` + `SettingsService` — pattern proven for `pushNotificationsEnabled`, `weeklyDigestEnabled`, `onboardingComplete`.

## Missing infrastructure

- QR code generation (`qr_flutter` ~16KB) — needed for #11, #12.
- Deep-link / universal-link handling for `rihla://join?code=…` (or `https://rihla.app/join/<code>`) — needed for QR scans to land on `/join-group`.
- Hosted Terms / Privacy / Help URLs — content blocker for #4, #5 (Play Store gate per memory `project_v2_ui_overhaul`).
- Per-participant split distribution model — needed for #14 (see memory `12815`).

---

## Tier 1 — quick wins (½ day total)

All reuse libs already in pubspec. Zero new dependencies.

### T1.A — Group invite Share button (#1)
**File:** `lib/features/groups/widgets/group_info_section.dart:283-292`
**Change:** Replace snack with `Share.share()` using the exact pattern at `create_group_screen.dart:527-532`. Body: `"Join my group on Rihla! Use code ${group.inviteCode} to join."`. Subject: `"Join ${group.name}"`.
**Tests:** none — pure delegation to system share sheet.

### T1.B — Profile header Share (#2)
**File:** `lib/features/settings/screens/profile_screen.dart:153-157`
**Change:** `Share.share("I'm splitting trip expenses with Rihla.")`. Add a Play Store URL once published — for now plain text. Optional subject `"Rihla"`.
**Tests:** none.

### T1.C — Help center (#4)
**File:** `profile_screen.dart:583`
**Change:** New constants file `lib/core/config/app_links.dart` holding `helpUrl`, `termsUrl`, `privacyUrl`, `feedbackEmail`. Open via `url_launcher.launchUrl(Uri.parse(AppLinks.help), mode: LaunchMode.externalApplication)`.
**Open question:** real URL or `https://rihla.app/help` placeholder? Decide before code.

### T1.D — Terms & privacy (#5)
**File:** `profile_screen.dart:603`
**Change:** Bottom sheet listing "Terms of service" + "Privacy policy" — each opens its URL via `url_launcher`. New widget `lib/features/settings/widgets/legal_links_sheet.dart`.
**Blocker:** real hosted policies (Play Store gate). Stub URLs OK for codepath; real URLs required before alpha.

### T1.E — Send feedback (#6)
**File:** `profile_screen.dart:593`
**Change:** `mailto:` via `url_launcher`. Pull `PackageInfo.fromPlatform()` once, prefill subject `Rihla feedback · v${version}+${build}`. Address pulled from `AppLinks.feedbackEmail`.
**Test:** mock `url_launcher` platform interface to assert mailto URI shape.

### T1.F — Profile gear icon dead branch (#10)
**File:** `profile_screen.dart:127-140`
**Decision:** Profile is always reached via push (`/settings` is its only entry per `app_router.dart`). The `!canPop` branch is dead. Cleanest fix: drop the leading icon entirely when `!canPop`, or replace with a hairline spacer to keep the title visually centered.

**Sprint 1 deliverable:** 6 snacks removed, 1 helper file (`app_links.dart`), 1 small sheet widget, 0 new dependencies.

---

## Tier 2 — small features (1 day)

### T2.G — Currency picker (#7)
**Files:** new `lib/features/settings/widgets/currency_picker_sheet.dart`; mutator on `SettingsNotifier.setCurrencyCode(String)`.
**Behaviour:** Sheet lists supported codes (OMR, AED, SAR, USD, EUR, GBP — confirm). Setting affects new-trip default currency. Existing trips keep their stored `currency`. Sheet copy must say "Default for new trips." to avoid implying retroactive conversion.

### T2.H — Default split (#9)
**Model change:** Add `enum DefaultSplitMode { equal, shares, exact, percent }` + field on `AppSettings`. Update `copyWith`, `SettingsService` (SharedPreferences key `default_split_mode`), `SettingsNotifier.setDefaultSplitMode`.
**UI:** sheet picker. Non-equal modes show "Locked — available in v1.2" badge until T4.N lands. Selecting them is disabled.
**Integration:** `AddExpenseScreen` reads `defaultSplitMode` to choose the initial selection in the split sheet.

### T2.I — Language picker shell (#8)
**Behaviour:** Sheet shows "English" selected, "Arabic — coming soon" disabled. Picker exists so the snack is gone; full i18n is its own multi-week effort (Tier 5).
**Risk:** could be misleading. Mitigate by labelling Arabic clearly disabled.

---

## Tier 3 — meaningful builds (1–2 days each)

### T3.J — QR invite (group) (#11)
**Add:** `qr_flutter` to pubspec.
**New sheet:** `lib/features/groups/widgets/qr_invite_sheet.dart` rendering a QR for `https://rihla.app/join/${group.inviteCode}` (universal link) — falls back to `rihla://join?code=${code}` (custom scheme).
**Router:** `app_router.dart` must accept `/join/:code` → preload `/join-group` with code prefilled.
**Native:**
- Android: `AndroidManifest.xml` intent filter for `rihla.app` + `rihla://` scheme.
- iOS: `Info.plist` URL types + Associated Domains entitlement for universal links.
**Apple/Android verification:** universal-link verification needs `apple-app-site-association` + `assetlinks.json` hosted on `rihla.app`. If hosting isn't ready, ship with `rihla://` scheme only and add HTTPS later.

### T3.K — Profile QR chip (#12)
Same QR plumbing as T3.J but encoding `https://rihla.app/u/${handle}` (or omit deep-link target and just show the handle as a QR for in-person trade). Bundle with T3.J to amortise the `qr_flutter` integration.

### T3.L — Ledger search (#3)
**New widget:** `lib/features/ledger/widgets/ledger_search_sheet.dart` — full-height sheet over the ledger timeline. Client-side filter (timeline already in memory).
**Filters:** text query (description, category, payer name), date range, amount range, payer chip multiselect.
**Open question:** scope. Just text search v1 (½ day) or full filter set (1.5 days)?

---

## Tier 4 — large effort

### T4.M — Buy me a coffee (#13)
**Cheap path:** `url_launcher` to an external Ko-fi / BMC / Stripe Tip page. Re-classify as Tier 1 if you want a real outbound funnel today.
**Native IAP path:** `in_app_purchase` plugin, Google Play + App Store consumable product configs, server-side receipt validation, restore-purchase flow. Multi-week.
**Recommendation:** ship URL version now, defer IAP indefinitely.

### T4.N — Custom split modes (Shares / Exact / Percent) (#14)
**Spec required first** — own doc `docs/design/custom-split-spec.md`.

Touches:
- **Data model.** Per-participant split record (shares: int; exact: Decimal; percent: Decimal). Per memory `12815`, distribution is not currently stored per person — only scope + participant set.
- **Migration.** Add `split_mode` enum column + `split_distribution` jsonb on `expenses`. Mirror in `safar_cache.db` (bump from v5 → v6).
- **Sheet UI.** Three new editors with live validation. Shares: integers ≥ 0, distribute by ratio. Exact: sum equals total within currency precision. Percent: sum equals 100% within ε.
- **BalanceCalculator.** Accept per-pid distribution; validate sum=total; preserve equal-mode parity for existing data.
- **Tests.** Regression on equal-mode parity; new tests per mode covering rounding edge cases (decimal package, OMR 3dp).

3–5 day estimate.

---

## Tier 5 — multi-week / external dependency

### T5.O — Full i18n (Arabic)
ARB extraction, `flutter_localizations`, RTL audit across every Row/Wrap/Padding/Alignment, mirrored layouts, number/date formats. Unlocks real value for T2.I.

### T5.P — Native IAP tipping
See T4.M.2.

---

## Sequencing summary

| Sprint | Items | Effort | Snacks killed (cumulative) |
|---|---|---|---|
| 1 | T1.A–F | ½ day | 6 / 14 |
| 2 | T2.G, H, I | 1 day | 9 / 14 |
| 3 | T3.J, K | 1.5 days | 11 / 14 |
| 4 | T3.L | ½–1.5 days | 12 / 14 |
| 5 | T4.N | 3–5 days | 13 / 14 |
| 6 | T4.M (URL flavour) | 1 hour | 14 / 14 |
| Backlog | T5.O, T5.P | weeks | — |

If T4.M ships as a URL link (Sprint 1 candidate), zero "Coming soon" snacks remain after Sprint 4.

## Sprint 1 — locked decisions (2026-05-13)

1. **URLs.** Stub `https://rihla.app/help`, `/terms`, `/privacy` for now. Real hosting tracked separately as a Play Store gate.
2. **Feedback email.** `nasserbusaidi@gmail.com` (personal). Switch to a shared alias once one exists.
3. **Buy me a coffee.** Promoted into Sprint 1 as **T1.G**. Implementation: PayPal donate URL targeting `nalbusaidi5@gmail.com`, USD (PayPal doesn't support OMR).
4. **Profile gear icon (#10).** Dropped entirely when `!canPop` — the leading icon is omitted in that branch.

Constants live in `lib/core/config/app_links.dart` as the single source of truth.

## Sprint 1 — outcome

- 7 snacks removed (T1.A – T1.G, plus the dead `!canPop` branch in T1.F).
- 1 new helper file: `lib/core/config/app_links.dart`.
- 1 new widget: `lib/features/settings/widgets/legal_links_sheet.dart`.
- 3 helper functions added to `profile_screen.dart`: `_shareApp`, `_openExternalUrl`, `_sendFeedback`.
- `_AboutCard` converted `StatelessWidget → ConsumerWidget` for ref access to `appMetadataProvider`.
- 0 new dependencies. Reused `share_plus`, `url_launcher`, `package_info_plus`.

## Sprint 2 — locked decisions (2026-05-13)

1. **Supported currencies.** OMR, AED, SAR, USD, EUR, GBP — the six already configured in `AppFormatters.currencyConfig`. No new codes added.
2. **Currency scope copy.** "Default for new trips. Existing trips keep their currency." — explicit to avoid implying retroactive conversion.
3. **Arabic language.** Rendered in the picker as a locked option labelled "Coming soon" — selecting it is a no-op. Full Arabic ships with T5.O.
4. **Locked split modes.** Shares / Exact / Percent show "Locked — available in v1.2" subtitle and are non-selectable. `SplitMode.isAvailable` gates the picker.
5. **SplitMode home.** Lifted from `lib/features/ledger/widgets/custom_split_sheet.dart` into `lib/core/models/split_mode.dart` so `AppSettings` can depend on it without inverting layers. The sheet re-exports the enum so existing callers keep working.

## Sprint 2 — outcome

- 3 snacks removed (T2.G–I): Currency / Language / Default split picker now open real sheets.
- 1 new shared model: `lib/core/models/split_mode.dart` (`SplitMode`, `SplitModeX`, `splitModeFromStorage`).
- 3 new picker sheets under `lib/features/settings/widgets/`: `currency_picker_sheet.dart`, `language_picker_sheet.dart`, `default_split_picker_sheet.dart`.
- `AppSettings.defaultSplitMode` field (defaults to `SplitMode.equally`), persisted to SharedPreferences via `SettingsService.saveDefaultSplitMode`, mutated via `SettingsNotifier.setDefaultSplitMode`.
- `_PreferencesCard` reads live `currencyCode`, `languageCode`, `defaultSplitMode` from `settingsProvider` and routes taps to the three sheets. Trailing labels come from new `_currencyTrailing` / `_languageTrailing` helpers + `SplitModeX.label`.
- 6 new unit tests in `test/unit/settings_default_split_mode_test.dart` covering round-trip, default, unknown-value fallback, `storageKey` stability, `isAvailable` table, and `copyWith` preservation.
- 0 new dependencies.
- **Deferred:** wiring `defaultSplitMode` into `AddExpenseScreen`'s initial selection. `CustomSplitSheet` has no `initialMode` parameter and `showCustomSplitSheet` is only called from `edit_expense_form.dart` today; the integration lands with T4.N when non-equal modes become functional.

---

## Remaining work — re-audited 2026-05-13

Re-scanning `lib/**/*.dart` for literal `"coming soon"` confirms exactly **4 surfaces** survive in shipped code (plus the Arabic locked option in the language picker, which is deliberate and tracked as T5.O):

| # | Surface | Location | Snack copy |
|---|---|---|---|
| 11 | Group invite QR icon | `lib/features/groups/widgets/group_info_section.dart:279` | `"QR invite coming soon"` |
| 12 | Profile QR chip | `lib/features/settings/screens/profile_screen.dart:289` | `"QR sharing coming soon"` |
| 3  | Ledger cover Search icon | `lib/features/ledger/screens/ledger_screen.dart:214` | `"Search coming soon"` |
| 14 | CustomSplitSheet → Shares/Exact/Percent | `lib/features/ledger/widgets/custom_split_sheet.dart:163` | `"{mode} splits are coming soon."` |

Ordered from quick win → hardest:

### Sprint 3 (next) — Ledger search (T3.L) · ½–1.5 days

**Why first:** zero new dependencies, single-feature scope, timeline data is already in memory, no native config touched. Highest "polish per hour" of the remaining work.

- Files: new `lib/features/ledger/widgets/ledger_search_sheet.dart`; rewire `ledger_screen.dart:214` to open the sheet.
- Scope decision (**open**):
  - **v1 minimal (½ day):** text query only — match expense description, category label, payer display name. Case-insensitive. Empty state when no matches.
  - **v1 full (1.5 days):** + date-range chip, amount-range chip, payer multiselect chip, category multiselect chip. Reuse `SearchFilterBar` from `lib/shared/widgets/`.
- Filter is client-side over the existing `expenses + settlements` timeline. No provider/repository changes.
- Tests: widget test that types a query and asserts filtered card count.
- **Recommended:** ship v1 minimal first; promote to full filter if QA flags it as too thin.

### Sprint 4 — QR invite bundle (T3.J + T3.K) · 1.5–2 days

**Why bundled:** both surfaces use the same `qr_flutter` integration and the same deep-link plumbing. Doing them together amortises the native config cost.

- Dependency: add `qr_flutter: ^4.1.0` to `pubspec.yaml`.
- T3.J — Group invite QR:
  - New `lib/features/groups/widgets/qr_invite_sheet.dart`. Encodes `https://rihla.app/join/${group.inviteCode}` with `rihla://join?code=${code}` fallback.
  - Router: add `/join/:code` → `JoinGroupScreen` with code pre-filled in `app_router.dart`.
  - Wire from `group_info_section.dart:274-282` (remove the snack).
- T3.K — Profile QR chip:
  - Encodes a static device-handle URL (e.g. `https://rihla.app/u/${handle}`) — no inbound routing required since handles aren't claimable yet, the QR is just an exchange artifact.
  - Wire from `profile_screen.dart:280-285` (remove the snack).
- Native config:
  - Android: intent filter on `MainActivity` for `https://rihla.app` + `rihla://` scheme (`android/app/src/main/AndroidManifest.xml`).
  - iOS: URL types + Associated Domains entitlement (`ios/Runner/Info.plist`, `ios/Runner/Runner.entitlements`).
- **Open question (blocker for universal links):** is `apple-app-site-association` / `assetlinks.json` hostable on `rihla.app` today? If no, ship with `rihla://` custom scheme only and add HTTPS verification post-launch. App still works fully — only the "tap link in iMessage → opens app" path requires AASA.
- Tests: golden test for QR sheet rendering; router test for `/join/:code` pre-fill.

### Sprint 5 — Custom split modes (T4.N) · 3–5 days · the hardest

**Why last:** touches data model, both databases (Supabase migration + `safar_cache.db` bump), balance math, three new editor UIs, and migration of existing equal-mode expenses. Requires a design spec before code.

- **Prerequisite:** write `docs/design/custom-split-spec.md` covering data shape, sum-validation rules per mode, rounding policy (OMR 3dp), and UI affordances.
- Data model:
  - Add `split_mode` enum column (`equally|shares|exact|percent`) + `split_distribution` jsonb on `expenses`.
  - Mirror in `safar_cache.db` schema v6 (migrate from v5).
  - Per-participant record: `shares: int ≥ 0`, `exact: Decimal`, `percent: Decimal` summing to 100±ε.
- Sheet UI:
  - Replace the snack at `custom_split_sheet.dart:163`.
  - Three editors with live validation. Shares: integer steppers, ratio bar. Exact: amount inputs, "remaining" pill, validate sum=total. Percent: percent inputs, validate sum=100.
- `BalanceCalculator` (lib/features/ledger/...):
  - Accept per-pid distribution. Preserve equal-mode parity for existing rows (treat null distribution as equal split across `participants`).
  - Round-trip tests covering OMR precision edge cases.
- Sync:
  - `OfflineRepository.saveExpense` writes mode + distribution to sync_queue.
  - `SyncService` upload/download paths handle the new columns.
- Wire `defaultSplitMode` into `AddExpenseScreen`'s initial mode (the Sprint 2 deferred item — finally usable).
- Tests: balance regression on existing data; per-mode rounding tests; widget tests on each editor's sum validation.

### Backlog (untouched)

- **T5.O — Arabic i18n.** Multi-week. Unlocks real value for the Arabic locked option in `language_picker_sheet.dart`. Not gated on anything in this plan.
- **T5.P — Native IAP tipping.** Replace the PayPal URL in `profile_support_section.dart` with `in_app_purchase`. Optional, defer indefinitely.

---

## Updated sequencing

| Sprint | Items | Effort | Snacks remaining after |
|---|---|---|---|
| 3 | T3.L (ledger search v1 minimal) | ½ day | 3 |
| 4 | T3.J + T3.K (QR bundle) | 1.5–2 days | 1 |
| 5 | T4.N (custom split modes) | 3–5 days | 0 |
| Backlog | T5.O, T5.P | weeks | — (Arabic locked option intentional) |

**Total remaining estimate:** ~5–8 dev-days to zero "Coming soon" snacks.

---

## Sprint 3 — outcome (2026-05-13)

- 1 snack removed (T3.L): `'Search coming soon'` → full-height bottom sheet.
- New widget: `lib/features/ledger/widgets/ledger_search_sheet.dart`.
  - Case-insensitive substring filter across expense (`description`, `categoryName`, `payerName`) and settlement (`payerName`, `recipientName`, `note`).
  - Results sort newest-first; empty-state hints for empty query and no-match.
  - Tapping an expense closes the sheet and pushes `/ledger/edit/:id`.
- New tests: `test/unit/ledger_search_filter_test.dart` (8 cases).
- Updated test: `test/features/ledger/ledger_screen_overflow_test.dart` asserts the sheet opens.
- Scope landed: **v1 minimal** (text query only). Filter chips (date / amount / payer / category) deferred.
- 0 new dependencies.

## Sprint 4 — outcome (2026-05-13)

- 2 snacks removed (T3.J + T3.K): `'QR invite coming soon'` and `'QR sharing coming soon'`.
- New widgets:
  - `lib/features/groups/widgets/qr_invite_sheet.dart` — encodes `https://rihla.app/join/<code>`; wired from `group_info_section.dart`.
  - `lib/features/settings/widgets/profile_qr_sheet.dart` — encodes `https://rihla.app/u/<handle>`; wired from the profile identity-chip row.
- 1 new dependency: `qr_flutter: ^4.1.0`.
- 2 widget tests pumping the sheets.
- The T3.J deep-link plumbing (`/join/:code` route, `app_links` cold/warm-start handler, Android intent filters, iOS URL types + Associated Domains) landed earlier on `codex/t3j-deeplink-routing` — the QR sheets ride on top.
- **Open question still open:** `apple-app-site-association` + `assetlinks.json` hosting on `rihla.app`. Without it, the HTTPS link won't autoverify; users get the in-app routing only via the custom `rihla://` scheme. The QR encodes the HTTPS form anyway because it's strictly the better long-term URI.

## Sprint 5 — outcome (2026-05-13)

The T4.N **data layer** shipped earlier on `codex/t4n-split-data-layer` (merged to main): `Expense.splitMode` + `splitDistribution`, sqflite v7→v8, `BalanceCalculator` mode dispatch with legacy parity + remainder-safe weighted allocation, 15 unit tests.

The **UI layer** lands now:
- `custom_split_sheet.dart` rewritten end-to-end:
  - Returns `SplitResult(SplitMode mode, Map<String, Decimal>? distribution)`. Equally returns `null` distribution (calculator handles the equal path); the other three modes return per-participant weights/amounts/percents.
  - Shares: per-participant integer stepper (0–99), Apply enabled when sum > 0.
  - Exact: per-participant amount inputs, Apply enabled when `|sum − total| ≤ 0.001`.
  - Percent: per-participant percent inputs, Apply enabled when `|sum − 100| ≤ 0.001`.
  - Live footer shows total or remainder, depending on mode.
- New "How" section in `ExpenseEditorBody` (orthogonal to the existing "Split between" scope picker). Hidden when fewer than 2 people are eligible. Tapping Customise opens the sheet with the current mode + distribution.
- `ExpenseEditorPayload` carries `splitMode` + `splitDistribution`; `addExpense` writes them to Firestore for non-equal modes (omitted for equally). `updateExpense` accepts `clearSplit: true` for revert-to-equal.
- Initial mode in add: `AppSettings.defaultSplitMode`. In edit: whatever the existing expense stored.
- When scope or custom-split membership changes, the editor resets to equally — keyed-by-id distribution would otherwise be stale.
- `SplitModeX.isAvailable` is now permanently `true`; `DefaultSplitPickerSheet` no longer shows the "Locked — v1.2" placeholder.
- 9 widget tests for the sheet (`test/features/ledger/custom_split_sheet_test.dart`) + 6 persistence tests in `expense_service_test.dart`. Suite: **921 passing**, 3 skipped.

## Current state — 2026-05-13 8:30pm

| Surface | Status |
|---|---|
| Group invite QR icon | **Shipped** (T3.J) |
| Profile QR chip | **Shipped** (T3.K) |
| Ledger search icon | **Shipped** (T3.L) |
| CustomSplitSheet → Shares/Exact/Percent | **Shipped** (T4.N: data + UI) |
| Arabic locked language option | Intentional (T5.O backlog) |

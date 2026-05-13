# "Coming Soon" Implementations — Plan

**Status:** Sprint 1 in progress — Sprint 2+ awaiting kickoff
**Branch:** `plan/coming-soon-implementations` (worktree: `worktree-coming-soon-plan`)
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

# Arabic Localization PR2a — Settings + Profile + Toggle Unlock

**Authored:** 2026-05-17
**Branch:** `feat/l10n-pr2a-settings-profile` (off `main` @ d0a8aea, PR1 merged via #34)
**Predecessor:** PR1 (#34, merged 2026-05-17) — l10n infrastructure
**Successors:** PR2b (Ledger), PR3 (Groups/Events/Home/Activity), PR4 (Polish)

---

## Scope

Translate the entire Settings + Profile surface (`lib/features/settings/`) to Arabic and unlock the language toggle. User-visible delta: picking "العربية" from Profile → Language now actually switches the app to Arabic; Settings + Profile render in Arabic; Ledger / Groups / Home stay English until PR2b + PR3.

**Surface:**
- 1 screen: `lib/features/settings/screens/profile_screen.dart`
- 12 widgets: `lib/features/settings/widgets/*.dart`
- 1 RTL fix: 2 `Alignment.centerLeft|Right` calls in `profile_screen.dart`
- 1 helper: `currencyDisplayName(code, l10n)` lookup
- 1 integration test widening: assert ar text on Settings in `golden_path_arabic_test.dart`

**Estimated ARB additions:** ~75 new keys (settings-specific) + 10 currency keys + ~5 common keys.

## Decisions (locked 2026-05-17)

| # | Decision | Rationale |
|---|---|---|
| Q1 | Split PR2 into PR2a (Settings+Profile+unlock) and PR2b (Ledger) | Keep scope grounded; Ledger has money-math UI surface that needs the codex gate |
| Q2 | Unlock toggle **in PR2a** | Standard l10n rollout — partial translation is acceptable WIP signaling, dogfood ar earlier |
| Q3 | Digits stay **Latin** (`0123`), not Arabic-Indic (`٠١٢٣`) | Locked grill decision; `RAmount` formatting unchanged |
| Q4 | Currency names use `currencyDisplayName(code, l10n)` helper backed by per-currency ARB keys | 10 keys (one per currency), code-locale lookup stays in Dart, easy to extend |
| Q5 | Brand tagline `'RIHLA · BUILT FOR JOURNEYS'` stays English | Brand mark convention — don't translate brand strings |

## Non-goals (deferred)

- **Ledger / Groups / Home / Events / Activity translation** — PR2b/PR3.
- **Onboarding strings** — PR3 (currently 3-page, English-only).
- **WordmarkLogo flourish RTL mirror** — PR4 (real-device QA call).
- **`_sharedAxisTransition` RTL flip** — PR4.
- **`RouteMark` canvas mirror** — PR4.
- **Arabic-Indic digits** — PR4-or-later if user feedback demands them; Q3 locked Latin for v1.
- **CLAUDE.md `EdgeInsetsDirectional` Do/Don't entries** — PR4.
- **Onboarding gate audit** — PR3.

## Codex gate

**Skipped.** Per Operating Contract:
- No money math (`BalanceCalculator`, `MoneySerializer` untouched)
- No `firestore.rules` or Cloud Functions
- No `app_router.dart` / route tree / deep links
- No schema / field-name change (`languageCode` already exists; toggle unlock changes a guard, not a contract)

One-sentence diff: "Translate Settings + Profile and unlock the language toggle." Gate-skippable.

PR2b will need the gate (RAmount + expense forms = money-math UI surface).

---

## ARB key inventory

All new keys land in Task 1. **Naming convention:** screen-prefixed for screen-specific keys (`profileSectionPreferences`, `languageSheetTitle`), `common*` for cross-screen reusables.

### `common*` (cross-screen, pre-add for PR2b/PR3 reuse)
- `commonCancel`, `commonSave`, `commonDelete`, `commonOK`

### Currency names (helper-backed)
- `currencyOMR / AED / SAR / USD / EUR / GBP / QAR / KWD / BHD / JPY` (10 keys)

### Language picker
- `languageSheetTitle`, `languageEnglish`, `languageArabic` (autonyms)

### Currency picker
- `currencySheetTitle`, `currencySheetSubtitle`

### Theme picker
- `themeSheetTitle`, `themeSystem` + `themeSystemDescription`, `themeLight` + `themeLightDescription`, `themeDark` + `themeDarkDescription` (7)

### Default split picker
- `defaultSplitSheetTitle`, `defaultSplitSheetSubtitle`

### SplitMode display names (helper-backed, codex round 1 P1-C)
- `splitModeEqually` — "Equal" / "بالتساوي"
- `splitModeShares` — "Shares" / "حصص"
- `splitModeExact` — "Exact amounts" / "مبالغ محددة"
- `splitModePercent` — "Percent" / "نسبة مئوية"

### Edit name sheet
- `editNameTitle`, `editNameHelper`, `editNameFieldLabel`, `editNameFieldHint`, `editNameInitialsCaption` (5; reuses commonCancel)

### Legal sheet (codex round 1 P1-B)
- `legalSheetTitle` — "Legal"
- `legalTermsOfService` — "Terms of service" (was `legalTerms` in round 0; replaced)
- `legalPrivacyPolicy` — "Privacy policy"
- `legalDeleteMyData` — "Delete my data"

### QR sheet
- `qrSheetTitle`, `qrSemanticsLabel`, `qrCopyHandle`, `qrHandleCopied` (4)

### profile_*_section widgets
- Sections: `profileSectionPreferences / Account / About / Display / Journey` (5)
- Stats: `profileStatsGroups / Events / Spent` (3 — singular for stats cards, `profileStatsJourneysLabel / GroupsLabel / SpentLabel` for ALLCAPS variants — 6 total)
- Notifications: `profileNotificationsTitle`, `profileNotificationsEnabled`, `profileNotificationsDisabledHint` (3)
- About: `profileAboutVersion`, `profileAboutSendFeedback`, `profileAboutLicenses` (3)
- Display: `profileDisplayTheme`, `profileDisplayThemeSystemValue`, `profileDisplayThemeLightValue`, `profileDisplayThemeDarkValue` (4 — three concrete value keys, not the parameterized form proposed in round 0; codex round 1 P1-D)
- Support (codex round 1 P1-B — round 0 missed three): `profileSupportSectionLabel` ("SUPPORT"), `profileSupportCoffeeTile` ("Buy me a coffee"), `profileSupportPaypalFailed` ("Couldn't open PayPal")

### Profile screen
- Header: `profileTitle`, `profileAnonymousTraveller`, `profileSetYourName`, `profileFinishRecovery` (4)
- Recovery card subtitle (codex round 1 P1-B): `profileRecoverySubtitle` ("A recovery link is waiting. Enter the email it was sent to.")
- Preferences row: `profilePreferencesCurrency / Language / DefaultSplit` (3)
- Account row: `profileAccountLinkedEmail / NotSet / SignOut / Delete / DeletePermanent` (5)
- Stats subtitles (codex round 1 P1-B): `profileStatsAllTime` ("all-time"), `profileStatsActive` ("active"), `profileStatsLifetime` ("lifetime")
- Share copy (codex round 1 P1-B): `profileShareMessage` ("I'm splitting trip expenses with Rihla. Give it a try.") — body translated; `Share.share`'s `subject: 'Rihla'` stays English per Q5
- Snacks: `profileSnackHandleCopied / SignedOut / SignOutFailed / OpenLinkFailed / NoEmailApp` (5)
- Deletion: `profileDeletionOk / NoUser / Error` (3)

**Estimated total: ~90 unique keys (up from ~75 after codex round 1).**

---

## Tasks

### Task 1: Bulk-add ARB keys
Add every key from inventory to `lib/l10n/app_en.arb` + `lib/l10n/app_ar.arb` with `@<key>` metadata in en. Verify with `dart run tool/check_arb_completeness.dart`. **Commit:** `feat(l10n): add Settings/Profile ARB keys (en + ar)`

### Task 2: Currency + SplitMode display name helpers
TDD. Two parallel helpers in the same task:

**2a. Currency.** Create `lib/core/utils/currency_display_name.dart` + `test/unit/currency_display_name_test.dart`. Switch on code → `l10n.currency<CODE>`. Unknown codes return the code itself.

**2b. SplitMode (codex round 1 P1-C).** Create `lib/core/utils/split_mode_display_name.dart` + `test/unit/split_mode_display_name_test.dart`. Signature: `String splitModeDisplayName(SplitMode mode, AppLocalizations l10n)`. Switch on the enum → `l10n.splitModeEqually / Shares / Exact / Percent`. The existing English-only `SplitModeX.label` extension in `lib/core/models/split_mode.dart:18-24` stays untouched (callers migrate to the helper instead — this keeps `split_mode.dart` independent of `AppLocalizations`).

Call sites to migrate (Task 4 + Task 7 handle these):
- `lib/features/settings/widgets/default_split_picker_sheet.dart:65` — picker option title
- `lib/features/settings/screens/profile_screen.dart:678` — preferences row `trailingText`

**Commit:** `feat(l10n): add currencyDisplayName + splitModeDisplayName helpers`

### Task 3: Translate `language_picker_sheet.dart` + unlock toggle
TDD. Three test cases:
1. en locale: title "Language", "English", "العربية", ar option enabled, no "Coming soon" subtitle.
2. Tap "العربية" → `setLanguage('ar')` called.
3. ar locale: title "اللغة", current selection ar.

Remove from `language_picker_sheet.dart`:
- Line 45: change `if (code == null || code == 'ar') return;` to `if (code == null) return;`
- Line 63: remove `style: TextStyle(color: colors.textSecondary)` from Arabic title
- Lines 65-68: remove `subtitle: Text('Coming soon', ...)` block
- Line 69: remove `enabled: false`
- Lines 9-12: update stale doc comment about T5.O.

Translate three strings via `context.l10n`.

**Test contracts (memory):**
- `SharedPreferences.setMockInitialValues({})` in setUp
- No `pumpAndSettle` post-helper

**Known cosmetic (codex round 1 P2-B, deferred):** Because the sheet awaits `setLanguage()` before `Navigator.pop()` (`language_picker_sheet.dart:46-50`) and watches `languageCode` at `:30`, the sheet's `Text('Language', ...)` may rebuild as Arabic for a single frame before dismissal. One-frame flicker. Not fixed in PR2a — fix lands when PR4 polish revisits cross-route transitions.

**Commit:** `feat(l10n): translate LanguagePickerSheet + unlock Arabic toggle`

### Task 4: Translate other picker sheets
Modify `currency_picker_sheet.dart`, `theme_picker_sheet.dart`, `default_split_picker_sheet.dart`.

- `currency_picker_sheet.dart`: delete local `_currencyNames` map (lines 20-25), use `currencyDisplayName(code, context.l10n)` from Task 2a.
- `theme_picker_sheet.dart`: replace 'System', 'Light', 'Dark' + their descriptions via `context.l10n.themeSheetTitle` / `themeSystem` / etc.
- `default_split_picker_sheet.dart:65`: replace `Text(mode.label)` with `Text(splitModeDisplayName(mode, context.l10n))` (Task 2b). Translate sheet title + subtitle.

**Commit:** `feat(l10n): translate Currency/Theme/DefaultSplit picker sheets`

### Task 5: Translate `edit_name_bottom_sheet.dart` + small sheets
Modify `edit_name_bottom_sheet.dart`, `legal_links_sheet.dart`, `profile_qr_sheet.dart`.

- `legal_links_sheet.dart` (codex round 1 P1-B — round 0 missed 3 of 4 strings): translate `'Legal'` header (line 61) + all three `_LegalRow.label` props at lines 74, 80, 86. Use `legalSheetTitle`, `legalTermsOfService`, `legalPrivacyPolicy`, `legalDeleteMyData`. The icons and URLs stay put — only the labels change.
- `edit_name_bottom_sheet.dart`: translate heading, helper, labels, button text.
- `profile_qr_sheet.dart`: QR snack uses `qrHandleCopied` (alias of `profileSnackHandleCopied`).

**Commit:** `feat(l10n): translate edit-name + legal-links + QR sheets`

### Task 6: Translate `profile_*_section.dart` widgets
All 5: display, notifications, about, support, stats.

- `profile_display_section.dart` (codex round 1 P1-D refinement): the `switch (mode)` at lines 24-28 currently returns English literals (`'System • Following device'`, `'Light'`, `'Dark'`). Replace with `context.l10n.profileDisplayThemeSystemValue` / `profileDisplayThemeLightValue` / `profileDisplayThemeDarkValue` (three concrete value keys — drops the originally-proposed `profileThemeSystemValue(themeName)` parameterization because the system case is a compound phrase and English-themed parameterization would still leak source text into Arabic context).
- `profile_stats_section.dart`: hardcoded `'YOUR JOURNEY'` literal at line 36 (no `.toUpperCase()` call — Arabic key renders verbatim). Translate the 6 stat labels (Groups/Events/Spent x2 — stats card pair).
- `profile_support_section.dart` (codex round 1 P1-B — round 0 missed all three): translate `'SUPPORT'` (line 46), `'Buy me a coffee'` (line 101), and the `"Couldn't open PayPal"` SnackBar text (line 70).
- `profile_notifications_section.dart`, `profile_about_section.dart`: translate per inventory.

**Commit:** `feat(l10n): translate profile section widgets`

### Task 7: Translate `profile_screen.dart`
~35 strings (up from ~30 after codex round 1 P1-B expansion). Categories: header, action labels, snack/error messages, stat labels, recovery card, preference/account/about rows, share message.

**Concrete code changes:**
- Recovery card subtitle (line 283): `'A recovery link is waiting...'` → `context.l10n.profileRecoverySubtitle`.
- `_StatCard` `sub` props at lines 495, 504, 521 (`'all-time'`, `'active'`, `'lifetime'`) → `context.l10n.profileStatsAllTime` / `Active` / `Lifetime`.
- `_PreferencesCard` row trailing text at line 678 (`settings.defaultSplitMode.label`) → `splitModeDisplayName(settings.defaultSplitMode, context.l10n)` (Task 2b helper).
- Share copy at line 1119: `"I'm splitting trip expenses with Rihla. Give it a try."` → `context.l10n.profileShareMessage`. The `subject: 'Rihla'` parameter at line 1120 stays English per Q5.
- **ALLCAPS removal (codex round 1 P2-A — re-aimed from Task 6 to here):** drop the `.toUpperCase()` call at line 611 in `_SectionLabel`. Arabic has no case concept; `.toUpperCase()` on the localized strings is a no-op but signals an English-only design intent. Removing it ensures the ARB values render verbatim. English readers still see uppercase because the ARB en values themselves can stay uppercase (`profileSectionPreferences` could store "PREFERENCES" if we want — pick natural-case for both per design taste; recommended: English natural-case Title Case + Arabic natural-case, since the design's all-caps was an English typographic flourish that doesn't carry to Arabic).

**Stays English (Q5):**
- Lines 868-869: `'RIHLA · BUILT FOR JOURNEYS'` tagline.
- Line 1138: `'subject': 'Rihla feedback · v$versionLabel'` (mailto subject — seen by support, not user).
- Line 1120: `Share.share`'s `subject: 'Rihla'` parameter (brand mark).

**Commit:** `feat(l10n): translate profile screen (sections, snacks, account actions)`

### Task 8: RTL audit + fixes
2 lines in `profile_screen.dart`:
- Line 182: `Alignment.centerLeft` → `AlignmentDirectional.centerStart`
- Line 200: `Alignment.centerRight` → `AlignmentDirectional.centerEnd`

Verify post-change grep returns 0 in `lib/features/settings/`. **Commit:** `refactor(l10n): convert Alignment.center* to AlignmentDirectional in profile_screen`

### Task 9: Widen Arabic golden-path integration test
Modify `integration_test/golden_path_arabic_test.dart`. After the wordmark block, tap the Profile tab and assert Arabic Settings content renders.

**Codex round 1 P1-A fix — use the real key:**

```dart
import 'package:safar/features/home/keys/home_keys.dart';

// ...after wordmark block...
final profileTab = find.byKey(HomeKeys.bottomNavProfile);  // Key('home_bottom_nav_profile')
expect(profileTab, findsOneWidget,
    reason: 'home_bottom_nav_profile missing on Home after skeleton clear (ar)');
await tester.tap(profileTab);
await _settle(tester);

expect(
  find.text('التفضيلات'),
  findsOneWidget,
  reason: 'Profile screen "Preferences" section not translated to ar — '
      'check localeProvider chain + ARB key profileSectionPreferences',
);
```

No silent-skip fallback. The key exists (verified in `lib/features/home/keys/home_keys.dart:30` and `lib/features/home/widgets/bottom_nav_shell.dart:120-123`); if it disappears the assertion fails loudly and the test maintainer fixes the navigation surface, not the test.

Re-run on iOS sim against emulator. **Commit:** `test(l10n): widen Arabic golden-path to assert Profile translation`

### Task 10: Final verification + PR
Same gate set as PR1 Task 12:
1. `flutter test --coverage` (CI test-dir list) → coverage ≥ 80%
2. `flutter analyze` → clean
3. `dart run tool/check_arb_completeness.dart` → OK
4. `bash tool/check_theme_purity.sh` → PASS
5. `git diff main...HEAD --stat` → matches expected file list
6. `gh pr create` with PR body summarizing PR2a + linking PR1 (#34)

---

## Codex round 1 findings applied

Run 2026-05-17, session `019e36be-65c2-7801-96c1-7f2d9b61305a`. Verdict: FAIL (4 P1, 2 P2). All four P1s applied; P2-A applied (re-aimed to Task 7); P2-B documented as known cosmetic.

- **P1-A** — Task 9's `Key('home_profile_tab')` was a hallucination. Real key is `HomeKeys.bottomNavProfile = Key('home_bottom_nav_profile')` (`lib/features/home/keys/home_keys.dart:30`, attached at `lib/features/home/widgets/bottom_nav_shell.dart:120-123`). Plan rewired + skip fallback dropped.
- **P1-B** — ARB inventory missed 12 strings: legal sheet rows (3), support section (3), profile_screen recovery subtitle (1), stat subtitles (3), share copy body (1), legal sheet title (1). All added.
- **P1-C** — `SplitMode.label` (`split_mode.dart:18-24`) feeds both `default_split_picker_sheet.dart:65` and `profile_screen.dart:678`. Plan added a `splitModeDisplayName(mode, l10n)` helper (Task 2b) parallel to currencyDisplayName; both call sites migrate. `SplitModeX.label` extension stays untouched (keeps `split_mode.dart` independent of `AppLocalizations`).
- **P1-D** — Parameterized `profileThemeSystemValue(String themeName)` was underspecified. The "System" case is a compound ("System • Following device") — parameterization would still leak English. Replaced with three concrete value keys: `profileDisplayThemeSystemValue / LightValue / DarkValue`.
- **P2-A** — ALLCAPS note re-aimed from Task 6 (profile_stats_section, which has hardcoded literals, not `.toUpperCase()`) to Task 7 (profile_screen.dart's `_SectionLabel` at line 611 actually calls `.toUpperCase()`). Plan now removes the `.toUpperCase()` call in Task 7.
- **P2-B (deferred)** — Sheet's `Text('Language', ...)` may rebuild as Arabic for one frame before `Navigator.pop()`. Single-frame cosmetic flicker. Documented in Task 3 as known; not fixed in PR2a.

## Notes on the Q2 unlock decision

PR1 left toggle locked, zero user-visible delta. PR2a unlocks. After PR2a merges:
- Arabic user opens Profile → sees Arabic.
- Taps to Ledger / Groups / Home → sees English.

Standard l10n rollout pattern (Slack, Notion, Linear all ship language packs incrementally). If real-device QA surfaces UX confusion, the lock is a one-line revert + a `Coming soon` re-add. Cost of revert is small; cost of holding Arabic locked through PR3 is real-device-QA-debt accumulation.

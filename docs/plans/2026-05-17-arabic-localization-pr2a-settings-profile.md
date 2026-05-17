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

### Edit name sheet
- `editNameTitle`, `editNameHelper`, `editNameFieldLabel`, `editNameFieldHint`, `editNameInitialsCaption` (5; reuses commonCancel)

### Legal + QR sheets
- `legalTerms`, `qrSheetTitle`, `qrSemanticsLabel`, `qrCopyHandle`, `qrHandleCopied` (5)

### profile_*_section widgets
- Sections: `profileSectionPreferences / Account / About / Display / Journey` (5)
- Stats: `profileStatsGroups / Events / Spent` (3 — singular for stats cards, `profileStatsJourneysLabel / GroupsLabel / SpentLabel` for ALLCAPS variants — 6 total)
- Notifications: `profileNotificationsTitle`, `profileNotificationsEnabled`, `profileNotificationsDisabledHint` (3)
- About: `profileAboutVersion`, `profileAboutSendFeedback`, `profileAboutLicenses` (3)
- Display: `profileDisplayTheme`, `profileThemeSystemValue(String themeName)` parameterized (2)
- Support: `profileSupportHelpCenter`, `profileSupportSendFeedback`, `profileSupportTerms` (3)

### Profile screen
- Header: `profileTitle`, `profileAnonymousTraveller`, `profileSetYourName`, `profileFinishRecovery` (4)
- Preferences row: `profilePreferencesCurrency / Language / DefaultSplit` (3)
- Account row: `profileAccountLinkedEmail / NotSet / SignOut / Delete / DeletePermanent` (5)
- Snacks: `profileSnackHandleCopied / SignedOut / SignOutFailed / OpenLinkFailed / NoEmailApp` (5)
- Deletion: `profileDeletionOk / NoUser / Error` (3)

**Estimated total: ~75 unique keys.**

---

## Tasks

### Task 1: Bulk-add ARB keys
Add every key from inventory to `lib/l10n/app_en.arb` + `lib/l10n/app_ar.arb` with `@<key>` metadata in en. Verify with `dart run tool/check_arb_completeness.dart`. **Commit:** `feat(l10n): add Settings/Profile ARB keys (en + ar)`

### Task 2: Currency display name helper
TDD. Create `lib/core/utils/currency_display_name.dart` + `test/unit/currency_display_name_test.dart`. Switch on code → l10n.currency<CODE>. Unknown codes return the code itself. **Commit:** `feat(l10n): add currencyDisplayName helper backed by ARB keys`

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

**Commit:** `feat(l10n): translate LanguagePickerSheet + unlock Arabic toggle`

### Task 4: Translate other picker sheets
Modify `currency_picker_sheet.dart`, `theme_picker_sheet.dart`, `default_split_picker_sheet.dart`. `currency_picker_sheet` deletes local `_currencyNames` map; uses `currencyDisplayName(code, context.l10n)`. **Commit:** `feat(l10n): translate Currency/Theme/DefaultSplit picker sheets`

### Task 5: Translate `edit_name_bottom_sheet.dart` + small sheets
Modify `edit_name_bottom_sheet.dart`, `legal_links_sheet.dart`, `profile_qr_sheet.dart`. QR snack uses `qrHandleCopied` (= `profileSnackHandleCopied`). **Commit:** `feat(l10n): translate edit-name + legal-links + QR sheets`

### Task 6: Translate `profile_*_section.dart` widgets
All 5: display, notifications, about, support, stats. `profile_display_section` has parameterized `profileThemeSystemValue(themeName)` — needs ARB placeholder.

**ALLCAPS note:** "JOURNEYS / GROUPS / SPENT" labels render as natural Arabic ("الرحلات / المجموعات / الإنفاق"); skip `.toUpperCase()` Dart-side if currently applied.

**Commit:** `feat(l10n): translate profile section widgets`

### Task 7: Translate `profile_screen.dart`
~30 strings. Categories: header, action labels, snack/error messages, stat labels, preference/account/about rows.

Stays English (Q5):
- Line 868-869: `'RIHLA · BUILT FOR JOURNEYS'` tagline
- Line 1138: `'subject': 'Rihla feedback · v$versionLabel'` (mailto subject — seen by support, not user)

**Commit:** `feat(l10n): translate profile screen (sections, snacks, account actions)`

### Task 8: RTL audit + fixes
2 lines in `profile_screen.dart`:
- Line 182: `Alignment.centerLeft` → `AlignmentDirectional.centerStart`
- Line 200: `Alignment.centerRight` → `AlignmentDirectional.centerEnd`

Verify post-change grep returns 0 in `lib/features/settings/`. **Commit:** `refactor(l10n): convert Alignment.center* to AlignmentDirectional in profile_screen`

### Task 9: Widen Arabic golden-path integration test
Modify `integration_test/golden_path_arabic_test.dart`. After wordmark block, navigate to Profile from Home and assert `find.text('التفضيلات')` (Preferences section). Skip-silently if Home profile-tab key doesn't exist (don't fail on routing assumptions).

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

## Notes on the Q2 unlock decision

PR1 left toggle locked, zero user-visible delta. PR2a unlocks. After PR2a merges:
- Arabic user opens Profile → sees Arabic.
- Taps to Ledger / Groups / Home → sees English.

Standard l10n rollout pattern (Slack, Notion, Linear all ship language packs incrementally). If real-device QA surfaces UX confusion, the lock is a one-line revert + a `Coming soon` re-add. Cost of revert is small; cost of holding Arabic locked through PR3 is real-device-QA-debt accumulation.

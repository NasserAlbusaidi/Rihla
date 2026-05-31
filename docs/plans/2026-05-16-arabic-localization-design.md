# Arabic Localization — Design Doc

**Date**: 2026-05-16
**Status**: Approved (brainstorm), pending implementation plan
**Ships**: Post-launch (does not block v1.2 Android release)
**Scope**: Arabic (`ar`) only, in-app screens only

---

## Locked Decisions

| Decision | Choice |
|---|---|
| Languages | Arabic only (in addition to English default) |
| Numerals | Western (1234.50) in both locales — keeps Geist Mono tabular alignment |
| Locale switching | Manual toggle in Settings; default English on first launch |
| Translation source | Claude drafts ARB, user reviews each batch in PR |
| Calendar | Gregorian with Arabic month names via `DateFormat.yMMMd('ar')` |
| Currency | `OMR 12.500` prefix preserved in Arabic (Bank Muscat / NBO convention) |
| Wordmark | Swap "Rihla" → "رحلة" when locale is Arabic |
| Scope | In-app screens only (groups, events, ledger, settle-up, activity, profile, settings, home) |
| Rollout | Staged: 3 PRs |

---

## Architecture

### Dependencies

```yaml
# pubspec.yaml
flutter_localizations:
  sdk: flutter
intl: ^0.20.2   # already present

flutter:
  generate: true   # enables ARB → Dart codegen
```

### Codegen config

`l10n.yaml` at repo root:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
nullable-getter: false
```

ARB files: `lib/l10n/app_en.arb` (source of truth), `lib/l10n/app_ar.arb` (drafted by Claude, reviewed in PR).

Generated class accessed via `AppLocalizations.of(context)`. Add a `context.l10n` extension in `lib/core/extensions/` for ergonomics.

### Settings model

`AppSettings.localeCode` — new immutable field, `'en' | 'ar'`, default `'en'`. Backed by SharedPreferences. Missing key migrates to `'en'`. No Firestore mirror (device-local preference, matches existing `deviceName` / `onboardingComplete` pattern).

### Provider wiring

- `settingsProvider` exposes `localeCode` getter (existing `StateNotifierProvider`).
- New `localeProvider` derived from `settingsProvider` returns `Locale(localeCode)`.

### MaterialApp wiring

In `SafarApp` (`lib/main.dart`):
- Watch `localeProvider` → pass to `MaterialApp.locale`.
- `localizationsDelegates: AppLocalizations.localizationsDelegates`.
- `supportedLocales: AppLocalizations.supportedLocales`.

Flutter's `MaterialApp` automatically sets `Directionality` based on locale — Arabic flips the widget tree for **directional** primitives.

### Settings UI

New `LanguageSettingsTile` in Profile/Settings. Two radio options (English / العربية). Writes via `settingsProvider`. Live-rebuilds the app — no restart needed.

---

## String Extraction

- **What gets extracted**: every user-visible string in `.dart` files within scoped features.
- **What stays English**: Sentry breadcrumbs, log messages, debug labels, error codes.
- **Key naming**: `featureScreenContext`, camelCase. Examples: `ledgerEmptyTitle`, `settleUpRecordPayment`, `groupSettingsLeaveAction`.
- **Interpolation / plurals**: ICU placeholders in ARB. Example:
  ```json
  "groupMemberCount": "{count, plural, =0{No members} =1{1 member} other{{count} members}}"
  ```
  Arabic plural rules (zero / one / two / few / many / other) handled by `intl`.
- **Tone**: formal MSA, declarative, terse. Numbers stay Western.
- **Review workflow**: Claude drafts `app_ar.arb` per PR2 batch; user spot-checks Arabic strings in PR comments before merge.

---

## RTL Audit Checklist

Concrete from grep over `lib/`:

| Pattern | Count | Action |
|---|---:|---|
| `Alignment.centerLeft` / `centerRight` | ~18 | Replace with `AlignmentDirectional.centerStart` / `centerEnd` |
| `EdgeInsets.only(left:/right:)` | 2 | Replace with `EdgeInsetsDirectional.only(start:/end:)` |
| `SlideTransition` with `Tween<Offset>` in `_sharedAxisTransition` | 3 | Wrap tween offsets with `Directionality.of(context)` check; invert X in RTL |
| `Icons.chevron_right` (dead `EventCommandCenter`) | 1 | Use directional pair or skip (dead code) |
| `LoadingButton` shimmer gradient (`centerLeft → centerRight`) | 1 | Cosmetic — flip via `Directionality` in PR3 |
| `RouteMark` canvas with fixed `Offset(146, 60)` | 1 | Mirror via `canvas.scale(-1, 1, dx: size.width)` in RTL |

Custom widgets requiring manual eyeball pass (rendered in Arabic context across all consumers): `RAmount`, `RAvatar`, `LedgerRosterStrip`, `LedgerHeroStatement`, `LedgerHeroBlock`, `SmartModuleCard`, `OfflineBanner`, `WordmarkLogo`, `DotStepIndicator` (verify it stays LTR — sequential progress conventionally LTR even in Arabic UI).

---

## Number / Currency / Date Formatting

- **Numerals**: Western in both locales. `NumberFormat('#,##0.000', 'en')` for OMR money in Arabic UI — preserves Geist Mono tabular alignment.
- **Currency**: `OMR 12.500` prefix preserved in Arabic — banking convention (Bank Muscat, NBO). String flips naturally via `Directionality`.
- **Dates**: `DateFormat.yMMMd(localeCode).format(date)` → `15 May 2026` / `15 مايو 2026`. Firestore stays Gregorian `Timestamp` — no data-layer change.
- **Relative time** (`"2 days ago"`): `intl` with `localeCode` parameter, or `timeago` package's `ar` locale.

---

## Staged Rollout

### PR1 — Foundation + Settings + Ledger

The bedrock — must be solid before anything else lands.

1. Add `flutter_localizations` + `generate: true` to `pubspec.yaml`
2. `l10n.yaml` at repo root, `lib/l10n/app_en.arb` + `app_ar.arb` skeleton with Settings + Ledger keys
3. `AppSettings.localeCode` field + SharedPreferences migration
4. `LanguageSettingsTile` in Profile/Settings
5. `MaterialApp` wiring (`locale`, `localizationsDelegates`, `supportedLocales`)
6. **Router `_sharedAxisTransition` RTL flip** — affects every navigation, must land here
7. `WordmarkLogo` swap to "رحلة" when locale is Arabic
8. Translate Settings + Profile + Ledger module (LedgerScreen, AddExpenseScreen, EditExpenseScreen, SettleUpScreen)
9. RTL audit for these screens — flip all directional primitives

**Outcome**: Arabic toggle works; Settings + Profile + Ledger render correctly in Arabic; other screens remain hardcoded-English but don't crash.

### PR2 — Groups + Events + Home + Activity

Translate and RTL-audit:
- GroupDetailScreen, GroupSettingsScreen, GroupSettleUpScreen, GroupActivityScreen
- EventTypePickerScreen, CreateEventScreen, EventSettingsScreen
- HomeScreen, CrossGroupActivityScreen, ActivityFeedScreen
- EmptyStateView shared variants

Cross-check shared widgets (`RAmount`, `RAvatar`, `LedgerRosterStrip`, `SmartModuleCard`, `OfflineBanner`) across all consumers.

### PR3 — Polish + Edge Cases

- `RouteMark` canvas mirror (`canvas.scale(-1, 1, dx: size.width)`)
- `LoadingButton` shimmer gradient direction
- `DotStepIndicator` LTR verification
- `chevron_right` icon decision (dead code — leave or fix)
- Final manual RTL spot-check on physical Android device
- Update `CLAUDE.md` "Do" rules with `EdgeInsetsDirectional` / `AlignmentDirectional` defaults so future code lands directional by default

---

## Testing

### Existing tests — minimize churn

Add a test helper that boots `MaterialApp` with `localizationsDelegates: AppLocalizations.localizationsDelegates` and forces locale to `'en'`. Existing widget tests asserting `find.text('Add expense')` keep working unchanged via the English ARB.

### New tests

- **Locale switching integration test**: boot app in `en`, assert known English string, write `'ar'` to `settingsProvider`, pump, assert Arabic string.
- **AppSettings.localeCode unit tests**: SharedPreferences migration, default, persistence.
- **LanguageSettingsTile widget tests**: radio selection writes via provider.
- **RTL widget tests**: wrap target screens in `Directionality(textDirection: TextDirection.rtl)`; assert via finder positions, not pixel coordinates.
- **Goldens**: skip Arabic (macOS-only, already CI-excluded). Manual visual QA on Android emulator with system locale `ar`.

### Coverage gate

Each PR keeps raw coverage ≥ 70% (current CI gate). New tests for locale provider + LanguageSettingsTile + AppSettings migration fill the gap from extracted-string assertions.

### Pre-merge

- `flutter analyze` clean
- `tool/check_no_hardcoded_colors.dart` passes
- `flutter test` passes
- Manual RTL spot-check screenshot in PR description

---

## Known Cuts (Tracked as Post-Launch Follow-ups)

Add to `docs/PRODUCTION-READINESS.md`:

- **Onboarding 3-page flow**: English-only. Acceptable — runs before user can toggle.
- **Recover / LinkEmail flows**: English-only. **Known inconsistency** for Arabic-toggled users who hit account recovery. Flag prominently; address in follow-up if it trips real users.
- **Play Store listing**: English-only. No Arabic title, description, or screenshots.
- **Legal pages** (`rihla-safar.web.app/privacy`, `/terms`, `/delete-data`): English-only web pages.
- **Eastern Arabic numerals** (`١٢٣٤`): not in scope.
- **Hijri calendar**: not in scope.

Add **RD-09** row to `docs/REAL-DEVICE-QA.md` covering Arabic RTL pass on a physical Android device before each PR merge.

---

## Open Questions for Implementation Plan

- Where exactly does `context.l10n` extension live? (`lib/core/extensions/build_context_l10n.dart` follows current naming.)
- Helper API for test boot: extend existing `test/helpers/` boot helper, or new `test/helpers/l10n_test_helper.dart`?
- ARB key namespacing: flat (`ledgerEmptyTitle`) vs nested (`ledger.empty.title`) — gen_l10n supports flat only, so flat.
- Should `LanguageSettingsTile` show "English / العربية" or "English / Arabic"? (Recommend native — `English / العربية`.)

These get resolved in the implementation plan (`writing-plans` skill, next step).

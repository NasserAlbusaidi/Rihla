# Group Currency (v1.2)

| | |
|---|---|
| **Status** | Historical spec snapshot; implementation has since shipped and evolved |
| **Target release** | v1.2 (Android-only Play Store launch) |
| **Author** | Nasser Albusaidi |
| **Created** | 2026-05-16 |
| **Supersedes** | The non-interactive `_ReadOnlyCurrencyField` placeholder on the create-group screen |
| **Followed by** | Multi-currency shipped in #382; FX remains out of scope |

> **Post-#50 / #61 / #382 update:** This is a historical design spec. The custom
> SQLite cache, onboarding flow, and profile/global currency picker were removed,
> and the shipped app now uses Firestore SDK persistence plus per-currency
> balance buckets. Sections 5-10 are the original planning record, not current
> implementation guidance; verify current behavior against live code.

## 1. Historical Problem

Historical state before the #61/#382 implementation: currency was half-wired.
This section records the pre-implementation diagnosis; it is not current live
behavior.

- `MoneySerializer` (per-currency subunit scaling), `AppFormatters.currencyConfig` (symbols + decimals), `AppSettings.currencyCode` (user preference), `CurrencyPickerSheet` (settings-side bottom sheet), `GroupModel.currency`, `ExpenseModel.currency`, `groupServiceProvider.createGroup(currency:)` — all built and tested.

At that point, the wires were not connected:

1. `create_group_screen.dart` had a read-only default-currency row with no tap target, no chevron, and smaller visual weight than sibling text fields.
2. Group creation did not yet thread the selected currency into `createGroup`.
3. The expense editor did not yet read the group/default expense currency.
4. Settlement write paths did not yet preserve their stored currency.

Historical user-visible effect: every group was OMR. The Profile currency picker
changed a value the rest of the app ignored; there is no global profile currency
picker in the shipped app.

Secondary problem: the existing `CurrencyPickerSheet` uses Material `RadioListTile`, which collides visually with the warm-paper, underline-input wireframe aesthetic of the create-group screen.

## 2. Goal

A user creating a new group picks one of the supported currencies. That currency is permanent for the lifetime of the group. New expenses default from it, settlements carry the selected balance bucket currency, and money surfaces render per-currency buckets with native precision and no FX conversion.

The shipped create-group picker defaults to OMR or a pending create intent's
currency; it does not read or write a global profile currency preference.

## 3. Non-goals

- **No mid-life currency change.** Once a group is created, currency is read-only. Enforced in both UI AND `firestore.rules` (see §7.1).
- **No FX conversion.** No rates, no display-currency preference. Deferred to v2.0.
- **Historical v1.2 constraint:** the original rollout scoped to group-default
  currency. The shipped #382 flow now allows per-expense supported currency
  codes and buckets balances per currency.
- **Historical picker scope:** the original spec proposed a six-currency
  display list. The shipped picker now uses the canonical GCC-first
  `kSupportedCurrencies` list, aligned with `MoneySerializer` and
  `AppFormatters`.
- **Historical display audit scope.** Codex audit (2026-05-16) flagged home/profile stats, the event settle-up screen, `RAmount` decimal handling, and shared amount widgets as separate display-audit surfaces. The shipped app now renders core money surfaces per currency; remaining literal OMR fallbacks must be documented empty/default states.

## 4. Why "lock at creation"

We considered allowing currency edits on existing groups, with the user-facing promise *"only the symbol changes, not the numbers."* Three walls killed that:

1. **`MoneySerializer` is per-currency.** OMR 10.500 stored as 10500 fils would re-decode as USD 105.00 if we just flipped `group.currency`. Honoring the symbol-only promise requires re-stamping every `expense.amountFils` and `settlement.amountFils` to the new currency's scale.
2. **Historical Firestore rules blocked client-side rewrites.**
   - Pre-open-edit rules gated expense updates on `requesterIsRecordCreator()`,
     so the actor changing the group currency could not rewrite expenses
     authored by anyone else. Current rules use the open-edit
     `isEventParticipant` branch for expense edits, so this line is rationale
     provenance rather than live authorization guidance.
   - Group-scoped settlements are total `allow update: if false;` (B3 append-only).
   - Event-scoped settlements allow updates only to `['note', 'isDeleted', 'deletedAt']` — `currency` is not in the allowlist.
3. **Server-side rewrite would need a Cloud Function.** Achievable but adds a callable, emulator tests, and a deploy step — surface area we're not adding to v1.2.

Locking at creation eliminates all three. Post-launch FX (v2.0) is the proper home for currency flexibility, and per-expense currency stamping is already in the model so that future work isn't blocked.

## 5. Historical User Scenarios

The first rollout scenarios below have been reconciled with the shipped model:
there is no profile/global currency picker, and create-group currency state is
local to the form unless restored from a pending create intent.

### 5.1 Primary: First-time group creator

1. User taps "Create group" from Home.
2. Form shows: Mood block → Glyph row → Group name → Your name in this group → **Default currency** (interactive) → Creator preview card.
3. Currency field shows OMR by default, or the pending create intent's currency
   after a gate restart. Tap target is the full row, with a chevron (`›`) on
   the right.
4. Tap → bottom sheet opens with the supported currency list. Current default is preselected.
5. User picks one. Sheet dismisses with light haptic.
6. Field updates to show the new selection. Sheet does **not** modify
   `AppSettings.currencyCode`; the legacy profile/global preference is removed
   from the UI.
7. User taps Create. Group is created with the chosen currency. New expenses
   default from it, expenses may carry a supported picked currency, and
   settlements record the selected balance bucket currency.

### 5.2 Repeat creator with a non-default preference

1. Historical-only: the original plan allowed a Profile default currency
   preference.
2. Shipped behavior: creating a group starts from OMR unless a pending create
   intent supplies a supported currency.
3. There is no profile/global default-currency picker in the shipped app.

### 5.3 Group settings: viewing currency

1. User opens an existing group → Settings.
2. The Defaults section shows a "Currency" row with the locked value (e.g., `OMR · ر.ع.`) and **no tap affordance** — no chevron, no inkwell.
3. Below the row, a single muted line: *"Set when the group was created. Create a new group to use a different currency."*
4. No edit path exists.

### 5.4 Edge: legacy group from before this feature

1. Every existing pre-launch group has `currency: 'OMR'` (verified — the field has always been written).
2. No migration. Behavior unchanged for these groups.

## 6. Visual Design

### 6.1 Field on create-group screen

Replace `_ReadOnlyCurrencyField` with an interactive row that matches the dimensions and rhythm of `_WireframeTextField`.

```
DEFAULT CURRENCY
─────────────────────────────────────────────
ر.ع.   Omani rial · OMR                    ›
─────────────────────────────────────────────
```

**Specs (token-mapped):**

- Container: full-width row, `padding: vertical 16dp`, bottom border `colors.ink2` (matches text-field underline). Total height ~49dp meets the Material/HIG 48dp touch-target minimum. Text fields above keep their 12dp padding because their hit zone is implicit through the focus/keyboard contract, but a tap-only row needs the larger hitbox.
- Label: `_FieldLabel('Default currency')` — same 11pt SemiBold caps, `letterSpacing: 0.8`, `colors.textSecondary`
- Row content: horizontal `Row` —
  - Symbol on the left (e.g., `ر.ع.`, `$`, `€`), `AppTypography.sans(fontSize: 17, color: colors.textPrimary)`, fixed-ish width slot ~36dp so the name aligns across selections
  - Name + code: `Omani rial · OMR`, `AppTypography.sans(fontSize: 17, color: colors.textPrimary)`, takes remaining space
  - Trailing chevron `Iconsax.arrow_right_3` 16dp, `colors.textMuted`
- Tap target: full row via `InkWell` with rounded splash, `BorderRadius.circular(8)` (visual ripple only — keep underline rigid)
- Pressed/focused state: chevron tints to `colors.textPrimary`; no underline color change (the underline is the field, not a focus indicator here)
- Disabled state: not used in v1.2 (always enabled on create form)
- Focus order on form mount: request focus on the Group Name field. The currency row is a tap target with a sensible default and does not need keyboard focus.

**Why these specs:** The text fields above use 17pt body and 12dp vertical padding with an underline border. Matching those dimensions makes the currency row feel like a peer field instead of a footnote, which fixes the "picker is so small compared to other fields" complaint. The 16dp vertical padding here (vs 12dp on the text fields) is a deliberate exception to meet the 48dp touch-target minimum for a tap-only row.

### 6.2 Bottom sheet (redesigned)

Replace the `RadioListTile`-based sheet with a warm-paper sheet matching the create-group screen's aesthetic. Reuse for Profile → Settings as well (single sheet, two callsites).

```
┌─────────────────────────────────────────┐
│                                          │
│  Currency                                │
│  Lock in the currency for this group.    │
│  This can't be changed later.            │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │ ر.ع.   Omani rial             OMR ●│  │  ← selected (filled dot)
│  ├────────────────────────────────────┤  │
│  │ د.إ    UAE dirham             AED ○│  │
│  ├────────────────────────────────────┤  │
│  │ ر.س    Saudi riyal            SAR ○│  │
│  ├────────────────────────────────────┤  │
│  │ $      US dollar              USD ○│  │
│  ├────────────────────────────────────┤  │
│  │ €      Euro                   EUR ○│  │
│  ├────────────────────────────────────┤  │
│  │ £      British pound          GBP ○│  │
│  └────────────────────────────────────┘  │
│                                          │
└──────────────────────────────────────────┘
```

**Specs:**

- Sheet container: `colors.cardSurface` (paper warm), top corners `Radius.circular(28)` matching the existing `_SharePrompt` sheet on the same screen
- Padding: `EdgeInsets.fromLTRB(24, 20, 24, 24)`
- Title: `'Currency'` — `AppTypography.display(fontSize: 24, color: colors.textPrimary)`
- Subtitle: 2 lines —
  - Create-group context: *"Lock in the currency for this group. This can't be changed later."*
  - Profile-settings context: *"Default for new groups. Existing groups keep their currency."*
  - 13pt, `colors.textSecondary`, `height: 1.5`
- Selectable rows: stacked `InkWell`s inside a rounded `Container` (`colors.cardSoft`, `BorderRadius.circular(20)`, border `colors.rule2`), thin `colors.rule2` dividers between rows
  - Row height: 56dp (comfortable touch target, exceeds 48dp minimum)
  - Symbol: 17pt, fixed 40dp leading slot, `colors.textPrimary`. Font handling per currency:
    - **OMR, SAR, AED**: use the recently-introduced single-glyph Unicode currency signs (Saudi Riyal `U+20C0`, UAE Dirham `U+20C2`, Omani Rial — verify codepoint at implementation; fall back to `ر.ع.` if no clean glyph exists). These render with reasonable consistency in Latin-family fonts including Geist.
    - **USD, EUR, GBP**: native Geist rendering of `$`, `€`, `£` — no special handling.
    - **Fallback**: if Geist fails to render any chosen symbol cleanly, wrap that specific symbol in a `TextSpan` with `Noto Naskh Arabic` (via `google_fonts`) sized to match Geist's x-height at 17pt (~ 19pt Naskh). Implementer's call per symbol; do not apply blanket Naskh.
  - Name: 15pt, `colors.textPrimary`
  - Code: 13pt, `colors.textMuted`, right-aligned
  - Selection indicator: 16dp circle on the far right — filled `colors.textPrimary` for selected, hollow `colors.ink2` for unselected (no Material radio chrome)
- Tap → light haptic (`HapticService.selection()`) → row visual selection updates → sheet auto-dismisses after 120ms (perceptible confirm, not jarring)
- **Accessibility**: each row is wrapped in `Semantics(inMutuallyExclusiveGroup: true, selected: isSelected, button: true, label: '$name, $code')`. The custom dot stays visual-only — TalkBack/VoiceOver get the radio-group semantics from the `Semantics` widget, not from any Material chrome.
- **Field row** (§6.1): also wrap the `InkWell` in `Semantics(button: true, label: 'Default currency, currently $name')` so the entry point reads correctly.
- **Directionality**: app is English-only in v1.2, but Arabic localization is on the roadmap for the GCC market. Spec the row content as `Row(textDirection: TextDirection.ltr, children: [symbol, name + code, dot])` to lock the visual order regardless of ambient direction. Currency codes (USD, OMR, AED) read LTR universally; flipping them in an Arabic UI would feel wrong. The sheet chrome (title, subtitle, padding) inherits ambient `Directionality` so RTL users get a properly mirrored container around an LTR-ordered row list. Same primitive applies to the field row in §6.1.
- **Backdrop tap behavior**: tapping outside the sheet dismisses it without changing the field value. This is `showModalBottomSheet` default — call it out explicitly because users panic-tap to escape and shouldn't lose their previous selection.
- **Auto-scroll to selection on open**: when the sheet opens, scroll the currently-selected row into view (light animation). Trivial today with 6 currencies; defensive for if the list ever grows.

### 6.3 Group settings: read-only currency row

Inside `_DefaultsSection`, the currency tile becomes:

- No `InkWell`, no `GestureDetector`, no chevron — purely informational. A tap on the row does nothing (no haptic, no snackbar, no sheet). The visual signals (absent chevron, lock icon, footer line) carry the meaning; we trust the vocabulary.
- Same row layout as before (`_DefaultsRow` with `title: 'Currency'`, `value: group.currency`) but with a small lock affordance: trailing `Iconsax.lock` 14dp at `colors.textMuted` (subtle, not heavy)
- Below the Defaults section, append a single muted footer line (12pt, `colors.textMuted`): *"Currency is set when the group is created. Create a new group to use a different currency."*

Keeping the visual presence of the row preserves discoverability ("yes, this group is in OMR"); the lock icon + footer line preempts the "why can't I tap this?" question.

## 7. Historical Implementation Plan

This table is the original May 2026 implementation plan. It is retained as
design provenance; obsolete rows and superseded equality assumptions are not
current guidance.

### 7.1 File changes

| File | Change |
|---|---|
| `lib/core/models/supported_currency.dart` (new) | New `enum SupportedCurrency { omr, aed, sar, usd, eur, gbp }` carrying `{ code, displayName, symbol, decimals, subunitScale }`. Single source of truth for display-supported currencies. `MoneySerializer._currencyScale` can stay broader (keeps KWD/BHD/QAR/JPY round-trip safety for legacy data) but the picker, formatter, and any new display logic derive from this enum. `AppFormatters.currencyConfig` reads from the enum; `CurrencyPickerSheet` iterates it. |
| `lib/features/groups/screens/create_group_screen.dart` | Replace `_ReadOnlyCurrencyField` with new `_CurrencyField` (interactive row spec'd in §6.1). Hold selected `SupportedCurrency` in `_CreateGroupScreenState` (initial = `SupportedCurrency.fromCode(settingsProvider.currencyCode)`). Pass `.code` to `createGroup(currency: _selectedCurrency.code)`. |
| `lib/features/settings/widgets/currency_picker_sheet.dart` | Rewrite UI per §6.2 (drop `RadioListTile`, build with paper-styled rows). Add a static `pick(BuildContext, {required String current})` returning `Future<String?>` for the "pick a value, don't persist" callsite. Keep the existing `show(context)` entry point that writes to `AppSettings` for Profile. Both entry points share the same row widget. |
| `lib/features/ledger/widgets/expense_editor_body.dart` | Inside the widget, `ref.watch(groupDetailProvider(widget.groupId))` and derive `_tripCurrency` from `group.currency` (handle AsyncValue via `valueOrNull` with a guarded fallback to a loading state — do NOT default to 'OMR'). No constructor change. Rename `_tripCurrency` → `_groupCurrency` while touching it (legacy "trip" naming). |
| `lib/features/ledger/models/settlement_model.dart` | Add `currency` as a required field on the `Settlement` model. `fromFirestore` reads `data['currency']`; `toFirestore` writes `this.currency` (drop `const currency = 'OMR'`). |
| `lib/features/ledger/services/settlement_service.dart` | Drop the `String currency = 'OMR'` default on `addSettlement`; make it required. |
| `lib/features/groups/services/group_settlement_service.dart` | Drop the `String currency = 'OMR'` default; make it required. Same shape as the ledger-scoped service. |
| `lib/features/ledger/screens/settle_up_screen.dart` | Record the selected balance bucket currency in `addSettlement(currency: ...)`; the group default is only the empty-ledger fallback bucket. |
| `lib/features/groups/screens/group_settings_screen.dart` | Apply §6.3 — drop tap handling on the currency tile (it has none today, but add the lock icon + footer line). |
| `security/firestore.rules` | Tighten `validCurrency(value)` from `value is string && value.size() == 3` to an explicit allowlist of supported storage/display currencies. Keep group `currency` write-once-on-create; money docs carry supported currency codes and are no longer forced to equal the parent group's default. |
| `lib/core/services/cache/settlement_cache_repository.dart` | **Obsolete:** custom SQLite cache removed in #50; Firestore SDK persistence owns offline reads/writes. |
| `lib/core/services/local_database.dart` | **Obsolete:** custom SQLite cache removed in #50; no local DB currency migration exists. |
| `lib/features/onboarding/screens/onboarding_screen.dart` | **Obsolete:** onboarding route/screen removed in #56. |
| `lib/features/ledger/widgets/expense_editor_body.dart` (additions) | **Add `currency` field to `ExpenseEditorPayload`** so editor packages its currency knowledge in the payload. **Add mode**: `await ref.read(groupDetailProvider(widget.groupId).future)` once in `initState` (or guard render until loaded) — no live re-format on currency change mid-edit. **Edit mode**: `_groupCurrency = widget.initial!.currency` (preserve original expense currency, do not silently re-stamp from group). Log a warning if `initial.currency != group.currency`. |
| `lib/features/ledger/screens/add_expense_screen.dart` | Pass `payload.currency` through to the `Expense` constructor on write (no longer hardcode group lookup at the write site). |
| `lib/features/ledger/screens/edit_expense_screen.dart` | Same — pass `payload.currency` through. The editor preserves `initial.currency`, so this happens automatically. |
| `test/unit/supported_currency_test.dart` (new) | Unit test for the new enum: each value's code/displayName/symbol/decimals/subunitScale; `SupportedCurrency.fromCode('OMR')` works; `fromCode('XYZ')` returns null or throws. |
| `test/unit/balance_calculations_test.dart` | Parameterize across all 6 currencies. Assert `MoneySerializer` round-trips correctly and the formatted output uses the right symbol + decimal precision. |
| `test/unit/settlement_model_test.dart` (modify or new) | `Settlement(currency: 'EUR').toFirestore()` writes `currency: 'EUR'` and `amountFils` scaled to EUR. `fromFirestore` round-trip preserves currency. `fromMap` (cache) round-trip preserves currency. Parameterized across 6 currencies. |
| `test/features/ledger/settlement_service_test.dart` (modify or new) | `addSettlement(currency: 'GBP', ...)` writes a Firestore doc with `currency: 'GBP'` and correctly-scaled `amountFils`. Test fails compile if `currency` becomes optional again. |
| `test/features/groups/group_settlement_service_test.dart` (modify or new) | Same as above for group-scoped settlements. |
| `test/features/ledger/expense_editor_currency_test.dart` (new) | Pump `ExpenseEditorBody` with a group whose `currency='SAR'`; assert the amount field's decimal mask matches SAR (2 decimals); assert displayed prefix is SAR symbol. Pump with a `Decimal` input + tap submit; assert `payload.currency == 'SAR'`. |
| `test/features/ledger/settle_up_screen_currency_test.dart` (new) | Pump settle-up screen for a group with `currency='AED'`; trigger settlement; assert captured `addSettlement` call has `currency: 'AED'`. |
| `test/features/groups/create_group_currency_test.dart` (new) | Render `CreateGroupScreen` with `AppSettings.currencyCode = 'USD'`. Assertions: (a) field shows USD by default, (b) tap → sheet opens, (c) pick AED → field updates, (d) tap Create → captured `createGroup` has `currency: 'AED'`, (e) form mounts with `_nameController.focusNode.hasFocus == true`, (f) field row hit-test rect height ≥ 48dp. |
| `test/features/settings/currency_picker_sheet_test.dart` (new or modify) | Sheet behavior tests: (a) **Semantics** — each row exposes `Semantics(inMutuallyExclusiveGroup, selected, button, label)`; verifiable via `tester.getSemantics(find.byType(...))`. (b) **Auto-scroll** — open sheet with `current='GBP'`, assert GBP row is in viewport. (c) **Backdrop dismiss** — open sheet, tap outside, assert `Future` resolves to `null` (field caller keeps previous value). (d) **REGRESSION: Profile show()** — invoking `CurrencyPickerSheet.show(context)` and selecting still writes to `AppSettings.currencyCode`. (e) **RTL** — wrap in `Directionality(textDirection: TextDirection.rtl)`; assert symbol/name/code visual order unchanged via geometry assertions. |
| `test/features/groups/group_settings_currency_lock_test.dart` (new) | Render `GroupSettingsScreen` for a group with `currency='OMR'`. Assertions: (a) currency tile shows 'OMR', (b) `Iconsax.lock` icon present in the row, (c) footer line text present below Defaults section, (d) tap on the row produces no callback / no navigation / no haptic. |

### 7.2 Out of scope for this PR

- No Cloud Functions.
- No new currencies.
- No changes to `MoneySerializer._currencyScale` (the broader 10-currency storage map stays for legacy round-trip safety).
- No changes to `GroupModel` (currency field already exists; the rule changes lock writes).
- Historical note: OMR-hardcoded display widgets outside the original
  wire-through path were later audited into per-currency bucket displays or
  documented empty/default fallbacks.

### 7.3 Newly in scope (from eng-review + Codex challenge)

- Historical rules change: `validCurrency` allowlist + group-currency
  immutability. The shipped #382 PRs later relaxed money-doc currency equality:
  expenses and settlements need a supported currency code, not equality with
  `group.currency`.
- Settlement cache write bug fix (pre-existing, exposed by this PR).
- SQLite schema v8 → v9 migration for the new `currency` column on settlements.
- Onboarding currency list consolidation into the new `SupportedCurrency` enum.
- `ExpenseEditorPayload` carries currency.
- Edit-mode preserves `initial.currency`; add-mode load-once-and-block.

## 8. Risks & Open Questions

- **Risk: copy ambiguity.** The picker says *"This can't be changed later"* — clear, but a user who picks wrong on creation has no recourse other than recreating the group. Acceptable for v1.2 (a freshly-created group has no expenses to lose); revisit when v2.0 ships FX.
- **Risk: settings-picker confusion.** The Profile picker says *"Default for new groups. Existing groups keep their currency."* — this is now literally true (it pre-fills the create-group field). Verify the copy holds after rewrite.
- **Obsolete risk: SQLite migration v8 → v9.** The custom SQLite cache was
  removed in #50; Firestore SDK persistence owns offline reads/writes.
- **Risk: Rules tightening could break existing client builds in the wild.** If any user is on an older client that writes settlements without a `currency` field, the new rule rejects the write. Pre-launch app, no live users, so this is theoretical — but verify with `firebase emulators` rules tests before deploying.
- **Risk: Unicode currency-sign rendering** is an implementation-time check, not a spec-time decision. Implementer must verify Saudi/UAE/Omani Unicode signs render in Geist on both Android + iOS device fleet before locking the chosen codepoints. If Geist doesn't render them cleanly, fall back to the Arabic abbreviations (`ر.ع.`, `د.إ`, `ر.س`) wrapped in `Noto Naskh Arabic` TextSpan per §6.2.
- **Risk: Asymmetry between MoneySerializer storage (10 currencies) and display (6) is deliberate** but a footgun if someone adds a 7th display currency without updating MoneySerializer's scale map, or vice versa. Mitigated by `SupportedCurrency` enum being the new single source of truth for display; storage map stays broader for legacy round-trip.
- **Open question (deferred): Do we expand the picker list before launch?** Defer — the GCC-focused list is intentional.
- **Open question (deferred): Should the sheet show a "currency in use by N of your groups" hint per row in the Profile context?** Possibly nice for v2.0 alongside FX. Out of scope here.

### 8.1 Historical Follow-up Audit Notes

Codex challenge (2026-05-16) surfaced these adjacent issues. Later PRs landed or
narrowed several of them; treat this list as audit provenance, not an open
release checklist.

1. **`RAmount` widget decimal handling** — now currency-driven (`MoneySerializer` / `AppFormatters`); keep JPY=0 and OMR/KWD/BHD=3 covered by tests.
2. **Hardcoded OMR in home/profile stats** — core balance surfaces now render per-currency buckets. Any remaining literal OMR fallback must be a documented empty/default state, not a cross-currency total.
3. **Shared amount widgets** — anything using `AppFormatters.currencyConfig` with a default to OMR must be audited before it reaches a non-empty money value.
4. **Picker auto-scroll-to-selected** — Codex argues this is overkill for 6 currencies and adds controller/key lifecycle complexity. Keep the spec'd implementation for forward-looking polish, but flag for removal if it complicates the sheet rewrite.
5. **`MoneySerializer._currencyScale` rename** — consider splitting into `StorageCurrency` (10 codes) vs `DisplayCurrency` (6 codes via `SupportedCurrency`) to make the asymmetry explicit in type signatures, not just in code comments.

## 9. Historical Done Criteria

Original acceptance checklist from the v1.2 design pass. It is intentionally
not a current issue checklist.

- [ ] Create-group form shows an interactive currency field matching the visual spec (§6.1) with 16dp vertical padding meeting the 48dp touch-target minimum.
- [ ] Field defaults to OMR or the pending create intent's currency; picker dismissal updates the field but doesn't write a global profile preference.
- [ ] Tapping the row opens the redesigned sheet (§6.2). Picking a currency updates the field and dismisses the sheet.
- [ ] Sheet rows wrapped in `Semantics(inMutuallyExclusiveGroup, selected, button, label)`; field row wrapped in `Semantics(button, label: 'Default currency, currently $name')`.
- [ ] Sheet rows use `Row(textDirection: TextDirection.ltr, ...)` for symbol/name/code order. Sheet chrome inherits ambient `Directionality`.
- [ ] Sheet auto-scrolls to the currently-selected row on open. Backdrop tap dismisses without changing the field value.
- [ ] Currency symbol rendering: OMR/SAR/AED use the recently-introduced single-glyph Unicode signs; USD/EUR/GBP use Geist native; fallback path to `Noto Naskh Arabic via TextSpan` documented if any chosen symbol fails to render cleanly.
- [ ] Create-group form auto-focuses the Group Name field on mount.
- [ ] Creating the group persists `currency` correctly; new expenses default from it, while settlements record the selected balance bucket currency.
- [ ] Group settings shows currency as locked (lock icon + footer line, no `InkWell`, no `GestureDetector`, taps are silent).
- [ ] Write paths no longer pin the default currency; any remaining OMR literal is an empty/default fallback with local justification.
- [ ] `flutter analyze` clean.
- [ ] New widget test covers the pick + create flow; existing balance/serialization tests parameterized across six currencies.
- [ ] Manual TalkBack/VoiceOver pass on the picker sheet confirms each row announces its selection state.
- [ ] `firestore.rules` updated: `validCurrency` allowlist enforced; group `currency` not in update allowlist; money docs carry supported currency codes. Emulator tests pass.
- [ ] Firestore offline persistence preserves queued non-OMR money writes; no custom SQLite cache or migration exists.
- [ ] Settlement write/read paths preserve their stored currency.
- [ ] No onboarding currency choices remain; onboarding was removed in #56.
- [ ] `ExpenseEditorPayload` carries `currency`; add mode awaits group future before render; edit mode preserves `initial.currency`.
- [ ] No regression in existing currency tests.

## 10. Historical Implementation Tasks

Original atomic tasks from the design pass. Current work should derive from live
code and the active plan, not from these unchecked historical boxes. Sources:
D = design review, E = eng review, X = Codex cross-model challenge.

**Foundation (do first — other tasks depend on this):**

- [ ] **T9 (P1) [E]** — Create `lib/core/models/supported_currency.dart` with enum + accessors. Refactor `AppFormatters.currencyConfig` to derive from it. Unit test the enum.
- [ ] **T10 (P1) [E]** — Add `currency` as required field to `Settlement` model; update `fromFirestore` and `toFirestore`. Parameterized round-trip test across supported currencies.
- [ ] **T14 (obsolete) [X]** — Custom SQLite cache work removed by #50; no local DB migration exists.

**Rules (deploy gate — must merge with code):**

- [ ] **T13 (P1) [X]** — `security/firestore.rules`: tighten `validCurrency` to explicit allowlist; remove `currency` from `groups/{gid}` update allowlist; money docs must carry supported currency codes. Emulator rules tests (Java 21 + jest in `functions/`).

**Wire-through (core feature):**

- [ ] **T11 (P1) [E]** — `settlement_service.dart` + `group_settlement_service.dart`: drop `String currency = 'OMR'` defaults, make required.
- [ ] **T12 (P1) [E]** — `settle_up_screen.dart`: watch `groupDetailProvider(groupId)`, pass `group.currency` to `addSettlement`.
- [ ] **T16 (P1) [X]** — `expense_editor_body.dart` + `add_expense_screen.dart` + `edit_expense_screen.dart`: add `currency` to `ExpenseEditorPayload`. Add mode uses the picked currency/default; edit mode preserves `initial.currency`.
- [ ] **T15 (obsolete) [X]** — onboarding was removed in #56.

**UI (design review decisions):**

- [ ] **T1 (P1) [D]** — `currency_picker_sheet.dart`: wrap each row in `Semantics(inMutuallyExclusiveGroup, selected, button, label)`.
- [ ] **T2 (P1) [D]** — `create_group_screen.dart`: new `_CurrencyField` widget, 16dp padding (48dp touch target), `Semantics(button, label)` on InkWell.
- [ ] **T3 (P1) [D]** — Picker sheet + `_CurrencyField`: `Row(textDirection: TextDirection.ltr, ...)` for symbol/name/code.
- [ ] **T4 (P2) [D]** — Symbol rendering: new Unicode signs for OMR/SAR/AED (verify codepoints at impl), Geist native for USD/EUR/GBP, `TextSpan + Noto Naskh` fallback per symbol.
- [ ] **T5 (P2) [D]** — Picker sheet: auto-scroll selected row into view on open via `Scrollable.ensureVisible`.
- [ ] **T6 (P2) [D]** — Create-group form: `FocusNode` on Group Name, `requestFocus` in `initState`.
- [ ] **T7 (P2) [D]** — `group_settings_screen.dart`: lock icon + footer line, no `InkWell` on currency row.
- [ ] **T8 (P3) [D]** — Code comment in `currency_picker_sheet.dart` for the backdrop-tap-preserves-value contract.

**Tests (boil-the-lake — all 19 paths):**

- [ ] **T20 (P1)** — `test/unit/supported_currency_test.dart` (new)
- [ ] **T21 (P1)** — `test/unit/settlement_model_test.dart` (new/modify) — parameterized 6-currency round-trip
- [ ] **T22 (P1)** — `test/unit/balance_calculations_test.dart` — parameterized 6-currency
- [ ] **T23 (P1)** — `test/features/ledger/settlement_service_test.dart`
- [ ] **T24 (P1)** — `test/features/groups/group_settlement_service_test.dart`
- [ ] **T25 (P1)** — `test/features/ledger/expense_editor_currency_test.dart` (add + edit mode, mismatch logging)
- [ ] **T26 (P1)** — `test/features/ledger/settle_up_screen_currency_test.dart`
- [ ] **T27 (P1)** — `test/features/groups/create_group_currency_test.dart` (field default, pick + create, focus, tap target)
- [ ] **T28 (P1)** — `test/features/settings/currency_picker_sheet_test.dart` (Semantics, auto-scroll, backdrop dismiss, profile-write regression, RTL)
- [ ] **T29 (P1)** — `test/features/groups/group_settings_currency_lock_test.dart`
- [ ] **T30 (P1)** — `functions/test/rules/currency.test.ts` (rules emulator tests for the three rule changes)
- [ ] **T31 (P1)** — `test/integration/settlement_cache_migration_test.dart` — populate v8 schema, migrate to v9, verify currency column populated for existing rows + new writes preserve currency.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | — |
| Codex Review | `/codex review` (plan challenge) | Independent 2nd opinion | 1 | ISSUES_FOUND→RESOLVED | 5 substantive findings, all integrated |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | CLEAR (PLAN) | 11 issues addressed, 3 critical gaps closed |
| Design Review | `/plan-design-review` | UI/UX gaps | 1 | CLEAR | score 7/10 → 9/10, 6 decisions added |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

**CODEX:** 5 substantive findings — rules don't enforce immutability/allowlist, settlement cache write omits currency (pre-existing bug), onboarding currency list missing SAR, ExpenseEditorPayload lacks currency field, edit-mode currency mismatch unspecified. All resolved in-spec via cross-model AskUserQuestion.

**CROSS-MODEL:** Strong agreement between Claude eng-review and Codex challenge on the architectural shape (Settlement model field, provider watch pattern, enum consolidation). Codex independently surfaced security/data-integrity issues Claude's eng-review missed at the wire-through level — the value of the second opinion. No unresolved tensions.

**UNRESOLVED:** 0 — all design-review (6), eng-review (11), and Codex-challenge (5) findings integrated into the spec.

**VERDICT:** DESIGN + ENG CLEARED — ready to implement. 31 atomic tasks queued in §10 (16 P1 wire-through + 12 P1 tests + 3 P2/P3 polish). 5 follow-up TODOs in §11 deferred to v1.3.

**Design review log:**
- Initial: 7/10 → Final: 9/10. Decisions: Arabic glyph rendering strategy, 48dp touch target, Semantics for custom controls, RTL primitive, settings-row silence, three handoff edges.

**Eng review log:**
- Step 0 — Scope: 8 files → proceeded as-is (minimum viable for the goal). Final file count: ~14 due to eng-review + Codex additions.
- Architecture: Settlement model gets required currency field; ExpenseEditorBody
  carries the picked expense currency; settle-up records the selected balance
  bucket currency.
- Code Quality: New `SupportedCurrency` enum consolidates 3 currency lists (picker, formatter, onboarding); `_tripCurrency` renamed.
- Tests: 19 untested paths identified, full boil-the-lake plan (12 test files).
- Performance: no issues.

**Codex challenge log (cross-model):**
- T1: Rules tightening — validCurrency allowlist + group lock + cross-doc equality.
- T2: Settlement cache write bug fix + SQLite v8→v9 migration.
- T3: Onboarding consume SupportedCurrency (SAR now appears).
- T4: ExpenseEditorPayload carries currency.
- T5: Edit-mode preserves initial.currency; add-mode load-once-block.

# #722 — Shareable recap card (PNG poster) · Slice 4 of #202

**Status:** signed-off design (mockup `docs/design/mockups/722-shareable-recap-card.html`), ready to build.
**Gate:** EXEMPT — pure display over `EventRecap`; no `BalanceCalculator`/`MoneySerializer`, no `firestore.rules`/Functions, no routing/back-guard, no schema field-name change with a write-path. Describable as a one-sentence diff per surface, but multi-file → this plan.

## Goal

A "wrapped" PNG poster of a closed/active event's recap, shared from the recap screen. Render a fixed-width card on-screen in a preview sheet, capture its `RepaintBoundary` at `pixelRatio 3` → 1080×1350, share via a new `shareImage()` chokepoint.

## Locked decisions (user sign-off 2026-06-30)

- Canvas **Portrait 4:5 / 1080×1350** (width fixed at 360 logical, height content-driven ≈ 450).
- Multi-currency → **primary-currency hero + note** (`+ £320 · OMR 85.500`), never cross-summed.
- **Full wrapped** content (Variant B), minus the people-avatar stack (overflowed 4:5; redundant with the People stat + top-spender avatar).

## Verified facts (re-checked against code, not memory)

1. `share_plus` resolved = **10.1.4** (pubspec.lock; the 12.0.1 in pub-cache is a stray). `shareXFiles(files, {subject,text,sharePositionOrigin,fileNameOverrides})` invokes method `'shareFiles'` with `paths`/`mimeTypes`/`originX..originHeight`.
2. `share_plus_platform_interface 5.0.2` `_getFile` writes an in-memory `XFile.fromData` to a temp file via `getTemporaryDirectory()` (it bundles `path_provider ^2.0.14`), naming it from `fileNameOverrides`. **So no `path_provider`/`dart:io` is added to the app.** `_mimeTypeForPath` resolves `image/png` from the `.png` temp name.
3. `share_helper.dart` already has the private `_shareOrigin(context)` non-zero-rect chokepoint (the #308/#309 trap). `shareImage` reuses it.
4. `RAmount(value, currency, size, showCurrency, sign, weight)` — tiered mono (ccy .42×@.78, whole 1×, dec .55×@.7), OMR=3dp via `AppFormatters.currencyConfig`.
5. `CoverArt(palette: CoverPalette.forEventType(event.type))` — procedural, any size. `EventType{trip,camping,travel,nightDayOut,custom}`.
6. `sortedGccFirst(Iterable<String>)`, `categoryNameForId(id,l10n)`, `categoryColorForId(colors,id)` — the same helpers the recap screen uses.
7. `formatShortMonthDayYear`/`formatDateRangeShort` exist; need a `formatMonthYear` (new, small, in `localized_dates.dart`) for the `· MAR 2026` caption.
8. Recap screen already has `recap` (`EventRecap`), `view.rosterDisplayNames` (`Map<String,String>`), `uid`, and `event` (`Event`, carries `.type`/`startDate`/`endDate`). The share entry point has everything it needs in scope.
9. `EventRecap` fields enumerated from the type: `totalSpentByCurrency`, `participantCount`, `expenseCount`, `payerTotalsByCurrency`, `biggestExpenseByCurrency`, `categoryTotalsByCurrency`, `participantNetsByCurrency`, `isSettledByCurrency`, `startDate`, `endDate`, `eventName`, `isEmpty`.

## Verification principles (run now)

1. **Callsite classification** — every money value on the card is **INBOUND** (display). The PNG goes to other apps but never re-enters Firestore or any balance computation. No OUTBOUND/BOTH callsite. ⇒ no money invariant at risk.
2. **Claims vs code** — every path/symbol above re-grepped this session (share_plus version, method name, helpers, EventRecap fields, EventType, date/currency helpers).
3. **One read-path per write-path** — there is **no write-path**. The card reads `EventRecap` (already-correct `BalanceCalculator` projection); it writes nothing.
4. **Fields from the type** — listed in (9) from `event_recap.dart`, not memory.
5. **Data contracts** — `RecapShareCard({required EventRecap recap, required Map<String,String> roster, required EventType eventType, String? uid})`. Hero = `sortedGccFirst(recap.totalSpentByCurrency.keys ∪ recap.participantNetsByCurrency.keys).first` (mirrors the screen's `_content`). `shareImage(BuildContext, Uint8List, {String fileName='rihla_recap.png', String? text, String? subject})`. `captureBoundaryPng(GlobalKey, {double pixelRatio=3})→Future<Uint8List?>`.
6. **Arithmetic decomposition** — none aggregated across slices. `avgPerDay`/`perPerson` are display-only ratios of the **hero-currency** total: `(heroTotal / Decimal.fromInt(n)).toDecimal(scaleOnInfinitePrecision: currencyDecimals)`. Never summed, never persisted. `days = max(1, endDate.difference(startDate).inDays + 1)` (inclusive) when both present, else per-person.
7. **Adversarial pass (orthogonal axis = identity/scope/time)**:
   - *Identity*: card reads `roster[id] ?? l10n.ledgerSomeone` — a departed-but-residual member (in nets, #249) renders by id-fallback, never throws.
   - *Scope*: hero selection ignores settlement-only currencies for the breakdown (categories/biggest are EXPENSE-keyed, may be absent for a settlement-only hero — guard with `?? const []`/null).
   - *Time*: `closedAt`/dates nullable during the offline-close window — caption month and date-range both conditional; never `!`.
   - *Empty*: `recap.isEmpty` (0 expenses) → the Share affordance is **hidden** (the screen already early-returns `_empty`), so the sheet is never reachable with no data.

## Build steps (TDD where it matters)

1. **`shareImage()`** in `lib/core/utils/share_helper.dart` + extend `test/core/utils/share_helper_test.dart` (mock share channel + `PathProviderPlatform` fake → assert non-zero origin, `image/png`, `rihla_recap.png`, text passthrough). RED→GREEN.
2. **`captureBoundaryPng()`** in `lib/core/utils/widget_to_image.dart` + `test/core/utils/widget_to_image_test.dart` (render a boundary, assert PNG magic `‰PNG` + non-empty).
3. **`RecapShareCard`** in `lib/features/events/widgets/recap_share_card.dart` (+ `formatMonthYear` in `localized_dates.dart`) + `test/features/events/recap_share_card_test.dart` (settled / outstanding / multi-ccy / no-dates build; hero total, status, brand present; never throws on departed member).
4. **`recap_share_sheet.dart`** (`showRecapShareSheet(...)`: FittedBox→RepaintBoundary card, "Share image" CTA → capture+shareImage, busy guard) + **share icon** in `event_recap_screen.dart` top row (only when `!recap.isEmpty`) + `event_keys.dart` keys. l10n in **both** ARBs; regen. `recap_share_sheet_test.dart` (CTA → `shareFiles` invoked) + extend `event_recap_screen_test.dart` (icon present non-empty / absent on empty).
5. **Verify**: `flutter analyze` clean, `bash tool/check_theme_purity.sh`, targeted tests, full suite. Adversarial Workflow review of the diff. Commit `feat(recap): shareable recap card (#722)` `Closes #722`; `/automerge` native path.

## New l10n keys (en + ar)

`recapShareButton` "Share recap", `recapShareSheetTitle` "Share recap", `recapShareCta` "Share image", `recapCardWrapped` "Wrapped", `recapCardAvgPerDay` "Avg / day", `recapCardPerPerson` "Per person", `recapCardWhereItWent` "Where it went", `recapCardStillToSettle` (k) "{count} still to settle", `recapCardAllSettled` "All settled", `recapShareText` (eventName) — the accompanying caption text. Reuse existing: `recapTotalSpent`, `recapTopPayer`→top spender? (keep `recapCardTopSpender` new for the card's shorter label), `recapBiggestExpense`→`recapCardBiggest` "Biggest splurge", `recapPeopleExpenses` no (card uses separate People/Expenses labels: `recapCardPeople`/`recapCardExpenses`).

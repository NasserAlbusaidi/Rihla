# Event header declutter — one-column top stack

- **Date:** 2026-07-09
- **Scope:** presentation-only, ONE screen file + its tests. No money/routing/schema/rules surface.
- **Owner file:** `lib/features/events/screens/event_command_center.dart`
- **Issue lineage:** #811 (labelled recap scent), #382 (per-currency header), #789 (live day badge), #1028 (error/pending honesty), #758 (tabbed hub).
- **Gate category:** design/presentation. It touches NO `BalanceCalculator`/`MoneySerializer`, NO `firestore.rules`/Functions, NO `app_router.dart`/deep-links/back-guards, NO schema field. The one route reference (`push('.../recap')`) is a **verbatim reuse** of the existing `_OpenRecapBanner.onViewRecap` string, not a new/changed route.

---

## Problem

Above the content tabs the event hub stacks four full-width bands in four different materials (bare paper header, bare paper balance, a 4%-ink tinted recap strip, a bordered pill tab bar), with ~12 competing labels — including three uppercase micro-label systems in three colors (saffron eyebrow, grey "YOUR BALANCE", green/red "YOU ARE OWED"/"YOU OWE"). The eye lands on metadata first and reaches the money fourth. User verdict on the whole region: "feels very cluttered."

Two concrete offenders in code:
1. **`_OpenRecapBanner` (~L951) wears system-status clothes** — `color: colors.textPrimary.withValues(alpha: 0.04)`, the *same* material as `_ClosedBanner` ("event closed") and directly above `OfflineBanner`. A tertiary nav link occupies a full-width interruption band.
2. **`_BalanceBlock` (~L574) triple-codes direction** — a permanent "YOUR BALANCE" overline + a colored state overline + a colored, signed amount. Direction is encoded up to four times; the 30px amount is sandwiched between two uppercase label rows and *shrinks* to 22px in multi-currency, exactly when there is more money to read.

## Goal

Collapse the top region into **one column, one left margin (20)**: title row → grey state label → big colored amount → one quiet progress/recap line → tabs. Between the title row and the tabs, at most three text lines. Tinted-strip material is reserved for genuine system states (`OfflineBanner`, `_ClosedBanner`). Every existing datum stays reachable (invariant §7).

## Non-goals / out of scope

- No change to `_HubState` computation, `ledgerViewProvider`, `nonZeroNetsGccFirst`, or the #1028 unavailable/pending gating logic (only the *rendering* of the resolved state changes).
- No new l10n string (all labels reuse existing EN+AR keys — see §L10N). No generated-l10n regen.
- No `_ClosedBanner` change — it is a real system state; its tint stays.
- No routing, no new EventKey semantics beyond repurposing two existing constants (§KEYS).
- Do not touch `event_details_card.dart` / `event_info_section.dart` (they already own the editable date/type surface — reachability only).

---

## KEYS decision (explicit)

**Keep the two existing constants; repurpose them onto the new progress line. No rename.** This is the minimal-diff choice and satisfies the "preserve a key on the tap target" requirement — the five test references (`event_command_center_test.dart` L308/327/341/362/421) keep resolving unchanged.

- `EventKeys.openRecapBanner` (`Key('event_open_recap_banner')`) → on the **outer progress-line widget**, present whenever the line renders (day-only OR recap-present); absent when the line renders nothing.
- `EventKeys.openRecapBannerViewRecap` (`Key('event_open_recap_view_recap')`) → on the **tappable recap target** (the InkWell), present ONLY when the recap fragment is shown.
- Update only the doc comments (L51-54 of `event_keys.dart`) from "banner" wording to "progress line". No constant name change, no test key-ref churn.

Rejected alternative: rename to `tripProgressLine`/`tripProgressViewRecap`. Cleaner names but forces churn on 5 test refs for zero behavioral gain; rejected for minimal-diff.

## L10N decision (explicit)

**No new string; no ARB or generated-l10n change.** Every label reuses an existing key (EN + AR both verified present):

| Surface | Key | EN | AR (exists) |
|---|---|---|---|
| owed label | `eventYouAreOwed` | "You are owed" | مستحق لك |
| owe label | `eventYouOwe` | "You owe" | عليك دفع |
| mixed label | `eventYourBalance` | "Your balance" | رصيدك |
| settled status | `eventAllSettled` | "All settled" | تمت التسوية |
| empty status | `eventNothingToSettleYet` | "Nothing to settle yet" | لا شيء للتسوية بعد |
| day segment | `eventDayOf` | "Day {currentDay} of {totalDays}" | اليوم … من … |
| recap segment | `eventViewReceipt` | "View recap" | عرض الملخّص |

`recapOpenBannerLead` ("See the trip so far", used only at L973) goes **vestigial** — its single call site is deleted. Leave the ARB entries in place (harmless dead string; removal would need a generated-l10n regen and is scope creep). Note it for a future dead-string sweep.

---

## Design — the after

Phone-width sketch (open, single-currency, live multi-day):

```
┌────────────────────────────────────────┐
│ (<)  Camping Trip             (o) (#)   │  title 20 display, Ink
│                                        │
│  You are owed                          │  label 13 w600, Ink-3 (grey)
│  +OMR 3.150                            │  amount 34 w800, sage-dark
│  [cup] Day 2 of 5 · View recap    >    │  13 w600 Ink-3, chevron saffron
│                                        │
│ ( Expenses | Settle up | Activity )    │  tab bar (unchanged)
├────────────────────────────────────────┤
│  expense list…                         │

multi-currency (mixed):     settled:               day-only (no expenses):    collapsed:
│  Your balance         │    │  All settled     │   │ [cup]? Day 2 of 5     │   │ (<) Camping  +OMR 3.150 (o)(#) │
│  +OMR 3.150           │    │  (no label line) │   │  (non-tappable,       │   │ ( Expenses | Settle | Act )   │
│  −USD 15.00           │    │                  │   │   no chevron)         │
│  [cup] Day 2·View recap>│  │  [cup] View recap>│
```

### `_HubState` → render mapping (all seven states)

The grey label is **always `colors.textSecondary`** (ink-3); color lives only on the amount. Rendering order inside `_BalanceBlock` keeps **unavailable → pending FIRST** (#1028) so wrong/missing nets never render as money.

Compute a leading label from state:
```
final String? label = switch (state) {
  _HubState.youOwed => context.l10n.eventYouAreOwed,   // "You are owed"
  _HubState.youOwe  => context.l10n.eventYouOwe,        // "You owe"
  _HubState.mixed   => context.l10n.eventYourBalance,   // "Your balance"
  _ => null,                                            // empty/settled/pending/unavailable
};
```

| state | grey label line | amount / status line (color) |
|---|---|---|
| `unavailable` | **absent** | warning row (`Iconsax.warning_2` + `homeBalanceUnavailable`, `textSecondary`), key `balanceHeaderUnavailable` — **rendered first**, unchanged |
| `pending` | **absent** | `SkeletonLoader.trailingBalance()`, key `balanceHeaderPending` — **rendered second**, unchanged |
| `empty` | **absent** | "Nothing to settle yet" (`eventNothingToSettleYet`), display **26** (was 24), `textSecondary` |
| `settled` | **absent** | "All settled" (`eventAllSettled`), display **26**, `successText` |
| `youOwed` | "You are owed" (grey) | 1 line → `RAmount` size **34** w800, tone `sage`, sign; N lines → loop `RAmount` size **26** w800, tone per-sign |
| `youOwe` | "You owe" (grey) | 1 line → `RAmount` **34** w800, tone `rust`, sign; N lines → loop **26** |
| `mixed` | "Your balance" (grey) | loop `RAmount` size **26** w800, tone per-sign (always ≥2 lines) |

Because `label` is `null` for `unavailable`/`pending`, the first rendered child in those states is still the warning/skeleton — #1028 preserved. Amount branch order is byte-for-byte the current order (unavailable → pending → empty|settled → `lines.length==1` → multi loop), only the sizes and the removal of the overline `Row` change.

Single-amount tone keeps the existing `isOwed = state == _HubState.youOwed` flag (L583) → `isOwed ? AmountTone.sage : AmountTone.rust`. Delete the now-unused `isUniform` local (L584) and the two-overline `Row` (L590-602). The `SizedBox(height: space4)` at L603 (the old overline-Row→amount gap) must be **emitted only alongside the grey label** — for `empty`/`settled`/`pending`/`unavailable` where `label == null`, don't render a leading invisible spacer before the warning/skeleton/status line (keep the first rendered child = the warning row / skeleton, #1028). [Gate R3-P3]

### Type / color (exact)

All via `context.colors` roles — **no raw `Color(0xFF…)`, no `.textMuted` read → zero new `check_theme_purity.sh` justification debt (#615).**

| Element | Before | After |
|---|---|---|
| Title (`event.name`, L468) | `displayOf` 18 | `displayOf` **20**, `textPrimary`, height 1.1, letterSpacing -0.2 |
| Grey state label | `_Overline` uppercase 10/w700/track1.4 | `AppTypography.sans(fontSize: 13, fontWeight: FontWeight.w600)`, `colors.textSecondary` — sentence case |
| Single amount (L651) | `RAmount` size 30 | size **34**, weight w800 |
| Multi lines (L667) | `RAmount` size 22 | size **26**, weight w800 |
| Settled/empty status (L638) | `displayOf` 24 | `displayOf` **26** |
| Progress day+recap text | (was two banner texts 12.5) | `AppTypography.sans(fontSize: 13, fontWeight: FontWeight.w600)`, `colors.textSecondary` |
| Progress chevron | banner used `textPrimary` | `DirectionalIcon(Iconsax.arrow_right, size: 14, color: colors.primary)` — the one saffron accent |
| Progress cup | `Iconsax.cup` 14 `textSecondary` | unchanged icon, shown only when recap present |
| Unavailable warning text (L617) | `displayOf` 20 | unchanged |
| Compact amount (L562) | `RAmount` 12 | unchanged |

### Progress line — new widget `_TripProgressLine`

Replaces `_OpenRecapBanner`. **No tint.** RTL-correct (`EdgeInsetsDirectional`, `AlignmentDirectional.centerStart`, `DirectionalIcon`).

```
class _TripProgressLine extends StatelessWidget {
  const _TripProgressLine({
    required this.dayLabel,     // String? — "Day 2 of 5" or null
    required this.showRecap,    // bool — !event.isClosed && hasExpenses
    required this.onViewRecap,  // VoidCallback — verbatim recap push
  });
  ...
  build:
    if (dayLabel == null && !showRecap) return const SizedBox.shrink();     // key absent → openRecapBanner findsNothing
    final colors = context.colors;
    final text = [ if (dayLabel != null) dayLabel!, if (showRecap) context.l10n.eventViewReceipt ].join(' · ');
    final row = Row(children: [
      if (showRecap) ...[ Icon(Iconsax.cup, size: 14, color: colors.textSecondary), const SizedBox(width: 8) ],
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: AppTypography.sans(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textSecondary))),
      if (showRecap) ...[ const SizedBox(width: 4),
        DirectionalIcon(Iconsax.arrow_right, size: 14, color: colors.primary) ],
    ]);
    if (!showRecap) {
      return Align(key: EventKeys.openRecapBanner, alignment: AlignmentDirectional.centerStart, child: row);
    }
    return Align(
      key: EventKeys.openRecapBanner,
      alignment: AlignmentDirectional.centerStart,
      child: InkWell(
        key: EventKeys.openRecapBannerViewRecap,
        onTap: onViewRecap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),   // ≥44pt tap target
          child: Align(alignment: AlignmentDirectional.centerStart, child: row),
        ),
      ),
    );
}
```

Fragment-presence rules:
- **day-only** (dayLabel != null, !showRecap): plain non-tappable text "Day 2 of 5", no cup, no chevron, no InkWell.
- **recap-only** (dayLabel == null, showRecap): "View recap ›", tappable full row.
- **both**: "Day 2 of 5 · View recap ›", tappable full row (tap anywhere → recap).
- **neither**: `SizedBox.shrink()` — nothing, no key.

`onViewRecap` is the **verbatim** existing push, moved up from L283-288 into the callback passed to `_EventHeader`:
`GoRouter.of(context).push('/group/${widget.groupId}/event/${widget.eventId}/recap')` (+ `HapticService.lightClick()`).

### Where the day-of computation lives (§2)

Unchanged — it stays inside `_EventHeader.build` (currently L426-431), only its *consumer* changes from the eyebrow to `_TripProgressLine`:
```
final day = event.isClosed ? null : liveTripDay(event.startDate, event.endDate, DateTime.now());
final dayLabel = day == null ? null : context.l10n.eventDayOf(day.currentDay, day.totalDays);
```
Inputs: `event.startDate`, `event.endDate`, `DateTime.now()`. `liveTripDay` (`lib/features/events/utils/event_display.dart`) already returns null for single-day/closed/out-of-range — #789 conditional preserved with zero logic change.

### Collapse-on-scroll (§4) — widget-tree change

The label + amount + progress line collapse **together**; `_CompactAmounts` behaviour is untouched.

`_EventHeader`'s `AnimatedSize` (L511-528) currently wraps only `_BalanceBlock`. Change its expanded child to a Column containing `_BalanceBlock` then the progress line, all under the existing `Padding(fromSTEB(20, 10, 20, 4))`:
```
child: collapsed
  ? const SizedBox(width: double.infinity)
  : Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BalanceBlock(state: state, lines: lines),
          const SizedBox(height: 6),
          _TripProgressLine(dayLabel: dayLabel, showRecap: showRecapLink, onViewRecap: onViewRecap),
        ],
      ),
    ),
```
`showRecapLink = !event.isClosed && hasExpenses` (header-local). When `collapsed`, the whole block → `SizedBox` (progress line collapses with it); `_CompactAmounts` still slides in beside the title (L486-493, unchanged). One left margin (20) now governs label, amount, and progress.

### `_EventHeader` new constructor params

Add two; day is still computed internally:
- `final bool hasExpenses;`
- `final VoidCallback onViewRecap;`

Inside `_EventHeader.build`, compute the header-local **`showRecapLink = !event.isClosed && hasExpenses`** — deliberately NOT named `showRecap`: `_ContentState` already has `showRecap = event.isClosed` (drives the Recap TAB) with the OPPOSITE meaning, so reusing the name invites a conflation bug. [Gate R1-P3]

`_ContentState.build` (~L235) passes `hasExpenses: expenses.isNotEmpty` and the recap callback (built there, where `context`/`widget.groupId`/`widget.eventId` are in scope — same pattern as the existing `onSettings`/`onSearch`).

### `_ContentState.build` placement change (L264-289)

Delete the `else if (expenses.isNotEmpty) _OpenRecapBanner(...)` branch — recap now lives inside `_EventHeader`. Keep the closed banner:
```
if (event.isClosed)
  _ClosedBanner(closedByName: …, onViewReceipt: …),   // unchanged
const OfflineBanner(),
_EventTabBar(…),
```

### Deletions

- `_OpenRecapBanner` class (L951-1013) — replaced by `_TripProgressLine`.
- `_Overline` class **in this file** (L1017-1036) — its only two callers (L593/L595) are removed. (Note: a *separate, unrelated* `_Overline` lives in `ledger_day_card.dart` — leave it.)
- eyebrow construction (L432-436), the eyebrow `Text` (L456-466), **and the `const SizedBox(height: 1)` spacer at L467** that sat between eyebrow and title in `_EventHeader` (else a stray 1px gap above the title). [Gate R2-P3]
- `dateRange` local (L424) **and** the `_formatDateRange` static helper (L533-542) — both orphaned once the eyebrow (their sole consumer) is deleted. **Must be removed or `flutter analyze` fails** (`unused_local_variable` on `dateRange`, `unused_element` on `_formatDateRange`) → T6 / readiness CI red. Verified: no other caller of either in the file. [Gate R1-P1]
- **The `import '../../../core/utils/localized_dates.dart';` at L11** — `_formatDateRange` is its ONLY consumer in the file (verified: `formatShortMonthDay`/`formatDateRangeShort` at L539-541 are the sole `localized_dates` symbols used; no other export appears). Deleting `_formatDateRange` orphans the import → `unused_import` **warning** → `flutter analyze` (CI runs it fatal-on-warnings, `readiness_check.yml`/`release_android.yml`) goes red. Symmetric sibling of R1-P1, one import-level up. [Gate R2-P1]
- Full orphan set from the eyebrow removal, all verified, nothing else: `dateRange` (L424) · `_formatDateRange` (L533-542) · `localized_dates` import (L11) · `SizedBox(height:1)` (L467). `colors.primaryDark`, `liveTripDay`, `eventDayOf`, `AppTypography`, and the `event_display` import all stay live (used elsewhere).
- `isUniform` local (L584) and the two-overline `Row` (L590-602) in `_BalanceBlock`.

---

## Tasks (each leaves the tree green)

- [ ] **T1 — Header:** delete eyebrow; bump title 18→20; add `hasExpenses`/`onViewRecap` params to `_EventHeader`; move day-of consumer to progress line; wrap `_BalanceBlock`+`_TripProgressLine` in the collapse Column.
- [ ] **T2 — Balance:** rewrite `_BalanceBlock` per the state table (grey leading label from `switch(state)`; drop overline Row + `isUniform`; single 30→34, multi 22→26, status 24→26). Keep `key: balanceHeader`, `balanceHeaderUnavailable`, `balanceHeaderPending`, and the unavailable→pending-first order. **Delete the file-local `_Overline` class IN THIS task** — its only callers are the overlines removed here; deleting it in a later task leaves an `unused_element` warning between commits, so T2 must land analyze-clean. [Gate R3-P3]
- [ ] **T3 — Progress line:** add `_TripProgressLine`; delete `_OpenRecapBanner`; repurpose the two EventKeys onto it; remove the `_OpenRecapBanner` branch from `_ContentState.build`.
- [ ] **T4 — Keys doc:** update `event_keys.dart` L51-54 comments (banner → progress line). No constant rename.
- [ ] **T5 — Tests:** update assertions (below); add the new guards.
- [ ] **T6 — Verify:** `flutter analyze` clean; `tool/check_theme_purity.sh` clean; run the five listed test files + a `flutter test test/features/events/`.

---

## Test plan (§6)

Grep each file for the removed strings/keys and fix at the assertion, don't patch around.

### `event_command_center_test.dart` — CHANGE

- L84 test 'you-are-owed … sage overline': rename to '…grey "You are owed" label'; `find.text('YOU ARE OWED')` → `find.text('You are owed')` (L103).
- L106 test 'you-owe … rust overline': rename to '…grey "You owe" label'; `find.text('YOU OWE')` → `find.text('You owe')` (L123).
- L155 test '#631: header computes "you owe" through the shared ledgerViewProvider': `find.text('YOU OWE')` → `find.text('You owe')` (L207). (Sibling uppercase assertion — enumerated for completeness; the T5 grep-and-fix directive covers it either way.)
- L244 group '#789 … eyebrow badge': rename to '#789 — live day segment in the progress line'.
  - L264 `find.textContaining('DAY 3 OF 7')` (findsOneWidget) → `find.textContaining('Day 3 of 7')`.
  - L278 `find.textContaining('DAY ')` (findsNothing) → `find.textContaining('Day ')`.
  - L287 `find.textContaining('DAY 3 OF 7')` (findsNothing) → `find.textContaining('Day 3 of 7')`.
- L482-483 (per-currency, settled-OMR/owe-USD): L483 `find.text('YOU OWE')` → `find.text('You owe')`. (L482 `All settled` findsNothing unchanged.)
- L493 'mixed signs … no tri-state overline': L530/531 `find.text('YOU ARE OWED')`/`'YOU OWE'` → `'You are owed'`/`'You owe'` (both findsNothing); **add** `expect(find.text('Your balance'), findsOneWidget);` (re-pins the mixed label). L532 unchanged.
- L582 (L13 sub-tolerance): `find.text('YOU ARE OWED')` → `find.text('You are owed')`.
- #811 group (L291+): key refs L308/327/362/421 **unchanged** (constants kept). **L341** ("open event, no expenses → banner hidden") needs a stronger guard: post-change `openRecapBanner` also marks a day-only line, so `find.byKey(openRecapBanner), findsNothing` now passes only because the test's dates are past (`liveTripDay`→null), not because there are no expenses. **Add `expect(find.byKey(EventKeys.openRecapBannerViewRecap), findsNothing)`** — the InkWell is the true "no recap affordance" proof for an empty open event. [Gate R1-P2] RTL-overflow test (L368+) still valid; extend it per new guard 7. No text-assert on `recapOpenBannerLead` exists.

### `event_hub_balance_error_states_test.dart` — CHANGE (was mislabeled "no change")

Besides the "Nothing to settle yet"/"All settled" absence + `balanceHeaderUnavailable`/`balanceHeaderPending` keys, it ALSO asserts `find.text('YOU OWE')` / `find.text('YOU ARE OWED')` **findsNothing** at L70-71 and L129-130 — the #1028 "no direction label inside an error/pending window" guard. After the change those pass trivially (the uppercase strings vanish app-wide), which **silently defangs the guard**. Update them to `find.text('You owe')` / `find.text('You are owed')`, findsNothing, so the guard still bites. [Gate R1-P2]

### `event_tabs_test.dart`, `event_module_redirect_navigation_test.dart`, `test/features/search/search_navigation_test.dart` (+ `recap_settle_cta_nav_test.dart`) — VERIFY

None reference the removed eyebrow/recap strings (greps clean). `event_module_redirect_navigation_test.dart` pumps the hub and asserts the title `'Dinner'` (survives — title still rendered, bumped to 20) plus an icon back-tap (`find.byIcon(Iconsax.arrow_left).first` — the back button, unaffected — the recap widgets use `arrow_right`). `event_tabs_test.dart` asserts `balanceHeader` descendants (multi-currency RAmount still resolves). `recap_settle_cta_nav_test.dart` does not pump `EventCommandCenter` (no header coupling). The only risk is a coordinate-based tap landing off-target if header height shifts — all covered by T6's `flutter test test/features/events/`. [Gate R3-P3]

### NEW guard tests (add to `event_command_center_test.dart`)

1. **Eyebrow gone:** live multi-day event → `expect(find.textContaining('DAY 3 OF 7'), findsNothing)` AND `expect(find.textContaining('Day 3 of 7'), findsOneWidget)` (uppercase eyebrow day migrated to sentence-case progress line). This pair is the eyebrow-removal proof.
2. **Progress line combined + tap-through:** open, live multi-day, ≥1 expense → `find.textContaining('Day 3 of 7')` and `find.textContaining('View recap')` both present; `tester.tap(find.byKey(EventKeys.openRecapBannerViewRecap))` → routes to recap (mirror L327/330 `find.text('RecapRoute:event-1')` via `_pumpEventHubRouter`).
3. **Day-only non-tappable:** live multi-day, **no** expenses → `find.textContaining('Day 3 of 7')` present, `find.byKey(EventKeys.openRecapBannerViewRecap)` findsNothing (no InkWell), `find.byKey(EventKeys.openRecapBanner)` findsOneWidget.
4. **Multi-currency:** mixed buckets → 2 currency codes render under `balanceHeader` (reuse the L533-541 descendant pattern) + `find.text('Your balance')` findsOneWidget.
5. **Settled — no label:** settled buckets → `find.text('All settled')` findsOneWidget AND `find.text('Your balance')` findsNothing AND `find.text('You are owed')` findsNothing.
6. **Collapse:** drive the ledger scroll (small drag steps) so `_onScroll` sets `_collapsed` → `find.byKey(EventKeys.headerCompactAmount)` becomes findable and the expanded balance/progress content collapses. If the `_wrap` harness can't produce a scrollable ledger cheaply, fall back to a KEY-based structural assertion (private widget classes aren't findable across the test-library boundary, so `find.byType(_TripProgressLine)` is impossible): `find.ancestor(of: find.byKey(EventKeys.openRecapBanner), matching: find.byType(AnimatedSize))` and the same for `EventKeys.balanceHeader` resolve to the same subtree. [Gate R1-P3]
7. **RTL longest line:** live multi-day + ≥1 expense, wrapped in `Directionality(TextDirection.rtl)` at ~320px width → the merged "Day 3 of 7 · View recap" (AR strings) renders with NO RenderFlex overflow (the `Flexible` + ellipsis guarantees it). The existing RTL-overflow test only hits recap-only (past dates → no day segment); this exercises the longest "both" string, which is the one that could overflow. [Gate R1-P3]

---

## Invariants preserved (§7)

- **#811 (recap labelled + tappable):** recap stays a labelled ("View recap") tappable target ≥44pt, shown only for open events with ≥1 expense; icon-only never returns. Touch area grows vs. the old trailing link.
- **#382 (multi-currency / settled / mixed):** per-currency lines still render one-per-bucket (26px, per-sign tone); "All settled"/"Nothing to settle yet"/mixed-sign states all mapped in the §1 table; `nonZeroNetsGccFirst`/`myNetByCurrency` untouched; exact-zero settled gate untouched.
- **#789 (day conditional):** `liveTripDay(startDate, endDate, now())` logic byte-unchanged; day shows only on live multi-day, suppressed when closed.
- **#1028 (error honesty):** unavailable → pending branches render FIRST; label is `null` for both; keys `balanceHeaderUnavailable`/`balanceHeaderPending` preserved; wrong/absent nets never render as money.
- **Collapse (#758):** balance + progress collapse together inside `AnimatedSize`; `_CompactAmounts` slides in beside the title, unchanged.
- **Reachability (§5):** date range + event type remain editable/visible in event settings (`event_details_card.dart` date pickers + the type field) and on the recap; event type also still surfaces as the Expenses-tab "CAMPING TOTAL" caption (#689, unaffected). Nothing becomes unreachable.

---

## Risks

1. **The bet:** date range + event type leave the *permanent* header surface (they stay reachable via settings/recap). Deliberate — mid-trip the live fact is "Day 2 of 5", which survives on the progress line. This is the one aesthetic risk being taken; if product wants the date always-visible, the fallback is a sentence-case subtitle under the title (Option B) — but that re-adds a permanent line the declutter is trying to remove.
2. **Key-name/semantics drift:** `openRecapBanner` now marks a progress line that can render day-only (no recap). No test probes `openRecapBanner`-present in a day-only-live scenario, so no conflict; documented in the keys comment. Chosen over a rename to avoid 5-file test churn.
3. **Collapse test fragility:** driving `_onScroll` in a widget test can be finicky (paginated `ListView` extent shrink — see CLAUDE.md); the structural fallback assertion is specified so T5 can't block on scroll flakiness.
4. **Layout-shift taps in nav tests:** the three nav/search tests don't assert header content but could miss a coordinate-based tap if header height changes; mitigated by running them in T6.
5. **Open-event recap AND live day counter collapse on scroll:** moving the recap link + the day segment into `_EventHeader`'s `AnimatedSize` means both hide while scrolled down. Previously "Day N of M" lived in the always-visible eyebrow (persistent even when collapsed); now it rides the collapsing block. Open events have no Recap tab, so recap is momentarily unreachable until scroll-up restores the header. Deliberate declutter, not a regression — restored on scroll-up; noted so neither is mistaken for one. [Gate R1-P3 / R2-P3]
```

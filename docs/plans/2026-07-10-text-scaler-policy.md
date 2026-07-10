# Text scale policy: clamp at 1.5× + harden the four audit offenders (#1064)

**Issue:** #1064 — no textScaler policy; home/profile break at iOS accessibility sizes (EN+AR).
**Gate status:** not Gate-mandatory (no money/routing/schema/rules surface). `lib/main.dart` will still classify GATE at `/automerge` time (fails-toward-review), so the diff gets a fresh Opus review + refuter before merge.

## Decision

**Option A + targeted hardening (the issue's "likely both", in one PR):**

1. **Global clamp at 1.5×.** `MaterialApp.router` (`lib/main.dart`) gains a `builder:` that clamps the inherited textScaler:
   ```dart
   builder: (context, child) {
     final mq = MediaQuery.of(context);
     return MediaQuery(
       data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.5)),
       child: child!,
     );
   }
   ```
   - Max only — no min clamp (users shrinking text stay honored).
   - `TextScaler.clamp` (not `TextScaler.linear(...)` reconstruction) so nonlinear iOS scaling below the cap is preserved.
   - Rationale for 1.5: iOS AX sizes reach ~3.1×, at which the current layouts are unusable in both locales; 1.5 is the largest value the existing compact layouts can honestly support with targeted hardening, and it is a floor we can raise later (raising a clamp is invisible; lowering one is a regression).
2. **Harden the four audited offender sites so 1.5× EN+AR is overflow-free:**
   - `lib/shared/widgets/section_header.dart` — title `Text` wrapped in `Flexible` with `maxLines: 1` + ellipsis; action label `Text` gets `maxLines: 1`; the `Spacer()` stays (collision resolved by the title yielding).
   - `lib/features/home/widgets/balance_hero_card.dart` hint row — hint `Text` wrapped in `Flexible` (`maxLines: 1`, ellipsis); row keeps centered alignment.
   - `lib/features/settings/screens/profile_screen.dart` hero — display name / "Set your name" `Text` gets `maxLines: 1` + ellipsis inside a flexible slot (whatever the current Row/Stack shape needs).
   - `lib/features/settings/screens/profile_screen.dart` `_StatCard`s — VALUE (incl. `_SpentValue` money) rendered inside `FittedBox(fit: BoxFit.scaleDown)` on a single line so money digits are never clipped; key labels get `maxLines: 2` + ellipsis (kills the mid-word "JOURNE YS" wrap at the supported max).
   - Home header set-name chip vs wordmark (#1010 interplay): constrain the chip to its side's available width (`Flexible`/`ConstrainedBox` + the existing #1010 ellipsis) so it can never paint over the centered wordmark at 1.5×. No redesign of the header slice — #1010's accepted ellipsis stands.
3. **Write the policy down** in `docs/DESIGN.md` (short subsection under the type/a11y section): OS text scale honored up to **1.5×** (clamped in the app `builder:`); screens must render overflow-free at 1.5× in EN and AR; money values never clip — scale down, never truncate digits.

## Non-goals

- No per-screen whack-a-mole beyond the four named sites + header chip.
- No redesign of #1010's header slice.
- Not raising support past 1.5× (follow-up if user demand appears).

## Verification

- Regression test (new, e.g. `test/features/home/text_scale_policy_test.dart` or `test/unit/`):
  - Pump the app/screens under `MediaQuery(textScaler: TextScaler.linear(3.0))` and assert an in-tree `Text` observes an effective scale of exactly 1.5 (pins the clamp, and pins that 3.0→1.5, not pass-through).
  - Pump Home and Profile at the supported max (1.5×), EN and AR, and assert zero exceptions (RenderFlex overflow throws in debug — `tester.takeException()` stays null / no FlutterError).
  - Money-clip pin: SPENT stat renders its full formatted value at 1.5× (FittedBox present / no clip).
- Full suite + `flutter analyze` green; goldens untouched (normal-scale rendering must be pixel-identical — hardening only changes behavior under large scale or overflow).

## Risks

- `builder:` composes with `SystemChromeThemeSync` and the cache-isolation overlay — the overlay branch returns before `MaterialApp.router`, so the clamp must live INSIDE the normal app's builder only; `_CacheIsolationApp` (splash cover) needs no clamp.
- `maxLines`/ellipsis on section headers changes nothing at 1.0× (strings fit today) — if any existing test asserts unbounded lines, update it, don't weaken the fix.

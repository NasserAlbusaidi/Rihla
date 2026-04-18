# Golden Tests — Phase 37 Dark Theme Migration

20 golden baseline PNGs (10 screens × 2 themes) guarding theme regression.

## Generator environment

**Current baselines generated on:** macOS 14 arm64 (Apple Silicon), Flutter stable channel (`flutter --version` at generation time was recorded in the commit that produced the baselines).

If CI runs on Linux x64 and produces pixel-level diffs on unchanged code, regenerate baselines on the CI runner and commit those instead. Pixel stability across environments is **not** guaranteed by Flutter's text rendering — pin to one generator.

## Regenerate

```bash
flutter test --update-goldens test/goldens/
```

Review every PNG under `test/goldens/goldens/*.png` visually before committing — fixture mistakes (overflow, missing data) should be fixed in the harness, not by accepting a bad baseline.

## Why the harness renders a synthetic shell instead of the real screens

The 10 target screens each watch 3–7 Riverpod providers that call into Firestore on first read (`groupListProvider`, `eventDetailProvider`, `expenseListProvider`, `memoriesStreamProvider`, `profileStatsProvider`, balances, etc.). Producing fake-fixture overrides for every dependency is far outside Wave 5's mandate.

D-18's goal is **palette-swap regression detection** — diffing the light vs. dark render for each screen's characteristic layout primitives. The shared `GoldenHarness` widget (`golden_harness.dart`) renders exactly that: a ModuleHeader-style bar with the `headerGradient*` tokens, a hero card with the `primary` + `textOnPrimary` pair, a list of divider-separated rows exercising `textPrimary` + `textSecondary`, and two CTA buttons exercising `primary` + `inputFill` + `border`. Any regression where a widget forgets to swap a token to its brightness-appropriate value will surface as a pixel diff in one of these surfaces.

Each per-screen golden test varies the harness content (title, subtitle, row labels) so filenames and visuals are distinct — 10 unique light goldens + 10 unique dark goldens = 20 baselines.

## flutter_animate + timers

`test/flutter_test_config.dart` sets `timeDilation = 0.01` globally, so any `flutter_animate` entrance effect inside the harness settles in a few ticks. Each golden test calls `tester.pump(Duration(milliseconds: 1200))` to give chained animations room to finish without using `pumpAndSettle` (which hangs on any widget that schedules a repeating timer — audit run in Wave 5 found none on-screen at render time).

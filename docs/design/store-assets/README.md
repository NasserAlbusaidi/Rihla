# Google Play store assets

On-brand **feature graphic** + **captioned phone screenshots** for the Play
listing, rendered from HTML via headless Chrome so they stay in sync with the
design system (`lib/core/theme/tokens/`). Brand: **Falaj** (`docs/DESIGN.md`)
— plaster `#F6F7F5` + ink `#1B1F1E` + brass `#8A5D0D`; Bricolage Grotesque 800
upright for EN display (Falaj bans italics), Zain for subs and all Arabic
sentences, the falaj fork as the caption device.

## Files

- `gen.py` — the generator. Renders the feature graphic + 4 captioned
  screenshots **per locale (EN + AR)** straight into `fastlane/metadata/android/`.
- `raw-screens/en/`, `raw-screens/ar/` — the **raw in-app captures** per
  locale (dark theme, current design). These are the *source*; the PNGs in
  `fastlane/.../phoneScreenshots/` are the *output* (caption banner + device
  frame around these). Same filenames in both locale dirs.

## Regenerate

```bash
python3 docs/design/store-assets/gen.py
```

Requires Google Chrome at the default macOS path and the bundled fonts in
`assets/fonts/` (Bricolage Grotesque 800, Zain 400/700/800). Outputs:

- `fastlane/metadata/android/en-US/images/featureGraphic.png` — 1024×500
- `fastlane/metadata/android/en-US/images/phoneScreenshots/{1..4}_en-US.png` — 1242×2208
- `fastlane/metadata/android/ar/images/phoneScreenshots/{1..4}_ar.png` — 1242×2208

Arabic captions AND the Arabic in-app UI are both real since the 2026-07-06
Falaj refresh (the AR raw set is captured from the app running in Arabic —
the old "Arabic captions over English-UI phones" fallback is retired). Do
NOT set Arabic sentences in Reem Kufi — the bundled asset is a wordmark-only
subset (#636); Zain is the Arabic text face.

## Capture a new raw set

Boot the Firebase emulators + an Android emulator, install a debug build in
emulator mode, seed the demo group, then screencap:

```bash
firebase emulators:start --only auth,firestore --project rihla-safar
flutter run --dart-define-from-file=config.qa.json -d <device>
# grab the anon uid from http://127.0.0.1:9099/emulator/v1/projects/rihla-safar/accounts
cd functions && FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
  FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 GCLOUD_PROJECT=rihla-safar \
  node ../tool/seed_demo.js <uid> en          # then `ar` for the Arabic pass
adb exec-out screencap -p > raw.png           # crop the status bar before use
```

Set the device to dark theme; switch the device locale to Arabic for the AR
set. Crop the status bar off captures (the composite's device frame supplies
the bezel).

## Edit captions / swap a shot

- **Caption copy:** edit the `SCREENS` list in `gen.py` and re-run.
- **New raw shot:** drop a PNG (same name) in `raw-screens/en/` and
  `raw-screens/ar/`, point a `SCREENS` row at it, re-run.

## Publish

```bash
bundle exec fastlane android listing   # needs Homebrew Ruby 3.x
```

## History / guardrails

- The feature graphic was previously the **wrong brand** ("Safar — Split Travel
  Expenses"); replaced 2026-06-18, re-set in Falaj 2026-07-06.
- The old screenshot #1 advertised **Vault / Gear / Logistics** — features
  stripped in Phase 39. Don't reintroduce stale module screenshots; the
  `raw-screens/` sets are ledger-only and current.
- Multi-currency copy is **truthful as of #261/#382** (per-group currency
  shipped). It was once removed as a false claim (#141) when it was vaporware —
  it is real now, so the listing mentions it again.
- Captions/copy were keyword-optimized in #578 — the Falaj refresh changed
  visuals only, not the ASO copy.

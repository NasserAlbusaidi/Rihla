# Google Play store assets

On-brand **feature graphic** + **captioned phone screenshots** for the Play
listing, rendered from HTML via headless Chrome so they stay in sync with the
design system (`lib/core/theme/tokens/`).

## Files

- `gen.py` — the generator. Renders the feature graphic + 4 captioned
  screenshots **per locale (EN + AR)** straight into `fastlane/metadata/android/`.
- `raw-screens/` — the **raw in-app captures** that feed the composites.
  These are the *source*; the PNGs in `fastlane/.../phoneScreenshots/` are the
  *output* (caption banner + device frame around these).

## Regenerate

```bash
python3 docs/design/store-assets/gen.py
```

Requires Google Chrome at the default macOS path and the bundled fonts in
`assets/fonts/`. Outputs:

- `fastlane/metadata/android/en-US/images/featureGraphic.png` — 1024×500
- `fastlane/metadata/android/en-US/images/phoneScreenshots/{1..4}_en-US.png` — 1242×2208
- `fastlane/metadata/android/ar/images/phoneScreenshots/{1..4}_ar.png` — 1242×2208
  (Reem Kufi RTL captions)

## Open items (need a fresh capture from the current app)

1. **Net-balance "who owes who" hero is missing.** The original slot-1 shot was
   an *old-theme* capture (bright emerald + "11% ring" Trip Settlement layout) —
   removed. To re-add it, capture the current group/settlement balance screen
   (sage palette) and drop it in `raw-screens/`, then add a `SCREENS` row.
2. **AR screenshots show English app UI.** The `raw-screens/` captures are
   English-locale. For a fully-localized AR listing, re-capture the app running
   in Arabic (RTL) and add an `ar/` raw set. Until then AR gets Arabic *captions*
   over English-UI phones — better than the English-caption fallback, not ideal.

## Edit captions / swap a shot

- **Caption copy:** edit the `SCREENS` list in `gen.py` and re-run.
- **New raw shot:** drop a PNG in `raw-screens/`, point its `SCREENS` row at
  it, re-run.

## Publish

```bash
bundle exec fastlane android listing   # needs Homebrew Ruby 3.x
```

## History / guardrails

- The feature graphic was previously the **wrong brand** ("Safar — Split Travel
  Expenses"); replaced with the Rihla wordmark + icon motif (2026-06-18).
- The old screenshot #1 advertised **Vault / Gear / Logistics** — features
  stripped in Phase 39. Don't reintroduce stale module screenshots; the
  `raw-screens/` set is ledger-only and current.
- Multi-currency copy is **truthful as of #261/#382** (per-group currency
  shipped). It was once removed as a false claim (#141) when it was vaporware —
  it is real now, so the listing mentions it again.

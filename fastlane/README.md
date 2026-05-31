# fastlane

Tools for editing the Play Store listing without clicking through Play Console.

## Setup (one-time)

```bash
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"   # use Homebrew Ruby 3.x, not system 2.6
bundle install
```

The Play service-account key lives at `secrets/play-key.json` (gitignored). If
it's missing, download a fresh JSON from the Google Cloud Console for the
service account that has Play access, and drop it there.

## Editing the listing

Two locales are managed: `fastlane/metadata/android/en-US/` (English) and
`fastlane/metadata/android/ar/` (Arabic). The `listing` lane pushes **both** —
edit the Arabic files too, or your en-US-only change ships alongside the existing
Arabic copy.

English assets and text live under `fastlane/metadata/android/en-US/`:

- `title.txt` / `short_description.txt` / `full_description.txt` — listing text
- `images/icon.png` — 512×512 listing icon (PNG or JPEG)
- `images/featureGraphic.jpeg` — 1024×500 banner
- `images/phoneScreenshots/*.png` — 1–8 screenshots, named `1_en-US.png`..`8_en-US.png`

Arabic assets live under `fastlane/metadata/android/ar/`:

- `title.txt` / `short_description.txt` / `full_description.txt` — Arabic listing text
- `images/phoneScreenshots/*.png` — screenshots named `1_ar.png`..`6_ar.png`

Edit any of those, then push:

```bash
bundle exec fastlane android icon       # icon + feature graphic only
bundle exec fastlane android listing    # icon + graphic + screenshots + text
```

Both lanes are AAB-safe — they never touch the binary or release notes, so they
won't interfere with an in-flight closed-testing review.

## Release notes

Release notes (changelogs) are **entered manually in Play Console** per release —
there is no `changelogs/` metadata and no lane uploads them (`skip_upload_changelogs`
is set everywhere). No `video.txt`/promo-video field is managed here either.

## Pulling current Play state

If the on-Play listing has drifted (someone edited via the web UI), pull it
back into the repo:

```bash
bundle exec fastlane android pull
```

This overwrites local files with what's currently live.

## Promoting to Production

CI builds and uploads each release to the closed **`first`** track only
(`.github/workflows/release_android.yml`). Once a build has soaked there and
you're ready to ship it to everyone, promote the **same** AAB up to Production —
no rebuild, no new versionCode:

```bash
bundle exec fastlane android promote_to_production                 # 10% staged rollout (default)
bundle exec fastlane android promote_to_production rollout:1.0     # full 100% rollout
bundle exec fastlane android promote_to_production status:draft    # stage a Production draft to publish by hand
bundle exec fastlane android promote_to_production version_code:18 # pin a specific build
```

It moves the existing binary between tracks; it does not touch listing assets or
release notes (enter Production release notes in Play Console).

**Before it will work:**

- The service account needs the **Release to production** permission in Play
  Console → Users and permissions.
- Production must be **unlocked** for the app. New personal Play accounts must
  complete the closed-testing requirement (≥12 testers for ≥14 days) before the
  Production track opens — until then the promotion is rejected regardless of
  this lane.

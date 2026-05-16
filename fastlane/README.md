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

Listing assets and text live under `fastlane/metadata/android/en-US/`:

- `title.txt` / `short_description.txt` / `full_description.txt` — listing text
- `images/icon.png` — 512×512 listing icon (PNG or JPEG)
- `images/featureGraphic.jpeg` — 1024×500 banner
- `images/phoneScreenshots/*.png` — 1–8 screenshots, named `1_en-US.png`..`8_en-US.png`

Edit any of those, then push:

```bash
bundle exec fastlane android icon       # icon + feature graphic only
bundle exec fastlane android listing    # icon + graphic + screenshots + text
```

Both lanes are AAB-safe — they never touch the binary or release notes, so they
won't interfere with an in-flight closed-testing review.

## Pulling current Play state

If the on-Play listing has drifted (someone edited via the web UI), pull it
back into the repo:

```bash
bundle exec fastlane android pull
```

This overwrites local files with what's currently live.

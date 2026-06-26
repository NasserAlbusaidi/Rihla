# Issue #140 bundled-font QA evidence

Run date: 2026-06-26

Checkout: `b335a12004b6` (`codex/140-font-qa`, `pubspec.yaml` `1.6.2+26`)

Device: Pixel 9 Pro XL, Android 16 / API 36, serial `4C171FDAS001U0`

## Build artifacts

- AAB command used for analysis:
  `flutter build appbundle --release --analyze-size --target-platform android-arm64 --dart-define-from-file=config.json`
- The exact issue command without `--target-platform` was attempted first and
  failed on Flutter 3.41.5 because size analysis now requires a single Android
  target platform instead of a multi-ABI bundle.
- AAB: `build/app/outputs/bundle/release/app-release.aab`
  - Size: `24,275,701` bytes (`24.3MB` Flutter output)
  - SHA-256: `bcbf2ab6aba3870544a2688eac7685ce89d6a5d29c78750d3212b6237b842f22`
  - Analyze-size summary: total compressed `23 MB`; `base/assets` `407 KB`
- APK used for device install: `build/app/outputs/flutter-apk/app-release.apk`
  - Size: `71,668,646` bytes (`71.7MB` Flutter output)
  - SHA-256: `99bc97036fcd4a5870e0a76ff8521f40ebef8b898e2589e0e6e628146fbb440b`

Bundled TTF raw sizes:

| Asset | Size |
|---|---:|
| `assets/fonts/Geist-Variable.ttf` | 168 KiB |
| `assets/fonts/GeistMono-Variable.ttf` | 168 KiB |
| `assets/fonts/ReemKufi-RihlaWordmark.ttf` | 12 KiB |
| `assets/fonts/InstrumentSerif-Regular.ttf` | 72 KiB |
| `assets/fonts/InstrumentSerif-Italic.ttf` | 72 KiB |

## Device pass

Fresh install path:

1. `adb uninstall com.safar.safar` returned `Success`.
2. Airplane mode was enabled before install and launch
   (`settings get global airplane_mode_on` returned `1`).
3. Installed the release APK with `adb install -r`.
4. Cleared logcat, launched with monkey, and captured
   `140-pixel-fresh-offline-launch.png`.
5. The fresh offline boot reached the startup error surface, which uses the
   bundled Instrument Serif display and Geist sans families. It cannot reach
   Home/Profile or render a ledger/profile money amount before Firebase Auth
   bootstrap because the device has no network.
6. `grep -i gstatic 140-pixel-fresh-offline-logcat.txt` returned no matches
   across 3,629 log lines.

Offline Home/Profile path:

1. Airplane mode was disabled once to let the release build complete anonymous
   Firebase bootstrap; `140-pixel-online-bootstrap.png` captures the resulting
   Home screen.
2. The app was force-stopped, airplane mode was re-enabled, logcat was cleared,
   and the app was cold-launched again offline.
3. `140-pixel-cold-offline-home-wordmark.png` captures the Rihla wordmark on
   Home with no network.
4. `140-pixel-cold-offline-profile-money.png` captures the profile `0.000`
   lifetime spend amount rendered via `RAmount` / Geist Mono with no network.
5. `grep -i gstatic 140-pixel-cold-offline-home-profile-logcat.txt` returned no
   matches across 4,869 log lines.

Airplane mode was restored off after the run
(`settings get global airplane_mode_on` returned `0`).

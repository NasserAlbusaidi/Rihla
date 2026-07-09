# iOS → TestFlight Setup

Personal paid Apple Developer account. **Team ID `T2U886CPS5`**, iOS bundle `com.nalbusaidi.rihla`.
Do NOT use the FRONTIER TECHNOLOGY team (`KZ93H835PC`) — that's a separate company account.

> **iOS bundle ≠ Android package.** `com.safar.safar` was already registered to another Apple team
> and couldn't be claimed, so iOS uses `com.nalbusaidi.rihla` while **Android keeps `com.safar.safar`**
> (already on Play). The two are independent — never "align" them. The iOS app has its own Firebase
> app (`1:231518921973:ios:c8bfaa64…`) + its own Google Sign-In OAuth client.

The repo is already wired for this team: signing (`ios/Runner.xcodeproj`), Push entitlement
(`ios/Runner/Runner.entitlements`), Universal Links (`hosting/.well-known/apple-app-site-association`),
export options (`ios/ExportOptions.plist`), and the `fastlane ios beta` lane. The steps below are the
**one-time account-side ceremony** those files depend on.

## One-time account setup (in order — most of it gates the first upload)

1. **Sign the paid agreements.** App Store Connect → Business / Agreements. A fresh account has these
   *pending*; nothing uploads until the relevant agreement is **Active**.

2. **Add the Apple ID to Xcode.** Xcode → Settings → Accounts → add the personal Apple ID (team
   `T2U886CPS5`). This lets automatic signing mint the certs + provisioning profiles.

3. **Register the App ID** `com.nalbusaidi.rihla` with **Push Notifications** + **Associated Domains**
   capabilities. Automatic signing creates it on first archive; the checked-in entitlements already
   request both capabilities. (Or register manually: Developer portal → Identifiers.)

4. **Create the app record** in App Store Connect → Apps → **+** → New App → iOS, name **Rihla**,
   bundle `com.nalbusaidi.rihla`, pick an SKU + primary language. Required before a build can appear in
   TestFlight.

5. **APNs Auth Key (turns on iOS push).** Developer portal → Keys → **+** → enable *Apple Push
   Notifications service (APNs)* → download the `.p8` (**one-time download**). Then Firebase Console →
   Project `rihla-safar` → Project Settings → Cloud Messaging → *Apple app configuration* → upload the
   APNs Auth Key with its **Key ID** and **Team ID `T2U886CPS5`**. Without this, iOS FCM tokens
   register but no notification is ever delivered.

6. **App Store Connect API key (for fastlane).** App Store Connect → Users and Access → **Integrations**
   → App Store Connect API → generate a key (**App Manager** role). Drop the downloaded
   `AuthKey_<KeyID>.p8` into `secrets/` **under Apple's own name** — the lane reads the Key ID from the
   filename. Then record the **Issuer ID** (the UUID at the top of that page):

   ```bash
   echo '<issuer-uuid>' > secrets/asc_issuer_id.txt   # or: export ASC_ISSUER_ID=<issuer-uuid>
   ```

   Both `secrets/AuthKey_*.p8` and `secrets/asc_issuer_id.txt` are gitignored.

## Deploy the Universal Links file

The AASA now points at `T2U886CPS5.com.nalbusaidi.rihla`. TestFlight/App Store builds are signed under the
new team, so deep links won't verify until the hosting file is redeployed:

```bash
firebase deploy --only hosting
```

Apple's CDN caches the AASA — reinstall the app after deploying to force a re-fetch.

## Ship a TestFlight build

Prerequisites: steps 1–6 done, `config.json` present at the repo root, Homebrew Ruby 3.x active.

```bash
bundle exec fastlane ios beta
```

The lane runs `flutter build ipa` (obfuscated, `--dart-define-from-file=config.json`,
`--export-options-plist=ios/ExportOptions.plist`) then `upload_to_testflight` via the API key.

**Build numbers must strictly increase per upload.** The IPA's `CFBundleVersion` comes from the
pubspec build number (`x.y.z+N`). Bump `N` before re-running if you upload again for the same version.
Do not hand-bump for a real release — `tool/release.sh` owns version bumps at tag time (Android); for
iOS-only TestFlight iterations, bumping just the `+N` build number is fine.

## No iOS CI yet

This lane runs locally on macOS. The gitignored `ios/Runner/GoogleService-Info.plist` (the iOS Firebase
config, project `rihla-safar`) must be present on the build machine for the archive — provide it locally
the same way `google-services.json` is provided for Android. Wiring the lane into GitHub Actions needs a
macOS runner plus that plist, the API key `.p8`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `config.json`
injected as encrypted secrets (mirror the base64 `CONFIG_JSON` pattern in `release_android.yml`) —
deferred until the manual lane is proven green.

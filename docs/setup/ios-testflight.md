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
`--export-options-plist=ios/ExportOptions.plist`) then `upload_to_testflight` via the API key,
and finally uploads debug symbols to Sentry (see below — optional, warn-not-block).

**Build numbers must strictly increase per upload.** The IPA's `CFBundleVersion` comes from the
pubspec build number (`x.y.z+N`). Bump `N` before re-running if you upload again for the same version.
Do not hand-bump for a real release — `tool/release.sh` owns version bumps at tag time (Android); for
iOS-only TestFlight iterations, bumping just the `+N` build number is fine.

## Sentry symbol upload (optional — crash symbolication)

The build is obfuscated, so without debug symbols Sentry shows unreadable, stripped crash
frames. After `upload_to_testflight`, the `beta` lane runs `dart run sentry_dart_plugin`
(the same plugin the Android release CI uses, configured under `sentry:` in `pubspec.yaml`)
to upload both symbol kinds for the build it just shipped:

- the **native iOS dSYMs** from `build/ios/archive/Runner.xcarchive/dSYMs/` (symbolicates
  the Swift/ObjC/engine frames), and
- the **Dart split-debug-info symbols** from `build/ios/symbols/` (from `--split-debug-info`;
  symbolicates the obfuscated Flutter/Dart frames).

The plugin reads `SENTRY_ORG`, `SENTRY_PROJECT` and `SENTRY_AUTH_TOKEN` from the environment.
The lane resolves those three, **environment variables first**, then falling back to a
gitignored **`secrets/sentry.env`** (simple `KEY=VALUE` lines, parsed in Ruby — never
shell-sourced, so the token stays out of shell history and the fastlane command log):

```bash
# secrets/sentry.env  (gitignored via the secrets/ rule)
SENTRY_ORG=<your-sentry-org-slug>
SENTRY_PROJECT=<your-sentry-project-slug>
SENTRY_AUTH_TOKEN=<sntrys_… token>
```

- **Org / project slugs:** Sentry → Settings → the org slug is in the URL / General Settings;
  the project slug is on the project's settings page.
- **Auth token:** Sentry → Settings → Auth Tokens (or an org internal-integration token) with
  the **`project:releases`** + **`project:write`** scopes. Nothing else needs those scopes.

**Warn-not-block, end to end.** The step runs *after* the TestFlight upload, so it can never
block a release. If any of the three values is unresolved, the lane logs a warning ("symbols
will NOT be uploaded, crash frames stay unsymbolicated") and continues; if the upload itself
fails, it logs an error and continues. A green TestFlight upload never depends on Sentry.

### Manual QA still open (not closeable from CI)

Symbolication can only be proven with a real crash from a real TestFlight build. After a
`beta` upload with the three values set: install the TestFlight build on a device, trigger a
test crash, and confirm in Sentry that **both** the native (Swift/ObjC/engine) **and** the
obfuscated Dart frames resolve to readable symbols. This device-dependent step is why #950
stays open after this change.

## No iOS CI yet

This lane runs locally on macOS. The gitignored `ios/Runner/GoogleService-Info.plist` (the iOS Firebase
config, project `rihla-safar`) must be present on the build machine for the archive — provide it locally
the same way `google-services.json` is provided for Android. Wiring the lane into GitHub Actions needs a
macOS runner plus that plist, the API key `.p8`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `config.json`
injected as encrypted secrets (mirror the base64 `CONFIG_JSON` pattern in `release_android.yml`) —
deferred until the manual lane is proven green.

# Plan — #354 WhatsApp-direct invite CTA (QR sheet)

**Date:** 2026-06-10
**Issue:** #354 — `design(invite): optional WhatsApp-direct (wa.me) invite CTA reusing the web.app/join link`
**Branch:** `feat/whatsapp-invite-354` (worktree `../Rihla-354`)
**Gate:** EXEMPT — no money math / firestore.rules / Cloud Functions auth / routing / schema-field. Rides `/automerge`.

## Goal

A WhatsApp CTA in the group invite QR sheet that opens WhatsApp prefilled with the
**existing** `groupShareInviteMessage` (which already embeds
`AppLinks.inviteUrl` → `rihla-safar.web.app/join/<CODE>`). Falls back to the OS
share sheet when WhatsApp isn't installed.

## Acceptance criteria (from #354)

- [ ] "Share via WhatsApp" CTA opens WhatsApp with the prefilled `groupShareInviteMessage` (code + web.app/join URL).
- [ ] Graceful fallback to the OS share sheet if WhatsApp isn't installed (`canLaunchUrl`).
- [ ] No `rihla.app` host anywhere; test asserts the web.app/join URL.

## Decision: scheme, not `wa.me`

The AC's literal combo — `https://wa.me/?text=` **and** `canLaunchUrl`-based
not-installed detection — is internally inconsistent: `canLaunchUrl` on an
`https://wa.me` URL returns true whenever *any* browser exists, so the
"not installed → fallback" branch could never fire and a WhatsApp-less phone
lands on `web.whatsapp.com`.

**Use the custom scheme** `whatsapp://send?text=<urlencoded message>` for both the
probe (`canLaunchUrl`) and the launch. It's the canonical native deep link and the
only form `canLaunchUrl` can use to detect WhatsApp's absence. The load-bearing
#354 requirement — the message carries `AppLinks.inviteUrl` (web.app/join), no
`rihla.app` — is preserved verbatim (we reuse `groupShareInviteMessage`).

## Load-bearing platform manifests (first `canLaunchUrl` use in the app)

`canLaunchUrl` is used nowhere today, so the package-visibility allow-lists were
never added. Without them the probe returns `false` even when WhatsApp IS
installed → feature silently dead on device (the #354 analogue of the iOS
share-origin trap):

- **Android** `android/app/src/main/AndroidManifest.xml` `<queries>`: add
  `<package android:name="com.whatsapp"/>`.
- **iOS** `ios/Runner/Info.plist`: add `LSApplicationQueriesSchemes` → `whatsapp`.

## Files

| File | Change |
|---|---|
| `lib/core/utils/whatsapp_share.dart` *(new)* | `whatsAppInviteUri(String message)` → `Uri(scheme:'whatsapp', host:'send', queryParameters:{'text': message})`. `shareInviteViaWhatsApp(BuildContext, String message, {required Future<void> Function() fallback})` → `canLaunchUrl` probe; installed → `launchUrl(externalApplication)`; not-installed OR throw → `await fallback()`. Single chokepoint — no callsite touches `url_launcher`. |
| `lib/features/groups/widgets/qr_invite_sheet.dart` | Insert a WhatsApp `_SheetButton` between Copy and Share. onTap → `shareInviteViaWhatsApp(context, msg, fallback: () => shareText(context, msg, subject: …))` where `msg = groupShareInviteMessage(name, uri, code)` (the existing call). |
| `lib/l10n/app_en.arb`, `app_ar.arb` | `groupShareViaWhatsApp` = "WhatsApp" / "واتساب" (+ `gen-l10n`). |
| `android/.../AndroidManifest.xml` | `<package android:name="com.whatsapp"/>` in `<queries>`. |
| `ios/Runner/Info.plist` | `LSApplicationQueriesSchemes` array w/ `whatsapp`. |
| `test/core/utils/whatsapp_share_test.dart` *(new)* | URI builder + fallback behaviour (mock `UrlLauncherPlatform.instance`). |
| `test/features/groups/.../qr_invite_sheet_*test.dart` | Button present; overflow guard. |

## Layout risk

Three icon+label buttons in one `Row` (Copy link / WhatsApp / Share) is tight,
worse in Arabic (`نسخ الرابط` / `واتساب` / `مشاركة`). Add an overflow widget test
(per `ledger_screen_overflow_test` discipline). If it trips: drop Copy to
icon-only, or stack WhatsApp full-width above the Copy/Share row.

## Icon

Iconsax has no WhatsApp brand glyph → default to a generic messaging icon
(`Iconsax.message`/`send_2`). Real green WhatsApp mark = brand SVG asset, deferred
unless requested.

## TDD order

1. **RED** `whatsapp_share_test.dart`:
   - `whatsAppInviteUri(msg)` → scheme `whatsapp`, host `send`, `queryParameters['text'] == msg`; encoded string contains `wa.me`? no — contains the web.app/join URL; asserts NO `rihla.app`.
   - `shareInviteViaWhatsApp`: mock `UrlLauncherPlatform` `canLaunch → false` ⇒ `fallback` called, `launchUrl` NOT called; `canLaunch → true` ⇒ `launchUrl` called once with the `whatsapp://send?text=` URL, `fallback` NOT called; `launchUrl` throws ⇒ `fallback` called.
2. **GREEN** `whatsapp_share.dart`.
3. Wire button into `qr_invite_sheet.dart`; widget test: button present + tap on not-installed path drives `shareText` channel.
4. Overflow widget test (EN + Arabic locale) → adjust layout if RED.
5. Manifests (Android `<queries>`, iOS `LSApplicationQueriesSchemes`).
6. `flutter analyze` clean; full `flutter test`.

## Verification (7 principles, abbreviated)

- **Callsite classification:** the message string is INBOUND-only (display/share payload, never persisted) — reuses `groupShareInviteMessage` unchanged, no write path touched.
- **Code-not-docs:** `AppLinks.inviteUrl` host confirmed `rihla-safar.web.app` (`app_links.dart:14`); `groupShareInviteMessage` arity `(groupName, uri, code)` confirmed (`app_localizations.dart:3931`). `url_launcher ^6.3.2`, `mocktail ^1.0.4` present. `canLaunchUrl` used nowhere (grep clean) → manifests required.
- **Read-path per write-path:** none — no persisted state changes.
- No Gate (no money/rules/routing/schema surface).

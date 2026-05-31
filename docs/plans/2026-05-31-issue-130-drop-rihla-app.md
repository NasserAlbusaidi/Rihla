# #130 — Drop the dead `rihla.app` deep-link host (commit to `rihla-safar.web.app`)

**Decision (this session):** `rihla.app` is dead/parked (Sedo). Reclaim-vs-drop → **DROP**. The app
standardizes on `rihla-safar.web.app` as its sole user-facing/legal domain. Any future reclaim re-adds
the host. This is a **deep-links change → runs The Gate before implementation.**

**Gate round 1 (codex) corrected two false premises in v1 of this spec** (now fixed below):
the AndroidManifest already declares a `rihla-safar.web.app` `/join` filter (no "missing web.app
filter"), and iOS entitlements + AGENTS.md + CHANGELOG also carry `rihla.app` and were missed.

## Live state (verified 2026-05-31, not memory)
- `curl https://rihla.app/privacy` → `000` (dead). `web.app/privacy|terms|delete-data` → `200`.
- App already mints `web.app` links (`app_links.dart:14 inviteLinkHost = 'rihla-safar.web.app'`).
- `hosting/.well-known/assetlinks.json` + `apple-app-site-association` carry **no** `rihla.app` refs
  (host-agnostic: appIDs + path components only). No change there.

## Full `rihla.app` inventory (repo sweep, excl. `docs/plans/archive/*` and historical plan docs)
| File | Line | Kind | Action |
|---|---|---|---|
| `lib/core/services/deep_link_service.dart` | 13 | INBOUND accept-host | remove |
| `android/app/src/main/AndroidManifest.xml` | ~58-66 | App Links intent-filter | remove block |
| `ios/Runner/Runner.entitlements` | 9 | associated-domain | remove |
| `test/unit/deep_link_service_test.dart` | 19,32,48,57,78,84,85,92 | fixtures | TDD (below) |
| `lib/core/config/app_links.dart` | 5-6 | comment | reword |
| `lib/features/groups/widgets/qr_invite_sheet.dart` | 17 | comment | reword |
| `lib/features/auth/services/auth_email_link_config.dart` | 24 | comment | reword |
| `AGENTS.md` | 167 | current guidance | → web.app |
| `CLAUDE.md` | invariant | current guidance | → "dropped per #130" |
| `CHANGELOG.md` | 99-100 | current-tense infra fact | → web.app |
| `docs/plans/2026-05-16-arabic-localization-design.md` | 193 | plan doc | → web.app |

Excluded (leave): `docs/plans/archive/*`, `docs/plans/2026-05-17-...pr2a...md` (those are the dead
`feedback@rihla.app` EMAIL literal in historical plan text; live `feedbackEmail` is already a gmail
address at `app_links.dart:23` — out of scope for a deep-link domain change).

## Functional changes (Gate-gated)

### 1. `lib/core/services/deep_link_service.dart` (INBOUND parse only)
`_universalJoinHosts` (12-16) is read by exactly one callsite, `_universalLinkInviteCode:80`. INBOUND
only — gates parsing an incoming https link into `/join/<code>`. Nothing mints from it.
- Remove line 13 `'rihla.app',`. Result: `{'rihla-safar.web.app', 'rihla-safar.firebaseapp.com'}`.

### 2. `android/app/src/main/AndroidManifest.xml` — FIVE intent-filters today
1. `firebaseapp.com` `/__/auth/links` (autoVerify) — **keep** (auth recovery)
2. `rihla-safar.web.app` `/join` (autoVerify) — **keep** (the minted host; open-in-app already works)
3. `firebaseapp.com` `/join` (autoVerify) — **keep**
4. `rihla` scheme (autoVerify=false) — **keep**
5. `rihla.app` `/join` (autoVerify) — **REMOVE this block only** (`android:host="rihla.app"`)

Edit must target **only** filter #5. Do not touch #1-#4. (v1 spec wrongly claimed web.app had no
filter — that was a mis-read of lines 31-39; deleting/altering #2 would regress live open-in-app.)

### 3. `ios/Runner/Runner.entitlements`
`associated-domains` array declares 3: `firebaseapp.com`, `web.app`, `rihla.app`.
- Remove line 9 `<string>applinks:rihla.app</string>`. Keep the other two.

## Tests (TDD)

### 4. `test/unit/deep_link_service_test.dart`
- **RED first:** add `test('rejects the retired rihla.app universal-link host (#130)')` →
  `parse('https://rihla.app/join/ABC123')` and `.../join?code=ABC123` both `isNull`. Fails today
  (rihla.app currently parses), passes after change #1.
- Positive fixtures off rihla.app (web.app already covered): L19 + L32 → delete the rihla.app lines
  (web.app equivalents already present at L21-23 / L36); L43 (case-insensitive) →
  `HTTPS://RIHLA-SAFAR.WEB.APP/join/abc123`; L48 (trim) → web.app; L57 (segment-beats-query) → web.app.
- Negative fixtures off rihla.app → web.app so they keep testing **path-validation**, not host-rejection:
  L78 `/groups/`, L84 `/join`, L85 `/join?code=`, L92 `/join/ABC_12`.

### 5. `test/unit/auth_link_hosting_files_test.dart` (regression guards — codex P2)
Neither the manifest test (78-88) nor the iOS test (90-98) asserts rihla.app present, so removal won't
break them. ADD absence guards so it can never silently reappear:
- manifest test: `expect(manifest, isNot(contains('android:host="rihla.app"')))`
- iOS test: `expect(entitlements, isNot(contains('applinks:rihla.app')))`

## Doc/comment scrub (no behavior; same PR)
- `app_links.dart:4-6` — drop "until `rihla.app` is wired … flipped back to the bare `rihla.app` host";
  state web.app is the canonical Hosting domain.
- `qr_invite_sheet.dart:17` — reword the "until the custom `rihla.app`" comment.
- `auth_email_link_config.dart:24` — drop the `auth.rihla.app` example.
- `AGENTS.md:167` — `rihla.app/join/<code>` → `rihla-safar.web.app/join/<code>`.
- `CLAUDE.md` invariant — "rihla.app … survives only as a legacy host …(reclaim-vs-drop tracked in #130)"
  → "rihla.app fully dropped per #130; web.app is the sole domain (deep-link host, App Links, legal)."
- `CHANGELOG.md:99-100` — `rihla.app/join` + `rihla.app/privacy|terms|delete-data` → web.app
  (current-tense infra claims, now false; in-scope because it's the same domain #130 fixes).
- `docs/plans/2026-05-16-arabic-localization-design.md:193` — `rihla.app/*` → `web.app/*`.

## Read-path / write-path trace
- `_universalJoinHosts` read-path: only `_universalLinkInviteCode`. No persistence/mint. Removing a host
  can only *reject* a link that today routes; the rejected host (rihla.app) is dead → no working link
  regresses. Inbound-set and mint-set (`app_links.inviteUrl`/`qr_invite_sheet`) both already on web.app.
- Android/iOS: dropping filter #5 / the entitlement only stops the OS associating the **dead** rihla.app
  host with the app. web.app + firebaseapp.com associations (the live ones) are untouched.

## Verification
- `flutter test test/unit/deep_link_service_test.dart test/unit/auth_link_hosting_files_test.dart`
  (new RED → GREEN; guards green; others green).
- `flutter analyze` clean.
- `flutter test` full suite.
- Manual gate (user, out-of-band): Play Console → App content → Privacy Policy URL =
  `https://rihla-safar.web.app/privacy`; re-curl → 200. (This is the actual issue-close gate.)

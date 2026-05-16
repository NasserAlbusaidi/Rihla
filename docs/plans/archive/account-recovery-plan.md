# Account Recovery — Implementation Plan (v1.2)

| | |
|---|---|
| **Status** | Ready for execution |
| **Spec** | [account-recovery.md](./account-recovery.md) (decisions locked 2026-05-13) |
| **Target** | v1.2 — P0 blocker for public Play Store launch (OD-8) |
| **Author** | Nasser Albusaidi |
| **Plan written** | 2026-05-13 |

This plan turns the locked spec into phased work for Codex. Each phase is independently shippable, ordered so the riskiest unknown (P0) is de-risked before any UI is built. Read the spec for *what* and *why*; this doc is *how* and *in what order*.

## Locked decisions (recap)

OD-1 Settings-only, no banner · OD-2 Sign-out shown only when email linked · OD-3 Wipe-and-rehydrate `safar_cache.db` on UID swap · OD-4 24h link expiry · OD-5 Firebase built-in throttling · OD-6 Permanent email in v1.2 · OD-7 No orphan cleanup · OD-8 P0 blocker for public launch.

## Phase plan

| # | Phase | Why first/next | Size |
|---|---|---|---|
| P0 | Spike: App Links / Universal Links continue page | Single largest unknown (spec §7.1). If this can't be made reliable, the whole feature changes shape. **Do not start P1+ until P0 lands a working dev-build flow.** | M |
| P1 | Auth helpers + `userChanges` plumbing | Foundational. All UI phases depend on it. Pure logic, easy to test. | M |
| P2 | Cache invalidation on UID swap | Foundational. Must be in place before any UI exposes the recovery path, or recovery will mix UIDs in cache. | S |
| P3 | Settings "Linked email" UI + link flow | First user-facing entry point. Per OD-1 this is the *only* entry point in v1.2. | M |
| P4 | Home empty-state "Restore from email" + recovery flow | Symmetric counterpart to P3. Required to deliver actual recovery value. | M |
| P5 | "Sign out of this device" (linked users only) | Small UI on top of P1 helpers. Gates the OD-2 use case (lend / sell phone). | S |
| P6 | Privacy policy + Play Store data safety + data deletion extension | Compliance gate. Must be live before any v1.2 build ships to public Play Store. Can run partially in parallel with P1–P5. | M |
| P7 | Regression + new-flow test suite | Locks the invariants. Must pass before tagging v1.2. | M |
| P8 | Release prep — version bump, alpha verification, public-launch readiness | Final gate before flipping the public Play Store listing on. | S |

Estimated total: ~2–3 focused weeks of Codex work, depending on how badly the P0 spike fights back.

---

## P0 — Spike: App Links / Universal Links continue page

**Goal.** Reach the point where, on a real Android device and a real iOS device, a Firebase email-link tapped from Mail opens the Rihla app (not a browser) and lands inside a Flutter route that has the email-link credential in hand.

**Why this first.** Firebase Dynamic Links was deprecated August 2025 (spec §7.1). Every legacy tutorial is wrong. Until we know the new path works for our `rihla-safar` Firebase project + `com.safar.safar` Android ID + the iOS bundle ID, we can't size the rest. If this phase blows up, the rest of the plan re-flows.

**Work.**

1. Stand up Firebase Hosting under `rihla-safar`. A single static `continue.html` is enough — it doesn't render anything important, it just exists at a stable URL so the OS can intercept it.
2. Add Android **App Links** verification:
   - `<your-domain>/.well-known/assetlinks.json` published from Firebase Hosting.
   - `AndroidManifest.xml` deep link intent filter on `<your-domain>/__/auth/links/*` (or whatever path we settle on), `autoVerify="true"`.
   - SHA-256 fingerprints for both debug and Play upload key. Pull from Play Console signing.
3. Add iOS **Universal Links**:
   - `<your-domain>/.well-known/apple-app-site-association` (no extension, no BOM, served as `application/json`).
   - Associated Domains entitlement in `ios/Runner/Runner.entitlements`: `applinks:<your-domain>`.
4. Flutter side: install + configure `firebase_dynamic_links` replacement. As of Jan 2026 the canonical FlutterFire path is `firebase_auth`'s `actionCodeSettings` with `handleCodeInApp: true` plus a deep-link listener (`uni_links` / `app_links` package). **Re-verify against FlutterFire docs on the day you start P0 — don't trust this paragraph blindly.**
5. Test matrix:
   - Send a sign-in link via `auth.sendSignInLinkToEmail(...)` to a real address from a dev build.
   - Open the email on the same device. Tap link. Verify the app opens (not a browser tab).
   - Verify `auth.isSignInWithEmailLink(deepLink)` returns true inside the app.
   - Repeat on iOS.
   - Bonus: open the email on a *different* device. Verify the fallback "enter your email" prompt path works (spec §4.7).

**Acceptance.** Two real devices (one Android, one iOS) where tapping a magic link opens the app and a `print()` inside a deep-link handler logs the credential URL. No production secrets baked in. Commit the Hosting config + association files to the repo.

**Risks.**

- **Android verification can take hours to propagate.** Plan a 24h buffer after publishing `assetlinks.json` before final acceptance test.
- **iOS Universal Links cache aggressively.** Test on a fresh install or after a device restart. `swcutil` on macOS can flush, but on a real iPhone the cleanest reset is uninstall + 24h wait or use a TestFlight build.
- **The Hosting domain becomes a hard dependency forever.** Pick the name carefully — `rihla.app` or a `firebaseapp.com` subdomain. Changing later is painful because every previously-sent link references it.

**Out of scope for P0.** Any UI inside the app. Any link/recover/signOut helpers. P0 ends when the deep-link plumbing is proven on real hardware.

---

## P1 — Auth helpers + `userChanges` plumbing

**Goal.** Add the four pure auth operations the rest of the feature needs, and route the rest of the app to `userChanges` (not `currentUser` snapshots) so UID swaps re-trigger downstream state.

**Files touched.**

- `lib/core/config/firebase_config.dart` — add `linkEmailToCurrentUser(String email)`, `sendRecoveryLink(String email)`, `completeRecovery(String emailLink)`, `signOutCurrentDevice()`. Keep `ensureAnonymousSession()` unchanged.
- `lib/features/auth/providers/auth_provider.dart` — replace any `currentUser` reads with a `StreamProvider` watching `auth.userChanges()`. Expose `uidProvider` and `linkedEmailProvider` derived from it.
- New: `lib/features/auth/services/auth_recovery_service.dart` — thin orchestration over `FirebaseConfig` for testability (wraps `linkWithCredential`, `signInWithEmailLink`, `signOut`, plus `firestore.waitForPendingWrites()` with timeout per spec §7.6).

**Acceptance.**

- `linkEmailToCurrentUser` calls `auth.sendSignInLinkToEmail` with `actionCodeSettings` (handleCodeInApp + URL from P0). On confirmation tap, the receiver path calls `linkWithCredential` and the UID is unchanged.
- `sendRecoveryLink` is the same send-side call but the receiver path calls `signInWithEmailLink` after first awaiting `firestore.waitForPendingWrites()` (5s timeout) and `auth.signOut()` of the device's prior anon UID.
- `signOutCurrentDevice` requires a linked email present; otherwise throws `StateError` (UI should never call it without a linked email per OD-2).
- `linkedEmailProvider` resolves from `userChanges().last.email` and is `null` for purely-anonymous users.
- Unit tests with mocked `FirebaseAuth` cover all four operations and the pending-writes-timeout branch.

**Risks.**

- `firestore.waitForPendingWrites()` can hang forever offline. Always wrap in a `Future.any` with a timer. Spec §7.6.
- Don't rebuild the entire app tree on every `userChanges` tick — gate downstream invalidation on actual UID change (`previousUid != currentUid`), not just any auth event.

---

## P2 — Cache invalidation on UID swap

**Goal.** When the active UID changes, wipe `safar_cache.db` before any provider reads under the new UID. Per OD-3.

**Files touched.**

- `lib/core/services/local_database.dart` — add `wipeAndReinitialize()` that closes the open db handle, deletes the file at the resolved path, and re-runs `_onCreate` / `_onUpgrade` on a fresh handle.
- New: `lib/features/auth/services/uid_change_listener.dart` — subscribes to `userChanges()`, holds the last seen UID, calls `LocalDatabase.wipeAndReinitialize()` + `ref.invalidate(...)` on any UID-affecting providers when the UID changes.
- `lib/main.dart` — start the listener after `ensureAnonymousSession()` and before `runApp` (or as an `ProviderObserver` registered at the top of the tree).

**Acceptance.**

- A widget test that simulates two `userChanges` emissions with different UIDs verifies `LocalDatabase.wipeAndReinitialize()` is called exactly once.
- Manual: with a populated cache, force a `signOut` + new anon sign-in. The cache file's `mtime` changes; subsequent reads re-hit Firestore.
- No reads against the cache happen between sign-out and wipe (i.e. providers that depend on UID are invalidated *before* the wipe completes, so they show a loading state, not stale-UID data).

**Risks.**

- `local_database.dart` is currently schema v5 per CLAUDE.md (spec §7.2 mentions v7; pick whichever is current in the codebase). The wipe must be schema-agnostic — don't hardcode table lists.
- Open transactions in flight when wipe fires will throw. Ensure providers cancel subscriptions on UID change before wipe runs.

---

## P3 — Settings "Linked email" UI + link flow

**Goal.** Per OD-1, the *only* v1.2 entry point. In Settings, show a "Linked email" section that either shows "Not set" + "Set up" CTA, or the linked email + the OD-2 sign-out action.

**Files touched.**

- `lib/features/settings/screens/profile_screen.dart` — add the "Linked email" section.
- New: `lib/features/auth/screens/link_email_screen.dart` — form to enter email, confirm-by-retyping, "Send link" action.
- New: `lib/features/auth/screens/link_email_sent_screen.dart` — "Check your inbox" interstitial with resend (60s cooldown per spec §10 risk row 3).
- Router: add `/settings/link-email` and `/settings/link-email/sent` under the existing GoRouter tree (CLAUDE.md routing rules).

**Acceptance.**

- Settings shows the correct state for both linked and unlinked users, driven by `linkedEmailProvider`.
- Submitting the form calls `linkEmailToCurrentUser` and routes to the sent screen.
- If the email is already linked to another Firebase user, the error path shows: *"This email is already linked to a Rihla account. Restore from that account instead."* (spec FR-LINK-5).
- Disclosure copy on the link screen: *"Your email is used only to restore your Rihla data. We don't send marketing email and we don't share it."* (spec §6.1).
- Widget tests with mocked `AuthRecoveryService` cover the happy path, the "already linked" error, and the resend cooldown.

**Risks.**

- Email validation. Use a permissive regex; do not block valid-but-uncommon TLDs.
- Don't store the entered email in `SharedPreferences` *before* the link succeeds — only after. Otherwise on app restart we'd think a link was in progress when it wasn't.

---

## P4 — Home empty-state "Restore from email" + recovery flow

**Goal.** On a device with no owned participant docs, surface "I had Rihla before — restore" alongside the existing "Create / Join trip" CTAs. Drive the recovery flow per spec §4.2.

**Files touched.**

- `lib/features/home/screens/home_screen.dart` — empty state gets a third CTA, visible only when `ownedParticipantDocsProvider.length == 0`.
- New: `lib/features/auth/screens/recover_screen.dart` — email entry form.
- New: `lib/features/auth/screens/recover_pending_screen.dart` — interstitial.
- New: `lib/features/auth/widgets/sign_out_first_dialog.dart` — the spec §4.3 blocking dialog when a populated device attempts recovery.
- Router: `/recover`, `/recover/pending`.
- Deep-link handler (from P0): when the app receives an email link AND no active anonymous-link-in-progress is in SharedPreferences, route to recovery path; otherwise route to link-confirmation path.

**Acceptance.**

- Empty-state CTA present and tappable only when there are zero owned participant docs.
- The dialog at spec §4.3 fires when there are docs, blocks recovery, and "Sign out and continue" cleanly hands off into the recovery flow.
- Successful recovery: P2's cache-wipe fires, the home screen re-hydrates with the restored user's trips, and a confirmation toast *"Welcome back"* shows.
- Unknown email surfaces FR-REC-5 copy: *"We couldn't find a Rihla account with this email. Make sure you linked it on your previous device first."*
- Integration test with mocked `AuthRecoveryService` covers happy path + sign-out-first + unknown email.

**Risks.**

- Detecting "owned participant docs" must be cheap on a cold start. A single Firestore query keyed on the current anon UID is fine — no scanning.
- The deep-link router must distinguish link-from-Settings vs. recovery from a never-linked device. Store an `inFlightOp: 'link' | 'recover'` flag in SharedPreferences when the send-link call succeeds; deep-link handler reads + clears it on entry.

---

## P5 — "Sign out of this device" (linked users only)

**Goal.** Per OD-2, expose sign-out in Settings only when an email is linked. Per spec §4.8, confirm with *"Your data stays in the cloud."*, wipe local state, return to empty home.

**Files touched.**

- `lib/features/settings/screens/profile_screen.dart` — sign-out row in the "Linked email" section, visible only when linked.
- New: `lib/features/auth/widgets/sign_out_confirm_dialog.dart`.

**Acceptance.**

- The row is invisible for unlinked users (no row, no disabled-row hint — completely absent per OD-2 reasoning).
- Tapping sign-out, confirming, awaits pending-writes (5s timeout), calls `auth.signOut()`, P2's UID-change pipeline runs (cache wipe + provider invalidation + new anon session via `ensureAnonymousSession`), user lands on empty home with the P4 "Restore from email" CTA visible.
- Widget test covering the dialog confirm and cancel branches.

**Risks.**

- If `waitForPendingWrites` times out, surface a warning and require the user to re-confirm (spec §7.6 + §10 risk row 7).

---

## P6 — Privacy policy + Play Store data safety + data deletion extension

**Goal.** Compliance gate (spec §6). Must land before any build with this feature reaches public Play Store.

**Work.**

1. **Privacy policy** — draft and host a real policy enumerating: email collection, purpose (recovery only), retention (until account deletion), no third-party sharing, no marketing email, anonymous-user data described. Host on the same Firebase Hosting site as the P0 continue page. Add a `/privacy` link to Settings.
2. **Play Store data safety form** — update to declare email as collected, not shared, used for "Account management", optional. All existing categories unchanged.
3. **Data deletion flow** — extend the existing flow (currently a Play Store readiness gap noted in S692 / obs 12259) to: (a) call `user.delete()` which cascades the email credential, (b) delete participant docs and authored expenses respecting existing soft-delete policy, (c) be reachable both in-app *and* via a documented out-of-app channel (Play policy requirement).
4. **Sentry / analytics audit** — grep for any logging that could leak email. Verify Sentry beforeSend strips it. Spec §7.7.

**Acceptance.**

- Privacy policy live at a stable URL, linked from Settings.
- Data safety form updated in Play Console draft (not submitted until v1.2 is ready).
- In-app deletion exercises all three steps end-to-end on a test account.
- Sentry test: trigger an error inside the link screen with the email field populated; verify the breadcrumb does not contain the email.

**Risks.**

- Privacy policy text is the user's call, not Codex's. Codex can draft a starting point; the user must review and own the final wording.
- `user.delete()` requires the user to have signed in recently; otherwise Firebase requires re-auth. Handle the `requires-recent-login` error path.

---

## P7 — Regression + new-flow test suite

**Goal.** Lock the invariants from spec §5.4–5.5 and §10 risk register before tagging v1.2.

**Coverage.**

- **Regression (unchanged behavior):** Every existing flow that ran under an anon UID must still work. Run the full integration suite under (a) a never-linked anon user, (b) a linked user on their original device. No flow should diverge.
- **Link:** unit + widget for `linkEmailToCurrentUser` happy path, already-linked error, network failure, send-link-cooldown.
- **Recover:** unit + widget for `completeRecovery` happy path, unknown email, expired link, sign-out-first dialog, different-device entry-email path (spec §4.7).
- **Sign-out:** widget for confirm and cancel, plus pending-writes-timeout branch.
- **Cache invariant:** integration test that confirms `safar_cache.db` is wiped on UID change and re-populated correctly.
- **Data invariants (FR-INV-1..3):** test that document IDs, displayName, and balance calculations are stable across link and recover.

**Acceptance.**

- `flutter test` green on all of the above.
- `flutter analyze` clean.
- Manual smoke test on real Android device covering all four flows.

---

## P8 — Release prep

**Goal.** Flip the public Play Store listing on (OD-8).

**Steps.**

1. Version bump: `pubspec.yaml` to `1.2.0+11` (or whatever the next code is when we get here).
2. CHANGELOG entry summarizing user-facing changes.
3. Build alpha-track AAB via the existing GitHub Actions workflow. Verify install + flows on a clean device.
4. Promote alpha → production in Play Console.
5. Submit updated data safety form (P6).
6. Update store listing copy if needed.
7. Watch for first-day error spikes in Sentry; have a rollback plan ready (Play Store managed publishing pause).

**Acceptance.** Production listing is public and at least one external tester (not the author) completes link → uninstall → reinstall → recover end-to-end successfully.

---

## Cross-cutting checks (run at end of each phase)

- `flutter analyze` clean.
- `flutter test` green.
- No new TODOs without a referenced spec section.
- No Sentry breadcrumb / log statement contains user email.
- No mention of "create account" / "sign up" / "password" anywhere in user-facing copy.

## Hand-off notes for Codex

- Read [account-recovery.md](./account-recovery.md) before starting any phase. The spec is the source of truth; this plan is the execution order.
- Treat phase boundaries as commit boundaries. One PR per phase, max.
- If P0 deviates from this plan (likely — FlutterFire is the most volatile dep), update the plan in the same PR. Do not let the plan and the code drift.
- Do not introduce a "create account" / "sign up" framing anywhere in code or copy. The mental model is *"attach an email so you can come back"* (spec §2). Identifier names like `signUp` or `register` are wrong; use `link`, `recover`, `signOut`.

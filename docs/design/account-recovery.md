# Account Recovery via Linked Email

| | |
|---|---|
| **Status** | Decisions locked 2026-05-13 — ready for implementation planning |
| **Target release** | v1.2+ (before public Play Store launch) |
| **Author** | Nasser Albusaidi |
| **Created** | 2026-05-12 |
| **Depends on** | Privacy policy + data-deletion flow (existing gap on Play Store readiness punch list) |
| **Blocks** | Marketed / public Play Store launch (recommended, not strict) |

## 1. Problem

Rihla currently signs every user in via Firebase **anonymous auth** only. The anonymous UID is the sole binding between a user and their data in Firestore — participant docs, group memberships, expenses, settlements, and activity logs all key off `auth.uid`. The UID is persisted locally in Firebase Auth's platform storage (Keychain on iOS, internal storage on Android).

If that local state is destroyed, **every record the user created is silently orphaned in Firestore**:

- "Clear app data" on Android (verified by the author 2026-05-12 — this is what triggered this spec)
- Factory reset
- Uninstall + reinstall on Android (iOS usually preserves Keychain across reinstall, Android does not)
- Auth state corruption from a bad app update
- Switching devices entirely

`_AuthGate` runs on every cold start; if no session is restored, it mints a fresh anonymous UID via `signInAnonymously()`. That new UID cannot read or claim the old user's documents — Firestore rules treat `auth.uid` as the membership key. The data still exists; the user just has no path back to it.

There is no recovery mechanism today. For a financial / expense-tracking app, this is a silent total-data-loss bug waiting to bite users — and exactly the kind of failure that drives 1-star reviews on a public Play Store listing.

## 2. Goal

Give users an **opt-in** way to attach an email to their anonymous Firebase identity and, on a new device or after losing local auth state, restore the same identity by entering that email and tapping a passwordless magic link.

The mental model is **"attach an email so you can come back"** — not "sign up," not "back up your data." We never adopt the framing of an account system.

### Non-goals

- **No "Sign up" / "Create account" flow.** First launch remains silent anonymous sign-in.
- **No login screen on first launch.** Recovery is exclusively initiated from inside the app (Settings) on a device that already has an anonymous session.
- **No password.** Email link only.
- **No data merging across UIDs.** If a device already has a populated anonymous session and the user attempts to recover, we refuse — we never silently merge two users' data.
- **No multi-device sync.** Recovery is for getting back to your identity, not for using Rihla on two phones simultaneously. Concurrent use of the same UID on multiple devices is not formally supported in v1.2.
- **No other recovery mechanisms.** No phone number, no social login (Google, Apple), no recovery codes. One path: email link.
- **Not a v1.1 feature.** This is parked for the pre-public-launch window.

## 3. Mental Model

The Firebase-side mechanism is `linkWithCredential(emailAuthCredential)` (on the original device) and `signInWithEmailLink()` (on the recovery device). The anonymous UID is **preserved** through linking — Firebase attaches the email as a second credential to the same underlying user. On recovery, signing in with the linked email returns the *same* UID.

This means:

- **Linking from the original device** is a one-time, non-destructive enhancement of the existing identity.
- **Recovering on a new device** is a credential swap, not a data move. Firestore data is already there; we're just changing which UID the local Firebase Auth client holds.
- **The "fresh anonymous UID" that the recovery device created at install time is discarded.** It owns no data, so dropping it costs nothing.

## 4. User Scenarios

### 4.1 Primary: User links email on their main device

1. User opens the app (existing anonymous session, has groups / expenses).
2. User navigates to Settings → "Linked email" (no proactive Home banner; entry is opt-in only per OD-1).
3. Settings shows "Not set" with a "Set up" CTA. User taps it.
4. User enters their email. App calls `linkWithCredential` with an email-link credential.
5. Firebase sends a confirmation link to the email. User taps the link on the same device.
6. App returns to Settings showing the email as linked.
7. From this point forward, the email is permanently attached to this Firebase identity.

### 4.2 Primary: User restores on a new device

1. User installs Rihla on a new phone (or after clearing data). `_AuthGate` runs, creates a new anonymous UID, no data.
2. App lands on Home. Empty state shows *"Welcome to Rihla"* + two buttons: *"Start a new trip"* (default flow) and *"I had Rihla before — restore"*.
3. User taps "I had Rihla before — restore." Recovery screen asks for their email.
4. User enters email. App sends a sign-in link via `sendSignInLinkToEmail`.
5. User opens email on the same device, taps the link.
6. App handles the deep link, calls `signInWithEmailLink`, receives the original UID, signs out of the fresh anonymous UID first.
7. Cache is wiped (`safar_cache.db`) and the app re-bootstraps under the restored UID. All groups, expenses, and balances reappear.
8. User sees a confirmation toast: *"Welcome back."*

### 4.3 Edge: Recovery device already has data

User attempts recovery on a device that already has a populated anonymous session (groups joined, expenses logged) — e.g., they were using two phones in parallel and forgot one was active.

- App detects this in step 3 of 4.2 (before sending the email) by checking whether the local UID has owned participant docs.
- Shows a blocking dialog: *"This device is already in use. To restore a different identity, you'll lose the data on this device. Sign out first?"*
- Two options: **"Sign out and continue"** (wipes local state, proceeds with recovery — old anon UID and its data are orphaned, just like today's bug) or **"Cancel."**
- We **never** auto-merge.

### 4.4 Edge: Email already linked to a different UID

User enters an email that's already linked to another Firebase identity (e.g., they previously linked from a different phone with a different anon UID).

- This is **the intended path** — sending the link still routes to the original UID. The current device's anon UID is discarded as in 4.2.
- The only ambiguous case is if a user uses the same email across two separate "first installs" that both linked. Firebase prevents this: `linkWithCredential` fails if the email is already linked to another user. The second link attempt surfaces an error: *"This email is already linked to a Rihla account. Restore from that account instead."*

### 4.5 Edge: User wants to change their linked email

**Not supported in v1.2.** Linking is one-way and permanent. Changing the email would require an unlink + re-link flow with security implications (race conditions, accidental lockout, audit trail). If user demand emerges post-launch, revisit as a separate feature.

If the user explicitly asks support how to change it: the only path is to keep using the old email (since recovery only matters when the phone is lost; changing email proactively is an account-management concern we don't have).

### 4.6 Edge: Link expires before user taps it

Firebase email links expire after a configurable period (default 1 hour, settable up to 7 days). On tap of an expired link the app shows: *"This link expired. Request a new one?"* with a button to resend.

### 4.7 Edge: User taps link on a different device

User requests a link on Phone A but taps the link on Phone B (e.g., they have email open on their tablet).

- Firebase email links are bound to the device that requested them via a stored `emailForSignIn` value. If Phone B doesn't have that stored value, the app prompts: *"Confirm your email to complete sign-in"* (entering the email manually).
- Once the email is re-entered, sign-in completes on Phone B. The anon session on Phone B (if any) is replaced.
- Phone A's request is invalidated.

### 4.8 Edge: User wants to "sign out" on linked device

User explicitly wants to remove their identity from a device (e.g., selling the phone, lending to family).

- Settings → "Linked email" → **"Sign out of this device"** (only visible if email is linked).
- Confirms with: *"Your data stays in the cloud. To restore, enter your email again on any device."*
- App calls `auth.signOut()`, wipes `safar_cache.db`, creates a fresh anonymous session, returns to empty Home.
- User can re-recover anytime by entering their linked email.

**Without a linked email, "sign out" does not exist** — there's no way to come back, so we don't offer it as a way to lose data.

## 5. Functional Requirements

### 5.1 Linking flow (FR-LINK)

- **FR-LINK-1:** Settings shows a "Linked email" section. When unlinked, it shows "Not set" + a "Set up" CTA. When linked, it shows the email + a "Sign out of this device" action.
- **FR-LINK-2:** *(Removed per OD-1 — no proactive Home banner in v1.2. Entry is Settings-only.)*
- **FR-LINK-3:** Linking is initiated by entering an email. The app sends a sign-in link via Firebase Auth's email-link mechanism, with the continue URL pointing back into the app via App Links / Universal Links.
- **FR-LINK-4:** On link confirmation tap, the app calls `linkWithCredential` to attach the email credential to the current anonymous user. The user's UID does **not** change.
- **FR-LINK-5:** If the email is already linked to another Firebase user, linking fails with a clear, actionable error message and a suggestion to restore from that account instead.
- **FR-LINK-6:** The linked email is displayed in Settings but cannot be changed in v1.2.

### 5.2 Recovery flow (FR-REC)

- **FR-REC-1:** The Home empty state on a device with no Firestore-backed data offers a "Restore from email" CTA next to the primary "Create a trip" / "Join a trip" actions.
- **FR-REC-2:** Recovery requires the device to have no owned participant docs. If any are detected, the app refuses recovery and shows the sign-out-first dialog (per scenario 4.3).
- **FR-REC-3:** On successful recovery, the device's prior anonymous UID is signed out and discarded. The local `safar_cache.db` is wiped before re-bootstrap.
- **FR-REC-4:** Firestore data appears under the restored UID exactly as it did on the original device. No migration step is required.
- **FR-REC-5:** A recovery attempt with an unrecognized or unlinked email shows a clear error: *"We couldn't find a Rihla account with this email. Make sure you linked it on your previous device first."*
- **FR-REC-6:** Failed recovery attempts are rate-limited at a sensible threshold (e.g., 5 attempts per email per hour) to prevent enumeration / abuse. Initial implementation can rely on Firebase Auth's built-in throttling; explicit rate-limiting via a Cloud Function is an optional hardening (requires Blaze).

### 5.3 Sign-out (FR-OUT)

- **FR-OUT-1:** "Sign out of this device" appears in Settings **only** when an email is linked.
- **FR-OUT-2:** Sign-out requires confirmation with the message: *"Your data stays in the cloud. To restore, enter your email on any device."*
- **FR-OUT-3:** On sign-out, the app calls `auth.signOut()`, wipes the local SQLite cache, then immediately runs `_AuthGate` to create a fresh anonymous session. User lands on the standard empty Home with the "Restore from email" CTA visible.

### 5.4 Cache & state integrity (FR-CACHE)

- **FR-CACHE-1:** `safar_cache.db` must be wiped on any active-UID change. The cache is a hydration of Firestore reads scoped to one UID; rehydration from Firestore is the contract.
- **FR-CACHE-2:** Riverpod providers that derive from auth state must invalidate / rebuild on UID change. The Firebase Auth `userChanges` stream is the source of truth.
- **FR-CACHE-3:** No background Firestore writes may be in flight at the moment of sign-out / recovery. The app should drain pending writes (Firestore's offline persistence queue) before signing out, or accept that pending writes will land under the old UID and become orphaned.

### 5.5 Data invariants (FR-INV)

- **FR-INV-1:** No Firestore document IDs change as a result of linking or recovery.
- **FR-INV-2:** Participant `displayName` per group remains tied to the participant doc; the UID swap does not rename the user inside any group.
- **FR-INV-3:** Balance calculations, settlement optimizations, and any UID-derived state remain stable across the link/recovery operation — because the UID itself is stable.

## 6. Privacy & Compliance

This feature converts Rihla from a **zero-PII** app into a **PII-collecting** app. Email is personally identifiable, and email + behavioral data (groups, expenses) is more sensitive than email alone.

### 6.1 Disclosure

- Before the user enters an email, the link UI must explicitly state: *"Your email is used only to restore your Rihla data. We don't send marketing email and we don't share it."*
- The privacy policy (currently a Play Store readiness gap) must be drafted and live before this feature ships. It must enumerate: email collection, purpose (recovery only), retention (until account deletion), no third-party sharing.

### 6.2 Data deletion

- The existing data-deletion flow (a separate Play Store requirement) must be extended to:
  1. Delete the linked email credential from Firebase Auth (`user.delete()` cascades).
  2. Delete the user's participant docs and authored expenses **after** any active groups have been notified / cleaned up per existing soft-delete policy.
- A user must be able to initiate deletion from within the app **and** via a documented out-of-app channel (per Play Store policy).

### 6.3 Play Store data safety form

The form must be updated to declare:

- Personal info → Email address → collected, not shared, used for "Account management" purpose, optional.
- All existing categories remain unchanged.

## 7. Implementation Notes & Risks

> This section is implementation-flavored on purpose — it captures known gotchas so the planning phase doesn't get blindsided. It is not the implementation plan.

### 7.1 Firebase Dynamic Links is dead

Firebase Dynamic Links was **deprecated August 25, 2025**. Every legacy tutorial that says "use Dynamic Links for the email-link continue URL" is stale. The current canonical path:

- Host a continue page (essentially an empty HTML page that triggers the app's deep link) on **Firebase Hosting** under the `rihla-safar` project (the current Firebase project in `lib/firebase_options.dart` and `.firebaserc`).
- Configure **App Links** (Android) via the Digital Asset Links file at `<your-hosting-domain>/.well-known/assetlinks.json`.
- Configure **Universal Links** (iOS) via the Apple App Site Association file at `<your-hosting-domain>/.well-known/apple-app-site-association`.
- Set `ActionCodeSettings.handleCodeInApp: true` and `ActionCodeSettings.url` to the hosted continue page.
- FlutterFire's current docs as of Jan 2026 should be re-verified before implementation — community examples are often out of date.

This is the single biggest piece of unknown work in this feature. Allocate research time before estimating.

### 7.2 SQLite cache invalidation

`lib/core/services/local_database.dart` does not currently key on UID. Per CLAUDE.md it's at schema v7 and serves balance calculations, cross-group rollups, and fast list reads. The simplest correct strategy on UID swap is **wipe and rehydrate**: delete the database file (or truncate all tables) and let providers re-hydrate from Firestore on next read. This is safe because the cache is reconstructable.

A more sophisticated alternative — UID-scoping every row — adds schema complexity and bug surface for no meaningful benefit, since recovery is rare and rehydration latency is acceptable in that context.

### 7.3 Firebase Spark vs. Blaze

The core feature works on Spark:

- `sendSignInLinkToEmail` is Firebase Auth's built-in email delivery; no Cloud Functions required.
- `linkWithCredential` and `signInWithEmailLink` are client-side SDK calls.

Cloud Functions (Blaze) are only required if we add:

- Custom rate-limiting beyond Firebase Auth's built-in throttling.
- Audit logging (e.g., recording recovery attempts to a Firestore collection for support purposes).
- Custom email templates beyond what the Firebase console allows.

Recommendation: ship on Spark first. Add Functions-based hardening in a follow-up if abuse becomes a real concern.

### 7.4 Orphaned UIDs

Every successful recovery on a new device leaves the device's freshly-minted anonymous UID with no owned data — an empty Firebase Auth user record. This is acceptable: Firebase doesn't bill for idle anonymous users on Spark, and the records are harmless. **Do not** attempt to delete the orphaned anon UID from the client — that requires the user to still be signed in as it, and we've already swapped credentials by the time we'd want to clean up. Background Cloud Function cleanup of orphaned anon UIDs is a future optimization, not v1.2 work.

### 7.5 Firestore rules

Existing rules treat `auth.uid` as the membership key. **No rule changes are required** for this feature, because the UID is preserved through linking. The only auth.uid the rules ever see is the original one.

### 7.6 Firestore offline writes & sign-out

Firestore's offline persistence queues writes locally. If the user signs out (recovery flow) while writes are pending, those writes will attempt to commit under the **new** UID and fail rules-checks. Mitigation: before sign-out, await `firestore.waitForPendingWrites()` with a timeout. If the timeout fires, surface a warning and require the user to confirm proceeding (data loss on those writes).

### 7.7 Sentry / analytics

Email is PII. Make sure email values are never logged to Sentry breadcrumbs, never sent in error reports, and never appear in any analytics event. Audit before launch.

## 8. Open Decisions — LOCKED 2026-05-13

All eight decisions resolved. Implementation planning may proceed.

| # | Decision | Final answer | Note |
|---|---|---|---|
| OD-1 | When to prompt the user to link an email | **Settings only, no Home banner.** | Override of original recommendation. Trades save-rate for restraint and simpler implementation (no banner state machine, no dismissal counter). SC-1 target revised downward (see §9). |
| OD-2 | Sign-out UX | **"Sign out of this device" visible in Settings only when an email is linked.** Confirmation copy: *"Your data stays in the cloud."* | Matches rec. Without a linked email, sign-out does not exist — there's no way back. |
| OD-3 | Cache invalidation on UID swap | **Wipe-and-rehydrate `safar_cache.db`.** | Matches rec. Safe because the SQLite cache is fully reconstructable from Firestore on next read. |
| OD-4 | Email link expiry duration | **24 hours.** | Matches rec. Firebase default-compatible window; balances "check email after work" UX with leaked-link blast radius. |
| OD-5 | Rate-limiting | **Firebase Auth built-in throttling only for v1.2.** | Matches rec. Ship on Spark. Cloud Function rate-limiter is a post-launch follow-up if abuse emerges. |
| OD-6 | Mutable linked email | **No. Permanent in v1.2.** | Matches rec. Revisit only if support load demands a change-email path. |
| OD-7 | Orphaned anon UIDs after recovery | **Leave them. No client cleanup.** | Matches rec. Documented as known accumulation. Future Cloud Function cleanup is optional. |
| OD-8 | Public Play Store launch gate | **P0 blocker. Public launch waits for v1.2 + privacy policy + data deletion.** | Matches rec. Closed alpha continues unblocked. |

## 9. Success Criteria

Measurable outcomes for after v1.2 ships:

- **SC-1:** *Revised post-OD-1 lock (was ≥40%, which assumed a Home banner).* ≥10% of users with ≥1 group link an email within 30 days. Lower target reflects the deliberate restraint of Settings-only entry. If conversion stays below 5% after a quarter, revisit OD-1 and consider re-introducing a banner.
- **SC-2:** ≥95% of recovery attempts on devices that previously linked an email complete successfully (measured: successful `signInWithEmailLink` over recovery attempts initiated).
- **SC-3:** Time from "I lost my phone" to "back in Rihla with my data" is under 3 minutes end-to-end for a user who has the linked email open on the new device (measured: time from recovery-screen first-paint to Home loaded with restored data).
- **SC-4:** Zero confirmed data-loss support tickets among users who linked an email and recovered. (Failed recovery attempts are acceptable; silent data loss is not.)
- **SC-5:** No regression in first-launch flow: users who never link an email continue to use the app exactly as in v1.1 (measured: time-to-first-group-creation in v1.2 ≤ v1.1 baseline).
- **SC-6:** Privacy policy + Play Store data safety form live before v1.2 ships, both reflecting email collection.

## 10. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| App Links / Universal Links misconfigured → magic link opens browser, not app | High (recovery flow fails silently for many users) | Build a hosted fallback page on Firebase Hosting that explicitly shows "Open in Rihla" deep link button. Test on real devices across iOS / Android versions before launch. |
| User links typo'd email → cannot recover, no support path | Medium | Require email confirmation step at link time (user must enter email twice OR confirm via test send before link is finalized). |
| Email deliverability issues (spam folder, corporate filters) | Medium | Use Firebase's verified `noreply@<project>.firebaseapp.com` sender. Document in-app: "Check your spam folder." Allow resend with 60s cooldown. |
| User links email tied to an account they later lose access to | Medium | Out of our control. Recommend in disclosure copy that they pick an email they'll keep long-term. |
| Abuse: attacker tries to recover with random emails to discover Rihla users | Low | Firebase Auth's built-in throttling handles this at scale. Error messages are uniform whether the email is linked or not ("If this email is linked, we sent a link"). |
| Cache wipe corrupts ongoing app state | Medium | Cache wipe runs only after `auth.signOut()` succeeds and before re-bootstrap. Wrap in a transaction-style guard: wipe-then-rehydrate or rollback. |
| Pending Firestore writes lost on sign-out | Low-Medium | `waitForPendingWrites()` with a 5s timeout before sign-out. Warn user if timeout fires. |

## 11. Glossary

- **Anonymous UID** — A Firebase Auth user created via `signInAnonymously()`. Has no credentials attached and is bound to the device's local Firebase Auth storage.
- **Linked UID** — An anonymous UID that has had an email credential attached via `linkWithCredential`. The UID is unchanged; the user can now also sign in via the linked email.
- **Linking** — One-way attachment of an email credential to an existing anonymous UID. Done on the original device.
- **Recovery** — Signing in on a new (or freshly-wiped) device with a previously linked email, swapping the local anon UID to the linked one.
- **Orphaned UID** — A Firebase Auth user record with no associated Firestore data. Includes both (a) old anon UIDs whose owner cleared app data without linking, and (b) brand-new anon UIDs discarded during recovery on a new device.
- **`safar_cache.db`** — Local SQLite cache of Firestore reads. Hydrated per UID; must be wiped on UID change.

## 12. Next Steps (Outside This Spec)

1. Confirm Open Decisions (Section 8) — review with self / collaborators.
2. Spike Firebase Hosting + App Links / Universal Links setup for the magic-link continue page (the single biggest unknown).
3. Draft the privacy policy + Play Store data safety form updates.
4. Write the regression test plan: every existing flow that ran under an anon UID must continue to work unchanged. Add new tests for link, recover, and sign-out flows.
5. Decide release boundary: v1.2 includes this + privacy policy + data deletion. Earlier minor versions can ship freely without it.

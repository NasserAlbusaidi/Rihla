# deviceName Self-Heal After Restore (#990) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A restored account on a fresh device gets its profile display name back automatically — seeded from the user's own Firestore member doc — instead of landing on "Set your name" while group rosters still show the name.

**Architecture:** A restore-breadcrumb-scoped reactive heal (Gate rounds 1+2 — see D2): when the post-restore boot notice VERIFIES the swap survived (`expectedUid == currentUid`), it persists a `recovery_name_seed_uid` breadcrumb in SharedPreferences. A listener provider then reactively (surviving offline first boots) fetches the user's own member doc (matched by the `userId` FIELD) and seeds the local name through a new INBOUND-only `SettingsNotifier.seedDeviceName` that can never propagate outward — but ONLY while the breadcrumb matches the current uid and the local name is still empty. No swap-flow ordering, rules, or schema line changes; the one recovery-file change is an additive prefs write in `surfaceRecoveryOutcome`'s already-verified success arm.

**Tech Stack:** Flutter, Riverpod 2.x, FakeFirebaseFirestore/mocktail for tests.

---

## Decision D1: breadcrumb-scoped REACTIVE heal — neither a pure state-heal nor an inline marker hook

Two simpler shapes were rejected:

1. **Seeding inline at `surfaceRecoveryOutcome`'s `has == true` arm** (`recovery_outcome_notice.dart:128-139`): the marker is one-shot (`readAndClearRecoveryOutcome`, cleared before the async probe), so a restore whose first boot is offline (probe `null`, groups unreadable) would lose its only seeding chance forever. The breadcrumb decouples "restore verified" (written once, persists) from "seed executed" (reactive, retries until it succeeds).
2. **A pure observed-state heal** (`deviceName empty && groups non-empty`, no restore signal): Gate rounds 1 and 2 killed it twice — the shadow-claim population reaches the same observed state with a creator-authored name, first as anon (round 1) and then via same-device linking (round 2). Only an explicit restore signal discriminates. The cost, accepted in D2: pre-fix restores are not auto-healed.

**Why empty-means-never-set holds on this device:** the only UI write path is `EditNameBottomSheet._handleSave` → `validateDisplayNameLocalized` (localized wrapper over `displayNameValidationError`) which rejects empty (`DisplayNameValidationError.empty`, `name_validators.dart:46-48`), so a user cannot deliberately clear to `''`. `AppSettings.deviceName` defaults to `''` (`app_settings_model.dart:44`) and lives only in SharedPreferences — fresh device ⇒ `''`.

## Decision D2 (Gate round-1 [P1] + round-2 [P1]): the heal is scoped by a RESTORE BREADCRUMB, not by auth state

`deviceName == '' && groups.isNotEmpty` is NOT restore-only: the shadow-claim completion path (`join_group_screen.dart` `_onCheckStatus` → `pushReplacement('/group/…')`) never calls `setDeviceName`, and the claim engine KEEPS the creator-authored shadow name on the re-keyed doc (`claimShadow.ts:764` — the joiner's free-typed name is discarded). So a claimant (e.g. claimed "Dad") holds groups + an empty local name. An unscoped heal would promote that creator-authored, per-group name to the device-wide identity — pre-filling future group-create name fields (`create_group_screen.dart:282` → the OUTBOUND member-doc write at `:108`) and reintroducing exactly the #293 per-group→device-wide coupling.

**Round-2 falsified the round-1 fix:** gating on `isDurableUserProvider` alone only DEFERS the promotion — the claimant who later links Google/email on the SAME device (the most-encouraged action in the app) flips durable with `deviceName` still empty, and the heal would fire right there, no restore anywhere. Auth state cannot discriminate "restored onto this device" from "linked on this device." Filtering member docs by `isShadow` also cannot (claim flips it false — `decideClaimRequest.ts:767`, `claimShadow.ts:428`).

**Fix: an explicit restore breadcrumb.** `surfaceRecoveryOutcome` (`recovery_outcome_notice.dart`) already holds the ONLY verified restore signal in the app: op ∈ {`opGoogle`, `opRecover`} (`recovery_outcome.dart:33-34`), `ok == true`, and `expectedUid == currentUid` (#458 — the swap provably survived the restart). At exactly that point (before the async #839 probe, which only picks message copy) it additionally writes `recovery_name_seed_uid = uid` to SharedPreferences. The heal fires ONLY while `prefs.recovery_name_seed_uid == currentUid` — and clears the breadcrumb when it seeds successfully, when it observes `deviceName` already non-empty, or when the stored uid mismatches the current uid (stale breadcrumb from an older swap). Transient fetch failures RETAIN the breadcrumb (retry on later emissions / next boot).

Consequences, all deliberate:
- The claim-then-link-on-same-device user NEVER heals (no restore ⇒ no breadcrumb) — keeps today's set-name nudge; #293 stands.
- A restored user whose history includes a claimed shadow DOES heal to that name: post-restore the roster name is the only name this device can know, it is the user's balance-carrying name everywhere, and it remains locally editable. This is the intended heal, not a leak.
- Restores completed BEFORE this fix ships have no breadcrumb and are not auto-healed (the marker was already consumed) — accepted: that population (known count: 1, the reporter's simulator) self-serves via the existing set-name chip.
- Two restores back-to-back: restore A seeds "Alice" and clears its breadcrumb; a later restore B finds deviceName non-empty → B's breadcrumb is cleared without seeding, and B's profile shows "Alice" until edited. Behaviorally identical to today's "user set a name, then restored another account" (deviceName persists across swaps — no `remove(_deviceNameKey)` exists); newly REACHABLE because A's restore populates a previously-empty field, accepted under the empty-only seed contract.
- `isDurableUserProvider` is KEPT in the trigger as a zero-cost belt (a breadcrumb can only be written for a durable swap, so the belt is redundant by construction — it guards future refactors of the notice, not a live path).

## Control-flow facts (verified against code)

1. `setDeviceName` (`lib/core/providers/settings_provider.dart:104-124`) runs the #390 collision check and — when non-empty — fire-and-forgets `propagateDisplayName` (OUTBOUND: batch-updates `displayName` on every own member doc). **The self-heal must NOT call `setDeviceName`** — seeding a name that came FROM the member docs must not write back to them (a no-op write today, but it burns writes, stamps docs, and couples the heal to the #390 fail-open path).
2. `userGroupsProvider` is an existing `StreamProvider<List<Group>>` (`group_provider.dart:637`) — the home screen already watches it, so the heal adds NO new standing listener; group docs carry no member-name map, so the member subcollection read is required (one `get`, only in the anomalous state).
3. Member docs: match by the `userId` FIELD, never doc id (mixed keying: client docs uid-keyed, server shadows + legacy creators uuid-keyed — CLAUDE.md Key Invariants). `GroupMember` carries `isTombstone` (`group_member_model.dart:18`) — tombstoned docs must be skipped. A claimed shadow's doc carries the balance-owning name — correct to seed.
4. Post-restore first boot has an EMPTY Firestore cache (`CacheUidBarrier` cleared it), so the member `get` goes to the server naturally; offline, `userGroupsProvider` streams nothing → the heal simply waits. Default `Source` is correct — no `Source.server` needed (unlike the #839 probe, a stale-cache name here is still the right name).
5. During a swap, `engageIsolation` flips `cacheIsolationProvider` and invalidates `appBootstrapProvider` — the heal must no-op while isolated (same guard as `recoveryOutcomeNoticeProvider`, `recovery_outcome_notice_provider.dart:71`).
6. `FirebaseConfig.currentUser` THROWS `[core/no-app]` in unit tests — any read goes inside try/catch (established pattern), though the primary uid source here is the injected/overridable provider graph, not a raw read.

## Data contract (exact — principle 5)

**New: `SettingsNotifier.seedDeviceName(String name)`** (in `lib/core/providers/settings_provider.dart`):

```dart
/// INBOUND-only deviceName seed (#990): writes the local name from the
/// user's own member doc after a cross-device restore. Unlike
/// [setDeviceName] it never runs the #390 collision check and never
/// propagates to Firestore — the value CAME from the member docs.
/// No-ops (returns false) unless the local name is still empty and
/// [name] normalizes to a valid display name.
Future<bool> seedDeviceName(String name) async {
  if (state.deviceName.trim().isNotEmpty) return false;
  final normalized = normalizeDisplayName(name);
  if (displayNameValidationError(normalized) != null) return false;
  await _service.saveDeviceName(normalized);
  state = state.copyWith(deviceName: normalized);
  return true;
}
```

**New: breadcrumb write in `surfaceRecoveryOutcome`** (`lib/features/auth/services/recovery_outcome_notice.dart`):

- New prefs key `recovery_name_seed_uid` (constant lives beside the marker keys in `recovery_outcome.dart`, with `writePendingNameSeed(prefs, uid)` / `readPendingNameSeed(prefs)` / `clearPendingNameSeed(prefs)` helpers).
- Written at the verified-success point — **with an EXPLICIT positive guard (Gate round-3 rubric [P2])**: the live control flow has only a NEGATIVE durability check (`if (expected != null && uid != expected) { …return; }`), after which BOTH `expected == null` (legacy/unverifiable) and the verified-match case fall through together. Writing "after that return" would stamp unverified legacy markers too. The write is therefore `if (expected != null) { await writePendingNameSeed(prefs, uid); }` placed in that fall-through (uid is non-null and `== expected` there: the `uidReadable == false` arm and the mismatch arm have both already returned) — NOT on `!outcome.ok`, NOT for `opSignOut`, and executed before the async `hasData` probe (the probe only picks snack copy).
- `surfaceRecoveryOutcome` already takes `prefs`; the write is awaited like the marker ops. No signature change.
- After `surfaceRecoveryOutcome` completes, `recoveryOutcomeNoticeProvider` bumps `deviceNameSeedRevisionProvider` (`StateProvider<int>`, watched by the heal) so the heal re-evaluates EXPLICITLY once the breadcrumb lands, instead of relying on a groups emission happening to arrive after the post-frame prefs write (Gate round-3 adversary [P3] hardening — the implicit ordering was practically safe but emission-dependent).

**New: `deviceNameSelfHealProvider`** — `lib/features/auth/providers/device_name_self_heal_provider.dart`, `Provider<void>`, watched from `lib/core/providers/app_bootstrap_provider.dart` (beside `recoveryOutcomeNoticeProvider`, line 75):

- Watches `settingsProvider.select((s) => s.deviceName)`, `userGroupsProvider` (unwrapped as `valueOrNull ?? []` — `AsyncLoading` and the #647 false-empty both fail toward not-firing), `isDurableUserProvider`, and `deviceNameSeedRevisionProvider`; reads `sharedPreferencesProvider` for the breadcrumb.
- Trigger condition: `breadcrumb != null && currentUid != null && breadcrumb == currentUid && deviceName.trim().isEmpty && isDurable && groups.isNotEmpty && !ref.read(cacheIsolationProvider)` (`currentUid = ref.read(currentUserIdProvider)`).
- Breadcrumb housekeeping inside the trigger evaluation — **the stale-clear requires a KNOWN, DIFFERENT uid (Gate round-3 rubric [P1])**: `currentUserIdProvider` derives from `authStateProvider`, a `StreamProvider` that is `AsyncLoading → valueOrNull == null` during the cold-boot auth-resolution window, so a `breadcrumb != current` comparison against a NULL current uid must RETAIN-AND-WAIT, never clear — otherwise every cold boot destroys a valid breadcrumb before auth resolves and the heal's primary offline-retry path is dead. Exact rules: `deviceName` non-empty with a breadcrumb present → `clearPendingNameSeed`, stop; `currentUid != null && breadcrumb != currentUid` → `clearPendingNameSeed` (stale from an older swap), stop; `currentUid == null` → do nothing this pass (auth still resolving; a later watched emission re-evaluates).
- **Attempt guard survives rebuilds (round-1 rubric [P2]) and retries transient failures (round-2 rubric [P2]):** companion `final deviceNameSelfHealInFlightProvider = StateProvider<bool>((_) => false)` — `ref.read` it (never watch) to check-and-set before the async fetch; RESET it in the fetch's `catch`/after a no-seed completion so a transient failure retries on the next emission (the breadcrumb, not the flag, is the terminal state: it survives until a successful seed clears it).
- Fetch: iterate `groups` in stream order; for each, `groups/{gid}/members where userId == uid limit 5` (5 bounds the legacy dual-doc case — a uuid-keyed legacy creator doc AND a uid-keyed recovery copy can coexist for one uid) via an injectable provider of `typedef FetchOwnMemberName = Future<String?> Function(String uid, List<String> groupIds)` (tests override it, mirroring `recoveryOutcomeProbeProvider`); first doc with `isTombstone == false` and a `displayName` whose `displayNameValidationError(normalizeDisplayName(...)) == null` wins; stop at the first group that yields one. (`isShadow` is deliberately not filtered — a doc matching `userId == uid` is never an unclaimed shadow, and claimed docs are `isShadow: false` anyway; see D2.)
- **`FetchOwnMemberName` return contract distinguishes terminal from transient (Gate round-3 adversary [P2]):** it returns the name, returns `null` ONLY as a definitive answer (every group queried successfully and no doc passed the tombstone+valid-name filter), and THROWS on any transient failure (network/permission/timeout). Caller mapping: name → seed + `clearPendingNameSeed`; `null` → `clearPendingNameSeed` WITHOUT seeding (terminal — an all-unseedable roster must not re-query on every emission and every boot forever); throw → retain breadcrumb, reset the in-flight guard, retry on a later emission.
- **The entire async continuation is try/caught (round-2 adversary [P2]):** `engageIsolation` invalidates `appBootstrapProvider`, disposing this provider while the `get` may be in flight — a post-await `ref.read` on the disposed ref throws `StateError`, which must land in the same catch as network errors (drop silently, breadcrumb retained). The post-fetch `ref.read(cacheIsolationProvider)` re-check (mirroring `recovery_outcome_notice_provider.dart:87`) therefore lives INSIDE the try.
- Seed via `seedDeviceName` (which re-checks emptiness at write time — the race guard against the user typing a name mid-fetch: last-writer is the USER because the seed no-ops once state is non-empty). On `seedDeviceName == true` OR on observing non-empty, `clearPendingNameSeed`.
- uid source: `ref.read(currentUserIdProvider)` (the same `authStateChanges`-derived uid the groups stream keys on — no raw throwing `FirebaseConfig.currentUser` read needed).
- Every failure path is silent (log via `FirebaseConfig.log` only) — this is polish, never a boot blocker.

## Verification principles (run while writing, reported per the Operating Contract)

1. **Callsite classification:** the heal's Firestore access is READ-only (groups stream already exists; one member `get`). The only write is LOCAL SharedPreferences via `seedDeviceName`, which by construction cannot reach `propagateDisplayName` (grep: `propagateDisplayName` has exactly one caller, `setDeviceName` — `settings_provider.dart:121` — and the heal never calls `setDeviceName`). **INBOUND end-to-end.** Downstream: `deviceName` feeds future OUTBOUND writes (creator member doc at group-create, `group_provider.dart`; settle-up display fields) — which is exactly why seeding validates with the same `displayNameValidationError` the write paths assume.
2. **Concrete claims verified:** `setDeviceName`/`propagateDisplayName` at `settings_provider.dart:104-124/178-210`; empty-save rejected at `name_validators.dart:67-69` + `edit_name_bottom_sheet.dart:54`; `userGroupsProvider` at `group_provider.dart:637`; `isDurableUserProvider` at `auth_provider.dart:62-65`; `GroupMember.userId/displayName/isShadow/isTombstone` at `group_member_model.dart:12-18`; `recoveryOutcomeNoticeProvider` watched from `lib/core/providers/app_bootstrap_provider.dart:75`; isolation guard at `recovery_outcome_notice_provider.dart:71` with the mid-async re-check at `:87`; marker one-shot at `recovery_outcome_notice.dart:80` (`readAndClearRecoveryOutcome`); claim flips `isShadow: false` and keeps the creator-authored name at `claimShadow.ts:428/:761-767`; members read permitted by `firestore.rules` `allow read: if isGroupMember(groupId)` on the members subcollection.
3. **Read-path per write-path:** the one write (local `deviceName`) has named readers: `HomeScreen` greeting/`_SetNameChip`/`RAvatar` (`home_screen.dart:521`), `ProfileScreen` name card, `create_group_screen`/`group_settle_up_screen` display fields — all react via `settingsProvider`.
4. **Fields enumerated from the type:** `GroupMember` = {id, groupId, userId, displayName, avatarInitials?, role, isShadow, isTombstone, joinedAt, …} — the heal reads `userId`, `displayName`, `isTombstone`; `isShadow` deliberately NOT filtered (a claimed shadow's name is the user's balance-carrying name); doc `id` deliberately unused (mixed keying).
5. **Data contracts spelled out:** exact API above; provider file path named; injectable fetch typedef mirrors `recoveryOutcomeProbeProvider` for testability.
6. **Arithmetic decomposition:** N/A — no money surface. (The heal never touches balances; it reads a name.)
7. **Orthogonal-axis pass (identity + offline):** worked example A (identity): user holds TWO member docs for the same uid in one group (legacy uuid-keyed creator doc + uid-keyed recovery copy, both `userId == uid`) with divergent names — heal takes the first non-tombstone valid one; both are the user's own names, either is correct, user can edit; no write occurs to Firestore so no divergence is created. Worked example B (offline/time): restore completes, first boot offline → groups stream empty → heal waits; connectivity returns → stream fires → heal seeds. If the user typed a name while offline, `seedDeviceName` no-ops on the emptiness re-check. Worked example C (identity, the two Gate P1s): shadow-claimant "Dad" — as anon: no breadcrumb, gate closed; after linking Google on the SAME device: still no breadcrumb (linking writes no recovery marker — only `restoreWithGoogle`/`restoreWithEmailLink` do, and only their VERIFIED success arm writes the breadcrumb), gate still closed; zero extra reads for the entire non-restored population. Worked example D (cross-uid): sign-out/deletion swaps never clear `deviceName` from prefs (no `remove(_deviceNameKey)` exists), so post-swap the name is either non-empty (heal gated off) or the device is genuinely fresh; the fetch is keyed to the CURRENT uid's own member docs (`userId == uid` against the current uid's groups stream), so no other identity's name is reachable.

## Out of scope

- No change to `setDeviceName`, `propagateDisplayName`, the #390 collision check, any swap-flow/recovery ordering, `firestore.rules`, or member-doc writes.
- Divergent-name reconciliation across docs (pre-existing pathology) — untouched.
- The #991 wordmark centering (separate branch/PR).

---

### Task 1: Failing tests (RED)

**Files:**
- Create: `test/features/auth/device_name_self_heal_test.dart`
- Modify: `test/unit/settings_provider_test.dart` (or the existing settings notifier test file — locate with `grep -rl setDeviceName test/`)

All app-booting/provider tests override `sharedPreferencesProvider` per the project rule (it throws by default). Tests (write first, watch them fail):
1. `seedDeviceName` seeds when empty + valid; returns true; SharedPreferences updated.
2. `seedDeviceName` no-ops (false) when a name is already set — including when called concurrently after the user typed one.
3. `seedDeviceName` no-ops on invalid input (33 chars, control chars) — and NEVER writes any Firestore doc (FakeFirebaseFirestore: member docs byte-identical before/after; pins the no-propagation contract).
4. Self-heal provider: breadcrumb == uid + empty name + DURABLE user + one group whose members hold `{userId: uid, displayName: 'Nasser', isTombstone: false}` → deviceName becomes 'Nasser' AND the breadcrumb is cleared.
5. Tombstone + invalid-name docs are skipped (falls through to the next group / no-ops, breadcrumb retained).
6. Non-empty deviceName with a breadcrumb present → fetch never invoked (spy), breadcrumb cleared.
7. `cacheIsolationProvider == true` → no attempt; isolation engaging AFTER the fetch resolves (completer-gated fake) → seed dropped, no throw.
8. **NO breadcrumb → fetch never invoked, even for a durable user with groups and an empty name (the round-2 link-after-claim pin). ANON user likewise (round-1 pin).**
9. Breadcrumb uid ≠ current uid (BOTH non-null) → fetch never invoked, breadcrumb cleared (stale-swap pin).
9b. **Current uid still NULL (auth resolving) with a valid breadcrumb → breadcrumb RETAINED, no fetch (the round-3 [P1] cold-boot pin); once the uid resolves to the breadcrumb's, the heal proceeds.**
9c. Terminal-empty fetch (returns null, no throw) → breadcrumb CLEARED without seeding; a THROWING fetch retains it (terminal-vs-transient pin).
10. In-flight guard: two `userGroupsProvider` emissions while the fetch is pending → the injected fetch runs ONCE; a THROWING fetch resets the guard so a later emission retries (breadcrumb retained).
11. `surfaceRecoveryOutcome` (extend its existing test file): verified google/recover success writes the breadcrumb; `ok:false`, uid-mismatch, `opSignOut`, and legacy `expectedUid == null` markers do NOT.

### Task 2: `seedDeviceName` (GREEN for tests 1–3)
### Task 3: `deviceNameSelfHealProvider` + bootstrap wiring (GREEN for 4–7)
### Task 4: `flutter analyze` clean, full `flutter test`, manual verification = a FRESH simulator restore run (erase → restore → relaunch → name appears; the reporter's existing simulator state has no breadcrumb — pre-fix restores are deliberately not auto-healed, set the name via the chip there), commit `fix(auth): seed deviceName from own member doc after a verified restore`, body `Closes #990`.

# deviceName Self-Heal After Restore (#990) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A restored account on a fresh device gets its profile display name back automatically — seeded from the user's own Firestore member doc — instead of landing on "Set your name" while group rosters still show the name.

**Architecture:** A reactive self-heal, not a restore-marker hook: a listener provider watches `settingsProvider.deviceName` + the already-streaming `userGroupsProvider`; when the local name is empty and the user has groups, it fetches the user's own member doc (matched by the `userId` FIELD) once per boot and seeds the local name through a new INBOUND-only `SettingsNotifier.seedDeviceName` that can never propagate outward. No swap-flow, recovery-ordering, rules, or schema line changes.

**Tech Stack:** Flutter, Riverpod 2.x, FakeFirebaseFirestore/mocktail for tests.

---

## Decision D1: reactive self-heal, restore-marker hook REJECTED

The obvious hook — `surfaceRecoveryOutcome`'s `has == true` success arm (`recovery_outcome_notice.dart:128-139`) — was rejected:

1. **The marker is one-shot** (`readAndClearRecoveryOutcome`, cleared before the async probe). A restore whose first boot is offline (probe `null`) would lose its only seeding chance forever.
2. **It can't heal the already-bitten.** Anyone who restored BEFORE this fix ships (1.8.0 is live on Android; the reporter's own simulator account) has already consumed their marker. A reactive heal fixes them on next boot.
3. The reactive predicate is strictly safer: it acts on the OBSERVED bad state (`deviceName == ''` while member docs carry a name) rather than on an event that implies it.

**Why empty-means-never-set holds on this device:** the only UI write path is `EditNameBottomSheet._handleSave` → `validateDisplayNameLocalized` which rejects empty (`DisplayNameValidationError.empty`, `name_validators.dart:67-69`), so a user cannot deliberately clear to `''`. `AppSettings.deviceName` defaults to `''` (`app_settings_model.dart:44`) and lives only in SharedPreferences — fresh device ⇒ `''`.

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

**New: `deviceNameSelfHealProvider`** — `lib/features/auth/providers/device_name_self_heal_provider.dart`, `Provider<void>`, watched from `app_bootstrap_provider.dart` (beside `recoveryOutcomeNoticeProvider`, `app_bootstrap_provider.dart:75`):

- Watches `settingsProvider.select((s) => s.deviceName)` and `userGroupsProvider`.
- Trigger condition: `deviceName.trim().isEmpty && groups.isNotEmpty && !ref.read(cacheIsolationProvider)`.
- One attempt per provider lifetime (`var attempted = false` in the provider closure; set before the async fetch). A failed fetch retries only on next boot / bootstrap invalidation — no loops.
- Fetch: iterate `groups` in stream order; for each, `groups/{gid}/members where userId == uid limit 5` via the existing feature service pattern (a small injectable `fetchOwnMemberName(String uid, List<String> groupIds)` typedef-provider so tests override it, mirroring `recoveryOutcomeProbeProvider`); first doc with `isTombstone == false` and a `displayName` whose `displayNameValidationError(normalizeDisplayName(...)) == null` wins; stop at the first group that yields one.
- Seed via `seedDeviceName` (which re-checks emptiness at write time — the race guard against the user typing a name mid-fetch: last-writer is the USER because the seed no-ops once state is non-empty).
- uid source: `FirebaseConfig.currentUser?.uid` inside try/catch (fail-silent, pattern per `group_provider._currentUid`).
- Every failure path is silent (log via `FirebaseConfig.log` only) — this is polish, never a boot blocker.

## Verification principles (run while writing, reported per the Operating Contract)

1. **Callsite classification:** the heal's Firestore access is READ-only (groups stream already exists; one member `get`). The only write is LOCAL SharedPreferences via `seedDeviceName`, which by construction cannot reach `propagateDisplayName` (grep: `propagateDisplayName` has exactly one caller, `setDeviceName` — `settings_provider.dart:121` — and the heal never calls `setDeviceName`). **INBOUND end-to-end.** Downstream: `deviceName` feeds future OUTBOUND writes (creator member doc at group-create, `group_provider.dart`; settle-up display fields) — which is exactly why seeding validates with the same `displayNameValidationError` the write paths assume.
2. **Concrete claims verified:** `setDeviceName`/`propagateDisplayName` at `settings_provider.dart:104-124/178-210`; empty-save rejected at `name_validators.dart:67-69` + `edit_name_bottom_sheet.dart:54`; `userGroupsProvider` at `group_provider.dart:637`; `GroupMember.userId/displayName/isShadow/isTombstone` at `group_member_model.dart:12-18`; `recoveryOutcomeNoticeProvider` watched from `app_bootstrap_provider.dart:75`; isolation guard at `recovery_outcome_notice_provider.dart:71`; marker one-shot at `recovery_outcome_notice.dart:83` (`readAndClearRecoveryOutcome`).
3. **Read-path per write-path:** the one write (local `deviceName`) has named readers: `HomeScreen` greeting/`_SetNameChip`/`RAvatar` (`home_screen.dart:521`), `ProfileScreen` name card, `create_group_screen`/`group_settle_up_screen` display fields — all react via `settingsProvider`.
4. **Fields enumerated from the type:** `GroupMember` = {id, groupId, userId, displayName, avatarInitials?, role, isShadow, isTombstone, joinedAt, …} — the heal reads `userId`, `displayName`, `isTombstone`; `isShadow` deliberately NOT filtered (a claimed shadow's name is the user's balance-carrying name); doc `id` deliberately unused (mixed keying).
5. **Data contracts spelled out:** exact API above; provider file path named; injectable fetch typedef mirrors `recoveryOutcomeProbeProvider` for testability.
6. **Arithmetic decomposition:** N/A — no money surface. (The heal never touches balances; it reads a name.)
7. **Orthogonal-axis pass (identity + offline):** worked example A (identity): user holds TWO member docs for the same uid in one group (legacy uuid-keyed creator doc + uid-keyed recovery copy, both `userId == uid`) with divergent names — heal takes the first non-tombstone valid one; both are the user's own names, either is correct, user can edit; no write occurs to Firestore so no divergence is created. Worked example B (offline/time): restore completes, first boot offline → groups stream empty → heal waits; connectivity returns → stream fires → heal seeds. If the user typed a name while offline, `seedDeviceName` no-ops on the emptiness re-check. Worked example C (fresh anon, no restore): deviceName empty AND groups empty → trigger condition never fires → zero extra reads for the entire normal first-run population.

## Out of scope

- No change to `setDeviceName`, `propagateDisplayName`, the #390 collision check, any swap-flow/recovery ordering, `firestore.rules`, or member-doc writes.
- Divergent-name reconciliation across docs (pre-existing pathology) — untouched.
- The #991 wordmark centering (separate branch/PR).

---

### Task 1: Failing tests (RED)

**Files:**
- Create: `test/features/auth/device_name_self_heal_test.dart`
- Modify: `test/unit/settings_provider_test.dart` (or the existing settings notifier test file — locate with `grep -rl setDeviceName test/`)

Tests (write first, watch them fail):
1. `seedDeviceName` seeds when empty + valid; returns true; SharedPreferences updated.
2. `seedDeviceName` no-ops (false) when a name is already set — including when called concurrently after the user typed one.
3. `seedDeviceName` no-ops on invalid input (33 chars, control chars) — and NEVER writes any Firestore doc (FakeFirebaseFirestore: member docs byte-identical before/after; pins the no-propagation contract).
4. Self-heal provider: empty name + one group whose members hold `{userId: uid, displayName: 'Nasser', isTombstone: false}` → deviceName becomes 'Nasser'.
5. Tombstone + invalid-name docs are skipped (falls through to the next group / no-ops).
6. Non-empty deviceName → the injected fetch is never invoked (spy).
7. `cacheIsolationProvider == true` → no attempt.

### Task 2: `seedDeviceName` (GREEN for tests 1–3)
### Task 3: `deviceNameSelfHealProvider` + bootstrap wiring (GREEN for 4–7)
### Task 4: `flutter analyze` clean, full `flutter test`, manual simulator verification on the restored account (the reporter's simulator is IN the bitten state — boot it with the fix and watch the name appear), commit `fix(auth): self-heal empty deviceName from own member doc after restore`, body `Closes #990`.

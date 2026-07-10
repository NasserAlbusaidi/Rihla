# #1091 — Shell-Emptiness Gate: Server-Confirmed Empty Before Any Cross-UID Swap

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `outgoingShellProvablyEmpty` may return `true` (swap allowed) only after a `Source.server` probe confirms the outgoing shell holds zero **live** group memberships — a cache-empty first snapshot must never be accepted as account-empty.

**Architecture:** The gate (`shell_emptiness_gate.dart`) gains a required `probeHasLiveData` thunk: `true` = server sees ≥1 LIVE membership (block), `false` = server-confirmed zero live memberships (proceed), `null` = inconclusive (block — this gate is destructive, deliberately UNLIKE #839's notice where `null` is treated kindly). Gate logic: stream-read non-empty → block (unchanged, no probe); stream-read empty → probe; only `false` proceeds. The production probe is a NEW function `hasAnyLiveGroupMembership` living beside the gate — the existing `hasAnyGroupMembership` (`recovery_outcome_notice.dart:34-46`) is **deliberately NOT reused**: it is tombstone-inclusive by design (its question is "did this account EVER hold data", right for the #839 notice), while the gate's question is "would the user LOSE live data" — soft-deleted groups retain `memberIds` (`functions/src/callables/deleteGroup.ts:295`), so the tombstone-inclusive probe would PERMANENTLY block restore for a shell whose only rows are tombstones (Gate round-1 P1). The new probe mirrors `watchUserGroups`' live-only semantics (`group_provider.dart:565` filters `!group.isDeleted` in memory). Wired through a new Riverpod provider so all four call sites add one line and tests override in one line; the param is **required** so the compiler enumerates every call site.

**Tech stack:** Flutter/Dart, Riverpod 2.x, mocktail + FakeFirebaseFirestore rigs.

**Issue:** #1091 (P1, data-integrity). Lineage #647/#648/#661 — residual gap INSIDE the gate. Gate round 1: 1 P1 + 2 P2 resolved in this revision.

---

## Context an implementer must know (verified 2026-07-10 against main @ 7d4a086c; round-1 reviewer citations re-verified)

- The bug: `_resolveShellEmpty` (`lib/features/auth/providers/shell_emptiness_gate.dart:52-60`) returns `groups.isEmpty` off the FIRST `userGroupsProvider` emission. `watchUserGroups` (`lib/features/groups/providers/group_provider.dart:552-567`) `.map()`s snapshots straight to `List<Group>`, discarding `QuerySnapshot.metadata` — `isFromCache` is structurally unavailable downstream. With `persistenceEnabled` and a cold/empty cache (iOS reinstall keeps the anon UID in Keychain but wipes the Firestore SQLite file), the first snapshot is cache-served and EMPTY, so a populated remote ledger passes the gate and the swap orphans it.
- The four call sites (all pass the same two thunks today; grep re-confirmed exactly four — `bottom_nav_shell.dart:69` is a comment, not a call):
  1. `lib/features/auth/providers/auth_email_link_bootstrap_provider.dart:161-166` — op=recover dispatch (authoritative swap gate)
  2. `lib/features/auth/widgets/google_restore_action.dart:27-31` — `triggerGoogleRestore` (authoritative)
  3. `lib/features/auth/widgets/durable_credential_sheet.dart:163-169` — `_outgoingShellEmpty` for the conflict-switch (authoritative; result future cached per conflict instance, and the sheet renders `_conflictLoadingContent()` while it resolves. Known accepted P3: a transient-network `null`→block result stays cached for that conflict instance's lifetime — re-attempting Google sign-in mints a new conflict and re-arms the gate)
  4. `lib/features/settings/screens/profile_screen.dart:1112-1116` — `_recoverWithEmail` advisory pre-check (swap gate downstream stays authoritative)
- Existing tests that drive the gate (all single-shot `Stream.value` — none models cache-vs-server): `test/features/auth/google_restore_guard_test.dart` (:65,:86,:112,:136), `test/features/auth/durable_credential_sheet_conflict_test.dart` (:100), `test/unit/auth_email_link_bootstrap_test.dart` (:101,:606), `test/features/home/home_restore_cta_test.dart` (:83 `_buildApp`, Google CTA taps at :116/:125/:146/:179/:187), `test/features/settings/profile_account_card_test.dart` (proceed tests :162 Google row, :180 email-recover row; block tests :223/:241 use a populated stream and short-circuit before the probe). There is NO unit test file for the gate itself today.
- Test gotcha: `FirebaseConfig.firestore` THROWS `[core/no-app]` in unit tests without `Firebase.initializeApp()`. Precise mechanism (round-2 reviewer correction): the default provider's non-async arrow evaluates `FirebaseConfig.firestore` synchronously, so the throw ESCAPES the probe's internal try and lands in `outgoingShellProvablyEmpty`'s outer catch → `false` (block) directly, not via `null`. Same end state: proceed-expecting tests fail VISIBLY rather than silently pass — with ONE exception called out in Task 4 (the vacuous-pass trap in `home_restore_cta_test.dart`).

## Deliberate decisions (do not re-litigate in implementation)

1. **`null` (inconclusive) blocks.** This gate is destructive; #839's notice treats `null` kindly because it is advisory. This FLIPS offline behavior: an offline, genuinely-empty shell that previously passed now blocks. Acceptable and desirable: both swap flows (`restoreWithGoogle`, `restoreWithEmailLink`) need the network anyway; blocking BEFORE the point of no return (isolation + guaranteed restart in `finally`) is strictly safer than failing inside it. Known side effect on the recover path: a blocked (offline) recover clears `inFlightOp`+`pendingEmail` (`auth_email_link_bootstrap_provider.dart:184-186`), so an offline user who taps their recovery link must re-request it once online — consistent with the block-first posture, accepted.
2. **Tombstone-only shells PROCEED (round-1 P1 resolution).** The probe counts LIVE memberships only, mirroring the stream's `!group.isDeleted` filter — a shell whose every membership row is a soft-deleted tombstone proceeds, exactly as it does pre-#1091 (the stream filters tombstones out). The user explicitly discarded that data; orphaning tombstones was always the accepted outcome. The probe therefore diverges from the stream on exactly ONE axis — cache-vs-server truth — and on no other. Do NOT use a server-side `.where('isDeleted', isEqualTo: false)` filter: legacy groups lack the field entirely (that is WHY `watchUserGroups` filters in memory) and would be under-counted → false proceed → data loss. Filter in memory with `data['isDeleted'] != true` (missing field = live; malformed doc = counts live → block; both fail-safe).
3. **`hasAnyGroupMembership` and `recoveryOutcomeProbeProvider` stay untouched.** The near-twin provider (`recovery_outcome_notice_provider.dart:25-26`) serves the #839 notice, whose tombstone-inclusive semantics are correct for its question. The gate gets its own function + provider because the SEMANTICS differ (live-only, no limit) — this is not accidental duplication; say so in the code doc comment.
4. **Block copy is reused** (`restoreBlockedHasData` / `authEmailLinkRecoverBlocked`, both present EN+AR). For an offline user the "you have data" phrasing is imprecise — accepted limitation; a dedicated string is an optional follow-up (new ARB keys, out of scope).
5. **`watchUserGroups` is untouched.** Surfacing `isFromCache` through the stream would ripple through every consumer; the probe achieves server truth without touching the shared stream. Do NOT touch `CacheUidBarrier`, CTA visibility, or `userGroupsProvider`.
6. **Stream check stays first.** A cache-served NON-empty result (including a queued offline group creation, #874 — pending writes surface in local snapshots) is proof enough to block with zero network. The probe runs only on the empty branch.
7. **Timeout budget:** outer gate timeout stays 5s (`shellEmptinessGateTimeoutProvider`); probe self-caps at 4s inside it. The probe is an UNBOUNDED (no `limit`) fetch of the uid's membership rows — bounded in practice by the user's group count; `limit(1)` is wrong now that tombstones must be filtered out in memory. A pathological overrun times out into block — fail-safe.
8. **No loading affordance at two call sites — accepted polish gap.** `triggerGoogleRestore` and `_recoverWithEmail` now await up to ~5s before any UI response where they were previously near-instant (P3, round 1). The conflict sheet already shows a loading state. Optional follow-up, not in scope.
9. **RED shape:** the bug is an omission — the pre-fix gate has no seam through which "server truth" can be expressed, so the RED evidence is the new gate unit-test file failing against the pre-fix signature (compile error), the same RED shape PRs #1088/#1090/#1115 used. Say so in the PR body.

---

### Task 1: Gate + probe unit tests (RED)

**Files:**
- Create: `test/unit/shell_emptiness_gate_test.dart`

**Step 1: Write the test file.** Two groups: (a) pure gate-logic tests with injected thunks; (b) probe-semantics tests for `hasAnyLiveGroupMembership` against `FakeFirebaseFirestore` (the fn takes the db as a parameter precisely so these tests need no Firebase app).

Gate-logic cases (inject `readUser`/`readGroups`/`probeHasLiveData` thunks, `timeout: const Duration(seconds: 2)`; `_MockUser extends Mock implements User` with `uid → 'uid-1'`):
1. cache-empty stream + probe `true` (server has live data) → `false` (BLOCK) — **the #1091 regression case**
2. cache-empty stream + probe `false` → `true` (proceed); assert the probe received `'uid-1'`
3. cache-empty stream + probe `null` → `false` (BLOCK — destructive-null semantics)
4. probe throws → `false` (fail-safe catch)
5. probe hangs (`Completer<bool?>().future`) + `timeout: 50ms` → `false` (outer timeout)
6. stream non-empty → `false` WITHOUT invoking the probe (track with a `probed` flag)
7. `readUser` → `null` → `true` WITHOUT invoking the probe (nothing to orphan)

Probe-semantics cases (`hasAnyLiveGroupMembership(db, 'uid-1')` with `FakeFirebaseFirestore`):
8. one live group (`memberIds: ['uid-1'], isDeleted: false`) → `true`
9. tombstone-only (`isDeleted: true`) → `false` — **the round-1 P1 case: tombstones must not block**
10. legacy doc with NO `isDeleted` key → `true` (missing = live)
11. zero matching docs → `false`
12. mixed: one tombstone + one live → `true`

`Group` fixture for case 6 — required constructor fields enumerated from `group_model.dart`: `id`, `name`, `inviteCode`, `createdBy`, `memberIds`, `createdAt` (the round-1 sketch omitted `inviteCode` and would not compile).

**Step 2: Run it — RED.**
Run: `flutter test test/unit/shell_emptiness_gate_test.dart`
Expected: FAIL to compile — `No named parameter with the name 'probeHasLiveData'` / undefined `hasAnyLiveGroupMembership`. Save the output verbatim for the PR body.

### Task 2: Gate + probe implementation (GREEN)

**Files:**
- Modify: `lib/features/auth/providers/shell_emptiness_gate.dart`

**Step 1: Implement.**

```dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../../groups/models/group_model.dart';

/// (existing shellEmptinessGateTimeoutProvider stays as-is)

/// Server-truth probe the gate runs before it may declare a shell empty
/// (#1091): a cold/reinstalled device serves the FIRST `userGroupsProvider`
/// snapshot from an EMPTY local cache, so stream-empty is not account-empty.
/// `true` = server sees ≥1 LIVE membership, `false` = server-confirmed zero
/// live memberships, `null` = inconclusive. Deliberately NOT
/// [hasAnyGroupMembership] (the #839 notice probe): that one counts
/// tombstones on purpose ("did this account ever hold data"), but soft
/// deletes keep `memberIds` intact (deleteGroup.ts), so it would permanently
/// block restore for a shell whose only rows are tombstones. This probe
/// mirrors `watchUserGroups`' live-only in-memory filter instead — missing
/// `isDeleted` (legacy) and malformed docs both count as live (block,
/// fail-safe). No `limit`: tombstones must be filtered client-side, so the
/// full (small) membership row set is fetched.
Future<bool?> hasAnyLiveGroupMembership(FirebaseFirestore db, String uid) async {
  try {
    final snap = await db
        .collection('groups')
        .where('memberIds', arrayContains: uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 4));
    return snap.docs.any((doc) => doc.data()['isDeleted'] != true);
  } catch (_) {
    return null;
  }
}

/// Overridable in tests. Default binds the live Firestore lazily so reading
/// the provider never touches FirebaseConfig in a test.
final shellEmptinessServerProbeProvider =
    Provider<Future<bool?> Function(String uid)>(
  (_) => (uid) => hasAnyLiveGroupMembership(FirebaseConfig.firestore, uid),
);
```

`outgoingShellProvablyEmpty` gains `required Future<bool?> Function(String uid) probeHasLiveData` and `_resolveShellEmpty` becomes:

```dart
Future<bool> _resolveShellEmpty(
  Future<User?> Function() readUser,
  Future<List<Group>> Function() readGroups,
  Future<bool?> Function(String uid) probeHasLiveData,
) async {
  final user = await readUser();
  if (user == null) return true; // no shell → nothing to orphan → proceed
  final groups = await readGroups();
  if (groups.isNotEmpty) return false;
  // #1091: stream-empty may be a cold cache (reinstall keeps the Keychain
  // UID, wipes Firestore persistence). Only server-confirmed zero LIVE
  // memberships may proceed; live-data AND inconclusive both block — this
  // gate is destructive, unlike the #839 notice where null stays kind.
  final hasLiveData = await probeHasLiveData(user.uid);
  return hasLiveData == false;
}
```

Update the gate's doc comment: "Only `data && empty`" becomes "Only server-confirmed zero live memberships (or no signed-in user — nothing to orphan) returns true."

**Step 2:** `flutter test test/unit/shell_emptiness_gate_test.dart` → all 12 pass.

**Step 3: Commit** `fix(auth): shell gate requires server-confirmed empty before cross-UID swap` (body: `Refs #1091`).

### Task 3: Wire the four call sites

**Files:**
- Modify: `lib/features/auth/providers/auth_email_link_bootstrap_provider.dart:161-166`
- Modify: `lib/features/auth/widgets/google_restore_action.dart:27-31`
- Modify: `lib/features/auth/widgets/durable_credential_sheet.dart:163-169`
- Modify: `lib/features/settings/screens/profile_screen.dart:1112-1116`

**Step 1:** Each call site adds one line inside the existing call (all four already import the gate file and have `ref` in scope):

```dart
probeHasLiveData: ref.read(shellEmptinessServerProbeProvider),
```

**Step 2:** `flutter analyze` → clean (the compiler enumerating call sites; a fifth caller found = wire identically + note in PR).

**Step 3: Commit** `fix(auth): wire server-confirm probe at all four swap-gate call sites` (body: `Refs #1091`).

### Task 4: Update existing rigs + per-call-site regression

**Files (explicit — round-1 P2s resolved):**
- Modify: `test/features/auth/google_restore_guard_test.dart` — proceed test needs the override; add it at the ProviderScope overrides (:65 region).
- Modify: `test/features/auth/durable_credential_sheet_conflict_test.dart` — same (:100 region).
- Modify: `test/unit/auth_email_link_bootstrap_test.dart` — same (:101, :606 regions).
- Modify: `test/features/settings/profile_account_card_test.dart` — proceed tests `'restore-with-Google row triggers restoreWithGoogle'` (:162) and `'restore-with-email row pushes /recover'` (:180) drive the gate to PROCEED; add the override to the shared build helper. Its block tests (:223/:241) use a populated stream and short-circuit before the probe — no override strictly needed, but the shared-helper placement covers them uniformly.
- Modify: `test/features/home/home_restore_cta_test.dart` — the Google CTA taps run `triggerGoogleRestore` → gate → probe. Put the override in the shared `_buildApp` (:83), NOT per-test. **Vacuous-pass trap:** `'a cancelled Google sheet is silent'` (:136) asserts only that the Google-error text is absent — without the override it would PASS VACUOUSLY while silently no longer testing the cancel path (the block snackbar is different text). Tests :116/:179 go RED and force the override; shared placement fixes :136 with them.

The override line everywhere:

```dart
shellEmptinessServerProbeProvider.overrideWithValue((_) async => false),
```

**Step 1:** Run the five files; every proceed-expecting test must go RED first (unoverridden probe → `[core/no-app]` → caught → `null` → block). Record which tests went red (behavioral RED evidence for the wiring). Then add the overrides; all green.

**Step 2:** Add ONE new regression case per authoritative call-site file (three files), same shape as each file's existing block test:
- `google_restore_guard_test.dart`: `'blocks restore when the stream is cache-empty but the server reports live data (#1091)'` — `watchUserGroups` → `Stream.value(const [])`, probe override → `(_) async => true`, assert blocked snackbar + `restoreWithGoogle` never called.
- `durable_credential_sheet_conflict_test.dart`: same scenario → conflict switch stays blocked.
- `auth_email_link_bootstrap_test.dart`: op=recover dispatch, empty stream + probe `true` → `restoreWithEmailLink` NOT invoked, blocked snack shown, in-flight op cleared.
Plus in ONE of them a probe-`null` variant (inconclusive → block) pinning destructive-null at integration level.

**Step 3:** Run those files → green.

**Step 4: Commit** `test(auth): pin cache-empty-vs-server-truth at every swap gate call site` (body: `Refs #1091`).

### Task 5: Full verification + ship

- [ ] `flutter test` — full suite green
- [ ] `flutter analyze` — clean
- [ ] `bash tool/check_theme_purity.sh` — no new widgets, expect clean
- [ ] PR: title `fix(auth): shell-emptiness gate requires server-confirmed empty (#1091)`; body: summary, `Closes #1091` in the FINAL commit body (squash-merge closes from commit bodies), `Spec: docs/plans/2026-07-10-1091-shell-gate-server-confirm.md`, Test plan, RED evidence (Task 1 compile-error output + Task 4 Step 1 behavioral reds), and the deliberate-decisions list (offline flip, tombstone-proceed, reused copy).
- [ ] `/automerge <PR>` — Gate-category posture (auth swap path); expect fresh review + refuter rounds.

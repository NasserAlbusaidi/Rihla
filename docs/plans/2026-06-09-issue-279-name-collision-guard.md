# #279 — Reject duplicate display names on join (server-authoritative)

**Date:** 2026-06-09
**Issue:** #279 (P2, data-integrity) — "no display-name collision guard on join — duplicate names make the ledger ambiguous"
**Decision (locked with user):** **Reject + ask again.** On a name collision the server throws a typed error; the client shows a localized "name taken — pick another." NOT auto-disambiguate, NOT the #278 claim model.
**Gate category:** YES — Cloud Function auth/validation (`joinGroupByInviteCode`) + money attribution. Run `/run-the-gate` before implementing.

---

## Problem (verified against live code, main @ `0ed6884`)

`joinGroupByInviteCode.ts:68 normalizeDisplayName` validates length + control-chars only — no uniqueness check. Two members can both be "Ahmed" / "Mama", making roster + settle-up attribution ambiguous. The display-side disambiguator (`MemberNameResolver`, #196/#289) only *renders* a ` (#last4)` suffix after the fact; it does not prevent the collision and is wired into only some surfaces.

## Why server-only (no client pre-check)

A joiner cannot read a group's member list before joining (rules: `isGroupMember` is false pre-join). So a client pre-check is **infeasible** — enforcement must live in the callable, the sole join write-path. (`validMemberCreate`, rules:796-815, only lets a client create a member doc for **itself** and only when already `isGroupMember`, so a non-member cannot self-write around the callable.)

## Collision key — match the existing oracle exactly

`MemberNameResolver.disambiguate` keys "same name" on `rawName.trim().toLowerCase()` (`member_name_resolver.dart:96,113,163`). The guard MUST use the **identical** normalization so the two layers agree:
- guard blocks any NEW `trim().toLowerCase()` collision on join,
- the display disambiguator continues to handle residual LEGACY collisions (pre-existing dupes are NOT retroactively fixed).

TS equivalent: `name.trim().toLowerCase()`. (JS/Dart default Unicode lowercasing agree for Latin + Arabic; Turkish-dotted-I class is out of cohort — acceptable parity, noted.)

---

## Changes

### 1. Server — `functions/src/callables/joinGroupByInviteCode.ts`

**Add a collision check INSIDE the existing `db.runTransaction` (the same txn that creates the member doc), scoped to genuine new joins.**

- After `groupSnap`/`memberSnap` are read and BEFORE the writes (~after line 298), read the members subcollection within the txn:
  ```ts
  const membersSnap = await tx.get(groupRef.collection('members'));
  ```
  (The txn already reads the full `events` subcollection with a size>400 guard; the members collection is bounded the same way in practice. No extra index.)
- Collision check ONLY for a **genuinely new member** — gate on `didJoin` (`== !memberSnap.exists && !memberIds.includes(uid)`), NOT bare `!memberSnap.exists`. (Auto-merge review P2: bare `!memberSnap.exists` would wrongly reject the #53 **heal path** — uid already in `memberIds` but member-doc missing — when its name matches another member; `didJoin` skips both idempotent re-join and heal-path restore.)
  ```ts
  if (didJoin) {
    const candidate = displayName.trim().toLowerCase();
    const taken = membersSnap.docs.some((d) => {
      if (d.get('userId') === uid) return false;            // exclude self (defensive; self has no doc here)
      const existing = d.get('displayName');
      return typeof existing === 'string'
        && existing.trim().toLowerCase() === candidate;
    });
    if (taken) {
      throw new HttpsError(
        'already-exists',
        'That name is already taken in this group. Please choose a different name.',
      );
    }
  }
  ```
- **Throw code = `already-exists`.** Verify against `isLookupFailure` (line 145): it returns true only for `not-found`/`failed-precondition`, so `already-exists` is NOT counted toward the join throttle (`recordFailedJoinAttempt`). A collision is a legitimate user error, not enumeration — it must not burn the 5/hr limit. **Do not** add `already-exists` to `isLookupFailure`.
- Throwing inside the txn → caught by the outer `catch` (line 354) → not a lookup failure → rethrown unchanged. `didJoin` stays false; no member-join notification fires (the throw precedes the writes).

**Match-by-`userId`-field, not doc id:** member docs key by `uid` for joiners but by random `uuid` for the creator (`userId` field carries the real uid). Collecting names from `membersSnap.docs` and comparing `displayName` is doc-id-agnostic, so the creator's name is correctly included in the collision set. (The `userId === uid` self-exclusion is defensive; in the `!memberSnap.exists` branch the joiner has no member doc yet.)

### 2. Client error routing — `lib/features/groups/providers/group_provider.dart`

`_joinGroupErrorMessage` (line ~232) add a case BEFORE the default:
```dart
'already-exists' => 'That name is already taken in this group.',
```
This string is matched by substring downstream to pick the localized copy (step 3). NOTE (Gate R1 P2): unlike what an earlier draft said, these `_joinGroupErrorMessage` strings ARE user-facing if `_errorMessage` ever falls through (every other case returns finished English copy too), so this string must read as acceptable English on its own — it does. Add the new case BEFORE the default; do NOT model it on the dead `'Already a member'` screen branch (join_group_screen.dart:138 — no emitter, Gate R1 P3).

### 3. Client localized copy — `lib/features/groups/screens/join_group_screen.dart`

`_errorMessage` (line 134) add BEFORE the fallback:
```dart
if (error.contains('already taken in this group')) {
  return context.l10n.groupJoinNameTaken;
}
```

### 4. l10n — `lib/l10n/app_en.arb` + `app_ar.arb` (+ regenerate)

New key `groupJoinNameTaken`:
- en: `"That name's already used in this group. Please pick a different name."`
- ar: `"هذا الاسم مستخدم بالفعل في هذه المجموعة. الرجاء اختيار اسم مختلف."`
Run `flutter gen-l10n` (or build) to refresh `lib/l10n/generated/*`.

### No firestore.rules change

Rules cannot efficiently enforce subcollection uniqueness, and the callable is the sole client join path. The only client-direct member create (`createGroup`, creator self-adds to an empty group) cannot collide. (See Out-of-scope for the self-rename surface.)

---

## Out of scope (acknowledged follow-ups — do NOT bundle)

1. **Self-rename collision.** `validSelfDisplayNameUpdate` (rules:817) lets a member rename themselves with no uniqueness check — a member could rename INTO a collision. TWO client paths hit it (Gate R1 P3): `updateMemberDisplayName` (D-07) AND `settings_provider.dart:112 propagateDisplayName` (a `batch.update` of the user's own member doc on every `setDeviceName`). Both are self-UPDATEs on the user's own doc (never creates), so both are correctly out-of-scope for "on join" — but name BOTH in the follow-up so neither is missed. The display disambiguator still covers them visually. (#279 is titled/scoped "on join"; the Gate confirmed `Closes #279` is honest.)
2. **Legacy pre-existing dupes** are not retroactively split — handled at render by `MemberNameResolver` (#289).
3. **Full localization of the OTHER join errors** (`_joinGroupErrorMessage` returns English routing tokens; only the final `context.l10n.*` is shown) → that's the #356 friendly-error-translator track. Here we only add one new localized path.

## Edge cases (decided)

- **"Anonymous" default** (no name sent → `normalizeDisplayName` returns `'Anonymous'`): treated like any other name — a second nameless joiner collides and is rejected. Deliberate (an all-"Anonymous" roster is exactly the ambiguity we're killing). Noted as a known sharp edge.
- **Whitespace/case:** `" owner "` / `"OWNER"` collide with `"Owner"` (trim+lowercase). Internal-whitespace collapse ("Al  Busaidi") is NOT done — matches the disambiguator's key.
- **Idempotent re-join** (same uid, member doc exists) AND **#53 heal path** (uid in `memberIds`, member-doc missing): collision check skipped (gated on `didJoin`) → both restore the existing name without self-rejection, even if it collides with another member.

---

## Test plan (TDD — RED first)

### Server — `functions/test/callables/joinGroupByInviteCode.test.ts` (Jest + emulator)

Harness: `seedInviteGroup()` already seeds member `Owner`. Add:
1. **RED→GREEN collision:** seed member "Owner"; join `ABC123` as a new uid with `displayName:'owner'` (case variant) ⇒ rejects with `HttpsError code 'already-exists'`; assert NO member doc created for the new uid and `groups/g1.memberIds` unchanged.
2. **Unique name passes:** join with `displayName:'Layla'` ⇒ succeeds, member doc created.
3. **No throttle on collision:** after a collision, `joinAttempts/{uid}` is absent/`failCount` unchanged (proves `already-exists` ∉ `isLookupFailure`).
4. **Idempotent re-join keeps working:** existing member re-calls join with their own name ⇒ succeeds (no self-collision).
5. **Trim/case variants collide:** `'  Owner '` ⇒ rejected.

### Client

6. Unit: `_joinGroupErrorMessage('already-exists')` contains `'already taken in this group'`.
7. Widget (mirror `create_join_group_test.dart` rate-limited test): stub `joinGroupCallableOverride` to throw `FirebaseFunctionsException(code:'already-exists')`; enter a code; assert the localized `groupJoinNameTaken` copy shows and the generic failure copy does not.

`flutter analyze` clean; `npm --prefix functions test` + the touched Flutter tests green.

---

## Verification principles (run on this spec)

1. **Callsite classification:** the new read (`membersSnap`) is INBOUND (comparison only); the only OUTBOUND remains the existing member-doc `tx.set` (unchanged). No display string reaches a write. ✅
2. **Concrete claims vs code:** `isLookupFailure` codes (145-148), `normalizeDisplayName` (68), member-doc create (330-339), creator-uuid keying, `MemberNameResolver` key (96) — all read and cited above. ✅
3. **Read-path per write-path:** new write paths = none (we only ADD a reject branch); the rejected path writes nothing. Consumer of the new error = `_joinGroupErrorMessage` → `_errorMessage` → `groupJoinNameTaken`. ✅
4. **Enumerate from type:** member doc fields (`id,userId,displayName,role,joinedAt,isShadow`, rules:799-806) — we read `userId`+`displayName` only. ✅
5. **Data contract:** server throw code `already-exists` ⇄ client `_joinGroupErrorMessage` case ⇄ substring `'already taken in this group'` ⇄ `groupJoinNameTaken`. Spelled exactly. ✅
6. **Arithmetic decomposition:** N/A (no money math changes; this protects attribution integrity upstream). ✅
7. **Adversarial / orthogonal axis (identity):** idempotent re-join (same identity) must not self-reject — covered by the `!memberSnap.exists` scope + test 4. Creator-keyed-by-uuid identity included via `userId`-field match — covered above. ✅

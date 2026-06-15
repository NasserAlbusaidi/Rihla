# #532 — Group/Member/Event.fromDoc hard-cast required fields → one malformed doc blanks the whole list

**Date:** 2026-06-15 · **Branch:** `fix/532-model-deserialize-fence` · baseline `origin/main` `e84882f8`
**Severity:** P2/P3 (data-integrity, forward-compat) · **Scope:** client-only · **Cluster:** `schema-debt` (continuation of #515's `Expense.fromFirestore` fence) · **Gate:** `models/**` → fresh-context Opus Gate (3 rounds).

> **SCOPE NARROWED after Gate R3 — `Group` + `GroupMember` only; `Event.fromDoc` DEFERRED.** R3 showed `Event.fromDoc` cannot be made genuinely total without also hardening `EventModules.fromMap` (its inner `ledger as bool?` throws on a wrong type) AND handling Firestore's `Map<dynamic,dynamic>` variance — which `FakeFirebaseFirestore` cannot reproduce (it returns `Map<String,dynamic>`), so the hardest event case is **untestable with the current harness** and a naive event fix would be falsely-green while diverging from the server oracle in prod. The event path is its own concern (model + `EventModules` + a real-Firestore test). This PR ships the money-critical, fully-testable **member-roster + group-list** slice and carries **`Refs #532`** (issue stays open, re-scoped to "Event.fromDoc total-parse + EventModules.fromMap hardening"). `watchGroupEvents` is left UNCHANGED (no skip-net) so no new event divergence is introduced.

## Problem (verified against live code)

A single malformed doc throws a `CastError` inside a list stream's `.map(fromDoc)` and errors the **entire** stream — the group list, member roster, or event list goes blank, not just the one row.

- `Group.fromDoc` (`group_model.dart` ~:43-61): hard-casts `name`/`inviteCode`/`createdBy as String`, `memberIds as List`, `createdAt as Timestamp` — no fallback.
- `GroupMember.fromDoc` (`group_member_model.dart` ~:31-43): hard-casts `userId`/`displayName`/`role as String`, `joinedAt as Timestamp` — no fallback.
- `Event.fromDoc` (`event_model.dart:103-153`): gives `createdAt` a 3-way `Timestamp|String|null` parse, but hard-casts `name`/`groupId`/`createdBy as String` and `participantIds as List?` / `participantNames as Map?` / `modules as Map<String,dynamic>?` (throw on a wrong-TYPE value).

Consuming **list** streams, none wrapped per-doc: `watchUserGroups` (`group_provider.dart` ~:424), `watchMembers` (~:439), `watchGroupEvents` (`event_service.dart:43`). `orderBy(createdAt/joinedAt)` excludes null/absent-order-field docs, so the create-time optimistic-null window does not crash these; live exposure is a **present-but-wrong-type** field (a migration / Admin tool / recovery copy). No live trigger today — forward-compat hardening, same cluster as #515 / #518.

## The R1 [P1] that reshaped the fix — oracle parity (verified)

The member roster is NOT display-only: it builds `allMemberIds` (`expense_provider.dart:122`), which **gates the #249 split-recipient fold** (`:212` `splitRecipientKeys.intersection(allMemberIds)`). A tombstoned former member who is a split recipient on a live expense — but not in `event.participantIds` and not a payer/settler — is folded into the balance **only because their member doc is in the roster**.

The **server oracle** `recomputeNet` (`groupNetBalance.ts:527-532`) builds `allMemberIds` gated **only** on `typeof data.userId === 'string'` — it never reads `joinedAt`/`role`/`displayName`. So a member with a valid `userId` but a malformed other field is **kept server-side** and keeps contributing to the fold (`:618`). A naive "skip the whole member doc on any throw" would drop that uid client-side → the fold excludes them → **client net diverges from the server oracle** (the drift `delete_group_balance_parity_test.dart` exists to forbid). Same for events: the server reads events tolerantly (`stringArray(participantIds)`, `:563`) and counts their expenses regardless of `name`/`createdBy`, so skipping a salvageable event client-side loses its expenses → divergence.

## Fix — TOTAL-PARSE factories (parity-safe) + skip-net catch-all

**The governing principle (why R1/R2 both found parity P1s):** for a doc that feeds the money oracle (members, events), **any throw inside `fromDoc` diverges the client from the server's tolerant reads** — the server never throws on a present-but-wrong-type field (`typeof userId === 'string'`, `data.isTombstone !== true`, `stringArray(participantIds)`). So `Member.fromDoc` and `Event.fromDoc` must be **TOTAL**: never throw on a non-null doc, except `GroupMember.userId` (the one deliberate hard gate that mirrors the server's `userId`-string exclusion). Concretely, replace **every** throwing cast with a total form:
- `x as String? ?? d` is NOT total — it throws on a non-null **non-String** (e.g. an int). Use `x is String ? x : d`.
- `x as bool? ?? false` throws on a wrong-typed bool. Use `x == true` (mirrors the server's `!== true`).
- `x as Timestamp` (even null-guarded) throws on a wrong type. Use the 3-way `Timestamp|String|null` helper.
- `List<String>.from(x as List? ?? [])` / `Map<String,String>.from(x as Map? ?? {})` throw on a bad **element** even when the container type is right. Use element-level filters: `(x is List) ? x.whereType<String>().toList() : <String>[]` and `{ for (e in (x is Map ? x.entries : const [])) if (e.key is String && e.value is String) e.key as String : e.value as String }` (mirrors the server's per-element `stringArray`).

**A. `GroupMember.fromDoc`** — `userId as String` stays HARD (parity gate). Total-parse the rest: `displayName is String ? … : ''`; `role is String ? … : 'MEMBER'`; `isShadow == true`; `isTombstone == true` (← R2 [P1]: was `as bool?`, threw on junk → dropped a tombstoned split-recipient the server keeps); `joinedAt` via the 3-way helper.

**B. `Group.fromDoc`** — total-parse for robustness (groups are NOT an oracle input — the user's group LIST never feeds the per-group `deleteGroup` oracle — so this layer is display-safety; salvage > skip keeps the group openable/leavable and in the #244-aware cross-group total): `createdAt`/`updatedAt`/`deletedAt` via the date helper (String branch uses **`DateTime.tryParse`**, never `parse`); `name`/`inviteCode`/`createdBy` via `is String ? … : ''`; `currency is String ? … : 'OMR'`; `memberIds` via `whereType<String>`; `isDeleted == true`. Group has NO nested-map field, so the Firestore `Map<dynamic,dynamic>` variance that defers Event does not arise here — fully testable with `FakeFirebaseFirestore`.

A small shared date helper (`DateTime? dateOrNull(dynamic)` + `DateTime dateOrNow(dynamic)` in `lib/core/utils/firestore_parse.dart`, String branch = `DateTime.tryParse(x) ?? fallback`) DRYs the 3-way parse (Event already inlines an equivalent; the deferred Event work will adopt this helper). After A–B, the only residual throw on these two streams is a null `doc.data()` or a member with no valid `userId` — both of which the **server also excludes** → the skip-net is parity-neutral.

**Event.fromDoc: DEFERRED** (see scope note) — `watchGroupEvents` is left exactly as-is. No event behavior changes in this PR.

**B. Per-doc skip-net** — new pure `lib/core/utils/safe_deserialize.dart`:
```dart
List<T> decodeDocsSkippingMalformed<T>(
  Iterable<DocumentSnapshot<Object?>> docs,
  T Function(DocumentSnapshot<Object?>) decode, {
  required String context,
}) {
  final out = <T>[];
  for (final doc in docs) {
    try { out.add(decode(doc)); }
    catch (e, st) {
      assert(() { debugPrint('[$context] skipped malformed doc ${doc.id}: $e'); return true; }());
      unawaited(Sentry.captureException(e, stackTrace: st)); // unawaited — matches write_ack.dart:42; no-op when Sentry uninit (test-safe)
    }
  }
  return out;
}
```
Route the **two** group streams — `watchUserGroups` and `watchMembers` — through it (replacing the bare `.map(fromDoc)`; keep `watchUserGroups`'s `.where(!isDeleted)` AFTER the decode). `watchGroupEvents` is NOT routed (Event deferred). After (A/B), this only fires on a doc-level catastrophe — null `data()`, or a member with no valid `userId` — both of which the **server also excludes**, so the skip-net is parity-neutral.

## Verification principles
1. **Callsite classification** — all INBOUND (list/roster render + the `members` balance READ). `toFirestore`/`toMap` write paths untouched → no display string reaches a write boundary.
2. **Claims vs code** — factory/stream callsites + the `allMemberIds` gate (client `:122/:212`, server `:529/:618`) + `Sentry`/`unawaited` convention (`write_ack.dart:42`) re-read this session. Method is `watchGroupEvents` (not `watchEvents`).
3. **Read-path per write-path** — no write change; consumers still get the same model types, only malformed docs behave differently (salvaged or, for catastrophes, skipped).
4. **Fields from the type** — every `fromDoc` field enumerated above; `userId` is the sole hard field (parity gate); all others salvage.
5. **Data contract** — `QuerySnapshot.docs` (`List<QueryDocumentSnapshot<Map<String,dynamic>>>`) is assignable to `Iterable<DocumentSnapshot<Object?>>` (covariant); `(d) => GroupMember.fromDoc(d, groupId)` closure type-checks.
6. **Arithmetic / oracle parity** — the corrected design preserves `allMemberIds` field-for-field against `recomputeNet`: a valid-`userId` member is always retained (salvage), and the only members the skip-net drops (no valid `userId`) are exactly those the server excludes. Events: tolerant parse ⇒ never skipped ⇒ expenses always counted, matching the server.
7. **Adversarial / orthogonal axis** — the regression test exercises the SETTLEMENT/IDENTITY axis: a **tombstoned split-recipient member with a malformed `joinedAt`/`role` AND a junk `isShadow`** stays in `allMemberIds` so `computeGroupBalances` still folds their owed share (proves no oracle drift); plus a bad-ISO-String `joinedAt`/`createdAt` that `DateTime.tryParse` rejects → salvaged to `DateTime.now()` (member/group KEPT, not skipped — the date is display/sort-only, never money).

## Tests (RED → GREEN)
- **`test/unit/safe_deserialize_test.dart`**: helper returns the good docs, drops the throwing one, doesn't rethrow.
- **`test/unit/model_deserialize_fence_532_test.dart`**:
  - `GroupMember.fromDoc` salvages `joinedAt` as ISO String, and a valid-`userId` member with junk `role`/`displayName` (RED today: `CastError`).
  - `Group.fromDoc`/`Event.fromDoc` salvage `createdAt`-as-String and missing `name` (RED today).
  - **Parity (R1):** a group whose live expense splits onto a **tombstoned** member (`isTombstone:true`) whose member doc has a malformed `joinedAt` AND a junk `isShadow` value — assert `computeGroupBalances` still credits that member's owed share (their uid survives in `allMemberIds`), proving no divergence from the server fold (`groupNetBalance.ts:618`).
  - **Stream:** `watchUserGroups`/`watchMembers` (via `FakeFirebaseFirestore`) with one truly-undecodable doc (a member with NO `userId`) + good docs → emits the good ones, stream does not error.
- Regression: existing model + provider/service tests stay green; `delete_group_balance_parity_test.dart` stays green.

## Non-goals
- **`Event.fromDoc` total-parse — DEFERRED to a follow-up** (the re-scoped #532). Needs `EventModules.fromMap` hardening (`ledger as bool?` throws on wrong type) + Firestore `Map<dynamic,dynamic>` variance handling, which `FakeFirebaseFirestore` cannot reproduce → needs a real-Firestore-backed test. `watchGroupEvents` stays as-is here.
- Single-doc detail reads (`watchGroup`, `watchEvent`) — return `null`/error for ONE entity, don't blank a list (#518 fenced their `isDeleted`).
- `fromMap` (SQLite) factories — dead since #50, untouched.
- Server-side changes — the server is already tolerant; this aligns the client TO it.

## Done
`flutter analyze` clean · new + parity + regression tests green · **`Refs #532`** (commit body too — partial: Group+Member only, Event deferred; issue stays open re-scoped) · ship via `/automerge` (review + refute).

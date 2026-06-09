# Self-Rename Display-Name Collision Guard (#390 / #279 follow-up) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Stop a member from renaming themselves *into* a duplicate display name within any group they belong to, closing the self-rename vector #279's join-time guard never covered.

**Architecture:** Client-side pre-check (the renamer is already a member and may read the roster — the one constraint that forced #279 server-side does not apply here; and firestore.rules cannot query a subcollection for duplicates, so a rules-layer guard is impossible regardless). `setDeviceName` reads every group the user belongs to, and if the new name collides (case-insensitive, trimmed) with any **other live** member in **any** group, it throws `DisplayNameTakenException` **before** persisting or propagating — reject + ask again, all-or-nothing. The three `setDeviceName` callers (Profile edit, join, create) catch it and surface a localized "name taken in <group>" message.

**Tech Stack:** Flutter, Riverpod, Cloud Firestore client SDK, `flutter_test`, `fake_cloud_firestore` (helper test only), Flutter l10n (`.arb`).

**Non-goals / locked decisions:**
- NOT server-authoritative; NO `firestore.rules` / Cloud Functions change. Display name is not a money invariant; the #279 join guard and #196/#289 disambiguator remain the backstops.
- All-or-nothing across groups (block the whole rename), NOT per-group skip.
- `updateMemberDisplayName` (D-07, `group_provider.dart:292`) has **no UI caller** today — out of scope; guard it when a per-group rename UI ships (noted in code).
- The collision key is `trim().toLowerCase()` — it MUST stay byte-identical to `MemberNameResolver.disambiguate` (`member_name_resolver.dart:96`) and the #279 server guard (`joinGroupByInviteCode.ts:318-324`).

---

## Background facts (verified against code, 2026-06-09)

- `setDeviceName` (`lib/core/providers/settings_provider.dart:89`): validates, normalizes, `saveDeviceName` (SharedPreferences), `state = copyWith`, then `unawaited(propagateDisplayName(normalized))`.
- `propagateDisplayName` (`:112`): queries `groups where memberIds arrayContains uid`, then per group queries `members where userId == uid`, batches `displayName` updates. Silent-catch (D-15). Reads `FirebaseConfig.firestore` / `FirebaseConfig.currentUser` as **statics** (not injected).
- **In unit tests `FirebaseConfig.currentUser` THROWS, not returns null** — `currentUser => FirebaseAuth.instance.currentUser` and `FirebaseAuth.instance` throws `[core/no-app]` when `Firebase.initializeApp()` was never called (the case in `settings_notifier_test.dart`). Proof: `group_service_test.dart:103-106` asserts `createGroup` (which reads `FirebaseConfig.currentUser?.uid`) `throwsA(isA<Exception>())` with no signed-in user. The existing `setDeviceName` tests stay green today ONLY because `propagateDisplayName` reads `currentUser` **inside** its `try` (`settings_provider.dart:113-114`) AND is `unawaited`. Therefore the new pre-check MUST read `currentUser` **inside** its own `try` so the `[core/no-app]` throw is caught and fails open — reading it outside the try (and awaiting it in `setDeviceName`) reddens every existing `setDeviceName` test. The genuine `uid == null` early-return only fires when Firebase IS initialized and no user is signed in.
- `GroupMember` fields (`group_member_model.dart`): `id, groupId, userId, displayName, role, isShadow, isTombstone, joinedAt`. `fromDoc` casts `userId/displayName/role` as **non-nullable** `String` → it THROWS on a malformed doc. The pre-check therefore reads **raw maps**, not `fromDoc`, mirroring the #279 server guard's lenient `typeof existing === 'string'` check.
- `MemberDisplay.isFormer` ⇐ `GroupMember.isTombstone`. `disambiguate` counts **live only** (`isFormer` skipped). The pre-check skips `isTombstone == true` for the same reason — a former "Ahmed" carries the `(former member)` suffix and is not ambiguous.
- Member-doc keying is inconsistent (#294): the creator's doc is `uuid`-keyed with `userId: uid` as a field. Own-doc exclusion MUST match by the `userId` **field**, never the doc id.
- `setDeviceName` callers:
  - `profile_screen.dart:142-144` via `EditNameBottomSheet.onSave`. `EditNameBottomSheet._handleSave` (`edit_name_bottom_sheet.dart:52-81`) has **no try/catch** around `await widget.onSave(...)` → an unhandled throw sticks `_isSaving = true` and hangs the sheet.
  - `join_group_screen.dart:81` — **outside** the try (try starts `:83`); `groupLoadingProvider` set true at `:78` → an unhandled throw sticks the loading spinner.
  - `create_group_screen.dart:73` — **outside** the try (try starts `:75`); same stuck-spinner.
- l10n: `groupJoinNameTaken` exists (`app_en.arb:1297`, `app_ar.arb:578`) — "...in **this group**...", which is wrong for a collision in a *different* existing group. Add a new placeholder key naming the group. Placeholder-key shape reference: `groupCreateError` (`app_en.arb:1254-1259`).

---

## Task 1: Pure collision predicate `nameCollidesInDocs`

The integrity core. Lives in `core/utils/name_validators.dart` (a pure, zero-import file already imported by `settings_provider`, the bottom sheet, and join/create via the localized wrapper) — NOT in `member_name_resolver.dart` (features/groups), to avoid the codebase's first core→features import edge. Map-based + lenient so it mirrors the #279 server guard byte-for-byte and never throws on a malformed doc.

**Files:**
- Modify: `lib/core/utils/name_validators.dart`
- Test: `test/unit/name_validators_test.dart` (file exists)

**Step 1: Write the failing tests**

Add to `test/unit/name_validators_test.dart`:

```dart
group('nameCollidesInDocs (#390 self-rename guard)', () {
  Map<String, dynamic> doc(String userId, String displayName,
          {bool isTombstone = false}) =>
      {'userId': userId, 'displayName': displayName, 'isTombstone': isTombstone};

  test('collides with a different live member, case/space-insensitive', () {
    expect(
      nameCollidesInDocs(
        candidate: '  ahmed  ',
        selfUid: 'me',
        memberDocs: [doc('other', 'Ahmed')],
      ),
      isTrue,
    );
  });

  test('own doc (matched by userId field, not doc id) never collides', () {
    expect(
      nameCollidesInDocs(
        candidate: 'Ahmed',
        selfUid: 'me',
        memberDocs: [doc('me', 'Ahmed')],
      ),
      isFalse,
    );
  });

  test('tombstoned (former) member is skipped', () {
    expect(
      nameCollidesInDocs(
        candidate: 'Ahmed',
        selfUid: 'me',
        memberDocs: [doc('ghost', 'Ahmed', isTombstone: true)],
      ),
      isFalse,
    );
  });

  test('non-string / missing displayName is skipped, never throws', () {
    expect(
      nameCollidesInDocs(
        candidate: 'Ahmed',
        selfUid: 'me',
        memberDocs: [
          {'userId': 'a', 'displayName': 42},
          {'userId': 'b'},
          doc('c', 'Sara'),
        ],
      ),
      isFalse,
    );
  });

  test('blank candidate never collides', () {
    expect(
      nameCollidesInDocs(
        candidate: '   ',
        selfUid: 'me',
        memberDocs: [doc('other', 'Ahmed')],
      ),
      isFalse,
    );
  });

  test('no collision when names differ', () {
    expect(
      nameCollidesInDocs(
        candidate: 'Ahmed',
        selfUid: 'me',
        memberDocs: [doc('x', 'Sara'), doc('y', 'Mona')],
      ),
      isFalse,
    );
  });
});
```

**Step 2: Run, verify fail**

Run: `flutter test test/unit/name_validators_test.dart`
Expected: FAIL — `nameCollidesInDocs` is not defined.

**Step 3: Implement**

Append to `lib/core/utils/name_validators.dart` (top-level function, matching the file's `validateDisplayName`/`normalizeDisplayName` style):

```dart
/// Whether [candidate] collides — by the shared #196/#279 collision key
/// `trim().toLowerCase()` — with any LIVE member in [memberDocs] whose
/// `userId` field differs from [selfUid].
///
/// The collision key MUST stay identical to `MemberNameResolver.disambiguate`
/// (`member_name_resolver.dart:96`) and the #279 server guard
/// (`functions/src/callables/joinGroupByInviteCode.ts:318-324`) so prevention
/// and the display disambiguator agree.
///
/// [memberDocs] are RAW Firestore member maps (not [GroupMember]) so a
/// malformed doc is skipped, never thrown on. Own-doc is matched by the
/// `userId` FIELD (the creator doc is uuid-keyed — #294), and tombstoned
/// (former) members are skipped to match the live-only counting in
/// `disambiguate`. Used by the self-rename pre-check (#390).
bool nameCollidesInDocs({
  required String candidate,
  required String selfUid,
  required Iterable<Map<String, dynamic>> memberDocs,
}) {
  final key = candidate.trim().toLowerCase();
  if (key.isEmpty) return false;
  for (final data in memberDocs) {
    if (data['userId'] == selfUid) continue;
    if (data['isTombstone'] == true) continue;
    final existing = data['displayName'];
    if (existing is String && existing.trim().toLowerCase() == key) {
      return true;
    }
  }
  return false;
}
```

**Step 4: Run, verify pass**

Run: `flutter test test/unit/name_validators_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/core/utils/name_validators.dart test/unit/name_validators_test.dart
git commit -m "feat(groups): pure display-name collision predicate for self-rename guard (#390)"
```

---

## Task 2: `DisplayNameTakenException`

**Files:**
- Modify: `lib/core/utils/name_validators.dart` (pure, no Firestore dep; already imported by the bottom sheet, settings provider, join/create screens via the localized wrapper)
- Test: covered indirectly by Tasks 3–4 (a bare data class needs no dedicated test).

**Step 1: Implement**

Append to `lib/core/utils/name_validators.dart`:

```dart
/// Thrown by `setDeviceName` (#390) when the requested display name already
/// belongs to another live member of [groupName] — the rename is rejected
/// whole (all-or-nothing) so the user picks a different, unambiguous name.
class DisplayNameTakenException implements Exception {
  const DisplayNameTakenException(this.groupName);

  /// Name of the group in which the collision was found (for the UI message).
  final String groupName;

  @override
  String toString() => 'DisplayNameTakenException(groupName: $groupName)';
}
```

**Step 2: Analyze**

Run: `flutter analyze lib/core/utils/name_validators.dart`
Expected: no issues.

(No separate commit — fold into Task 3's commit, which first uses the type.)

---

## Task 3: `setDeviceName` collision pre-check + l10n key

**Files:**
- Modify: `lib/core/providers/settings_provider.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`
- Test: `test/unit/settings_notifier_test.dart` (regression guard: no-op when unauthenticated)

**Step 1: Add the l10n key**

In `app_en.arb` (next to `groupJoinNameTaken`):

```json
"displayNameTakenInGroup": "That name's already used in {groupName}. Please pick a different name.",
"@displayNameTakenInGroup": {
  "placeholders": {
    "groupName": {}
  }
},
```

In `app_ar.arb` (next to `groupJoinNameTaken`):

```json
"displayNameTakenInGroup": "هذا الاسم مستخدم بالفعل في {groupName}. الرجاء اختيار اسم مختلف.",
```

Run: `flutter gen-l10n` (or rely on the build) so `AppLocalizations.displayNameTakenInGroup` is generated.

**Step 2: Write the failing regression test**

In `test/unit/settings_notifier_test.dart` add:

```dart
test('setDeviceName is a no-op collision-wise when unauthenticated '
    '(FirebaseConfig.currentUser == null) — still persists', () async {
  final container = await makeContainer();
  final notifier = container.read(settingsProvider.notifier);
  // No Firebase in unit tests → uid null → pre-check must early-return,
  // never throw, and the name still persists.
  await notifier.setDeviceName('Ahmed');
  expect(container.read(settingsProvider).deviceName, equals('Ahmed'));
});
```

(This passes once the early-return is correct; it FAILS if the pre-check is wired to throw or await something that blows up under a null uid. It is the guard that the new code does not regress the existing unauth/offline path.)

**Step 3: Implement the pre-check**

No new import: `setDeviceName` already imports `../utils/name_validators.dart` (line 13), which now exports both `nameCollidesInDocs` and `DisplayNameTakenException`.

Edit `setDeviceName` to gate before persisting:

```dart
Future<void> setDeviceName(String name) async {
  final normalized = name.trim().isEmpty ? '' : normalizeDisplayName(name);
  if (name.trim().isNotEmpty) {
    final error = validateDisplayName(name);
    if (error != null) {
      throw ArgumentError.value(name, 'name', error);
    }
    // #390: reject a rename that would collide with another live member in
    // ANY group the user belongs to (all-or-nothing). Throws
    // DisplayNameTakenException BEFORE persisting/propagating.
    await _ensureDisplayNameAvailable(normalized);
  }

  await _service.saveDeviceName(normalized); // SharedPreferences first (D-16)
  state = state.copyWith(deviceName: normalized);
  if (normalized.isNotEmpty) {
    unawaited(propagateDisplayName(normalized)); // D-15 fire-and-forget
  }
}
```

Add the private pre-check:

```dart
/// Throws [DisplayNameTakenException] if [normalized] collides with another
/// live member in any group the current user belongs to (#390).
///
/// Reads `FirebaseConfig.currentUser` / `FirebaseConfig.firestore` (same as
/// [propagateDisplayName]); the renamer is a member of these groups so the
/// roster read is permitted. The `currentUser` read is INSIDE the `try` on
/// purpose: with no Firebase app initialized (unit tests) it throws
/// `[core/no-app]`, which the `catch (_)` swallows → fail-open. Fail-OPEN on
/// ANY read error (offline cold cache / transient / no-Firebase-app): a rename
/// is never blocked by a failed read — the #279 join guard is the
/// authoritative collision boundary and the #196/#289 disambiguator is the
/// display backstop. A real collision (DisplayNameTakenException) is always
/// rethrown.
Future<void> _ensureDisplayNameAvailable(String normalized) async {
  try {
    final uid = FirebaseConfig.currentUser?.uid;
    if (uid == null) return; // genuinely unauthenticated — nothing to check
    final db = FirebaseConfig.firestore;
    final groupsSnap = await db
        .collection('groups')
        .where('memberIds', arrayContains: uid)
        .get();
    for (final groupDoc in groupsSnap.docs) {
      final membersSnap = await db
          .collection('groups')
          .doc(groupDoc.id)
          .collection('members')
          .get();
      final collides = nameCollidesInDocs(
        candidate: normalized,
        selfUid: uid,
        memberDocs: membersSnap.docs.map((d) => d.data()),
      );
      if (collides) {
        final groupName = (groupDoc.data()['name'] as String?) ?? '';
        throw DisplayNameTakenException(groupName);
      }
    }
  } on DisplayNameTakenException {
    rethrow; // a real collision is a real rejection
  } catch (_) {
    return; // fail-open: read failure / offline cold cache / no Firebase app
  }
}
```

> Ordering note: the `on DisplayNameTakenException { rethrow; }` clause MUST precede `catch (_)`, or the generic catch would swallow the rejection. Dart evaluates `on`/`catch` clauses top-to-bottom. The whole body (including the `currentUser` read) is inside the `try` so a `[core/no-app]` throw under no-Firebase-init is caught — this is what keeps the existing `setDeviceName` unit tests green.

**Step 4: Run, verify pass**

Run: `flutter test test/unit/settings_notifier_test.dart`
Expected: PASS (all existing `setDeviceName` tests + the new no-op guard).

**Step 5: Commit**

```bash
git add lib/core/providers/settings_provider.dart lib/core/utils/name_validators.dart lib/l10n/app_en.arb lib/l10n/app_ar.arb test/unit/settings_notifier_test.dart
git commit -m "feat(settings): reject self-rename into a duplicate display name (#390)"
```

---

## Task 4: Surface the rejection in `EditNameBottomSheet` (primary rename surface)

**Files:**
- Modify: `lib/features/settings/widgets/edit_name_bottom_sheet.dart`
- Test: `test/features/settings/edit_name_bottom_sheet_test.dart` — **already exists** (#227); EXTEND it, reusing its `openEditName(tester, currentName:, onSave:)` helper (opens the sheet via `Key('open')`) and `saveButton(tester)`. Do NOT recreate the harness.

**Step 1: Write the failing widget test (append to the existing file's `main()`)**

```dart
testWidgets('shows taken-name error and recovers when onSave rejects',
    (tester) async {
  await openEditName(
    tester,
    currentName: 'Ahmed',
    onSave: (_) async =>
        throw const DisplayNameTakenException('Trip to Muscat'),
  );

  // Type a valid name and Save → onSave throws DisplayNameTakenException.
  await tester.enterText(find.byKey(ProfileKeys.nameTextField), 'Sara');
  await tester.pump();
  await tester.tap(find.byKey(ProfileKeys.saveNameButton));
  await tester.pumpAndSettle();

  // Localized error names the group; spinner cleared (Save interactive again);
  // sheet NOT popped (still on screen).
  expect(find.textContaining('Trip to Muscat'), findsOneWidget);
  expect(saveButton(tester).onPressed, isNotNull);
  expect(find.byKey(ProfileKeys.saveNameButton), findsOneWidget);
});
```

Add `import 'package:safar/core/utils/name_validators.dart';` to the test (for `DisplayNameTakenException`). `pumpAndSettle()` drains the sheet's 600/800ms success-animation timers (here they never start, but settling is harmless and avoids a pending-timer teardown if the path changes).

**Step 2: Run, verify fail**

Run: `flutter test test/features/settings/edit_name_bottom_sheet_test.dart`
Expected: FAIL — error text not found / pending-timer or unhandled-exception.

**Step 3: Implement**

In `edit_name_bottom_sheet.dart`, wrap the `onSave` call in `_handleSave`:

```dart
setState(() => _isSaving = true);
HapticService.medium();

final stopwatch = Stopwatch()..start();
try {
  await widget.onSave(displayName);
} on DisplayNameTakenException catch (e) {
  if (!mounted) return;
  setState(() {
    _isSaving = false;
    _errorText = context.l10n.displayNameTakenInGroup(e.groupName);
  });
  return;
}
final elapsed = stopwatch.elapsedMilliseconds;
```

Add `import '../../../core/utils/name_validators.dart';` (for `DisplayNameTakenException`).

**Step 4: Run, verify pass**

Run: `flutter test test/features/settings/edit_name_bottom_sheet_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/features/settings/widgets/edit_name_bottom_sheet.dart test/features/settings/edit_name_bottom_sheet_test.dart
git commit -m "feat(settings): surface duplicate-name rejection in the edit-name sheet (#390)"
```

---

## Task 5: Handle the rejection in join + create flows (no stuck spinner)

These call `setDeviceName` **outside** their try blocks; a throw would stick the loading state. Wrap each in its own guard. The collision here is in a *different* existing group (the user isn't yet/sole member of the new one), so naming the group is correct.

**Files:**
- Modify: `lib/features/groups/screens/join_group_screen.dart`
- Modify: `lib/features/groups/screens/create_group_screen.dart`

**Step 1: Join — wrap the `setDeviceName` call**

Replace `join_group_screen.dart:81`:

```dart
try {
  await ref.read(settingsProvider.notifier).setDeviceName(trimmedName);
} on DisplayNameTakenException catch (e) {
  ref.read(groupLoadingProvider.notifier).state = false;
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.displayNameTakenInGroup(e.groupName))),
    );
  }
  return;
}
```

Add `import '../../../core/utils/name_validators.dart';` if not already present.

**Step 2: Create — wrap the `setDeviceName` call**

Replace `create_group_screen.dart:73`:

```dart
try {
  await ref.read(settingsProvider.notifier).setDeviceName(trimmedName);
} on DisplayNameTakenException catch (e) {
  ref.read(groupLoadingProvider.notifier).state = false;
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.displayNameTakenInGroup(e.groupName))),
    );
  }
  return;
}
```

Add the `name_validators.dart` import if absent.

**Step 3: Analyze + full suite**

Run: `flutter analyze`
Expected: clean.

Run: `flutter test`
Expected: PASS (full suite — the prior tasks' tests + no regressions in join/create/settings/groups).

**Step 4: Commit**

```bash
git add lib/features/groups/screens/join_group_screen.dart lib/features/groups/screens/create_group_screen.dart
git commit -m "feat(groups): handle duplicate-name rejection in join/create flows (#390)"
```

---

## Task 6: Final verification

**Step 1: Analyze**

Run: `flutter analyze`
Expected: No issues found.

**Step 2: Targeted tests**

Run:
```
flutter test test/unit/name_validators_test.dart \
  test/unit/settings_notifier_test.dart \
  test/features/settings/edit_name_bottom_sheet_test.dart
```
Expected: all PASS.

**Step 3: Full suite**

Run: `flutter test`
Expected: PASS, coverage ≥ 80%.

**Step 4: Open the PR**

Body MUST carry `Closes #390`, a `Spec:` line pointing at this plan, and the RED→GREEN evidence for the bug-fix (the pure-helper test failing before the predicate existed). Gate-classify via `/automerge` (path denylist may mark this Gate-exempt — feature lib + l10n, no money/rules/routing/`models/`; if so it auto-merges on green `readiness`; if classified Gate-category, the fresh-context diff review + refuter run first).

---

## Test matrix summary

| Behavior | Test | Type |
|---|---|---|
| collision key trim/case-insensitive | `nameCollidesInDocs` collides | unit |
| own doc excluded by `userId` field (#294) | own-doc no-collide | unit |
| tombstone/former skipped (live-only, matches disambiguate) | tombstone skipped | unit |
| malformed/non-string doc never throws | non-string skipped | unit |
| blank candidate | blank → false | unit |
| no false positive on distinct names | differ → false | unit |
| unauth/offline path unchanged (early-return, still persists) | no-op when uid null | unit |
| primary rename surface shows error + recovers (no hang) | sheet rejects | widget |
| join/create no stuck spinner | analyze + full suite | static + suite |

## Risks / edges considered

- **Double read:** the pre-check reads rosters, then `propagateDisplayName` re-reads to write. Acceptable — rename is rare and reads hit the offline cache; kept separate because the pre-check must gate *before* `saveDeviceName`, while propagate is post-persist fire-and-forget.
- **Fail-open on read error:** a rename is never blocked by a transient/offline read failure (worst case a duplicate persists and the #196 disambiguator shows ` (#last4)` until corrected). Blocking all renames offline is worse.
- **Parity drift vs #279:** the client pre-check **skips tombstones**; the deployed #279 server guard does **not** yet (its acknowledged P3). Both are safe (a former member carries the `(former member)` suffix). Aligning #279 to skip tombstones is a separate, deferred server change — do NOT bundle it here.
- **`updateMemberDisplayName` (D-07):** still unguarded but has no UI caller; guard it (reuse `nameCollidesInDocs`) when a per-group rename UI lands.
- **Internal-whitespace normalization asymmetry (pre-existing, out of scope):** the client `normalizeDisplayName` collapses `\s+`→` ` (`name_validators.dart:73`) while the server `normalizeDisplayName` only edge-trims (`joinGroupByInviteCode.ts:84`). The shared collision key `trim().toLowerCase()` does NOT collapse internal runs, so a server-stored `"Al  Said"` (two spaces) and a client `"Al Said"` (one) miss each other — a false negative. This pre-dates and is unchanged by this spec (the predicate uses the exact same key as `disambiguate` and the #279 guard); fixing it means changing the shared collision key everywhere, which is its own Gate. Noted, not addressed here.

# Group Glyph → "Trip Stamps" Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the fake decorative glyph row on Create-Group (and the name-letter-only group tile) with a real, persisted **trip-stamp** identity — a chosen symbol (one of 12 monoline glyphs) + an ink colour, defaulting to the serif monogram, rendered everywhere the group tile appears.

**Architecture:** Add two optional fields to the `Group` model (`glyph`, `inkIndex`); persist them on the create write path and a creator-only edit path; allow-list + bound them in `firestore.rules`; rewrite the `GroupGlyph` widget to render symbol-or-monogram in the chosen (or name-hash-derived) ink; ship the 12 glyphs as bundled SVG assets via `flutter_svg`. The monogram is the no-symbol default, so groups with no stored fields render unchanged in behaviour.

**Tech Stack:** Flutter, Riverpod, Firestore (client SDK + security rules), `flutter_svg` (new dep), Jest + Firebase emulator (rules tests), `flutter_test`.

**Design source of truth:** `docs/design/mockups/claude-design-trip-stamps.html` (signed off via claude.ai/design, project "Rihla Design System"). The 12 glyph SVG paths are the `<g id="g-…">` sprite in that file (ids `g-tent … g-camera`; **exclude `g-route`**, which is unused).

---

## Locked decisions (carry into the Gate)

1. **Flavour:** ship **A** (clean rounded tile) everywhere; **C** (monogram) is the built-in no-symbol default; **B** (passport perforation) is NOT shipped on list tiles — optionally only on the large picker hero (deferred, not in this plan).
2. **Icon delivery:** ship the 12 glyphs as **bundled SVG assets rendered with `flutter_svg`**, recoloured via `ColorFilter.mode(ink, BlendMode.srcIn)`. Rejected: an icon font (stroke→outline conversion alters the glyphs and loses stroke control) and hand-ported `CustomPainter` (12× transcription risk). **Pin the EXACT version `flutter pub add flutter_svg` resolves on the dev toolchain (Flutter ^3.10.1 / AGP 8.9.1), not a caret range** — flutter_svg pulls `vector_graphics`; a future minor could drift. A failed resolve is a blocker, not a "fix later."
3. **Zero-regression = INDEX-stable, not colour-identical.** A group with **no `inkIndex`** (every legacy group, any pre-feature doc) derives a **stable** ink index as `_hash(name) % 6`, deterministic and per-group constant. Because the 6-ink palette is being **rebased to `cat1..cat6`** (the current widget uses a different bg/fg pair set), **the rendered colour at a given index changes once, at ship, for existing groups** — intended (the restyle is the whole point; no real users yet). The tile *styling* (tinted bg + hairline border) also applies to ALL groups. So: **monogram letter preserved**, **derived index stable per group**, **colour rebased once**. Do NOT write a colour-equality regression test against the old palette — assert the resolved **index** only (Task 4).
4. **Default-vs-chosen model (both fields nullable end-to-end).** `glyph` AND `inkIndex` are nullable everywhere — model, picker, write. **`null` = "defaulted"** (monogram for `glyph`; name-derived ink for `inkIndex`); **non-null = explicit user pick.** The create write persists **only explicit picks** (conditional key omission — never writes the derived fallback). The picker hero renders `inkIndex ?? _hash(name)%6`, so while the ink is unpicked the hero **tracks the live group name per keystroke** — this is honest WYSIWYG: the hero shows exactly the name-derived ink that will render after create (because null persists → render derives from the final name). **Empty-name transient:** before the user types a name the hero shows the `·` monogram in `cat1` (`_hash('')%6==0`); create is name-gated — `_createGroup` early-returns on the form validator (`validateDisplayNameLocalized` rejects empty, not a disabled button) — so an empty-name group never persists. Clearing on the edit path uses **`FieldValue.delete()`** (a cleared field == a never-set field), which **sidesteps explicit-null rules semantics entirely** (resolves G1).

## Ink palette (index ⇄ token ⇄ hex)

The 6 inks are the existing category/avatar palette (`color_tokens.dart` / `rihla.css`), exposed as `context.colors.cat1..cat6` (verified to exist with these exact hexes). `inkIndex` is 0-based:

| index | token  | hex      | design name |
|-------|--------|----------|-------------|
| 0     | `cat1` | #C2693B  | Terracotta  |
| 1     | `cat2` | #4F7B96  | Harbour     |
| 2     | `cat3` | #8C6A2F  | Ochre       |
| 3     | `cat4` | #6F7A3A  | Olive       |
| 4     | `cat5` | #94517A  | Plum        |
| 5     | `cat6` | #4D5A6A  | Slate       |

Tile (size `s`): `borderRadius = s*0.30`; `background = ink @ 13% alpha over colors.scaffoldBackground`; `border = 1px ink @ 28% alpha`; symbol/monogram = full ink. (Matches `.stamp` in the design. `ink.withValues(alpha: …)` is house style.)

## Glyph id allow-list (id ⇄ asset ⇄ ARB label key)

Stored `glyph` value = the bare id (e.g. `"tent"`). `null`/absent = monogram. The 12 valid ids:

`tent, mountain, palm, sun, wave, compass, anchor, house, dining, coffee, gift, camera`

Each maps to `assets/glyphs/<id>.svg` (lift the matching `<g id="g-<id>">` path data from the design sprite into a standalone `<svg viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">…</svg>`), and an ARB label key `groupStampSymbol_<id>` (tooltip only; not required for v1 functionality).

---

## Verification report (the 7 principles, run against live code; round-2 corrections folded in)

1. **Callsite classification.** `GroupGlyph` callsites: `home_screen.dart:682` (INBOUND, display, default `size`), `group_info_section.dart:122` (INBOUND, display, `size: 44`). The only other `GroupGlyph(` hit is the constructor. No OUTBOUND read of the rendered glyph. The OUTBOUND path is the picker → `createGroup`/edit-write. No display-string-persisted hazard.
   - **Test fallout (must REPLACE, not patch — CLAUDE.md):** `create_join_group_test.dart:117-119` asserts `find.text('Group glyph')`, `find.text('⛺')`, **`find.text('⌂')`** (the first two of `_GlyphRow._glyphs = ['⛺','⌂','↗','✦','◐','⌘']`). Renaming the `groupGlyph` ARB value to "Stamp" and deleting `_GlyphRow` breaks **all three**. Task 8 replaces them with the picker's presence.
2. **Claims verified against code.** WRITE path = the **inline camelCase `batch.set` map** in `group_provider.dart:208-222` (writes `'inviteCode'`, `'createdBy'`, … → Task 6 adds `'glyph'`/`'inkIndex'` camelCase). READ path = `Group.fromDoc` (`group_model.dart:51-68`, camelCase total-parse). **`Group.toMap`/`Group.fromMap` (`:70-106`) are DEAD SQLite-era methods — zero production callers (grep: the only live `.toMap()`/`.fromMap` are `EventModules`, a different class); the SQLite cache was removed in #50.** They are exercised ONLY by `test/unit/group_model_test.dart`. So the live (de)serialization contract is **fromDoc (read) + the inline camelCase create map (write)** — `toMap`'s `ink_index` snake_case is NOT a wire format and must not be presented as one. Rules guard checks `request.resource.data.inkIndex` (camelCase) — agrees with the write. `firestore.rules:251` (`validGroupCreate` `hasOnly`), `:282-295` (`validCreatorMetadataUpdate` — gates `name` via `hasAny(['name'])`, so a **stamp-only update with no name change is reachable**; creator-only via `isCreator()`), `:319-321` (`allow update: … && (validCreatorMetadataUpdate() || validMemberIdsRefresh())` — `validCreatorMetadataUpdate` is **LIVE**, not the dead-rules trap). Tokens `colors.cat1..cat6` / `colors.scaffoldBackground` / `AppTypography.display(fontSize:,color:,height:)` exist. `_hash` is `static int` (`group_glyph.dart:55`). `pubspec.yaml:52` = `iconsax` only; no `flutter_svg`. All read this session.
3. **One read-path per write-path.** WRITE `glyph`/`inkIndex` (create map + creator-edit) → READ in `GroupGlyph` (home list tile + group-detail header). Named, single widget.
4. **Fields enumerated from the type.** `Group` (`group_model.dart`): id, name, inviteCode, createdBy, memberIds, currency, createdAt, updatedAt, isDeleted, deletedAt → **adding** `glyph` (String?), `inkIndex` (int?). **Serializers to touch: ctor, `fromDoc` (camel), `copyWith`.** **Deliberately NOT `toMap`/`fromMap`** — they are dead (no production caller; SQLite #50). A one-line code comment on them states glyph/inkIndex are intentionally omitted, so a future reader doesn't "helpfully" re-add a snake_case path that nothing reads.
5. **Data contracts (exact).**
   - Picker type: `typedef GroupStampSelection = ({String? glyph, int? inkIndex});` — **both nullable.**
   - `createGroup`/`stageGroup` signature gains `{String? glyph, int? inkIndex}` (optional, default null).
   - Create `batch.set` map: include `'glyph'` **only when non-null**; include `'inkIndex'` **only when non-null** (never write the derived fallback; keeps `hasOnly` satisfied for default groups).
   - `updateGroupStamp({required String groupId, String? glyph, int? inkIndex})` → update map `{'updatedAt': serverTimestamp(), 'glyph': glyph ?? FieldValue.delete(), 'inkIndex': inkIndex ?? FieldValue.delete()}` (clear == delete).
   - Rules `validGroupCreate.hasOnly` adds exactly `'glyph'`, `'inkIndex'`; `validCreatorMetadataUpdate.affectedKeys().hasOnly` adds the same two.
   - `GroupGlyph({String? glyph, int? inkIndex, required String name, double size = 40})`.
6. **Arithmetic / bounds.** Only computation is the fallback `inkIndex = _hash(name) % 6`. `_hash` returns `h & 0xffffffff` (≥ 0, verified), so `% 6 ∈ [0,5]`, matching the rule bound `inkIndex >= 0 && inkIndex <= 5`. **The derived fallback is RENDER-ONLY and is NEVER persisted** — only an explicit picker `inkIndex` is written. Reuse `_hash`; don't re-derive. No aggregate to decompose. `BalanceCalculator`/`MoneySerializer` untouched (Group is not a balance-oracle input — `group_model.dart:46-50`).
7. **Adversarial pass (orthogonal axes).** Fix is on the *schema/display* axis; adversarial tests target **security** — forged `glyph:'pwned'` / `glyph:5` and `inkIndex:6 / -1 / '3'` must be rules-DENIED on both create and update; **explicit `glyph:null` must be DENIED** (unsupported — clearing uses `FieldValue.delete()`, whose post-state has the key absent → passes via `!('glyph' in data)`) — and **identity** — a non-creator updating a group's `glyph` must be DENIED by `validCreatorMetadataUpdate`'s `isCreator()`. All in the rules table test.

---

## Phase 1 — Model fields + render foundation (no new write; shippable restyle)

### Task 1: `Group.glyph` + `Group.inkIndex` model fields

**Files:**
- Modify: `lib/features/groups/models/group_model.dart`
- Test: `test/unit/group_model_test.dart` (extend; mirror its style)

**Step 1: Write failing tests** (the LIVE read path is `fromDoc`; `copyWith` for the picker/edit flows. **Do NOT add `toMap`/`fromMap` round-trip tests — those methods are dead per #50**). NOTE: the existing file has **no `fakeDoc` helper** — the live `fromDoc` test (`group_model_test.dart:186`) builds the snapshot via `FakeFirebaseFirestore()` → `ref.set({...})` → `await ref.get()` (async). Either follow that async pattern or add a tiny `fakeDoc` helper; the `fakeDoc({...})` shorthand below is illustrative:

```dart
group('Group glyph/inkIndex serialization', () {
  test('fromDoc reads valid glyph + inkIndex (camelCase)', () {
    final g = Group.fromDoc(fakeDoc({'name': 'Trip', 'glyph': 'tent', 'inkIndex': 3, ...base}));
    expect(g.glyph, 'tent');
    expect(g.inkIndex, 3);
  });
  test('fromDoc absent fields → null (legacy group)', () {
    final g = Group.fromDoc(fakeDoc({'name': 'Trip', ...base}));
    expect(g.glyph, isNull);
    expect(g.inkIndex, isNull);
  });
  test('fromDoc salvages wrong types → null (total-parse #532)', () {
    final g = Group.fromDoc(fakeDoc({'name': 'Trip', 'glyph': 42, 'inkIndex': 'x', ...base}));
    expect(g.glyph, isNull);
    expect(g.inkIndex, isNull);
  });
  test('copyWith updates both', () {
    final g = baseGroup.copyWith(glyph: 'palm', inkIndex: 1);
    expect(g.glyph, 'palm');
    expect(g.inkIndex, 1);
  });
});
```

**Step 2:** Run `flutter test test/unit/group_model_test.dart` → FAIL (no such fields).

**Step 3: Implement.** Add to the class:
```dart
  /// #287/trip-stamps: chosen symbol id (one of the 12 allow-listed ids) or
  /// null → render the name monogram. INBOUND display only.
  final String? glyph;
  /// #287/trip-stamps: chosen ink index 0..5 into the 6-ink palette, or null →
  /// derive a stable ink from the name hash (`_hash(name) % 6`). INBOUND only;
  /// the derived fallback is never persisted.
  final int? inkIndex;
```
Add `this.glyph` / `this.inkIndex` to the const ctor. In `fromDoc` (camelCase total-parse, mirror existing salvage lines):
```dart
      glyph: data['glyph'] is String ? data['glyph'] as String : null,
      inkIndex: data['inkIndex'] is int ? data['inkIndex'] as int : null,
```
In `copyWith`: add both params + `glyph: glyph ?? this.glyph` / `inkIndex: inkIndex ?? this.inkIndex`. Leave `==`/`hashCode` id-only. **`toMap`/`fromMap`: do NOT add the fields** — instead add a one-line comment (`// trip-stamps glyph/inkIndex intentionally omitted: dead SQLite path (#50), groups (de)serialize via fromDoc + the inline create map`) so the omission reads as deliberate, not forgotten.

**Step 4:** Run the test → PASS.
**Step 5:** Commit `feat(groups): add Group.glyph + inkIndex model fields (trip-stamps)`.

### Task 2: Add `flutter_svg` + bundle the 12 glyph assets

**Files:**
- Modify: `pubspec.yaml` (dep + assets dir)
- Create: `assets/glyphs/{tent,mountain,palm,sun,wave,compass,anchor,house,dining,coffee,gift,camera}.svg`

**Steps:** Run `flutter pub add flutter_svg` (let it resolve), then **pin the exact resolved version** in `pubspec.yaml` (not a caret). Add `assets/glyphs/` to `flutter: assets:`. Author each SVG by lifting the matching `<g id="g-<id>">` path data from `docs/design/mockups/claude-design-trip-stamps.html` into a standalone 24×24 SVG (header as in the allow-list section). Run `flutter pub get`. If resolve fails on the toolchain → STOP, it's a blocker. Commit `chore(groups): bundle trip-stamp glyph SVG assets + flutter_svg`.

### Task 3: `GroupStampIcon` — render one glyph id in an ink colour

**Files:**
- Create: `lib/features/groups/widgets/group_stamp_icon.dart`
- Test: `test/features/groups/widgets/group_stamp_icon_test.dart`

**Behaviour:** `GroupStampIcon({required String glyph, required Color ink, double size})` → `SvgPicture.asset('assets/glyphs/$glyph.svg', colorFilter: ColorFilter.mode(ink, BlendMode.srcIn), width: size, height: size)`. Unknown id → `const SizedBox.shrink()` (caller `GroupGlyph` already gates with `_isKnownGlyph` and degrades to the monogram; defence-in-depth). Test: a known id builds an `SvgPicture`; asserts the asset key. **Test helper:** these widgets read `context.colors`, so wrap in a themed `MaterialApp` — write a small local `pumpStamp(tester, widget)` that does `tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, localizationsDelegates: …, home: Scaffold(body: Center(child: widget))))` (the wrapper pattern at `create_join_group_test.dart:178`), NOT the full app-boot helper.

Commit `feat(groups): GroupStampIcon renders a glyph asset in ink`.

### Task 4: Rewrite `GroupGlyph` to the trip-stamp tile

**Files:**
- Modify: `lib/features/home/widgets/group_glyph.dart`
- Modify callsites: `lib/features/home/screens/home_screen.dart:682`, `lib/features/groups/widgets/group_info_section.dart:122`
- Test: `test/features/home/widgets/group_glyph_test.dart` (create; uses the `pumpStamp` helper from Task 3)

**Step 1: Failing tests** (the zero-regression contract lives here — assert resolved **index**, never colour-equality against the old palette):

```dart
testWidgets('symbol present → renders GroupStampIcon', (t) async {
  await pumpStamp(t, const GroupGlyph(name: 'Salalah', glyph: 'tent', inkIndex: 1));
  expect(find.byType(GroupStampIcon), findsOneWidget);
});
testWidgets('glyph null → monogram first char, no icon', (t) async {
  await pumpStamp(t, const GroupGlyph(name: 'salalah', inkIndex: 4));
  expect(find.text('S'), findsOneWidget);
  expect(find.byType(GroupStampIcon), findsNothing);
});
testWidgets('unknown/forged glyph id → degrades to monogram, not blank', (t) async {
  await pumpStamp(t, const GroupGlyph(name: 'Doha', glyph: 'pwned', inkIndex: 0));
  expect(find.text('D'), findsOneWidget);
  expect(find.byType(GroupStampIcon), findsNothing);
});
testWidgets('empty name + null glyph → "·" fallback, renders, no crash', (t) async {
  await pumpStamp(t, const GroupGlyph(name: ''));      // both null
  expect(find.text('·'), findsOneWidget);
});
// PURE-FUNCTION assertion on the static seam — plain `test`, NOT `testWidgets`:
test('inkIndex null (legacy) → resolved index == _hash(name) % 6 (stable, derived)', () {
  expect(GroupGlyph.debugResolvedInkIndex('Muscat', null), GroupGlyph.debugHash('Muscat') % 6);
  expect(GroupGlyph.debugResolvedInkIndex('Muscat', null),
         GroupGlyph.debugResolvedInkIndex('Muscat', null));   // deterministic
});
```

**Step 2:** Run → FAIL (current `GroupGlyph` has no glyph/inkIndex params).

**Step 3: Implement.** New signature `GroupGlyph({super.key, required this.name, this.glyph, this.inkIndex, this.size = 40})`. Build:
```dart
final inks = [colors.cat1, colors.cat2, colors.cat3, colors.cat4, colors.cat5, colors.cat6];
final idx = inkIndex ?? (_hash(name) % inks.length);     // render-only fallback; never persisted
final ink = inks[idx];
final bg = Color.alphaBlend(ink.withValues(alpha: 0.13), colors.scaffoldBackground);
// Container: width/height size, radius size*0.30, color bg,
//   border: Border.all(color: ink.withValues(alpha: 0.28)), alignment center
// child: (glyph != null && _isKnownGlyph(glyph!))
//   ? GroupStampIcon(glyph: glyph!, ink: ink, size: size * 0.56)
//   : Text(monogram, AppTypography.display(fontSize: size * 0.56, color: ink, height: 1.0))
```
Keep `_hash` (static) and the empty-name `'·'` monogram logic. Expose `@visibleForTesting static int debugResolvedInkIndex(String name, int? inkIndex)` + `@visibleForTesting static int debugHash(String name)`. Expose `const kGroupGlyphIds` (the 12 ids) + `bool _isKnownGlyph(String)`.

**Step 4:** Update the 2 callsites to pass `glyph: group.glyph, inkIndex: group.inkIndex` (both already hold the `Group`; preserve `home_screen.dart`'s default size and `group_info_section.dart`'s `size: 44`). Run `flutter test` + the 2 callsite screens' tests → PASS. `flutter analyze` clean.

**Step 5:** Commit `feat(groups): GroupGlyph renders trip-stamp tile (symbol|monogram + ink)`.

> **Phase 1 ships independently:** every group (incl. legacy) now wears the new stamp tile with a stable per-group ink index (colour rebased once); monograms preserved. No write/rules change yet.

---

## Phase 2 — Persist on create (rules + write + picker)  ← Gate-critical; SPLIT into two PRs

### Task 5: Rules — allow + validate `glyph`/`inkIndex` on create & creator-edit  *(PR-2a, deploy-gated)*

**Files:**
- Modify: `security/firestore.rules`
- Test: `functions/test/firestore-rules-publish-readiness.test.ts`

**Step 1: Failing rules tests** (table-driven clean/warn/error — security-critical). **Add `import { FieldValue } from 'firebase/firestore'`** (the suite doesn't import it yet; precedent: `balanceReconciler.test.ts`). **Use `new Date()` for `updatedAt`** (the suite's existing convention at `:261-262`/`:288-289`; satisfies `updatedAt is timestamp` — using the wrong JS type gives a false-RED on the timestamp guard, not the logic under test):

| case | write | expect |
|------|-------|--------|
| valid | create with `glyph:'tent', inkIndex:3` | ALLOW |
| optional | create WITHOUT glyph/inkIndex | ALLOW |
| monogram | create with `inkIndex:0`, no glyph | ALLOW |
| forged glyph | create with `glyph:'pwned'` | DENY |
| glyph type | create with `glyph: 5` | DENY |
| explicit null glyph | create with `glyph: null` | DENY (unsupported — omit/delete) |
| ink high | create with `inkIndex: 6` | DENY |
| ink low | create with `inkIndex: -1` | DENY |
| ink type | create with `inkIndex: '3'` | DENY |
| creator edit | creator updates `glyph:'wave', inkIndex:2, updatedAt` | ALLOW |
| creator clear glyph | creator updates `glyph: FieldValue.delete(), updatedAt` | ALLOW |
| creator clear ink | creator updates `inkIndex: FieldValue.delete(), updatedAt` | ALLOW |
| non-creator edit | member (≠creator) updates `glyph` | DENY |
| forged edit | creator updates `glyph:'x'` | DENY |

Run scoped (CLAUDE.md trap — the runner ignores args; pass the env var): `RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand firestore-rules-publish-readiness.test.ts" npm run test:emulator` → new cases FAIL.

**Step 2: Implement.** Add helpers near `validCurrency` (`firestore.rules:75`):
```
function validGlyph(value) {
  return value is string && value in [
    'tent','mountain','palm','sun','wave','compass',
    'anchor','house','dining','coffee','gift','camera'
  ];
}
function validInkIndex(value) {
  return value is int && value >= 0 && value <= 5;
}
```
In `validGroupCreate` (`:251`): add `'glyph'`, `'inkIndex'` to the `hasOnly([...])` list, and append:
```
  && (!('glyph' in request.resource.data) || validGlyph(request.resource.data.glyph))
  && (!('inkIndex' in request.resource.data) || validInkIndex(request.resource.data.inkIndex))
```
In `validCreatorMetadataUpdate` (`:282`): extend `affectedKeys().hasOnly(['name','updatedAt'])` → `hasOnly(['name','updatedAt','glyph','inkIndex'])`, and append the **same two** `!('…' in …) || valid…` guards (creator-only already enforced by `isCreator()`; `name` stays optional via the existing `hasAny`). Keep the guards **strict** (explicit null rejected) — clearing flows through `FieldValue.delete()`, whose post-state has the key absent → passes via `!('…' in …)`. Leave `allow create/update` wiring (`:319-321`) unchanged. The member OR-branch `validMemberIdsRefresh()` keeps its own `hasOnly(['memberIds','updatedAt'])` → no privilege bleed.

**Step 3:** Run the scoped rules suite → PASS. **Emulator-verify (CLAUDE.md: rules membership semantics are emulator-truth, not doc-specified) that a creator `FieldValue.delete()` write leaves the key ABSENT in `request.resource.data` so the strict guard passes** — the "creator clear" rows. Run the FULL readiness suite → green.
**Step 4:** Commit `feat(rules): allow-list + bound group glyph/inkIndex on create & creator-edit`.

> **Deploy note:** `firestore.rules` change → PR-2a is its own deploy-gated PR. After merge run the **deploy-ceremony** skill (`tool/pending_deploy.sh`). No client-compat gating (no real users — CLAUDE.md).

### Task 6: Thread `glyph`/`inkIndex` through the create write path  *(PR-2b, client-only)*

**Files:**
- Modify: `lib/features/groups/providers/group_provider.dart` (`createGroup` :150, `stageGroup` :177, batch map :208, local Group :252)
- Test: `test/features/groups/providers/` (extend create coverage)

**Steps (TDD):** Add `String? glyph, int? inkIndex` params to `createGroup` + `stageGroup`. In the batch.set map (`:208`) add — *conditionally, never the derived fallback*:
```dart
      if (glyph != null) 'glyph': glyph,
      if (inkIndex != null) 'inkIndex': inkIndex,
```
In the local `Group(...)` build (`:252`) pass `glyph: glyph, inkIndex: inkIndex` so the pre-snapshot tile matches the persisted doc. Test: stageGroup with glyph+inkIndex writes both keys (FakeFirebaseFirestore) and the returned `Group` carries them; omitting them writes **neither** key (assert `!doc.data().containsKey('inkIndex')`). Commit `feat(groups): persist chosen glyph/inkIndex on group create`.

### Task 7: `GroupStampPicker` widget (hero + ink row + symbol grid)  *(PR-2b)*

**Files:**
- Create: `lib/features/groups/widgets/group_stamp_picker.dart`
- Test: `test/features/groups/widgets/group_stamp_picker_test.dart`

**Contract:** `GroupStampPicker({required String name, required GroupStampSelection value, required ValueChanged<GroupStampSelection> onChanged})` where `typedef GroupStampSelection = ({String? glyph, int? inkIndex});`. Renders:
- a live hero `GroupGlyph`(size ~80) reflecting `value` (hero derives `value.inkIndex ?? _hash(name)%6` → **auto-tracks the live name while ink is unpicked**);
- an **Ink** row of 6 swatches — the selected swatch (when `value.inkIndex != null`) carries a saffron ring; **when `inkIndex == null` NO swatch is ringed** (nothing explicitly chosen — the hero still shows the derived colour, honest WYSIWYG);
- a **Symbol** grid — monogram cell first (ringed when `glyph==null`), then the 12 `GroupStampIcon`s (selected = saffron ring + tint).

Tapping a symbol emits `(glyph: id, inkIndex: value.inkIndex)`; tapping the monogram cell emits `(glyph: null, …)`; tapping an ink emits `(…, inkIndex: n)` (a real non-null index — the explicit pick that persists). All emits are immutable copies.

Tests: tapping a symbol → `onChanged` fires with that glyph (inkIndex unchanged); tapping the monogram cell → `glyph:null`; tapping an ink → non-null inkIndex; with `inkIndex:null` no swatch is ringed but the hero still renders; **`name:''` + `inkIndex:null` → hero renders (`·`, cat1) without crash**; selected ring follows state. Commit `feat(groups): GroupStampPicker (ink + symbol selection)`.

### Task 8: Wire the picker into Create-Group; delete the fake `_GlyphRow`  *(PR-2b)*

**Files:**
- Modify: `lib/features/groups/screens/create_group_screen.dart` (remove `_GlyphRow` :528-577 + its `const _GlyphRow()` use :355; add picker state; thread into `_createGroup`)
- Modify: `lib/l10n/app_en.arb` + `lib/l10n/app_ar.arb` (then regen)
- Test: `test/features/groups/create_join_group_test.dart` (replace the broken assertions) + create-flow coverage

**Steps:** Add state — **`String? _selectedGlyph;` and `int? _selectedInkIndex;` (both start null = defaulted; the hero auto-tracks the name via the `?? _hash(name)%6` fallback, so NO manual "recompute on name change" code is needed)**. Replace `const _GlyphRow()` (:355) with `GroupStampPicker(name: _nameController.text, value: (glyph: _selectedGlyph, inkIndex: _selectedInkIndex), onChanged: (sel) => setState(() { _selectedGlyph = sel.glyph; _selectedInkIndex = sel.inkIndex; }))`. In `_createGroup`, pass `glyph: _selectedGlyph, inkIndex: _selectedInkIndex` into `createGroup(...)`/`stageGroup(...)` (both nullable → unpicked stays null → key omitted → render derives). **Delete** `_GlyphRow` (:528) and `_GlyphColor`.

ARB: keep key `groupGlyph`, set value **"Stamp"**; add `groupStampInk` "Ink", `groupStampSymbol` "Symbol", `groupStampMonogramHint` "Your initial is the default" (+ `app_ar.arb` counterparts — **every new key in BOTH locales or l10n gen fails**). **Run the l10n codegen (`flutter gen-l10n`, or a build) after ARB edits** so `context.l10n.groupStampInk` etc. exist before referencing them.

**Replace the broken tests (CLAUDE.md — delete obsolete assertions, don't patch):** `create_join_group_test.dart:117-119` (`'Group glyph'`, `'⛺'`, `'⌂'`) → assert `find.byType(GroupStampPicker)` (+ the "Stamp" label if asserted). Grep the whole suite for any other `_GlyphRow` / `'Group glyph'` / `⛺` / `⌂` literal.

**Test (RED→GREEN):** a create-screen widget test that selects an ink + a symbol and asserts the (overridden) group provider's `createGroup` is called with `glyph:'…', inkIndex:n`; and a second that creates WITHOUT touching the picker and asserts `glyph:null, inkIndex:null` reach the provider. Commit `feat(groups): real trip-stamp picker on Create-Group (removes the dead glyph row) — closes #287`.

---

## Phase 3 — Edit an existing group's stamp (creator-only)  *(follow-up PR)*

### Task 9: Edit entry + `updateGroupStamp`

**Files:**
- Modify: `lib/features/groups/providers/group_provider.dart` (new `updateGroupStamp({required String groupId, String? glyph, int? inkIndex})` → `.update({'updatedAt': FieldValue.serverTimestamp(), 'glyph': glyph ?? FieldValue.delete(), 'inkIndex': inkIndex ?? FieldValue.delete()})`; mirror the existing metadata-update method ~:418-427)
- Modify: `lib/features/groups/widgets/group_info_section.dart` — **reuse the existing creator-only edit affordance already at `:122`** (the `widget.isCreator` pencil badge stacked on the `GroupGlyph`); have it open the `GroupStampPicker` in a `showModalBottomSheet`, seeded from the current `group.glyph`/`group.inkIndex`. No new route.
- Test: provider test + a widget test (creator sees the affordance; non-creator does not)

**Clear semantics (resolves G1 — `FieldValue.delete()`, NOT explicit null):** to reset a symbol back to monogram (or ink to derived), the picker emits `null` for that field and `updateGroupStamp` writes `FieldValue.delete()`. The post-write doc has the key **absent** — byte-identical to a never-set group — so `!('glyph' in request.resource.data)` is true and the strict rules guard passes. **We never write explicit `null`.** The provider test asserts clearing writes a delete sentinel (and the Task 5 emulator test proves the resulting absent-key write is ALLOWED for the creator).

Commit `feat(groups): creator can edit a group's trip stamp`.

---

## Open questions / Gate targets (status after 2 rounds)

- **G1 (rules/null-clear) — RESOLVED by design.** Clearing uses `FieldValue.delete()` (post-state key absent → passes the strict guard); we never depend on explicit-null membership. Task 5 emulator test PROVES the delete-write is ALLOWED and explicit `glyph:null` is DENIED. `FieldValue.delete()` is supported in the rules-test harness (precedent: `balanceReconciler.test.ts`).
- **G2 (write-map optionality) — CONFIRMED.** `if (glyph != null) 'glyph': glyph` keeps the key absent for default groups; Task 6 test asserts it.
- **G3 (callsite completeness) — CONFIRMED.** Only 2 `GroupGlyph(` callsites; both updated in Task 4.
- **G4 (flavour creep).** Passport (B) hero is OUT of this plan; if it sneaks into the picker hero it's scope creep.
- **G5 (RTL monogram) — known limitation, OUT of scope.** `GroupGlyph` renders the monogram in `AppTypography.display` (Latin Instrument Serif) regardless of script; pre-existing, not a regression. `arabicDisplay` exists (`typography_tokens.dart:71`) for a later script-aware follow-up.
- **G6 (toMap/fromMap) — RESOLVED.** Dead SQLite-era methods (no production caller; #50); fields added only to ctor/fromDoc/copyWith; a code comment marks the deliberate omission.

## Execution / branch & PR note

Author/execute on a fresh feature branch off `main`. **One concern per PR:**
- **PR-1** — Phase 1 (model fields + flutter_svg + GroupStampIcon + GroupGlyph rewrite + restyle). Client-only, no deploy.
- **PR-2a** — Task 5 only (rules + rules-tests). Gate-category, **deploy-gated** (deploy-ceremony after merge). Kept separate so the deploy state isn't entangled with the client diff.
- **PR-2b** — Tasks 6–8 (provider write + picker + Create-Group rewire + l10n). Client-only, no deploy. Depends on PR-2a's rules being live (or merged) so writes aren't rejected.
- **PR-3** — Phase 3 (creator edit). Client-only.

**Gate status:** run twice (round 1 → 5 P1s applied; round 2 → 3 P1s applied, all spec-accuracy). Re-run **run-the-gate** with a fresh subagent; stop when the verdict has no [P1]s.

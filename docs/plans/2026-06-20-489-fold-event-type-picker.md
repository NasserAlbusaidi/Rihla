# #489 — Fold the event type-picker into CreateEventScreen (3 screens → 2)

**Date:** 2026-06-20 · **Issue:** #489 (enhancement, P3, design; milestone 1.6.0)
**Owner decision (2026-06-19):** Build in 1.6.0. Fold the type picker into a chip row at the top of `CreateEventScreen` per mockup §A5. Keep `/create-event/:type` resolving cold. **Routing change → fresh-context Gate.**
**Design sign-off (2026-06-20):** Direction approved via claude.ai/design canvas doc *"CreateEventScreen — Fold the type picker (#489)"* (Rihla Design System `791a90a9…`, "Screens"). **4 chips — Custom dropped from creation.**
**Gate: PASSED.** Round 1 (4 Opus reviewers + refuter) → 5 P1 (all spec-completeness, folded in). Round 2 → **0 upheld P1** (1 found, refuted) + P2/P3 build-hygiene, all folded in below. Approach (fold / 4 chips / coercion / both routes) unchallenged both rounds.

## Current flow (verified on `e6978d64`)
- Route `create-event` → `EventTypePickerScreen(groupId)` — grid of 5 type cards + "Continue with Trip" → `context.push('…/create-event/<type>')` (`event_type_picker_screen.dart:88-90`).
- Route `create-event/:type` → `CreateEventScreen(groupId, eventType: EventType.fromString(:type ?? 'custom'))` (`app_router.dart:296-308`). Both routes: `pageBuilder`+`CustomTransitionPage`+`_sharedAxisTransition`.
- **Live nav callers (verified):** exactly 2, both push the **bare** `/group/:gid/create-event` (`group_detail_screen.dart:215, :299`). The ONLY emitter of typed `/create-event/:type` is the picker itself (`event_type_picker_screen.dart:89`) — deleted here. ⇒ **After the fold, no in-app caller emits `:type`; only an external deep link / typo can.**
- `widget.eventType` is read in **5 places**: initState :76 (`_modules`); submit :148 (`type:`) + :155 (`modules: …==custom?…:null`); build :247 (`final typeConfig = EventTypeConfig.forType(widget.eventType)`) + :258 (`ModuleHeader(title: …localizedLabel)`). The badge at :293 (`EventTypeBadge(typeConfig: typeConfig)`) consumes the **:247 local**, not `widget.eventType` — so it pairs with the :247 deletion below.
- **`EventModules.forType(type)` ALWAYS returns `const EventModules(ledger: true)`** (`event_model.dart:52-53`, vestigial since Phase 39 / #246). **No module-editing UI exists.** So `_modules` is inert; the type only drives label/icon + the persisted `type` enum.

## Target
1. **`EventTypeConfig`** — add `static List<EventTypeConfig> get selectableTypes => allTypes.where((c) => c.type != EventType.custom).toList();` (4 creatable types, order: trip, camping, travel, nightDayOut). **`allTypes` (5) retained** because `selectableTypes` derives from it; existing-event config rendering (incl. Custom) uses `EventTypeConfig.forType(...)`, not `allTypes` — so dropping Custom from creation does **not** hide existing Custom events (`forType` keeps all 5; `EventType.fromString` still maps `'custom'`).
2. **`CreateEventScreen`** — rename ctor param `eventType` → `initialEventType`. Add `late EventType _selectedType`. initState (order matters): `_selectedType = (widget.initialEventType == EventType.custom) ? EventType.trip : widget.initialEventType;` then `_modules = EventModules.forType(_selectedType);` — **coerces the only non-selectable value to the default** so a cold `/create-event/custom` (or unknown `:type` → `fromString`=custom) always lands on a valid selected chip.
   - **Reads:** of the 5 `widget.eventType` reads, **4 map to `_selectedType`** (:76, :148, :155, :258). The **5th (:247 `typeConfig` local) is DELETED** together with the badge (its sole consumer) — not renamed. Submit: `type: _selectedType`, `modules: _selectedType == EventType.custom ? _modules : null` (the conditional never fires now — kept defensively; `null` == every preset type's existing behavior).
   - **`_TypeChipRow`** (new, feature-local — **there is no shared/Flutter `Chip` widget**; the DS `Chip` is a *web-mirror* component only, so hand-build): horizontal **scrollable** `SingleChildScrollView(scrollDirection: Axis.horizontal)` (overflow guard — see Landmines) over `EventTypeConfig.selectableTypes`. Each chip:
     - `Container` decoration — **selected** (`config.type == _selectedType`): fill `context.colors.saffronTint` (#FBEED5, "selected chip backgrounds"), border `context.colors.primary` (saffron); **unselected**: fill `context.colors.cardSurface`, border `context.colors.border`.
     - content: `Icon(config.icon, …)` (the app's Iconsax glyph; color `config.resolveColor(context.colors)` or `textPrimary`) + `Text(config.type.localizedLabel(context.l10n))` — the `localizedLabel` extension `EventTypeDisplay` is on **`EventType`** (`event_display.dart:4`), already imported (`create_event_screen.dart:27`).
     - `key: EventKeys.eventTypeCard(config.label)` (kept). Wrap in `Semantics(selected: config.type == _selectedType, button: true)` so tests assert selection via the flag (mirrors the picker `_TypeCard` :221-226). Note `eventTypeCard('Night/Day Out')` → `Key('event_type_card_night/day_out')` (slash retained — benign; the picker was the only other caller, deleted).
     - `onTap: () { HapticService.selection(); setState(() { _selectedType = t; _modules = EventModules.forType(t); }); }`.
   - **Badge removal:** delete the `EventTypeBadge` import (`create_event_screen.dart:30`) and the `[EventTypeBadge]` doc-comment line (:35); replace the badge in the `Form` column (build :293 + its animate slot) with `_TypeChipRow`, keeping the existing `if (disableAnimations) chipRow else chipRow.animate().fadeIn(delay:60.ms).slideY(begin:0.05)` ternary (the chip-row is non-const — fine). `EventTypeConfig` import stays (needed for `selectableTypes`/`forType`).
   - **Header:** `ModuleHeader(useDarkTheme: true, title: context.l10n.eventNew, subtitle: ref.watch(groupDetailProvider(widget.groupId)).valueOrNull?.name)`. `group_provider.dart` is **already imported** (:22, used at :249) — no new import. `groupDetailProvider` is `StreamProvider.family<Group?, String>` (:614); `valueOrNull?.name` is null while loading/error/missing → `ModuleHeader` renders no subtitle (`if (subtitle != null)`). `eventNew` ("New event") already exists.
3. **Router (`app_router.dart`)** — both routes build `CreateEventScreen`:
   - `create-event` → `CreateEventScreen(groupId, initialEventType: EventType.trip)`.
   - `create-event/:type` → `CreateEventScreen(groupId, initialEventType: EventType.fromString(state.pathParameters['type'] ?? 'custom'))`.
   - Both paths build the same screen; cold deep links resolve (no `state.extra`; path strings; no `goNamed`). **Delete the `EventTypePickerScreen` import (:10)** and replace the instantiation (:288).
4. **Nav callers** — unchanged (both already push the bare `create-event`).

## Deletes (grep-confirmed)
- `lib/features/events/screens/event_type_picker_screen.dart` (whole file; referenced by `app_router.dart:10` import + :288 + `create_event_test.dart:19`).
- `lib/features/events/widgets/event_type_badge.dart` (**now dead** — only `CreateEventScreen` used it; no test refs).
- `EventKeys.eventTypePickerScreen`, `EventKeys.eventTypePickerTitle` (picker-only). **KEEP `eventTypeCard(label)`** (chip keys).
- l10n in **both** ARBs: `eventPickerTitle` (en :1435 / ar :557), `eventPickerSubtitle` (en :1436 / ar :558), `eventContinueWith` (en :1437 / ar :559) **+ the `@eventContinueWith` block (en :1438-1442; ar has none)**. **KEEP `eventNew`.** Then **run `flutter gen-l10n`** to regenerate committed `lib/l10n/generated/app_localizations*.dart` (the 3 getters live there — grep is not zero until regen; `generate: true`, `output-dir: lib/l10n/generated`, `nullable-getter: false`).
- Docs: drop `event_type_picker_screen.dart` (`lib/features/events/README.md:18`) and `event_type_badge.dart` (`README.md:22`).

## Callsite classification
- **INBOUND** (routing/nav/display): both routes, both nav callers, header title/subtitle, chip-row.
- **OUTBOUND** (write): event creation. Same value space (`EventType`), same `stageEvent`; choice now via `_selectedType`. `_modules` inert; `modules:` → `null` for every selectable type (== today's preset behavior).

## Tests (RED first for chip behavior)
**`test/features/events/create_event_test.dart` — full surgery** (imports the picker at :19 → deleting it breaks whole-file compilation; 12 `eventType:` callsites):
1. Drop `import '…/event_type_picker_screen.dart';` (:19).
2. **Delete the entire `group('EventTypePickerScreen', …)` block (:247-354)** — 4 tests (:248, :264, :273, :288-353) — and the dead `_wrapPicker` helper (:84-94). (Also removes the lone `EventType.fromString` callsite :310.)
3. **Rename every remaining `CreateEventScreen(eventType:` → `initialEventType:`** — 11 callsites after the block delete (:131, :211, :368, :397, :417, :433, :457, :474, :490, :523, :553). Note `_wrapCreateRouted` (:117) hardcodes `initialEventType: EventType.trip` in its builder — fine for routed tests; the coercion test (5d) builds the screen directly with `initialEventType: EventType.custom`.
4. **Retarget the 2 badge-era tests:** 'shows event type badge with type label' (:390-408, builds Camping, asserts `find.text('Camping')`) → the Camping chip renders 'Camping' **exactly once**, so tighten to `findsOneWidget` and add `expect(find.text(<eventNew>), findsOneWidget)` for the header. 'does NOT show module toggles for non-Custom types' (:410-426) → still true (no module toggles ever); keep/relabel.
5. **Add chip tests** in `group('CreateEventScreen', …)` — RED first:
   - (a) default: built with `initialEventType: trip` → Trip chip selected (Semantics `selected:true` / saffron decoration), Custom chip absent (4 chips).
   - (b) selection: tap `eventTypeCard('Camping')` → Camping selected, Trip not.
   - (c) submit: re-stub `stageEvent` to expect `type: EventType.camping`; tap Camping, submit → `stageEvent` called with `type == camping`.
   - (d) **coercion (OUTBOUND assertion — the only thing distinguishing coerced-Trip from default-Trip, since there is no Custom chip):** build with `initialEventType: EventType.custom`, submit → `stageEvent` called with `type == EventType.trip`.

**`test/unit/app_router_test.dart` — NO picker edit.** Match-only (`findMatch(path).isError`); no `eventTypePickerScreen`-key assertion to remove; both `/create-event` and `/create-event/custom` are already in its resolve list (:100-101) and must stay green. The "builds CreateEventScreen / Trip-selected / coercion" assertions are pump-based → they live in create_event_test.dart (step 5).

**Scrub list — corrected: NO functional change.** `test/helpers/test_router.dart`, `test/helpers/navigation_test.dart`, `group_detail_navigation_test.dart`, `group_detail_events_test.dart` use **stub** routes/Scaffolds, **zero** picker refs — keep their stub `create-event`/`:type` routes. Optional cosmetic: rename a `navigation_test.dart` test description containing "picker". `event_service_test.dart` matches `EventService.createEvent` (service method) — leave. `group_screens_test.dart` asserts `find.text('New event')` = the GroupDetail `eventNew` CTA (retained), not the picker — passes unchanged. **No `event_type_picker_screen_test.dart` exists.**

**`icon_rtl_guard_test.dart`:** unconditionally walks `lib/features` recursively; the picker passes today (uses `DirectionalIcon`), deletion only shrinks the corpus, and `_TypeChipRow` renders non-arrow category glyphs (no new offender) — re-run to confirm green.

**Gate:** `flutter analyze` clean (`prefer_const_constructors`, **no orphaned `typeConfig`/import/unused after the badge delete**); after `flutter gen-l10n`, grep for the 3 l10n keys + 2 EventKeys = **zero** refs in `lib/` + `test/`.

## Routing landmines (CLAUDE.md)
- `/create-event/:type` cold-resolves (parsed type; `fromString` unknown → custom → coerced to trip). No `state.extra`; path strings; no `goNamed`.
- NESTED routes under top-level `/group/:gid`; `canPop()` always true → bare back-pop reaches parent. The chosen `ModuleHeader(useDarkTheme:true)` back button **already** carries `canPop()?pop():go('/home')` (`module_header.dart:144-150`) — **leave it as-is** (the `/home` branch is inert here). Do NOT add a NEW screen-level `PopScope`/fallback (#243 — top-level only).
- Chip row must be horizontally scrollable (`Axis.horizontal`) — a bare `Row` of 4 chips risks RenderFlex on narrow screens / long Arabic labels (`ledger_screen_overflow_test.dart` precedent).

## Out of scope
- #245 (auto-seed default event / skip hub) — paired but separate.
- `AppRoutes.createEvent` / `AppRoutes.createEventTyped` constants (`app_router.dart:33` class; :51-52) are unreferenced (routes use literal path strings) — leave.

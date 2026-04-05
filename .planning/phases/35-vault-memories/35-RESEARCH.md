# Phase 35: Vault & Memories - Research

**Researched:** 2026-04-05
**Domain:** Flutter visual refresh — token compliance and OfflineBanner pattern
**Confidence:** HIGH

## Summary

Both VaultScreen and MemoriesScreen are fully functional production screens. This phase is a narrow visual refresh following the identical pattern applied in Phases 33 (Ledger) and 34 (Gear + Logistics). The work is surgical: two hardcoded `Color(0xFF...)` literals must be replaced with module tokens, and `OfflineBanner` must be inserted into both screens.

ModuleHeader is already present in both screens with `useDarkTheme: true`. SkeletonLoader is already used (`documentList` in Vault, `photoGrid` in Memories) — both are existing named factories in `SkeletonLoader`, so no skeleton upgrade is needed unlike Phase 34's `cardList → gearList` fix. No new packages, no provider changes, no business logic changes.

All module tokens exist: `AppColorTokens.light.moduleVault`, `moduleVaultLight`, `moduleMemories`, `moduleMemoriesLight`. Zero test files exist for these two screens — Wave 0 must create test stubs asserting `OfflineBanner` renders in each screen body, following the exact pattern in `gear_screen_mutations_test.dart`.

**Primary recommendation:** Two-task structure. Plan 00 = write failing OfflineBanner test stubs. Plan 01 = fix hardcoded colors + add OfflineBanner to both screens + turn tests green.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Vault Screen
- Dark ModuleHeader ("Vault" / "Documents" + event name subtitle) — if not already present
- Refresh document cards with earthy color tokens
- SkeletonLoader loading states (replace any CircularProgressIndicator)
- Keep existing upload/view/delete functionality unchanged

#### Memories Screen
- Dark ModuleHeader ("Memories" + event name subtitle) — if not already present
- Refresh photo grid/timeline with earthy tokens
- SkeletonLoader loading states
- Keep existing upload/view functionality unchanged

### Claude's Discretion
- All implementation details — this is a token refresh following the established Phase 28-34 pattern

### Deferred Ideas (OUT OF SCOPE)
None
</user_constraints>

## Standard Stack

No new packages required. All dependencies already in `pubspec.yaml`.

### Core (already installed)
| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| `flutter_animate` | `^4.5.0` | Entrance animations (FadeInList) | Already used — `FadeInList` wraps document cards |
| `shimmer` | `^3.0.0` | SkeletonLoader shimmer effect | Already used in both loading states |
| `iconsax` | `^0.0.8` | Module icons | Already imported in both screens |

**Installation:** None needed.

## Architecture Patterns

### Established Phase 28-34 Pattern (authoritative)

Every module screen uses this Column body structure:

```dart
// Source: lib/features/gear/screens/gear_screen.dart (Phase 34 final state)
body: Column(
  children: [
    ModuleHeader(
      title: 'ModuleName',
      subtitle: event.name.toUpperCase(),
      useDarkTheme: true,
    ),
    const OfflineBanner(),    // immediately after ModuleHeader, before Expanded
    Expanded(child: ...),
  ],
),
```

**Important constraint:** The pre-event loading Scaffold (shown while `eventAsync.isLoading` is true) does NOT get OfflineBanner — consistent across all prior phases. Only the main loaded Scaffold body gets it.

### EmptyStateView accentGradient — token replacement rule

```dart
// Source: Phase 34 fix pattern
// Before (hardcoded — CI blocks this):
accentGradient: const LinearGradient(
  colors: [Color(0xFF8B7355), Color(0xFFA89372)],
),

// After (token-compliant):
accentGradient: LinearGradient(
  colors: [AppColorTokens.light.moduleVault, AppColorTokens.light.moduleVaultLight],
),
// Remove `const` from LinearGradient (non-const). Also remove `const` from
// enclosing EmptyStateView if present — it is no longer const-constructable.
```

### Token mapping for this phase

| Hardcoded | Token | Hex (for verification) |
|-----------|-------|------------------------|
| `Color(0xFF8B7355)` (VaultScreen) | `AppColorTokens.light.moduleVault` | `#6B7280` |
| `Color(0xFFA89372)` (VaultScreen) | `AppColorTokens.light.moduleVaultLight` | `#F3F4F6` |
| `Color(0xFF9B7A5C)` (MemoriesScreen) | `AppColorTokens.light.moduleMemories` | `#6B7280` |
| `Color(0xFFB89878)` (MemoriesScreen) | `AppColorTokens.light.moduleMemoriesLight` | `#F3F4F6` |

### OfflineBanner import

```dart
import '../../../shared/widgets/offline_banner.dart';
```

Both screens are at `lib/features/{vault,memories}/screens/` — the relative path to `lib/shared/widgets/` is `../../../shared/widgets/offline_banner.dart`.

### SkeletonLoader — no changes needed

VaultScreen already uses `SkeletonLoader.documentList()`. MemoriesScreen already uses `SkeletonLoader.photoGrid()`. Both are correct named factories. No upgrade needed (this differs from Phase 34 where `cardList → gearList` was required).

### ModuleHeader — already present

Both screens already have `ModuleHeader` with `useDarkTheme: true` and correct subtitle. No changes needed.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Offline indicator | Custom banner widget | `OfflineBanner` from `lib/shared/widgets/` | Already exists, watches `connectivityProvider` internally, zero-size when online |
| Loading skeleton | Custom shimmer layout | `SkeletonLoader.documentList()` / `SkeletonLoader.photoGrid()` | Already correct factories |
| Color tokens | Inline Color(0xFF...) literals | `AppColorTokens.light.moduleVault` etc. | CI blocks hardcoded literals |

## Current State Audit (HIGH confidence — direct code inspection)

### VaultScreen (`lib/features/vault/screens/vault_screen.dart`)

| Check | Status | Detail |
|-------|--------|--------|
| ModuleHeader present | PASS | `ModuleHeader(title: 'Vault', useDarkTheme: true)` — line 57, 99, 119 |
| OfflineBanner | MISSING | Not imported, not rendered anywhere |
| SkeletonLoader | PASS | `SkeletonLoader.documentList()` — correct factory |
| Hardcoded colors | 1 VIOLATION | Line 190: `colors: [Color(0xFF8B7355), Color(0xFFA89372)]` in `EmptyStateView.accentGradient` |
| AppColorTokens imported | PASS | Line 18 |

### MemoriesScreen (`lib/features/memories/screens/memories_screen.dart`)

| Check | Status | Detail |
|-------|--------|--------|
| ModuleHeader present | PASS | `ModuleHeader(title: 'Memories', useDarkTheme: true)` — lines 196–200, 238–243, 271–276 |
| OfflineBanner | MISSING | Not imported, not rendered anywhere |
| SkeletonLoader | PASS | `SkeletonLoader.photoGrid()` — correct factory (lines 200, 245) |
| Hardcoded colors | 1 VIOLATION | Line 297: `colors: [Color(0xFF9B7A5C), Color(0xFFB89878)]` in `EmptyStateView.accentGradient` |
| AppColorTokens imported | PASS | Line 17 |

### Existing Tests

| Screen | Test File | Exists |
|--------|-----------|--------|
| VaultScreen | `test/features/vault_screen_*` | NO — none exist |
| MemoriesScreen | `test/features/memories_screen_*` | NO — none exist |
| MemoryService | `test/unit/memory_service_test.dart` | YES — 7 unit tests, service-layer only |
| DocumentService | `test/unit/document_*` | NO |

Zero widget tests exist for either screen. Wave 0 plan must create test stubs.

### MemoriesScreen — OfflineBanner placement note

MemoriesScreen uses `memoriesAsync.when(...)` directly as the `Scaffold.body` (not a Column wrapper), unlike VaultScreen which uses `Column(children: [ModuleHeader, Expanded(...)])`. The `data:` branch renders a `CustomScrollView` with `ModuleHeader` as the first `SliverToBoxAdapter`.

OfflineBanner must be added consistently to the data branch's top-level Column. The cleanest approach: wrap the data branch in a `Column` adding OfflineBanner after ModuleHeader, mirroring the VaultScreen and GearScreen pattern. Alternatively, add `OfflineBanner` as the second `SliverToBoxAdapter`. The Column wrap is the established pattern — use that.

For the data branch only:
```dart
data: (memories) => Column(
  children: [
    ModuleHeader(
      title: 'Memories',
      subtitle: event.name.toUpperCase(),
      useDarkTheme: true,
    ),
    const OfflineBanner(),
    Expanded(
      child: CustomScrollView(
        slivers: [
          // MemoriesHeroCard and grid — no more ModuleHeader here
          ...
        ],
      ),
    ),
  ],
),
```

The error branch also needs OfflineBanner (it has a Column + ModuleHeader already). The loading branch renders a `CustomScrollView` with ModuleHeader in a Sliver — consistent with not adding OfflineBanner to the loading path.

## Common Pitfalls

### Pitfall 1: Removing `const` from enclosing widget
**What goes wrong:** Replacing `const LinearGradient(colors: [...])` with a non-const expression inside a `const EmptyStateView(...)` breaks compilation.
**Why it happens:** The `accentGradient` parameter is inside a const constructor call.
**How to avoid:** Remove `const` from both the `LinearGradient` and the `EmptyStateView` call site.
**Warning signs:** Compiler error "Arguments of a constant creation must be constant expressions."

### Pitfall 2: MemoriesScreen body restructure breaks loading/error branches
**What goes wrong:** Adding OfflineBanner to the data branch but not the error branch leaves the error branch inconsistent.
**Why it happens:** MemoriesScreen branches all three `when` cases independently.
**How to avoid:** Add OfflineBanner to both the `data:` and `error:` branches. Leave `loading:` branch unchanged.

### Pitfall 3: Missing `connectivityProvider` override in tests
**What goes wrong:** `OfflineBanner` watches `connectivityProvider` internally. Tests that don't override it may fail with an uninitialized provider error.
**Why it happens:** The test helper doesn't include `connectivityProvider` in its `ProviderScope.overrides`.
**How to avoid:** Override `connectivityProvider` in the test helper wrapper:
```dart
connectivityProvider.overrideWith((ref) => ConnectivityStatus.online),
```
Reference: `gear_screen_mutations_test.dart` does NOT override `connectivityProvider` because GearScreen uses `ref.watch(connectivityProvider)` at the top of build (not inside OfflineBanner only). Check if `OfflineBanner` internally watches the provider and whether that requires a test override.

### Pitfall 4: MemoriesScreen's Navigator.push pattern
**What goes wrong:** Refactoring the Scaffold body of MemoriesScreen incorrectly can disrupt the `_showFullScreen` full-screen overlay, which uses `Navigator.of(context).push` with `opaque: false`.
**Why it happens:** This is the one permitted `Navigator.push` in the codebase — documented exception per CLAUDE.md.
**How to avoid:** Do not change `_showFullScreen`. Only modify the `when` branches' top-level structure.

## Code Examples

### Test stub pattern (from `gear_screen_mutations_test.dart`)

```dart
// Source: test/features/gear_screen_mutations_test.dart
group('GearScreen — offline banner', () {
  testWidgets('GearScreen — OfflineBanner renders in body', (tester) async {
    await tester.pumpWidget(_wrapGearScreen(
      mockService: mockGearService,
      mockUser: mockUser,
      items: const [],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(OfflineBanner), findsOneWidget);
  });
});
```

Vault and Memories equivalents will follow this exact structure, with their respective provider overrides.

### Required provider overrides for VaultScreen tests

VaultScreen watches: `eventDetailProvider`, `eventDocumentsProvider`, `documentLoadingProvider`, `connectivityProvider`.

```dart
ProviderScope(
  overrides: [
    eventDetailProvider(_testEventRef).overrideWith((ref) => Stream.value(_testEvent)),
    eventDocumentsProvider(_testEventRef).overrideWith((ref) => Stream.value([])),
    documentLoadingProvider.overrideWith((ref) => false),
    connectivityProvider.overrideWith((ref) => ConnectivityStatus.online),
  ],
  child: MaterialApp(home: VaultScreen(groupId: 'group-1', eventId: 'event-1')),
)
```

### Required provider overrides for MemoriesScreen tests

MemoriesScreen watches: `eventDetailProvider`, `eventMemoriesProvider`.

```dart
ProviderScope(
  overrides: [
    eventDetailProvider(_testEventRef).overrideWith((ref) => Stream.value(_testEvent)),
    eventMemoriesProvider(_testEventRef).overrideWith((ref) => Stream.value([])),
  ],
  child: MaterialApp(home: MemoriesScreen(groupId: 'group-1', eventId: 'event-1')),
)
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter SDK built-in) |
| Config file | none — standard `flutter test` |
| Quick run command | `flutter test test/features/vault_screen_mutations_test.dart test/features/memories_screen_mutations_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VAULT-OFFLINE | OfflineBanner renders in VaultScreen body | widget | `flutter test test/features/vault_screen_mutations_test.dart` | Wave 0 |
| VAULT-TOKENS | No `Color(0xFF...)` in vault files | static grep | `grep -r "Color(0xFF" lib/features/vault/` | N/A |
| MEMORIES-OFFLINE | OfflineBanner renders in MemoriesScreen body | widget | `flutter test test/features/memories_screen_mutations_test.dart` | Wave 0 |
| MEMORIES-TOKENS | No `Color(0xFF...)` in memories files | static grep | `grep -r "Color(0xFF" lib/features/memories/` | N/A |

### Sampling Rate
- **Per task commit:** `flutter test test/features/vault_screen_mutations_test.dart test/features/memories_screen_mutations_test.dart`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/features/vault_screen_mutations_test.dart` — covers VAULT-OFFLINE (OfflineBanner renders in body). Initial state: test exists but FAILS (no OfflineBanner yet)
- [ ] `test/features/memories_screen_mutations_test.dart` — covers MEMORIES-OFFLINE (OfflineBanner renders in body). Initial state: test exists but FAILS

*(No framework install gap — flutter_test is SDK-native)*

## Project Constraints (from CLAUDE.md)

| Directive | Impact on Phase 35 |
|-----------|-------------------|
| All colors via AppColorTokens — CI blocks `Color(0xFF...)` | The 2 hardcoded gradients MUST be replaced |
| TDD mandatory — write tests first (RED phase) | Wave 0 writes failing OfflineBanner test stubs before implementation |
| 80%+ coverage maintained | New test files cover OfflineBanner presence |
| Immutability — create new objects, never mutate | No state mutation concerns in this phase (visual only) |
| Keep existing functionality unchanged | `_uploadDocument`, `_openDocument`, `_deleteDocument`, `_addPhoto`, `_showFullScreen` untouched |
| GSD workflow — no direct edits outside GSD | Phase uses Plan 00 (stubs) + Plan 01 (fixes) structure |
| No Navigator.push except MemoriesScreen full-screen overlay | `_showFullScreen` pattern must not be changed |

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — this phase is code-only changes to existing Flutter files).

## Sources

### Primary (HIGH confidence)
- Direct inspection: `lib/features/vault/screens/vault_screen.dart` — hardcoded colors confirmed at line 190
- Direct inspection: `lib/features/memories/screens/memories_screen.dart` — hardcoded colors confirmed at line 297
- Direct inspection: `lib/core/theme/tokens/color_tokens.dart` — moduleVault, moduleVaultLight, moduleMemories, moduleMemoriesLight tokens confirmed
- Direct inspection: `lib/shared/widgets/skeleton_loader.dart` — `documentList` and `photoGrid` factories confirmed
- Direct inspection: `test/features/gear_screen_mutations_test.dart` — OfflineBanner test pattern confirmed

### Secondary (MEDIUM confidence)
- Phase 34 PLAN.md — established two-plan structure (00=stubs, 01=fixes) and OfflineBanner Column placement pattern

## Metadata

**Confidence breakdown:**
- Current state audit: HIGH — all findings from direct code inspection
- Token mapping: HIGH — tokens confirmed in color_tokens.dart
- Test patterns: HIGH — exact pattern from gear_screen_mutations_test.dart
- MemoriesScreen body restructure: MEDIUM — the `when` branching means OfflineBanner placement requires wrapping the data branch; verified against existing code structure but implementation detail left to planner

**Research date:** 2026-04-05
**Valid until:** Indefinite (stable codebase, no external dependencies)

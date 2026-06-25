# #666 — `/activity` top-level direct-entry `/home` back fallback

**Type:** routing / back-guard hardening (Gate-category). **Priority:** P3 / tech-debt. **Issue verdict:** PARTIALLY TRUE — facts true, harm latent (defense-in-depth).

**Revised after Gate round 1 (FAIL).** The original spec proposed `GroupDetailScreen`'s `PopScope(canPop:false)` + always-on button. Gate caught a [P1]: `CrossGroupActivityScreen` is **also** the Activity bottom-nav tab, where that change visibly regresses the tab. The correct precedent is `ProfileScreen` (the structural twin), not `GroupDetailScreen`.

## Problem

`/activity` (`CrossGroupActivityScreen`) is a **top-level** route (`app_router.dart:452-459`, sibling of `/home`). Its `_TopBar` renders the back button only `if (canPop)` (a live `GoRouter.of(context).canPop()` probe); the `else` is a bare `SizedBox(width: 40)` — no `/home` fallback. If `canPop()` is `false` on the **route** entry (cold-entry / sole-stack page), the user is stranded: no home affordance.

### Two render paths (the thing the first spec missed — verified against live code, b660efa7)

`CrossGroupActivityScreen` is rendered **two** ways:
1. **Bottom-nav tab** — `bottom_nav_shell.dart:60` `case 1: return const CrossGroupActivityScreen();`. The shell is the body of the `/home` route (`home_screen.dart:55` → `BottomNavShell`), so on the tab `canPop()` is **false today**, and the current `_TopBar` correctly shows **no** back arrow (the `else SizedBox`). This is the **primary** way users reach the feed.
2. **Pushed route** — `context.push('/activity')` from `home_screen.dart:152` and `:485`. Push leaves `/home` beneath ⇒ `canPop()` is **true** ⇒ button renders, `pop()` works.

`/activity` is **absent** from the deep-link parser (`deep_link_service.dart`, `core/config/app_links.dart` — grep clean), so the route path 2 can never cold-enter today. The harm is therefore latent — but the fix must not touch path 1 (the tab).

This is exactly the structure of `ProfileScreen`: dual-mode tab + route screen.

## Decision — mirror `ProfileScreen` (the structural twin), NOT `GroupDetailScreen`

`ProfileScreen` is the established pattern for a screen rendered both as a `BottomNavShell` tab and as a route:

- `ProfileScreen({super.key, this.showBack = false})` — `profile_screen.dart:65`.
- Tab builds `const ProfileScreen()` ⇒ `showBack:false` ⇒ no back affordance (`bottom_nav_shell.dart:62`).
- Router builds `const ProfileScreen(showBack: true)` ⇒ back affordance (`app_router.dart:422`).
- `_TopBar` renders the back button `if (canPop)` where `canPop` is fed `showBack` (`profile_screen.dart:81,206`); its `_back` helper does `GoRouter.maybeOf(context)` → `router.canPop() ? router.pop() : router.go(AppRoutes.home)` (`profile_screen.dart:179-194`).
- **No `PopScope`.** ProfileScreen, also top-level + tab, does not use one.

We adopt this verbatim for `CrossGroupActivityScreen`:

1. Add `CrossGroupActivityScreen({super.key, this.showBack = false})` + `final bool showBack;`.
2. Thread it: `_TopBar(showBack: widget.showBack)`.
3. In `_TopBar`: render the back button **iff `showBack`** (replacing the live `canPop` probe), `else const SizedBox(width: 40)` (unchanged, keeps the title centred against the trailing 40 spacer). Add a `_back(context)` helper identical to ProfileScreen's. The button `onTap` calls `_back(context)`.
4. Router (`app_router.dart:456`): `child: const CrossGroupActivityScreen(showBack: true)`.
5. `BottomNavShell` case 1: **unchanged** — `const CrossGroupActivityScreen()` (`showBack` defaults false).

### Why not `PopScope` / why not `GroupDetailScreen`

- `GroupDetailScreen` is **route-only** (never in a tab), so it can freely wrap in `PopScope(canPop:false)`. `CrossGroupActivityScreen` cannot: an unconditional `PopScope(canPop:false)` would hijack the Android system-back gesture on the Activity **tab** and force `go('/home')`. (Predictive-back is moot — `enableOnBackInvokedCallback` absent from `android/` — but the system-back hijack on the tab is real and wrong.)
- A `showBack`-gated `PopScope` would be more than `ProfileScreen` does and would make the two structurally-identical tab screens inconsistent. Mirror the twin exactly: button-only.
- The issue's suggested fix ("Add `else go('/home')` … or a `PopScope` home fallback") is satisfied by the button's `_back` → `go(AppRoutes.home)` else-branch.

### Behavior change today: NONE (now actually true)

- **Tab** (`showBack:false`): button still hidden (`else SizedBox`), identical to today's `canPop==false` rendering. No `PopScope`, so the tab's system-back is untouched.
- **Pushed route** (`showBack:true`, `canPop()==true`): button renders, `_back` → `pop()`, identical to today.
- **New** only on a hypothetical cold-entry of the `/activity` route (`showBack:true`, `canPop()==false`): `_back` → `go(AppRoutes.home)`.

## Classification (verification principle 1)

Pure UI navigation. No money math, no Firestore read/write path, no schema/field-name, no rules. Only contract: GoRouter `pop`/`go` + the new `showBack` widget param. INBOUND/OUTBOUND N/A.

## Exact diff — `lib/features/home/screens/cross_group_activity_screen.dart`

- Add import `'../../../core/router/app_router.dart';` (for `AppRoutes.home`).
- Class: `const CrossGroupActivityScreen({super.key, this.showBack = false});` + `final bool showBack;`.
- State `build`: `const _TopBar()` → `_TopBar(showBack: widget.showBack)`.
- `_TopBar`: `const _TopBar();` → `const _TopBar({required this.showBack});` + `final bool showBack;`. Remove `final canPop = GoRouter.of(context).canPop();`. Add:

```dart
void _back(BuildContext context) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    router.go(AppRoutes.home);
  }
}
```

Button block becomes:

```dart
if (showBack)
  RIconButton(
    variant: RIconButtonVariant.ghost,
    icon: Directionality.of(context) == TextDirection.rtl
        ? Iconsax.arrow_right
        : Iconsax.arrow_left,
    tooltip: context.l10n.commonBack,
    onTap: () => _back(context),
  )
else
  const SizedBox(width: 40),
```

(No haptic — matches the current `_TopBar` button, which has none. The trailing `const SizedBox(width: 40)` balancer stays.)

## Tests — RED first (`test/features/home/cross_group_activity_screen_test.dart`)

New `CrossGroupActivityScreen navigation` group:

1. **`route cold-entry: back button routes home`** — router with `/home` + `/activity` where `/activity` builds `CrossGroupActivityScreen(showBack: true)` (as the real route will) and `initialLocation: '/activity'` (sole-stack ⇒ `canPop()==false`). Expect `find.byTooltip('Back')` `findsOneWidget`; tap; expect `Home`. RED pre-fix: `showBack` param does not exist → test won't compile (failing for the right reason: the route-only fallback contract is absent). GREEN post-fix.
2. **`route pushed: back button pops (no regression)`** — keep/retain the existing `back button pops route` test (push `/activity`, `canPop true`, tap back → returns to home pusher). With `showBack:true` on the route. Proves the common flow is unchanged.
3. **`tab (showBack=false): no back affordance`** — build `const CrossGroupActivityScreen()` (tab default) at `initialLocation:'/activity'` (canPop false). Expect `find.byTooltip('Back')` `findsNothing`. Guards the [P1] regression the Gate caught — must be GREEN before and after. (Also covered indirectly by `widgets_test.dart` Test 7 mounting it via `BottomNavShell`; this unit-level guard is cheaper and explicit.)

## Verification

- `flutter test test/features/home/cross_group_activity_screen_test.dart` — RED before, GREEN after.
- `flutter analyze` clean.
- `bash tool/check_theme_purity.sh` (touched a `lib/` widget).
- Full `flutter test`.

## Gate

Round 1: FAIL (tab-path [P1]). Spec revised to the ProfileScreen pattern. Re-run a fresh-context Opus subagent on this revised spec before implementation; stop when no [P1]s.

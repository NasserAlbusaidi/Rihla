# #1208 — Deep-link / notification dirty-draft guard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A runtime join deep-link or notification tap must not silently destroy a dirty expense draft — the same discard confirmation that guards back/X guards declarative route replacement.

**Architecture:** A tiny process-wide guard registry (`DraftNavigationGuard`) that dirty-capable editors register a confirm-callback with. The two runtime navigation injectors — `DeepLinkService.openJoinLink` and `NotificationService._navigate` — consult it before `router.go()`: no guard → navigate synchronously exactly as today; guard present → await the editor-owned discard confirmation, navigate only on confirm. `PopScope` can't help here (it intercepts only the pop channel, never declarative rebuilds — the editor's own comment acknowledges this), so the guard must run BEFORE the navigation call.

**Tech Stack:** Plain Dart singleton (matches `DeepLinkService.instance` style — `DeepLinkService` has no Riverpod ref), existing `_showDiscardConfirmDialog` in the editor.

**Issue:** #1208 (refuter-verified). Gate category: routing/deep links.

---

## Verified context (re-checked against live code 2026-07-13)

- `lib/core/services/deep_link_service.dart:127-136`: `bool openJoinLink(GoRouter router, Uri uri, {Set<String>? dedupeKeys})` → parse, dedupe (cold-start window only), `router.go(target); return true;`. Called from the runtime `uriLinkStream` listener (`:52-66`) and the cold-start initial-link path (`:83-96`). The `routed` return value is consumed ONLY during the cold-start window (`initialJoinRouted` / install-referrer suppression); the runtime listener ignores it after `collectingInitialStream = false`.
- `lib/core/services/notification_service.dart` `_navigate(String location)` (~:358-370): honors a `_onNavigateOverride` test seam, else `_ref.read(routerProvider).go(location)` in try/catch. All tap destinations funnel through it (`/join/<code>`, `/join-group`, `/group/:gid`, `/group/:gid/event/:eid`, `…/ledger`).
- Editor: `lib/features/ledger/widgets/expense_editor_body.dart` — `PopScope(canPop: !_isDirty, onPopInvokedWithResult: … _confirmDiscard())` (~:1113); `_showDiscardConfirmDialog()` returns `Future<bool?>` (`:632`); `initState` (`:287`), `dispose` (`:360`). Embedded by BOTH `add_expense_screen.dart:191` and `edit_expense_screen.dart:90` — one registration site covers add + edit.
- A second app_links consumer exists (`authEmailLinkBootstrapProvider`) — it does NOT flow through `openJoinLink` (parse returns null for non-join links, `openJoinLink` returns false before any guard consult). Email-link recovery flows are deliberately OUT of scope (account recovery is intentionally disruptive; guarding it would touch the #647/#648 swap-safety machinery).

## Design contract (exact shapes)

**New file `lib/core/services/draft_navigation_guard.dart`:**

```dart
/// #1208: guards DECLARATIVE navigation (deep links, notification taps)
/// against silently destroying a dirty editor. PopScope only intercepts the
/// pop channel; router.go() disposes the current stack without any callback,
/// so injected navigation must ask first.
///
/// Editors register a confirm-callback while mounted (register in initState,
/// unregister in dispose). The callback returns true when navigation may
/// proceed (pristine editor, or user confirmed the discard).
class DraftNavigationGuard {
  DraftNavigationGuard._();
  static final DraftNavigationGuard instance = DraftNavigationGuard._();

  final List<Future<bool> Function()> _guards = [];
  bool _consultInFlight = false;

  void register(Future<bool> Function() guard) => _guards.add(guard);
  void unregister(Future<bool> Function() guard) => _guards.remove(guard);

  bool get hasGuards => _guards.isNotEmpty;

  /// True → caller may navigate. Consults the MOST RECENT guard (top-most
  /// editor). While a consult's dialog is showing, concurrent requests are
  /// refused (returns false) — the second deep link loses, the user's
  /// dialog wins.
  Future<bool> mayNavigate() async {
    if (_guards.isEmpty) return true;
    if (_consultInFlight) return false;
    _consultInFlight = true;
    try {
      return await _guards.last();
    } finally {
      _consultInFlight = false;
    }
  }

  @visibleForTesting
  void reset() { _guards.clear(); _consultInFlight = false; }
}
```

**`DeepLinkService.openJoinLink`** — keep the signature and sync return (cold-start callers depend on it). After parse+dedupe succeed:

```dart
final target = joinUri.toString();
if (dedupeKeys != null && !dedupeKeys.add(target)) return false;

if (DraftNavigationGuard.instance.hasGuards) {
  // Runtime link over a dirty-capable editor: confirm-then-go. Return true
  // ("this was a join link and it was handled") — the return value only
  // feeds cold-start bookkeeping, and no editor can be mounted during the
  // cold-start window (guards register from screen initState, long after
  // DeepLinkService.init runs in bootstrap).
  unawaited(_confirmThenGo(router, target));
  return true;
}
router.go(target);
return true;
```

with `Future<void> _confirmThenGo(GoRouter router, String target) async { if (await DraftNavigationGuard.instance.mayNavigate()) { router.go(target); } }` (wrap the `go` in the same try/catch style as `_reportError` if an error path is plausible; a declined confirm simply drops the link — for the DEEP-LINK case the user can re-tap it. Gate r1 note: for the NOTIFICATION path there is no re-tap — Android auto-cancels a tapped notification — so a declined confirm permanently drops that tap; the destination stays reachable via normal nav and draft preservation is the priority, accepted).

**`NotificationService._navigate`** — same consult, before the existing override/try-catch:

```dart
void _navigate(String location) {
  final override = _onNavigateOverride;
  if (override != null) { override(location); return; }
  unawaited(_guardedGo(location));
}

Future<void> _guardedGo(String location) async {
  if (!await DraftNavigationGuard.instance.mayNavigate()) return;
  try {
    _ref.read(routerProvider).go(location);
  } catch (e) {
    if (kDebugMode) debugPrint('FCM: navigation to $location failed: $e');
  }
}
```

(Keep the override seam SYNCHRONOUS and unguarded — existing tests drive it; new guard tests use the real path or assert via the registry.)

**Dialog coordination (Gate r1 adversary [P2] — mandatory):** the guard must NOT stack a second discard dialog over one the editor already has showing (X-button/back paths at `expense_editor_body.dart:667,684,697` all call `_showDiscardConfirmDialog`; a deep link arriving mid-dialog would stack an identical twin, and confirming the top one orphans the other over the new screen). Track visibility at the single chokepoint: `_showDiscardConfirmDialog` sets a `bool _discardDialogVisible = true` before `showDialog` and clears it in a `finally`; the guard closure refuses early — `if (_discardDialogVisible) return false;` — BEFORE its own `_showDiscardConfirmDialog` call. Test: with the dialog already up (tap X on dirty editor), `mayNavigate()` → false, exactly one dialog in the tree.

**Editor registration** (`expense_editor_body.dart`): a stable field so unregister removes the exact instance:

```dart
late final Future<bool> Function() _draftNavigationGuard = () async {
  // mounted FIRST (Gate r1): _isDirty reads controllers that throw after
  // dispose; unregister-on-dispose makes this unreachable in practice, but
  // the ordering removes the latent footgun for free.
  if (!mounted) return true;
  if (!_isDirty) return true;
  final confirmed = await _showDiscardConfirmDialog();
  return confirmed == true;
};
// initState: DraftNavigationGuard.instance.register(_draftNavigationGuard);
// dispose:   DraftNavigationGuard.instance.unregister(_draftNavigationGuard);
```

Note: on confirm, do NOT pop the editor — the imminent `router.go()` replaces the stack; popping first would double-navigate.

## Non-goals

- No draft persistence (that's a feature, not this fix).
- No guarding of email-link recovery, in-app `context.go/push` (in-app flows already run their own confirms, e.g. `_handleChangeDestination`), or cold-start initial links (no editor can be mounted yet).
- No other dirty forms wired up (registry is generic; expense editor only for now — the issue's scope).

---

### Task 1: RED tests — guard registry + both injectors

**Files:**
- Create: `test/unit/draft_navigation_guard_test.dart` — registry semantics: empty→true; registered-false→false; registered-true→true; LIFO (last registered consulted); concurrent consult refused; unregister restores.
- Modify/Create: deep-link tests — the existing file is `test/unit/deep_link_service_test.dart` (Gate r1: it drives via `service.init(router)` with a `_MockGoRouter`, never calling `openJoinLink` directly — do NOT grep for `openJoinLink` callers). Add: with a registered guard returning `false`, a runtime join link does NOT `go` (mock router records calls) and `openJoinLink` still returns `true`; guard returning `true` → `go('/join/CODE12')` happens (async — `await pumpEventQueue()`/`untilCalled`). No guard → sync `go` exactly as today (existing tests must stay green unmodified — they prove the no-guard path).
- Modify/Create: notification navigate test: real path (no override) with guard-false → assert via the REGISTRY (guard consulted, navigation refused), not via spying the real GoRouter — production `_navigate` reads `_ref.read(routerProvider).go(...)` whose no-widget-tree throw lands in the existing try/catch, so "router invoked" is awkward to assert directly (Gate r1). Guard-true → assert the guard was consulted and no exception escapes.
- **Singleton hygiene (Gate r1, both reviewers): EVERY test file that touches `DraftNavigationGuard.instance` — deep-link, notification, AND editor tests — must call `DraftNavigationGuard.instance.reset()` in `setUp` AND `tearDown`.** A leaked registered guard flips `openJoinLink` onto the async branch and breaks `deep_link_service_test.dart`'s synchronous `verify(() => router.go(...)).called(1)` assertions (:135-139). ALSO: since `ExpenseEditorBody.initState` now registers a guard, EVERY existing editor-pumping test file (add/edit screens, goldens) touches the singleton — instead of editing them all, register a global `tearDown(() => DraftNavigationGuard.instance.reset());` in `test/flutter_test_config.dart` (its `testExecutable` runs per test file; a `tearDown` registered there applies to every test), keeping the per-file resets in the guard-focused tests for clarity.
- Create: `test/features/ledger/expense_editor_draft_guard_1208_test.dart` — pump the add-expense editor, verify a guard is registered (`DraftNavigationGuard.instance.hasGuards`); make it dirty (enter amount), invoke `mayNavigate()` → discard dialog appears; cancel → false + editor still mounted; confirm → true. Pristine editor → `mayNavigate()` true with NO dialog. Dispose (navigate away) → `hasGuards` false. Reset the singleton in setUp/tearDown (`reset()`).

**Step 2: Run them; the injector + editor tests must fail for the RIGHT reason** (registry file doesn't exist yet → write registry first if needed so failures are behavioral, not compile errors: acceptable order is Task 2 registry, then RED on injectors/editor). Capture failing output verbatim.

### Task 2: Implement registry → GREEN registry tests. Commit.

### Task 3: Wire `openJoinLink` + `_navigate` → GREEN injector tests. Commit.

### Task 4: Wire editor registration → GREEN editor tests. Commit.

### Task 5: Full check

`flutter test test/unit/ test/features/ledger/ <deep-link/notification test files>`, `flutter analyze`, `bash tool/check_theme_purity.sh` (editor file touched). The existing cold-start dedupe test (`auth_email_link_bootstrap_test.dart` "cold-start dedupe") and existing deep-link tests must pass UNMODIFIED — if one needs editing, stop and re-examine (semantics drifted).

### Task 6: PR

Push `-u`, `gh pr create`: summary + test plan + RED output + `Closes #1208` + `Spec: docs/plans/2026-07-13-1208-deeplink-dirty-draft-guard.md` (include the spec file in the branch). No auto-merge — lead runs /automerge (gate-category).

## Acceptance

- [ ] Dirty add/edit expense draft + runtime join link → discard dialog; cancel keeps draft (no navigation), confirm navigates to `/join/:code`.
- [ ] Same for notification-tap navigation (real path).
- [ ] Pristine editor: navigation proceeds with no dialog. No editor mounted: byte-identical behavior to today (existing tests unmodified).
- [ ] Cold-start initial-link path unaffected (guards can't exist at bootstrap; existing dedupe tests green).
- [ ] `flutter analyze` clean; diff coverage ≥90%.

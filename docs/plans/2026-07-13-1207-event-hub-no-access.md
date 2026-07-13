# #1207 — EventCommandCenter terminal no-access state Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give `EventCommandCenter` the #358 terminal no-access treatment: a permission-denied event listen renders a friendly "no access" state with a Home CTA instead of an infinitely-retrying error view.

**Architecture:** Mirror the existing, test-pinned pattern in `GroupDetailScreen` (`lib/features/groups/screens/group_detail_screen.dart:96-108`): special-case `permission-denied` in the `eventAsync.when(error:)` branch, log to Sentry, render a terminal `_NoAccessState` (no Retry — retrying just re-denies). All other errors keep today's `_ErrorState` + Retry.

**Tech Stack:** Flutter/Riverpod, `sentry_flutter`, `EmptyStateView`, existing l10n keys (no ARB changes).

**Issue:** #1207 (refuter-verified). Gate category: routing/back-guards (deep-link landing surface).

---

## Verified context (re-checked against live code 2026-07-13)

- `lib/features/events/screens/event_command_center.dart:79-85`: `body: eventAsync.when(loading: …, error: (_, _) => _ErrorState(onRetry: () => ref.invalidate(eventDetailProvider((groupId: groupId, eventId: eventId)))), data: …)`. No permission-denied case. `_ErrorState` (`:1054-1074`) renders `Iconsax.warning_2` + `eventLoadFailedTitle` + `activityLoadFailedMessage` + `commonRetry` only — no home/back affordance (`Scaffold` has no appBar; the `onBack` header lives in `_Content`, data-branch only).
- Reference implementation `group_detail_screen.dart:96-108`: `if (_isPermissionDenied(error)) { unawaited(Sentry.captureException(error, stackTrace: stackTrace)); return const _NoAccessState(); }`. `_isPermissionDenied` (`:1109-1110`): `error is FirebaseException && error.code == 'permission-denied'`. `_NoAccessState` (`:1407-1427`): `SafeArea > Center > Padding(space24) > EmptyStateView(icon: Iconsax.lock, title: l10n.groupNoAccessTitle, message: l10n.groupNoAccessMessage, actionLabel: l10n.groupBackHome, onAction: () => GoRouter.of(context).go('/home'))`.
- The denial genuinely reaches the hub: `watchEvent` (`event_service.dart:74`) → `recoverDeniedListen` (`listen_recovery.dart`) `addError`s after `kListenRecoveryMaxRetries=2`; `eventDetailProvider` (`event_provider.dart`) surfaces it as `AsyncError`.
- l10n keys exist (`lib/l10n/app_en.arb`): `groupNoAccessTitle` (:1813), `groupNoAccessMessage` (:1814), `groupBackHome` (:1817). The message copy ("You're no longer a member of this group, or it's no longer shared with you.") is accurate for the event case too — event access IS group membership. **Reuse them; add no ARB keys.**
- Reference test: `test/features/groups/group_detail_no_access_test.dart`. Existing hub error-state test file: `test/features/events/event_hub_balance_error_states_test.dart` (harness patterns for pumping the hub with provider overrides).
- Back-guard asymmetry (CLAUDE.md #243) is untouched: `event/:eid` is nested; `go`-navigation materializes ancestors. We add ONLY a CTA inside the body — no `PopScope`, no route changes.

## Non-goals

- No shared extraction of `_isPermissionDenied`/`_NoAccessState` (2 call sites; extract at the 3rd).
- No retry-with-backoff for transient staging denials (#574 is a group-create phenomenon; `recoverDeniedListen` already absorbs 2 retries before erroring).
- No changes to `_ErrorState`, routing, rules, or providers.

---

### Task 1: RED test — permission-denied renders no-access, not Retry

**Files:**
- Create: `test/features/events/event_hub_no_access_1207_test.dart`
- Reference: `test/features/groups/group_detail_no_access_test.dart` (copy its override/pump idiom), `test/features/events/event_hub_balance_error_states_test.dart` (hub-specific pumping)

**Step 1: Write the failing test.** Pump `EventCommandCenter(groupId: 'g', eventId: 'e')` with `eventDetailProvider((groupId: 'g', eventId: 'e'))` overridden to an error stream/AsyncError carrying `FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')`. Assert:
1. `find.text(<groupNoAccessTitle copy via l10n>)` present, `commonRetry` ABSENT (terminal — no retry affordance);
2. the Home CTA (`groupBackHome`) is present; tapping it routes to `/home`. **Note (Gate r1):** the reference test only asserts CTA *presence*, never taps — you must write the tap yourself (its test router already declares `/home` → `Text('Home')`: tap `groupBackHome` → `pumpAndSettle` → expect `Home`);
3. companion case: a NON-permission error (e.g. generic `Exception`) still shows `commonRetry` (pins that we didn't widen the terminal state). **Trap (Gate r1):** do NOT copy the reference test's second case verbatim — `group_detail_no_access_test.dart:101` asserts `find.byType(NetworkErrorWidget)` because GROUP detail's generic error uses `NetworkErrorWidget`; the EVENT hub's `_ErrorState` uses `EmptyStateView` + `commonRetry`. Assert on `commonRetry`, not `NetworkErrorWidget`.
End with `pumpAndSettle()` (`EmptyStateView` schedules a `flutter_animate` ticker). Override `sharedPreferencesProvider` if the harness boots the app.

**Step 2: Run it, verify it fails for the RIGHT reason** — the permission-denied case must currently render `commonRetry` (assertion 1 fails), not a compile error. Capture output verbatim for the PR body.

Run: `flutter test test/features/events/event_hub_no_access_1207_test.dart`

### Task 2: Implement the no-access branch

**Files:**
- Modify: `lib/features/events/screens/event_command_center.dart:79-85` (error branch) + add `_NoAccessState` widget near `_ErrorState` (`:1054`) + `_isPermissionDenied` helper at file bottom + imports (`sentry_flutter`, `FirebaseException` via `package:firebase_core/firebase_core.dart` or the exact import `group_detail_screen.dart` uses — mirror it, and mirror its `unawaited` import).

**Step 1:** Change the error branch to (signature: keep the two-arg error callback so `stackTrace` is available):

```dart
error: (error, stackTrace) {
  // #1207 / #358: a removed member's event listen is permission-denied
  // forever — retrying just re-denies. Terminal no-access state with a
  // Home CTA; raw error goes to Sentry, not the UI.
  if (_isPermissionDenied(error)) {
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    return const _NoAccessState();
  }
  return _ErrorState(
    onRetry: () => ref.invalidate(
      eventDetailProvider((groupId: groupId, eventId: eventId)),
    ),
  );
},
```

**Step 2:** Add (mirroring `group_detail_screen.dart:1407-1427` and `:1109-1110`, `Iconsax.lock`, reusing `groupNoAccessTitle`/`groupNoAccessMessage`/`groupBackHome`, `onAction: () => GoRouter.of(context).go('/home')`):

```dart
class _NoAccessState extends StatelessWidget {
  const _NoAccessState();
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(context.spacing.space24),
          child: EmptyStateView(
            icon: Iconsax.lock,
            title: context.l10n.groupNoAccessTitle,
            message: context.l10n.groupNoAccessMessage,
            actionLabel: context.l10n.groupBackHome,
            onAction: () => GoRouter.of(context).go('/home'),
          ),
        ),
      ),
    );
  }
}

/// True when a stream error is a Firestore `permission-denied` — the caller
/// lost access (removed from group / group deleted). Duplicate of the private
/// helper in group_detail_screen.dart (2 call sites; extract at the 3rd).
bool _isPermissionDenied(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';
```

**Step 3:** Run the RED test → PASS. Run: `flutter test test/features/events/`

**Step 4:** `flutter analyze` (clean) + `bash tool/check_theme_purity.sh` (new widget code — no hardcoded colors used, should pass).

**Step 5:** Commit: `fix(routing): terminal no-access state for EventCommandCenter (#358 pattern)` — include the RED output in the PR body later.

### Task 3: PR

Push `-u`, `gh pr create`, body: summary + test plan + pasted RED output + `Closes #1207` + `Spec: docs/plans/2026-07-13-1207-event-hub-no-access.md`. Include this spec file in the branch (copy from main checkout if absent). Do NOT enable auto-merge (lead runs /automerge — gate-category).

## Residual (Gate r1 adversary — name it in the PR body, do NOT fix here)

Sibling event-load landing surfaces keep their generic states on permission-denied: `ledger_screen.dart:78` (`_ErrorState`+Retry), `activity_feed_screen.dart:124` (`_ErrorView`), `event_recap_screen.dart:60` (`_notFound` — shows "not found" to a removed member). The hub is the documented primary landing (rows/tickets push the bare hub route), so #1207 scopes to the hub; the siblings are a tracked follow-up, not part of this PR.

## Acceptance

- [ ] Permission-denied event load renders lock icon + no-access copy + Home CTA; NO Retry.
- [ ] Home CTA navigates `/home` (test-asserted).
- [ ] Non-permission errors keep today's `_ErrorState` + Retry (test-asserted).
- [ ] Sentry captureException called on the denied path (mirrors group detail; assert via test if the group-detail test does, else skip).
- [ ] `flutter analyze` clean; `test/features/events/` green; diff coverage ≥90%.

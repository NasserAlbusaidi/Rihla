# Task: Fix two post-launch v1.2.0+14 bugs

## Context

Rihla shipped v1.2.0+14 to Play closed-test ("first" track) on 2026-05-16. Real-device testing surfaced two bugs documented in `docs/REAL-DEVICE-QA.md` under **"Known issues — verify next real-device session"**. Both have static analysis done, root cause / suspects identified, and proposed fixes. Implement them. Do not introduce new scope.

Project conventions are in `CLAUDE.md` at the repo root. Read it before editing — especially: GoRouter (no Navigator.push, no goNamed, no state.extra), `decimal` package for money (not double), `context.colors` / `context.spacing` / `context.shadows` for styling (no hardcoded `Color(0xFF...)` literals), Riverpod 2.x without codegen.

## Goal

1. **Group detail back button** (Android-only) on `/group/:gid` works reliably from any entry path. System back button (Android predictive back / gesture) also returns to `/home` or pops correctly.
2. **Event-level settlement rows** display real participant names (e.g. "Ali paid Sara") instead of "Someone paid Someone".

## Constraints

- Flutter SDK ^3.10.1, Riverpod 2.x without codegen, GoRouter 13.x declarative.
- All money math uses `decimal` package — never `double`.
- Styling via `context.colors` / `context.spacing` / `context.shadows`. No hardcoded `Color(0xFF…)` outside `lib/core/theme/tokens/`.
- No `Navigator.push`, no `state.extra` for required nav data, no `goNamed`. Path-based GoRouter only.
- Soft-delete pattern for user-visible records. Settlements are append-only (do not add update/delete paths).
- `MoneySerializer` is the only place that converts Decimal ↔ integer subunits, and only at the Firestore boundary.
- Comments: default to none. Only add a comment when the WHY is non-obvious.
- Do NOT touch `lib/firebase_options.dart`, `pubspec.yaml` version, or any CI files.
- Do NOT reintroduce dropped features (memories/vault/gear/logistics). Do NOT add new global repositories.
- Do NOT modify the temporary App Check disable on `joinGroupByInviteCode` — leave that alone.

## Bug 1: Group detail back button (Android-only)

**Symptom (verbatim from REAL-DEVICE-QA.md):** Tapping the on-screen ← arrow at top-left of `GroupDetailScreen` cover header has no effect on Android (Play closed-test install). iOS Simulator works fine. User must force-close the app.

**Code path:**
- Button: `_PaperIconButton` in `lib/features/groups/screens/group_detail_screen.dart:259` (definition at line 311).
- It is currently a 36×36 `SizedBox` inside an `InkResponse(radius: 22)` inside a `Material(shape: CircleBorder)`, placed inside `Positioned(top: statusBar + 8, left: 12, right: 12)` inside the cover `Stack`.
- `onTap`: `HapticService.lightClick()` then `final router = GoRouter.of(context); if (router.canPop()) router.pop(); else router.go('/home');`
- No `PopScope` / `WillPopScope` exists in the app today.

**Required fixes:**
1. Expand the back-button hit-target to at least 48×48 (Material spec). Keep the 36×36 *visual* circle, but widen the tappable area — wrap the `Material`+`InkResponse` in an outer `SizedBox(width: 48, height: 48)` with centered alignment, or use `Padding` to inflate the hit zone. Do the same for the right-side `_OverflowMenu` button so they stay visually balanced.
2. Wrap the entire `GroupDetailScreen` `Scaffold` body (or `Scaffold` itself) in `PopScope(canPop: false, onPopInvokedWithResult: (didPop, result) { if (didPop) return; final router = GoRouter.of(context); if (router.canPop()) router.pop(); else router.go('/home'); })`. This catches the Android system back button / predictive back gesture so it can never strand the user.
3. The `onTap` of the existing on-screen back button does not need to change — but verify it still works after the PopScope wrapper is added (PopScope only intercepts system back, not synthesized `pop()` calls, so it should be fine).

**Do NOT:**
- Refactor the cover header to a `SliverAppBar` (out of scope; would touch the design system).
- Change visual style of the button (color, size, icon, shadow).
- Add any new dependencies.

## Bug 2: Event-level settlements show "Someone paid Someone"

**Symptom:** Settlement rows in the event ledger render "Someone paid Someone" even when participants are named. Group-level settlements (group settle-up flow) display real names correctly. Only event scope is broken.

**Root cause:** `SettlementService.addSettlement` in `lib/features/ledger/services/settlement_service.dart` writes `payerParticipantId` / `recipientParticipantId` but does NOT persist `payerName` / `recipientName` to Firestore. The `Settlement` model already supports both fields (`lib/features/ledger/models/settlement_model.dart:13-14, 39-40, 66-69, 114-115`). The UI fallback is `settlement.payerName ?? 'Someone'` (`lib/features/ledger/widgets/ledger_day_card.dart:150,344`; `lib/features/ledger/widgets/ledger_search_sheet.dart:439-440`).

Group-level reference: `GroupSettlementService.addGroupSettlement` already does this correctly — see `lib/features/groups/services/group_settlement_service.dart:55-100` (takes optional `payerName` / `recipientName` and writes them at lines 86-87). Mirror the same shape.

**Required fixes:**
1. `lib/features/ledger/services/settlement_service.dart`: add `String? payerName` and `String? recipientName` optional parameters to `addSettlement`, and include them in the Firestore data map (alongside `payerParticipantId` etc.).
2. `lib/features/ledger/screens/settle_up_screen.dart`: `_handleSettlement` already has `fromName` and `toName` in scope (lines 200-247). Thread them through `_recordSettlement` (currently lines 250-307) so they reach the new `addSettlement` params. Update both function signatures.
3. **Do NOT migrate existing legacy data.** Pre-fix settlement docs will continue to display "Someone paid Someone" — that is acceptable. Add a one-line comment at the top of the new `payerName`/`recipientName` Firestore field write explaining "fields absent on pre-2026-05-16 docs render as 'Someone' via the model fallback". (This is one of those non-obvious WHY comments.)

**Do NOT:**
- Add an activity-log write inside event settle-up (it currently doesn't log to the event activity feed; that's a separate gap, out of scope here).
- Backfill old settlement docs.
- Change the `Settlement` model — fields already exist.
- Change `MoneySerializer` boundary behavior.

## Files to touch

- `lib/features/groups/screens/group_detail_screen.dart` — back button hit-target + PopScope wrapper (Bug 1).
- `lib/features/ledger/services/settlement_service.dart` — add `payerName` / `recipientName` params + persist (Bug 2).
- `lib/features/ledger/screens/settle_up_screen.dart` — thread names through `_handleSettlement` → `_recordSettlement` → `addSettlement` (Bug 2).
- Test files under `test/features/groups/`, `test/features/ledger/`, or `test/unit/` as needed to cover the changes.

## Files NOT to touch

- `lib/firebase_options.dart`
- `pubspec.yaml` (version, dependencies)
- `functions/**` (Cloud Functions out of scope here)
- `lib/core/router/app_router.dart` (no router changes needed for this fix)
- `lib/features/ledger/models/settlement_model.dart` (fields already exist)
- `lib/features/groups/services/group_settlement_service.dart` (reference only)
- `lib/firebase_options.dart`, `.github/workflows/**`, `android/**` (except generated build outputs ignored by git)

## Acceptance criteria

- [ ] Bug 1: `flutter run` on iOS simulator AND a deploy candidate `flutter build apk --debug` are both buildable. Static analysis (`flutter analyze`) clean.
- [ ] Bug 1: A new widget test in `test/features/groups/` confirms the PopScope wrapper invokes `context.go('/home')` when `canPop()` is false. Existing back-button tests (if any) still pass.
- [ ] Bug 1: `_PaperIconButton` hit-target is ≥ 48×48 (assert via test that measures the tap region, e.g. with `tester.getSize(find.byKey(...))` or a Semantics test).
- [ ] Bug 2: A new unit test in `test/features/ledger/` or `test/unit/` writes a settlement via `SettlementService.addSettlement` with `payerName`/`recipientName`, reads it back via `watchSettlements`, and asserts the names round-trip.
- [ ] Bug 2: An updated widget test for `settle_up_screen.dart` (or new one) confirms the screen calls `addSettlement` with the resolved `fromName` / `toName` arguments.
- [ ] `flutter analyze` is clean. `flutter test` passes locally. Coverage gate (70%) not regressed.
- [ ] No hardcoded `Color(0xFF...)` literals added (CI lint will catch this — verify locally with `dart tool/check_no_hardcoded_colors.dart`).
- [ ] No new files outside the listed paths (other than new test files).
- [ ] Commit messages follow conventional format (`fix(scope): ...`).

## Verification commands

```bash
# Static analysis — must be clean
flutter analyze

# Theme purity (no hardcoded colors)
bash tool/check_theme_purity.sh

# Targeted tests
flutter test test/features/groups/
flutter test test/features/ledger/
flutter test test/unit/

# Full suite as final gate
flutter test
```

## Out of scope

- Re-enabling `enforceAppCheck` on `joinGroupByInviteCode` (different change set; will follow Play Integrity verification).
- Adding event-scoped activity-log writes on settlement (separate gap; defer).
- Migrating legacy settlement docs to backfill `payerName` / `recipientName`.
- Bumping `pubspec.yaml` version or shipping a new Play build (that's the orchestrator's job after review).
- Touching the cover header design, the overflow menu, or any other UI not directly required for the back-button fix.
- Refactoring the two settle-up flows into a shared service (existing duplication is intentional per recent settle-up unification work — see commit history; out of scope).

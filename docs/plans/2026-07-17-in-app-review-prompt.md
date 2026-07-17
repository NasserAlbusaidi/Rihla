# In-App Review Prompt (#1263) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ask for a store review at the natural moment — right after a settle-up completes — via the platform in-app review APIs (Play In-App Review / SKStoreReviewController), cooldown-gated and emulator-guarded.

**Architecture:** A new `ReviewPrompt` core service mirrors the `NotificationPrompt` pattern (`lib/core/services/notification_prompt.dart`): a Riverpod `Provider`, one fire-and-forget `maybeRequest()` safe to call from UI success handlers, all gating internal to the service. Cooldown state is a raw SharedPreferences key (service-internal state, NOT a user setting — deliberately avoids `AppSettings`/`settings_service.dart` and keeps the diff out of `**/models/**.dart`, so the PR stays Gate-exempt). Trigger wiring copies the #367 WhatsApp-nudge precedent in both settle-up screens: single-tile clean-record path + stepped-walk completion, in each screen.

**Tech Stack:** `in_app_review: ^2.0.12` (verified latest on pub.dev 2026-07-17; Android + iOS + macOS), `shared_preferences` (already a dep), `mocktail` for the plugin mock.

**Gate status:** Exempt — no money math, no rules/Functions, no routing, no schema. Verified: the only persisted state is one new local prefs key (write-path: `ReviewPrompt`; read-path: `ReviewPrompt` — same file). No Firestore surface. The diff must not touch `expense_provider.dart`, `**/models/**.dart`, `functions/**`, `security/`, or `lib/core/router/**` — if implementation drifts into any of those, STOP and run `/run-the-gate` first.

**Design constraints (from #1263, Google guidance):**
- Trigger after a completed settle-up, never a CTA button. No pre-rating question.
- Optimistic call: Play quota (~1 successful prompt/device/1–2 weeks) silently no-ops extra requests; iOS OS-throttles (≤3/365 days). Client cooldown of 14 days between *attempts* keeps us inside the Play cadence and preserves the iOS budget.
- Never fire on QA/emulator flows: compile-time `USE_FIREBASE_EMULATOR` guard (same key/parse as `lib/main.dart:40` — `bool.fromEnvironment(..., defaultValue: false)`).
- Fail-silent everywhere: a review prompt must never break or delay a settle flow. `sharedPreferencesProvider` throws when unoverridden and `InAppReview` throws `MissingPluginException` in widget tests — both must land in a swallow-all `catch (_)` (the established `FirebaseConfig.currentUser` fail-open pattern), so every existing app-booting test passes unchanged.

**Wiring rule (4 sites, both screens structurally parallel):**

| Screen | Site | Gate |
|---|---|---|
| `lib/features/ledger/screens/settle_up_screen.dart` | single-tile, after the #367 nudge block (~L787), before `return outcome;` | `stepLabel == null && outcome.kind == recorded && !outcome.alreadyRecorded` |
| same file | `_runSteppedSettle` end (~L556), after the summary snackbar | `recorded > 0` (already early-returned) |
| `lib/features/groups/screens/group_settle_up_screen.dart` | single-tile, after the #367 nudge block (~L770), before `return outcome;` | same as event screen |
| same file | `_runSteppedSettle` end (~L580), after the summary snackbar | `recorded > 0` |

The `stepLabel == null` conjunct prevents per-step double-firing during a walk (the walk-end site covers it once). `alreadyRecorded` (#1129 idempotent replay) never prompts — same reasoning as #367: the user already had their moment for this exact payment. The review block sits AFTER the awaited #367 nudge so the two prompts are sequential, never stacked. Corrections (`correctSettlement` flows) deliberately get no prompt — fixing a mistake is not a delight moment.

---

### Task 1: Branch + dependency

**Files:**
- Modify: `pubspec.yaml` (dependencies block, near `share_plus`/`package_info_plus`)
- Modify: `pubspec.lock` (generated)

**Step 1: Branch from origin/main**

```bash
git fetch origin && git checkout -b feat/1263-in-app-review-prompt origin/main
```

**Step 2: Add the dependency**

In `pubspec.yaml` under `dependencies:`, alphabetical placement:

```yaml
  in_app_review: ^2.0.12
```

**Step 3: Resolve**

Run: `flutter pub get`
Expected: resolves cleanly, `pubspec.lock` gains `in_app_review` + `in_app_review_platform_interface`.

**Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): add in_app_review for the store review prompt (#1263)"
```

### Task 2: `ReviewPrompt` service (TDD)

**Files:**
- Create: `lib/core/services/review_prompt.dart`
- Test: `test/core/services/review_prompt_test.dart`

**Step 1: Write the failing tests**

`test/core/services/review_prompt_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/review_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockInAppReview extends Mock implements InAppReview {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockInAppReview review;

  setUp(() {
    review = _MockInAppReview();
    when(review.isAvailable).thenAnswer((_) async => true);
    when(review.requestReview).thenAnswer((_) async {});
  });

  Future<(ProviderContainer, SharedPreferences)> makeContainer({
    Map<String, Object> initialPrefs = const {},
    DateTime Function()? now,
    bool emulatorRun = false,
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        inAppReviewProvider.overrideWithValue(review),
        reviewPromptProvider.overrideWith(
          (ref) => ReviewPrompt(ref, now: now, emulatorRun: emulatorRun),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container, prefs);
  }

  test('happy path: requests review and persists the attempt timestamp',
      () async {
    final now = DateTime.utc(2026, 7, 17, 12);
    final (container, prefs) = await makeContainer(now: () => now);

    await container.read(reviewPromptProvider).maybeRequest();

    verify(review.isAvailable).called(1);
    verify(review.requestReview).called(1);
    expect(
      prefs.getInt(ReviewPrompt.lastAttemptPrefsKey),
      now.millisecondsSinceEpoch,
    );
  });

  test('cooldown: a 13-day-old attempt suppresses the request', () async {
    final now = DateTime.utc(2026, 7, 17, 12);
    final last = now.subtract(const Duration(days: 13));
    final (container, _) = await makeContainer(
      initialPrefs: {
        ReviewPrompt.lastAttemptPrefsKey: last.millisecondsSinceEpoch,
      },
      now: () => now,
    );

    await container.read(reviewPromptProvider).maybeRequest();

    verifyNever(review.isAvailable);
    verifyNever(review.requestReview);
  });

  test('cooldown expiry: a 15-day-old attempt allows a new request', () async {
    final now = DateTime.utc(2026, 7, 17, 12);
    final last = now.subtract(const Duration(days: 15));
    final (container, prefs) = await makeContainer(
      initialPrefs: {
        ReviewPrompt.lastAttemptPrefsKey: last.millisecondsSinceEpoch,
      },
      now: () => now,
    );

    await container.read(reviewPromptProvider).maybeRequest();

    verify(review.requestReview).called(1);
    expect(
      prefs.getInt(ReviewPrompt.lastAttemptPrefsKey),
      now.millisecondsSinceEpoch,
    );
  });

  test('emulator/QA runs never prompt and never touch prefs', () async {
    final (container, prefs) = await makeContainer(emulatorRun: true);

    await container.read(reviewPromptProvider).maybeRequest();

    verifyNever(review.isAvailable);
    verifyNever(review.requestReview);
    expect(prefs.getInt(ReviewPrompt.lastAttemptPrefsKey), isNull);
  });

  test('unavailable platform: no request, no timestamp burned', () async {
    when(review.isAvailable).thenAnswer((_) async => false);
    final (container, prefs) = await makeContainer();

    await container.read(reviewPromptProvider).maybeRequest();

    verifyNever(review.requestReview);
    expect(prefs.getInt(ReviewPrompt.lastAttemptPrefsKey), isNull);
  });

  test('plugin throwing is swallowed (fail-silent in success handlers)',
      () async {
    when(review.isAvailable).thenThrow(Exception('MissingPlugin'));
    final (container, _) = await makeContainer();

    await expectLater(
      container.read(reviewPromptProvider).maybeRequest(),
      completes,
    );
  });

  test('unoverridden prefs (throwing provider) is swallowed', () async {
    final container = ProviderContainer(
      overrides: [
        inAppReviewProvider.overrideWithValue(review),
        reviewPromptProvider.overrideWith(
          (ref) => ReviewPrompt(ref, emulatorRun: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(reviewPromptProvider).maybeRequest(),
      completes,
    );
    verifyNever(review.requestReview);
  });

  test('re-entrancy: concurrent calls produce one request', () async {
    final (container, _) = await makeContainer();
    final prompt = container.read(reviewPromptProvider);

    await Future.wait([prompt.maybeRequest(), prompt.maybeRequest()]);

    verify(review.requestReview).called(1);
  });
}
```

Note: the re-entrancy test relies on `_inFlight` being set synchronously before the first await (same discipline as `NotificationPrompt`). The second concurrent call must bail on `_inFlight`; the sequential-second-call case is covered by the cooldown test.

**Step 2: Run to verify it fails**

Run: `flutter test test/core/services/review_prompt_test.dart`
Expected: FAIL — `review_prompt.dart` doesn't exist / `reviewPromptProvider` undefined.

**Step 3: Implement**

`lib/core/services/review_prompt.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';

import '../providers/settings_provider.dart';

/// Seam for tests — the plugin singleton talks to a platform channel.
final inAppReviewProvider = Provider<InAppReview>((_) => InAppReview.instance);

/// Coordinates the contextual store-review ask (#1263).
final reviewPromptProvider = Provider<ReviewPrompt>(ReviewPrompt.new);

/// Asks for a store review at a natural moment — a settle-up completing —
/// via the platform in-app review flow (Play In-App Review /
/// SKStoreReviewController). Mirrors [NotificationPrompt]'s shape: one
/// fire-and-forget entry point, all gating internal, safe to call from any
/// UI success handler.
///
/// Gating, in order: emulator/QA builds never prompt; at most one attempt
/// per [cooldown] (Play quota is ~1 successful prompt per device per 1–2
/// weeks and silently no-ops beyond it; iOS grants ≤3/year — the client
/// cooldown keeps attempts inside both budgets); the platform must report
/// the flow available (absent Play Services → skip, timestamp not burned).
/// Every failure path is swallowed — a review ask must never surface an
/// error into a settle flow.
class ReviewPrompt {
  ReviewPrompt(this._ref, {DateTime Function()? now, bool? emulatorRun})
    : _now = now ?? DateTime.now,
      _emulatorRun =
          emulatorRun ??
          const bool.fromEnvironment(
            'USE_FIREBASE_EMULATOR',
            defaultValue: false,
          );

  static const String lastAttemptPrefsKey = 'reviewPromptLastAttemptMs';
  static const Duration cooldown = Duration(days: 14);

  final Ref _ref;
  final DateTime Function() _now;
  final bool _emulatorRun;
  bool _inFlight = false;

  /// Fire-and-forget: requests the in-app review flow if every gate passes.
  Future<void> maybeRequest() async {
    if (_inFlight || _emulatorRun) return;
    _inFlight = true;
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      final lastMs = prefs.getInt(lastAttemptPrefsKey);
      final now = _now();
      if (lastMs != null &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) <
              cooldown) {
        return;
      }
      final review = _ref.read(inAppReviewProvider);
      if (!await review.isAvailable()) return;
      // Persist BEFORE requesting: the OS shows UI next, and a kill mid-flow
      // must not re-arm an immediate retry on next launch.
      await prefs.setInt(lastAttemptPrefsKey, now.millisecondsSinceEpoch);
      await review.requestReview();
    } catch (_) {
      // Fail-open on purpose: unoverridden prefs in tests, MissingPlugin in
      // widget tests, or any platform hiccup — never let the ask leak an
      // error into the settle flow that triggered it.
    } finally {
      _inFlight = false;
    }
  }
}
```

**Step 4: Run to verify it passes**

Run: `flutter test test/core/services/review_prompt_test.dart`
Expected: 8 tests PASS.

**Step 5: Commit**

```bash
git add lib/core/services/review_prompt.dart test/core/services/review_prompt_test.dart
git commit -m "feat(review): ReviewPrompt service — cooldown-gated in-app review ask (#1263)"
```

### Task 3: Wire the event settle-up screen

**Files:**
- Modify: `lib/features/ledger/screens/settle_up_screen.dart` (two sites: after the #367 nudge block ~L787; end of `_runSteppedSettle` ~L556)
- Test: extend the existing record-success harness (start from `test/features/ledger/settle_up_dedup_1093_test.dart` / `settle_up_screen_test.dart` — whichever already drives a clean record through the sheet; reuse its fakes)

**Step 1: Write the failing wiring test**

New file `test/features/ledger/settle_up_review_prompt_test.dart`, cloning the existing successful-record setup. Spy pattern:

```dart
class _SpyReviewPrompt extends ReviewPrompt {
  _SpyReviewPrompt(super.ref);
  int calls = 0;
  @override
  Future<void> maybeRequest() async => calls++;
}

// in the harness overrides:
late _SpyReviewPrompt spy;
// ...
reviewPromptProvider.overrideWith((ref) => spy = _SpyReviewPrompt(ref)),
```

Assertions:
- driving one clean single-tile record → `spy.calls == 1`
- driving an #1129 `alreadyRecorded` replay (the dedup test already models this) → `spy.calls == 0`

**Step 2: Run to verify it fails**

Run: `flutter test test/features/ledger/settle_up_review_prompt_test.dart`
Expected: FAIL — `spy.calls == 0` on the clean record (wiring absent).

**Step 3: Implement the wiring**

In `settle_up_screen.dart`, import `review_prompt.dart` (and `dart:async` if `unawaited` isn't already imported). After the #367 block, before `return outcome;`:

```dart
    // #1263: a completed settle is the natural review moment. Fire-and-forget —
    // cooldown/availability/emulator gating all live inside ReviewPrompt. The
    // #1129 idempotent replay never re-prompts (same reasoning as the #367
    // nudge above); stepped walks prompt once at walk end, not per step.
    if (stepLabel == null &&
        outcome.kind == _StepOutcomeKind.recorded &&
        !outcome.alreadyRecorded) {
      unawaited(ref.read(reviewPromptProvider).maybeRequest());
    }
```

At the end of `_runSteppedSettle` (after the summary snackbar; `recorded == 0` already returned early):

```dart
    // #1263: one review ask per completed walk (see the single-tile site).
    unawaited(ref.read(reviewPromptProvider).maybeRequest());
```

**Step 4: Run to verify it passes**

Run: `flutter test test/features/ledger/settle_up_review_prompt_test.dart`
Then the screen's existing suites: `flutter test test/features/ledger/`
Expected: all PASS (the fail-silent catch keeps every existing app-booting test green).

**Step 5: Commit**

```bash
git add lib/features/ledger/screens/settle_up_screen.dart test/features/ledger/settle_up_review_prompt_test.dart
git commit -m "feat(review): ask for a store review after an event settle-up (#1263)"
```

### Task 4: Wire the group settle-up screen

**Files:**
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart` (after the #367 nudge block ~L770; end of `_runSteppedSettle` ~L580)
- Test: `test/features/groups/group_settle_up_review_prompt_test.dart` (clone from `group_settle_up_callable_1129_test.dart` / `group_settle_up_screen_test.dart` harness)

Steps mirror Task 3 exactly (same gate, same spy, same RED→GREEN order). Group screen note: its `_runSteppedSettle` takes `context` as a parameter — the fire-and-forget uses `ref` (State field), unaffected.

Run after GREEN: `flutter test test/features/groups/`

**Commit:**

```bash
git add lib/features/groups/screens/group_settle_up_screen.dart test/features/groups/group_settle_up_review_prompt_test.dart
git commit -m "feat(review): ask for a store review after a group settle-up (#1263)"
```

### Task 5: Changelog + full verification

**Files:**
- Modify: `CHANGELOG.md` (new `## [Unreleased]` section above `## [1.9.2]` if absent)

**Step 1: Changelog entry**

Under `### Added`:

```markdown
- Rihla now asks for a store review right after a settle-up completes — at
  most once every two weeks, only when the platform review flow is available,
  and never on QA builds.
```

**Step 2: Full local verification (report results verbatim)**

```bash
flutter analyze                      # must be clean
flutter test                         # full suite
bash tool/check_theme_purity.sh      # CI-only check, run locally — lib/ changed
```

Expected: analyze clean, all tests pass, theme purity clean (no colors/textMuted touched, but new lib/ files make the local run mandatory per CLAUDE.md #615).

**Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): in-app review prompt entry (#1263)"
```

### Task 6: PR + automerge

**Step 1: Push and open the PR**

```bash
git push -u origin feat/1263-in-app-review-prompt
gh pr create --title "feat(review): contextual in-app review prompt after settle-up (#1263)" \
  --body "$(cat <<'EOF'
Closes #1263.

Spec: docs/plans/2026-07-17-in-app-review-prompt.md

## Summary
- `in_app_review: ^2.0.12`; new `ReviewPrompt` core service (NotificationPrompt pattern): 14-day cooldown in a raw prefs key, `USE_FIREBASE_EMULATOR` guard, `isAvailable()` check, fail-silent.
- Triggered fire-and-forget after clean settle-up completion — single-tile + stepped walk, event and group screens (the #367 nudge sites). `alreadyRecorded` replays and corrections never prompt.

## Test plan
- `test/core/services/review_prompt_test.dart` — 8 unit tests (cooldown both sides, emulator guard, unavailable platform, throw-swallowing, re-entrancy, timestamp persistence).
- Wiring tests both screens: clean record → exactly one `maybeRequest`; #1129 replay → none.
- `flutter analyze` clean; full `flutter test`; `tool/check_theme_purity.sh` clean.
EOF
)"
```

**Step 2: Review the full branch diff before automerge**

```bash
git diff origin/main...HEAD --stat
```

Confirm the diff touches ONLY: `pubspec.yaml`, `pubspec.lock`, `lib/core/services/review_prompt.dart`, the two screens, three test files, `CHANGELOG.md`, and this plan doc. Any `**/models/**`, `functions/**`, `security/`, router, or `expense_provider.dart` file in the list → STOP, do not merge, run the Gate.

**Step 3: Run `/automerge <N>`** — never raw `gh pr merge`.

# Late-write failure notice: queued writes that die on replay tell the user (#scorecard critical 1)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> **Provenance:** 2026-07-03 whole-app scorecard critical #1 ("onLateError wired at 0 of ~18 callsites — silent money-loss on sync failure"), user-approved fix-first sequencing. All claims verified against `origin/main` @021f571e.

**Goal:** when a queued-offline Firestore write is REJECTED on replay (rules rejection, validation), the user is told — today the failure is `debugPrint` + Sentry only (`write_ack.dart:41-44`), the SDK reverts the optimistic local write, and the user's expense/settlement silently vanishes.

**Non-goals:** no retry queue (the SDK owns replay; a rules rejection is terminal by design), no per-callsite wiring (19 callsites stay untouched — the fix is at the chokepoint), no change to ack/queued semantics or `kWriteAckTimeout`, no persistence (pure display).

## Verified facts (all re-grepped @021f571e)

- `awaitServerAck` (`lib/core/utils/write_ack.dart:31`) is the single chokepoint every offline-tolerant write runs through: 14 real invocations in 8 files (19 raw grep matches; 5 are doc-comment mentions), **zero** pass `onLateError` (the symbol appears only in write_ack.dart itself).
- Late failure today = `debugPrint` + `Sentry.captureException` + `onLateError?.call` (`write_ack.dart:41-44`) — no user surface.
- `appMessengerKey` (`lib/core/services/app_messenger.dart:10`) is the established context-free snack surface, mounted at `main.dart:271`; l10n resolves via `appMessengerKey.currentContext` (the #843 pattern used by `auth_email_link_bootstrap_provider.dart:44-63` and `recovery_outcome_notice_provider.dart:44,88`).
- `classifyError`/`friendlyMessageFor` (`lib/core/utils/error_message_translator.dart:34,64`) already translate FirebaseException codes to localized cause phrases (`errorNetwork`/`errorPermissionDenied`/`errorTooManyRequests`/`errorUnexpected`, app_en.arb:2253-2265, AR present).
- Home staleness after a revert is NOT in scope: the online home path reads the server-maintained #366 aggregate doc (write rejected ⇒ aggregate never changed ⇒ home already correct); live in-group streams get the SDK's cache-revert event and self-heal. No `ledgerRevisionProvider` bump needed — a rejected write changes nothing server-side.

## 1. New module: `lib/core/services/late_write_notice.dart`

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../extensions/build_context_l10n.dart';
import '../utils/error_message_translator.dart';
import 'app_messenger.dart';

/// Presenter seam — swapped in tests. The default shows a SnackBar on the
/// root messenger; a null context/messenger (app tearing down, widget tests
/// without the root MaterialApp) makes it a silent no-op: the notice is
/// best-effort by the same contract as write_ack's late observer.
@visibleForTesting
void Function(Object error) lateWriteNoticePresenter = defaultLateWriteNoticePresenter;

/// Called by `awaitServerAck`'s late-failure observer. Kept trivially thin so
/// a presenter bug can never break the observer (see write_ack try/catch).
void notifyLateWriteFailure(Object error) => lateWriteNoticePresenter(error);

void defaultLateWriteNoticePresenter(Object error) {
  final ctx = appMessengerKey.currentContext;
  final messenger = appMessengerKey.currentState;
  if (messenger == null) return;
  // Mirror recovery_outcome_notice_provider.dart:44-58: l10n via the messenger
  // context with an EN-literal fallback, so the notice still fires in the
  // no-Localizations window rather than silently dropping the signal.
  String message;
  try {
    message = ctx == null
        ? _fallbackMessage
        : ctx.l10n.lateWriteFailedNotice(friendlyMessageFor(ctx, error));
  } catch (_) {
    message = _fallbackMessage;
  }
  messenger.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
  );
}

const String _fallbackMessage =
    "A recent change couldn't be saved. Please check and re-enter it.";
```

- No `action:` on the SnackBar ⇒ the #411 `persist` default-true trap is not engaged (it derives `persist = action != null`); 8s matches the established important-failure duration (blocked leave/remove sites).
- **Burst behavior (Gate r1 adversary P2, decided): NO `removeCurrentSnackBar` — notices QUEUE.** N rejections at reconnect (several invalid queued money writes) must produce N sequential notices, not last-wins collapse: under-reporting multi-write loss is the exact failure the feature exists to prevent. `ScaffoldMessenger` queues natively. (The one-shot `recovery_outcome_notice_provider` precedent uses removeCurrent safely because it fires once; this chokepoint fires per-write.)
- **No cache-isolation guard on purpose** (adversary P3): unlike `recovery_outcome_notice_provider.dart:87`, the presenter has no `ref` to read `cacheIsolationProvider` — and the state is unreachable: `outgoingShellProvablyEmpty` blocks every swap while the shell holds a group, and all money writes require a group, so no write can be pending-and-rejecting mid-swap.
- **`errorNetwork` cause phrasing** ("check your connection") is mildly off for a post-reconnect terminal error (adversary P3) — accepted: terminal replay rejections are in practice `permission-denied` (retryable network codes get retried by the SDK, not delivered terminally).
- `behavior:` NOT passed — both themes set `snackBarTheme.behavior: floating` (#419/#437); a per-call override is redundant by contract.
- Reset in tests: any test that swaps `lateWriteNoticePresenter` restores it in `tearDown` (module-level mutable seam, same discipline as mocked channels).

## 2. `lib/core/utils/write_ack.dart` — one addition inside `observeLate`

```dart
onError: (Object error, StackTrace stackTrace) {
  debugPrint('Queued write failed on replay: $error');
  unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  try {
    notifyLateWriteFailure(error);          // NEW — user-visible notice
  } catch (_) {
    // The notice is best-effort; a presenter bug must never break the
    // observer or re-enter Sentry with a secondary failure loop.
  }
  onLateError?.call(error, stackTrace);
},
```

- `onLateError` param KEPT unchanged (future per-site customization; the global notice makes the 0-callers state safe rather than silent).
- Ack/queued return semantics, `kWriteAckTimeout`, `skipWait` — byte-identical.
- Import: `../services/late_write_notice.dart`.

## 3. l10n — one new key, EN + AR

- `app_en.arb`: `"lateWriteFailedNotice": "A recent change couldn't be saved: {cause}"` (+ `@lateWriteFailedNotice` with `cause` placeholder, description noting it fires after reconnect when a queued write is rejected).
- `app_ar.arb`: `"lateWriteFailedNotice": "تعذّر حفظ تغيير حديث: {cause}"` (nominal, gender-neutral per #858 convention).
- Run `flutter gen-l10n`; commit generated files (the #245 trap).

## 4. Tests — RED first

1. `test/core/utils/write_ack_test.dart` additions:
   - timeout→late-rejection calls the presenter exactly once with the error (swap `lateWriteNoticePresenter` for a recorder; `Completer.completeError` after the queued return). RED: symbol doesn't exist yet.
   - `skipWait: true` path also reaches the presenter on rejection.
   - a THROWING presenter does not break the observer (no unhandled error, Sentry path still reached — assert via no test-framework error and the recorder-before-throw pattern).
   - existing acked/queued/propagate-in-window pins stay green untouched.
2. New `test/core/services/late_write_notice_test.dart` (widget): pump `MaterialApp(scaffoldMessengerKey: appMessengerKey, ...)` with l10n delegates; call `notifyLateWriteFailure(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'))`; expect a SnackBar with `l10n.lateWriteFailedNotice(l10n.errorPermissionDenied)` and NO `cloud_firestore` raw text; second test: no MaterialApp mounted ⇒ no-op, no throw.
3. Guards that stay green: `dark_snackbar_theme_test.dart` (theme-level floating behavior), all 4 `*_offline_412_test.dart` suites — add_expense, create_group, edit_expense, event_settings (ack semantics untouched — run them all).

## 5. Rollout

One PR (`fix/late-write-failure-notice`): this spec + module + write_ack edit + ARB pair + generated l10n + tests. Commit `fix(core): surface queued-write replay rejections to the user` with body describing the silent-loss failure mode; no issue to close (scorecard finding — reference the scorecard doc). `flutter analyze` clean, `bash tool/check_theme_purity.sh`, run: write_ack_test, late_write_notice_test, all `*_offline_412_test.dart`, dark_snackbar_theme_test, then the full suite in CI. `/automerge` (expect GATE-adjacent classification to land wherever the classifier says — `lib/core/utils/` is not on the denylist but classify honestly; the diff is display-only).

---

**Verification-principles record:** (1) Every touched surface is INBOUND — the notice renders a SnackBar; nothing feeds a write, no persistence, no IPC (Sentry capture pre-exists unchanged). (2) Concrete claims re-grepped @021f571e: chokepoint signature `write_ack.dart:31-35`, observer body :37-46, 19 callsites/0 onLateError, `appMessengerKey` def + mount, translator signatures :34/:64, ARB error keys :2253-2265. (3) Read-path per write-path: n/a — no data-shape change; the one new read is `appMessengerKey.currentContext`, consumer named (the presenter). (4) No model/schema fields touched — n/a. (5) Data contracts spelled: presenter signature `void Function(Object error)`, l10n key + placeholder named exactly, snack duration/behavior stated. (6) No arithmetic — n/a. (7) Orthogonal-axis probes: **lifecycle axis** — app killed before replay ⇒ notice lost, ACCEPTED and documented (pre-existing best-effort contract in write_ack's doc); **re-entrancy axis** — presenter throwing must not kill the observer (guarded + pinned by test); **locale axis** — cause phrase resolves from the CURRENT context locale at fire time, so a notice after a locale switch renders in the new locale (correct, not a bug); **theming axis** — no per-call `behavior` override per #419/#437 contract; **#411 axis** — no action ⇒ persist trap not engaged.

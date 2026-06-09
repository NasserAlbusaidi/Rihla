# Issue #370 — DeepLinkService cold-start seenKeys dedupe

## Problem

`app_links` can emit the same cold-start URI through **both** `getInitialLink()`
and `uriLinkStream` on a single cold start. `DeepLinkService.init` wires both:

- `uriLinkStream.listen((uri) => _openJoinLink(router, uri))`
- `await getInitialLink()` then `_openJoinLink(router, initialLink)`

Each emission that resolves to a valid join code calls `router.go(joinUri)`. With
no dedupe, the same cold-start invite link can fire `router.go` twice. Harmless
today (navigating to the same `/join/<code>` path twice is idempotent in
GoRouter), but it is an asymmetry vs. the email-recovery consumer
(`authEmailLinkBootstrapProvider`), which guards with a per-instance `seenKeys`
set (`auth_email_link_bootstrap_provider.dart:108/120`). The asymmetry is a
latent trap if join handling ever gains side effects.

## Fix (minimal, mirrors the email path)

Add a per-`DeepLinkService`-instance `final Set<String> _seenKeys = <String>{};`.
In `_openJoinLink`, after a non-null `parseJoinLink`, compute the dedupe key from
the **resolved join path** and short-circuit on a repeat:

```dart
void _openJoinLink(GoRouter router, Uri uri) {
  final joinUri = parseJoinLink(uri);
  if (joinUri == null) return;

  final target = joinUri.toString(); // e.g. '/join/ABC123'
  if (!_seenKeys.add(target)) return; // duplicate emission → ignore

  router.go(target);
}
```

### Key choice — resolved join path, not the raw URI

`parseJoinLink` already normalizes case/trailing-slash/path-vs-query into a
single canonical `/join/<UPPER>` path. Two emissions of the *same* cold-start
invite (e.g. one via `getInitialLink`, one via the stream) resolve to the
identical `target`, so keying on `joinUri.toString()` dedupes them. This mirrors
the email path's intent (`_dedupeKey` collapses on the stable `oobCode`), and is
strictly safer than keying on `uri.toString()` because app_links may surface the
two emissions with cosmetically-different raw URIs that still mean the same join.

`router.go` already passed `joinUri.toString()` today (line 68) — so reusing
`target` for both the key and the navigation is behavior-preserving for the
first emission.

## What this is NOT

- NOT a routing-tree change: no new routes, no redirect/back-guard edits,
  no `app_router.dart` touch. Only `DeepLinkService._openJoinLink` gains a guard.
- NOT a schema/money/rules change.
- Does NOT touch `authEmailLinkBootstrapProvider` (the email path keeps its own
  `seenKeys`; the CLAUDE.md double-fire trap lives there and is untouched).

## Read-path / write-path trace

- Only writer of the dedupe set: `_openJoinLink` (called from the stream listener
  and the cold-start `getInitialLink` branch — the two emission sources).
- Only reader: same method, the `add` return value. No persistence, no other
  consumer. Set lifetime == `DeepLinkService` instance lifetime (process-lifetime
  singleton in prod; fresh per test via `withAppLinks`).
- Downstream of `router.go(target)`: GoRouter `/join/:code` route (unchanged).

## Behavior preserved

- First cold-start emission still navigates (`add` returns true).
- Runtime stream links with distinct codes still navigate (distinct keys).
- A genuinely *new* invite arriving later in the same process (different code)
  navigates (distinct key). Re-opening the *same* code later is intentionally
  deduped — acceptable: the user is already on/just visited that join target,
  and the email-path precedent treats a repeat key as a no-op too.
- `dispose()` cancels the subscription; the set is not cleared because the prod
  instance is a process-lifetime singleton that is never re-init'd after dispose
  in practice, and tests use fresh instances. (No requirement to reset.)

## Tests (TDD, RED first)

New test in `test/unit/deep_link_service_test.dart`, `DeepLinkService.init` group:

1. **RED → GREEN (acceptance #2):** cold-start URI seen via *both*
   `getInitialLink` and the stream → assert `router.go('/join/ABC123')` is
   `.called(1)`, not 2. Drive `getInitialLink` to return the invite URI, then,
   after `init`, push the same URI onto the stream; pump; verify single `go`.

Existing tests must stay green (single-emission cold-start, runtime stream,
dispose, error reporting, no-duplicate-listeners).

## Verification

- `flutter analyze` clean (mark any const-eligible literal `const`).
- `flutter test test/unit/deep_link_service_test.dart`.

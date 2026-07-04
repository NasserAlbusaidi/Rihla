# ADR-0005 — Android install referrer only pre-fills invite joins

- **Status:** Proposed (2026-06-27)
- **Issue:** #368

## Context

Rihla's hosted invite page already redirects installed users through
`rihla://join/<CODE>` and sends not-yet-installed Android users to Google Play
with `referrer=${encodeURIComponent('code=' + code)}`, which appears in the
browser URL as `referrer=code%3DABC123`. The missing piece is the Android
consumer: after a Play install, first launch should recover that code and land
on the normal join screen.

The Play install referrer is not a trust boundary. It can be influenced by the
link the user opened before installing, and it can carry malformed or irrelevant
data. It also only exists for Google Play installs, not sideloads or future iOS
distribution.

## Decision

Use the Android Play Install Referrer API only as a **one-shot invite prefill**.
If the first launch referrer contains a valid six-character invite code, route to
the existing `/join/<CODE>` screen. Route prefill must not call
`joinGroupByInviteCode`, `listUnclaimedShadows`, `requestClaimShadow`,
`listMyClaimRequests`, create a local pending intent, or perform any
write/read-write side effect. Those paths remain behind existing explicit
join-screen user actions.

The explicit-link route has priority over the Play referrer even when Android's
link plugin reports the cold-start URI through the initial stream rather than
`getInitialLink()`. Bootstrap therefore waits for a bounded 50 ms initial stream
window and a bounded 250 ms initial-link lookup before deciding whether to
evaluate the Play referrer.

For install-referrer arbitration, recognized explicit links include invite join
links handled by `DeepLinkService`, `rihla://auth-link?...` fallback URLs, and
Firebase auth continue URLs accepted by `AuthEmailLinkConfig`. Auth links only
suppress the Play referrer; the existing auth email-link bootstrap remains the
component that handles them.

The Play referrer reader uses method channel
`com.safar.safar/install_referrer` and method `getInstallReferrer`. The parser
accepts query-string-only decoded `code=ABC123` and decode-once
`code%3DABC123` forms, trims and uppercases before validation, ignores unrelated
extra params, and rejects absolute URIs plus missing, malformed, or duplicate
`code` values. Malformed percent escapes are silent no-ops. The platform check
is injectable so CI can force Android for parser/routing tests and force
non-Android for no-op tests. The native read is bounded at 750 ms by default so
startup cannot hang on the Play service.

Install-referrer one-shot consumption is separate from AppLinks duplicate
emission dedupe. A Play referrer must not mark `/join/<CODE>` as permanently
seen for the process; if the user later opens the same real invite link, the
runtime AppLink should still navigate.

Cold-start work is ordered by one coordinator: explicit-link detection,
install-referrer consume/route, gate replay, then app bootstrap. Auth email-link
handling starts only after a valid suppressed Play referrer has been consumed,
so recovery restart cannot race the one-shot marker write. Boot-time
notification sync still runs, but initial notification-tap routing is skipped
when an explicit or deferred invite already navigated; later notification taps
continue to route normally.

The accepted safety model is the current post-#648 model: App Check on the
callable, 5/hour per-UID throttling, invite-code/name validation server-side,
and prefill-never-auto-submit client behavior. Do not rely on the old #441
anonymous-join reject; that gate was intentionally removed in #648.

## Rejected alternatives

1. **Silent auto-join from the referrer** — rejected because the referrer is
   attacker-controllable and would turn an attribution hint into authorization.
2. **Reintroduce an anonymous join gate** — rejected because it reverses #648's
   product decision: participation is allowed anonymously; creation and account
   recovery remain the durable-credential boundaries.
3. **Build an iOS clipboard fallback now** — rejected until an App Store build
   exists. The current production acquisition path is Android/Google Play only.

## Consequences

- The Android consumer must be one-shot. The persisted key is
  `installReferrerInviteConsumedCode`, and the value is the normalized code that
  successfully routed or was consumed without routing because a current explicit
  link won.
- A current explicit app/universal link should beat an older Play referrer on
  the same cold start.
- This includes explicit join links delivered by the app-links stream during the
  bounded initial cold-start window.
- Runtime re-opening of the same explicit invite link after the cold-start
  duplicate window still routes.
- Auth recovery restart and boot-time notification initial-tap routing cannot
  clobber a winning invite route.
- A deferred invite should still win initial notification handling on the same
  cold start; when a join wins, notification initial-tap routing is suppressed
  for that launch.
- A recognized auth link suppresses an older Play referrer without changing the
  auth-link completion flow.
- Invalid, missing, unsupported, or native-error referrers are silent no-ops.
- End-to-end verification requires a Play-delivered build; unit tests can cover
  parsing, bootstrap ordering, one-shot behavior, and source-level native bridge
  shape.

# #710 claimShadow per-shadow reservation

## Problem

Two different pending `claimRequests` can target the same shadow member. Before
this change, `decideClaimRequest` serialized only one request document, then ran
`claimShadowEngine` outside that transaction. Overlapping approvals for the same
shadow could therefore run two engines and leave a claimer-A / claimer-B torn
mix with no remaining shadow reference for the #558 shadow-reference scan to
catch.

## Implemented Shape

- Add server-only per-shadow lock docs at
  `groups/{groupId}/claimShadowLocks/{shadowMemberId}`.
- Add a non-identifying group freeze mirror:
  `claimingInProgress`, `claimLockedAt`, optional `claimMutationStartedAt`.
- Move approval into a reservation transaction:
  `pending -> claiming`, lock doc write, group freeze write, then engine call.
- Pass a lock token to `claimShadowEngine`; the engine verifies the lock and
  writes `claimMutationStartedAt` to the request, lock, and group immediately
  before Phase B child-document writes begin.
- Compare-release the lock and group freeze only after terminal request status.
- Reset/release pre-mutation failures back to `pending`; leave post-marker
  failures frozen for `claimShadowLockReaper`.
- Add `claimShadowLockReaper`:
  - stale pre-mutation reservations reset to `pending` and clear the freeze;
  - stale mutation-marked reservations resume the locked claim and release.
- Make `requestClaimShadow` preserve existing durable request fields and reject
  existing `claiming` requests without mutation.
- Update claim notifications for the new `claiming` transient state.
- Re-key itemized `splitExplanation` participant ids and recursive activity
  metadata on claim; scrub itemized explanation identity on account deletion.
- Add account-deletion mutual exclusion so active claim state preserves the Auth
  user for retry instead of deleting a pre-join claimant.
- Extend Admin writer guards, balance aggregate writes, `listUnclaimedShadows`,
  and Firestore rules to honor claim/account-deletion freezes.

## Verification Anchors

- `functions/test/callables/claimRequest.test.ts`
  covers lock reservation, pre/post-mutation failure behavior, lock-doc
  rejection, and request-field preservation.
- `functions/test/scheduled/claimShadowLockReaper.test.ts`
  covers stale pre-mutation reset and mutation-marked resume.
- `functions/test/callables/claimShadow.test.ts`
  covers itemized split re-key and recursive activity metadata re-key.
- `functions/test/callables/deleteAccount.test.ts`
  covers itemized deletion scrub, scrub sentinel, and active pre-join claim
  state blocking Auth deletion.
- `functions/test/firestore-rules-publish-readiness.test.ts`
  covers deny-all `claimShadowLocks`, freeze write rejection, and scrub sentinel
  rule compatibility.

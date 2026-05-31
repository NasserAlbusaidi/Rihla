# ADR-0001 — Settlement names are live-resolved with a snapshot fallback

- **Status:** Accepted (2026-05-31)
- **Issue:** #48 (was P1 "stale names after rename" → P3 decision)

## Context

`groups/{gid}/settlements` (and event settlements) persist `payerName` /
`recipientName` snapshots, and the collections are hard append-only
(`allow update: if false; allow delete: if false`, the B3 invariant —
corrections are new offsetting rows). The original concern: after a member
renames, those stored names can never be corrected, so a money app would show
permanently stale names on settlement history.

## Decision

Accept and document the current behavior: settlement names are **live-resolved
from current member docs, with the stored snapshot used only as a fallback.**

Every *active* render path resolves the live `displayName`:
- Event ledger → `MemberNameResolver.resolveEventScoped(...)`
- Group settle-up / balances → `MemberNameResolver.resolveGroupScoped(...)`

`member_name_resolver.dart` returns the current member's `displayName` when the
uid is still a live member, a tombstone name if they left as a tombstoned
member, and only then the stored `payerName`/`recipientName` snapshot. So a
renamed-but-still-present member always shows the current name. The snapshot is
the **former-member / offline fallback**, not the display source.

## Rejected alternatives

1. **Stop denormalizing names on settlements** — would remove the fallback that
   keeps a departed member's name renderable and would couple every settlement
   render to a live member lookup. Net loss.
2. **Add a rule-gated update path for name reconciliation** — breaks the B3
   append-only invariant (the financial audit trail) for a purely cosmetic gain
   that the live-resolve already delivers.

## Consequences

- The denormalized snapshot keys stay required in `firestore.rules`; append-only
  stays. The only residual "stale" case is a member who has *left* the group —
  acceptable, since live resolution is no longer possible for them.
- The one widget that read the raw snapshot (`RecordedSettlementsSection`) was
  dead and is already removed.
- Shared validator already extracted (`validSettlementCore`, #72); removal of the
  `eventId == groupId` group-scope sentinel is tracked separately in #71.

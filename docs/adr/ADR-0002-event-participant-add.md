# ADR-0002 — Any event participant may additively add members

- **Status:** Accepted (2026-05-31)
- **Issue:** #57 (P3 decision)

## Context

`validEventLightUpdate` (`security/firestore.rules`) lets **any current event
participant** additively add other members to an event (`participantIds` /
`participantNames`), while removing and renaming are blocked on the light path.
Combined with the join fan-out, the question was whether this is a griefing
vector or an intentional collaboration rule.

## Decision

Keep additive participant-add as the **intended collaboration model.** Events are
collaborative; the people on a trip routinely add each other, and requiring an
admin for every add is friction with no payoff for a solo-friendly trip app.

**Abuse boundary (verified against code):** added IDs are constrained to
**existing group members.** The light path runs
`requesterIsParticipant()` → `validEventUpdateCommon()` → `validEventBase()`,
and `validEventBase` enforces `participantIds.hasOnly(groupMembers())`. So the
blast radius is *in-group* griefing (a member spuriously adding another member to
an event), never outsider injection. Removal and rename of participants remain
admin-only (`validEventAdminUpdate`). The join fan-out
(`joinGroupByInviteCode`) is a **self**-add by the joiner, not a third-party add.

## Rejected alternative

Restrict event-participant mutation to event/group admins or a controlled
callable. Over-restrictive for the collaboration model, and there is no observed
abuse to justify the friction.

## Consequences

- Documented in `docs/SECURITY-RULES.md` under the light-update path.
- If abuse ever emerges, the tightening is to move adds behind
  `validEventAdminUpdate` or a callable — **not** to widen `validEventLightUpdate`.

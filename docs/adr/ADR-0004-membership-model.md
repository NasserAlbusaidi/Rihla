# ADR-0004 — Shadow members: creators add members by name at creation

- **Status:** Accepted (2026-06-05)
- **Issue:** #278 (P2, `decision`)

## Context

**Historical note:** this context records the pre-implementation state from
2026-06-05. The decision has since shipped: `addShadowMember` creates
server-minted shadow members, and `requestClaimShadow` / `decideClaimRequest`
drive the creator-approved claim flow.

`createGroup` writes a **single** member doc — the creator's — and there is no
add-member-by-name UI anywhere (`group_provider.dart:99-160`; the create screen
has only group-name + your-name fields). Every other person must self-install
and join via invite code, so a freshly created group is a **group of one** and
nothing can be split until others act. For a Splitwise-refugee, non-tech-savvy
cohort splitting *tonight's* dinner, the app fails to do its job on first
session.

At the time, the data model already half-supported the alternative:
`GroupMember.isShadow`
exists (`group_member_model.dart:15`) and the split UI already renders a
**"Shadow Profile"** label for shadow participants
(`split_scope_selector.dart:320`). But shadow creation was not wired:
`createGroup` hardcoded `isShadow:false` (`group_provider.dart:159`) and the
add-participant grep returned nothing. It was a dormant, half-built feature, not
a decided-against one.

## Decision

Adopt the **Splitwise-style shadow-member model.** At creation (and later) the
creator may add other members **by name**; each becomes a real `GroupMember`
with `isShadow:true` — a placeholder with no UID. Expenses can be split against
shadow members immediately, so a group is usable on first session without
waiting for anyone else to install. This activates the dormant `isShadow` field
and the existing "Shadow Profile" label.

A real person later **claims** a shadow: they join via the invite code, are
matched to a placeholder ("Are you Ali?"), and their UID is merged onto that
member — re-keying the member doc and any `splitDistribution` / payer /
settlement references from the placeholder id to the real UID.

## Rejected alternative

**Name-based self-join only** (status quo): no add-by-name; nobody enters the
ledger until they self-join by code, and the group-of-one problem is attacked
purely through the invite funnel (#276/#277) plus push notifications
(#288/#179). Rejected because it leaves the creator unable to split the very
first expense — the core job — until friends install and join. Choosing this
path would have meant deleting `isShadow` + the "Shadow Profile" label as dead
code and closing #278 won't-do.

## Consequences

- **Implemented after this ADR.** The shipped build uses server-minted shadows
  (`addShadowMember`) and creator-approved claim requests
  (`requestClaimShadow` → `decideClaimRequest`).
- **The claim/merge path is a money + schema write-path** (re-keying
  `splitDistribution` keys, payer ids, settlement parties from placeholder →
  UID). It went through the Gate and must continue to respect the
  `calculateBalances` parity contract and the member-doc-keying history flagged
  in #294/#524: new client-created members key by `{uid}`, legacy creator docs
  and server-minted shadows can be uuid-keyed, so match members by the `userId`
  field, never the doc id.
- Uniqueness/disambiguation becomes load-bearing: duplicate display names are
  already possible and the disambiguator (#196) is only wired into 2 of ~6
  surfaces. A claim flow that asks "which name are you?" intersects #279
  (prevention) and #289 (display); those should be resolved alongside.
- The old CLAUDE.md "Name-based members" invariant correction was superseded by
  the shipped creation + claim paths.

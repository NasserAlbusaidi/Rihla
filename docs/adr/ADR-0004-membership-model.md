# ADR-0004 — Shadow members: creators add members by name at creation

- **Status:** Accepted (2026-06-05)
- **Issue:** #278 (P2, `decision`)

## Context

`createGroup` writes a **single** member doc — the creator's — and there is no
add-member-by-name UI anywhere (`group_provider.dart:99-160`; the create screen
has only group-name + your-name fields). Every other person must self-install
and join via invite code, so a freshly created group is a **group of one** and
nothing can be split until others act. For a Splitwise-refugee, non-tech-savvy
cohort splitting *tonight's* dinner, the app fails to do its job on first
session.

The data model already half-supports the alternative: `GroupMember.isShadow`
exists (`group_member_model.dart:15`) and the split UI already renders a
**"Shadow Profile"** label for shadow participants
(`split_scope_selector.dart:320`). But **no write path ever creates a shadow
member** — `createGroup` hardcodes `isShadow:false` (`group_provider.dart:159`)
and the add-participant grep returns nothing. It is a dormant, half-built
feature, not a decided-against one.

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

- **Not implemented by this ADR.** This records direction only; the build is a
  separate, larger piece of work.
- **The claim/merge path is a money + schema write-path** (re-keying
  `splitDistribution` keys, payer ids, settlement parties from placeholder →
  UID). Per the Operating Contract it is **Gate-mandatory** before
  implementation, and it must respect the `calculateBalances` parity contract
  and the member-doc-keying inconsistency flagged in #294 (creator doc keyed by
  random uuid with `userId:uid`, joiners keyed by `{uid}` — match members by the
  `userId` field, never the doc id).
- Uniqueness/disambiguation becomes load-bearing: duplicate display names are
  already possible and the disambiguator (#196) is only wired into 2 of ~6
  surfaces. A claim flow that asks "which name are you?" intersects #279
  (prevention) and #289 (display); those should be resolved alongside.
- The CLAUDE.md "Name-based members" invariant correction is **already in flight**
  on `docs/name-based-members-correction` (#294) and stands regardless of this
  ADR — it documents *today's* code (creator adds only self; joiner free-types).
  When the shadow-member build lands, that invariant is updated again to
  describe the new creation + claim paths.

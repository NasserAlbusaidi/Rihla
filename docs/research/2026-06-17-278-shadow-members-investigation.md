# #278 Shadow Members — Investigation & Build Map (2026-06-17)

> Multi-agent investigation (6 cluster investigators + synthesis), verified live against `main`.
> Replaces the never-committed `docs/research/2026-06-15-278-shadow-members-research.md` (a ghost-doc cited in the #278 thread but never on disk).
> Scope **DECIDED by owner (2026-06-17): Full** — add-by-name **and** claim/merge-on-join. Delivery is incremental: the add-by-name (Minimal) slices ship first; claim/merge follows as Gate-heavy fast-follow.

## Decisive facts (verified, do not re-litigate)

1. **A shadow MUST be in `groups/{gid}.memberIds`** to participate. Event expenses gate `participantIds.hasOnly(groupMembers()==memberIds)` (`firestore.rules:367`); split-keys (`:477`), payer (`:548`), customSplit (`:554`), settlement payer/recipient (`:886-887`) all chain off membership. A member id outside the balance universe is silently dropped (`#249` contract).
2. **`memberIds` is fully server-authoritative.** Client group-update allows only `validCreatorMetadataUpdate` (name) or `validMemberIdsRefresh` which requires `memberIds` **unchanged** (`:308`). #524 (`:782-783`) requires a member doc's `id == userId == auth.uid`. → **Shadow create MUST be an Admin-SDK callable**, never a client rules carve-out (a carve-out reopens the #524 forged-member hole).
3. **Oracle is identity-blind.** `0 isShadow` in `groupNetBalance.ts` and `expense_provider.dart`. A placeholder uuid (non-empty String `userId`, `isTombstone:false`, present in memberIds + each event's participantIds) is counted in balances with **no oracle change**.
4. **`removeMember.ts` is identity-blind** — validates `targetUserId` as any non-empty slash-free string, matches by `where('userId','==',targetUserId)` (`:107`), creator-gated (`:90`), per-currency net==0 gate (`:131`), `arrayRemove` (`:163`). A zero-balance placeholder is removable by the creator **today** → reuse it; no new removal callable.
5. **The SUM-on-collision map re-keyer `mergeUidMapKey` was deleted (#441)** — only `renameMapKey` (OVERWRITE, `deleteAccount.ts:269`) survives. A claim re-keying `splitDistribution` where the claimer already holds a slice would **silently lose money**. The claim path must restore the SUM variant. Arrays reuse `replaceUid` which **already dedups** (`deleteAccount.ts:220`) — only the map needs the new helper.

## Surface map — ADD-BY-NAME (Minimal, ships first)

| # | Surface | Where | Change |
|---|---|---|---|
| A1 | **`addShadowMember` callable (NEW)** | `functions/src/callables/`, export in `index.ts` | Admin-SDK: creator-gated (`group.createdBy===uid`), reject anon, enforceAppCheck, validate displayName (reuse `normalizeDisplayName`), #279-style collision check, mint uuid, `tx.set(members/{uuid},{id:uuid,userId:uuid,isShadow:true,role:'MEMBER',displayName,joinedAt})`, `arrayUnion(uuid)` into memberIds. **GATE.** |
| A2 | Shadow removal — **REUSE `removeMember`** | `removeMember.ts` | No new callable. Zero-balance shadow removable by creator today; non-zero correctly refused. |
| A3 | **No firestore.rules change** for ADD | — | `isShadow` already in member-create allow-list (`:773`) + bool-checked (`:789`); Admin SDK bypasses `:782-783`. |
| A4 | Add-by-name chips at create | `create_group_screen.dart` | "Who's in?" chips → after `stageGroup` ack, call `addShadowMember` per chip. **Requires connectivity** (callables don't offline-replay). |
| A5 | In-group add-shadow + shadow badge | `group_members_section.dart` (dead `groupManage` header), `group_settings_screen.dart` | Wire Manage → add-shadow sheet; shadow pill on member tiles. |
| A6 | Event participant picker | `event_participants_card.dart` | Shadows already appear (no isShadow filter); add pill + disambiguation. Adding an in-memberIds shadow to `event.participantIds` is a legal client write (`:430-431` additive + `:367` hasOnly(memberIds)). |
| A7 | Make `editorShadowProfile` LIVE | `split_scope_selector.dart:20-30,334-342` | The only existing isShadow UI is **dead** — `_eventParticipants` defaults `isShadow:false`. Thread `GroupMember.isShadow` (by userId) so the subtitle renders. |
| A8 | Shadow flag in custom split | `custom_split_sheet.dart` | Add optional `isShadow` to `SplitParticipant`. |
| A9/A10 | No oracle / no #366 trigger change | — | Triggers self-heal (member-doc create → T4; participantIds → T3). |

**Add-path owner constraints (judgment calls, v1):** creator-only shadow add (aligns with "one person logs"); both create-time + in-group; event fan-out is **opt-in per event** via the existing participant picker (no retroactive auto-fan-out).

## Surface map — CLAIM/MERGE (fast-follow, gated on owner decisions)

| # | Surface | Change |
|---|---|---|
| B1 | **`claimShadow` callable (NEW)** | Re-key engine modeled on `deleteAccount.ts` Phase-B/C, tx-serialized on the shadow doc (`isShadow && !claimed`), guard `isDeleted/deletingInProgress`, reject anon, require caller already a member. |
| B2 | **`mergeUidMapKey` SUM-on-collision (NEW/restored)** | For `splitDistribution` only. Table-driven money tests mandatory. |
| B3 | Arrays reuse `replaceUid` | Already dedups — no new array de-duper. |
| B4 | In-callable parity assert | Post-re-key `recomputeNet` net == priorShadowNet + priorClaimerNet per currency, else abort. |
| B6 | Claim picker on join | Shadow list **cannot** be read client-side pre-join (member-gated `:312/:815`) → comes via callable payload (join result or `listUnclaimedShadows`). |
| B7 | Claimed member doc | Copy→`{uid}` doc + delete uuid doc (deleteAccount precedent), **set `isShadow:false`**. |

### Claim re-key field list (ordered, `memberIds` LAST)
Phase B (batched, BatchWriter ≤450/flush, idempotent): 1) event `participantIds` (`replaceUid`) · 2) event `participantNames` (`renameMapKey` — display names, overwrite-safe) · 3) **expense `splitDistribution` ★SUM** · 4) expense `payerParticipantId` (scalar) · 5) expense `customSplitParticipants` (`replaceUid`) · 6) expense `createdBy` · 7) event settlements payer/recipient/createdBy (Admin update, bypasses append-only) · 8) group settlements same · 9) activity logs `actorId`/`targetParticipantId` (best-effort). Phase C (tx): 11) member doc copy+delete, `isShadow:false` · 12) group `createdBy` (defensive) · 13) 🔴 `group.memberIds` arrayRemove(uuid)+arrayUnion(uid) **LAST**. Then parity assert.

## Claim-auth — owner decisions required before the CLAIM spec is Gated

Recommended model: **creator-approval** (creator typed the name; the trust anchor already exists, `removeMember.ts:90`) + a **"no — I'm new" escape hatch** (join as a fresh member). A self-select claim gated only by the re-shareable invite code is the rejected Option-E impersonation hole (`memory 27034`).

- **D1 Solo-group claim** — creator-approval enough, or per-shadow claim-code?
- **D2 Claimer-already-has-a-slice** — SUM the positions (→ `mergeUidMapKey` is the success path) or REJECT?
- **D3 Reversibility** — un-claim allowed (no new activity since) or final? (settlements append-only → wrong claim on a high-debt shadow = worst-case loss.)
- **D4 Member-doc disposition** — copy+delete vs userId-field swap in place.
- **D6 Anon claimer** — require durable account to claim (recommend yes).

## Top risks the spec + Gate must neutralize
- **P1 money-clobber on claim** → restore SUM-on-collision (`mergeUidMapKey`); table tests clean/claimer-present/claimer-is-payer.
- **P1 Admin-SDK-only** → no client carve-out for add/claim/remove (reopens #524 forgery).
- **P1 claim impersonation** → creator-approval + D1.
- **P1 shadow dropped from balances** if not in memberIds AND each event.participantIds → addShadowMember arrayUnion + parity test.
- **P1 claim atomicity / two-phantom-identity** → BatchWriter chunk, memberIds-LAST, idempotent, tx-serialized.
- **P2** double-claim race; offline half-state at create; #279 collision guard inverts on the claim path; non-creator removal gap (only if non-creators may add).

## PR-slice sequence
**Add-by-name (ship first):** PR1 `addShadowMember` callable (GATE) · PR2 add-by-name chips at create (exempt) · PR3 in-group add + shadow badge (exempt) · PR4 thread isShadow into split/payer pickers (exempt) · PR5 oracle parity test — shadow split/payer/settle (GATE, RED-first).
**Claim/merge (fast-follow, after D1–D6):** PR6 `mergeUidMapKey` SUM helper (GATE) · PR7 `claimShadow` re-key engine (GATE) · PR8 claim authorization (GATE) · PR9 claim picker on join (GATE).

**Gate this feature** — money + rules + Functions auth + schema field-name re-key (4/4 Gate categories). Spec authored per-slice; `/run-the-gate` before code.

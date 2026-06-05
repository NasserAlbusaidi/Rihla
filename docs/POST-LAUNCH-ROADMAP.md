# Post-Launch Roadmap

**As of 2026-06-05 — v1.4.0+21 on Play "first" track.** This is a navigable map of the open backlog after the 1.0/1.4 launch, grouped by *root-cause cluster* (theme) and layered onto the existing *phase* milestones.

> This doc is a planning overlay, not a source of truth for issue state. Each issue is canonical for its own scope. When this doc and an issue disagree, the issue (and the code) win — fix the doc.

## Two axes

- **Phase** = GitHub **milestone** (`1.0 release readiness` · `Post-launch hardening` · `Post-release features` · `Backlog`). *When* it happens.
- **Theme** = GitHub **`cluster:*` label**. *What architectural problem* it belongs to. Filter a cluster with e.g. `gh issue list --label cluster:money-trust`.

An issue carries one milestone and (usually) one cluster label. The two compose; neither was collapsed into the other.

## Verified state snapshot (code/git truth, 2026-06-05)

These were checked against `origin/main` and the GitHub API, not issue text — several issues are partly shipped:

- **#219** (Node 22) — code done on `chore/issue-219-node22-runtime`; **PR #268 is OPEN, not merged.** One merge away.
- **#223** (server-side split validation) — the **sign/negative half shipped** (`firestore.rules:492` `splitValuesNonNegative`, wired into create `:572` + update `:626`, 5 passing emulator tests). The **sum-within-tolerance half is genuinely unbuilt** and *cannot* be a rules predicate (CEL has no numeric fold over map values) — it needs a callable chokepoint or an onWrite remediation trigger, an architecture decision. Stays open, re-scoped to that decision.
- **#244** (partial-balance bug) — money-safety half **shipped** (PR #253: `groupFailedEventIdsProvider` + "balance may be incomplete" banner on the OUTBOUND group settle-up surface). Home-hero is already loud-safe (full error card, never a wrong number). What's open is the *graceful-partial* UX polish on the home hero — needs the Gate on the once-path.
- **#220** (#194 tail) — money/correctness tails **shipped** (PR #252: allocator negative guard + settlement read-fence). Open work is only the client free-text validator + inline editor feedback (pure UX).
- **#40** (RD-QA matrix) — 2026-06-05 RD-QA ran **9/9 on a debug build** with an emulator standing in for RD-04; `RIHLA_REAL_DEVICE_QA_READY` left unset, so the release gate stays red. Closing it needs a real-device pass against a release AAB.
- **PR #44** (codex auth-recovery hardening) — stale-open since 2026-05-28, `mergeable=UNKNOWN`. Decide: rebase+land or close.

All dependency parents are closed: #61 (OMR-only 1.0), #192/#193 (rules value-domain), #216 (recovery ledger migration), #247 (attribution decoupling), #249 (conservation drop), #126 (RTL back-arrow), #41 (backend deploy).

---

## Phasing

### Phase 0 — Quick wins (no Gate, do first)
- **#219** — merge PR #268 (Node 22). Hard deadline 2026-10-30 (deploys break after), but it's already done.
- **#251** — reword the "minimum transactions" claim in `README.md:13` + `docs/ARCHITECTURE.md:383` to "greedy heuristic, conservation-correct, near-optimal." Docs-only, no Gate. *Do NOT* build an n≤8 solver — 4/5 panelists agreed it's the wrong axis.

### Phase 1 — Correctness & safety (`Post-launch hardening`)
The trust boundary and the recovery machinery are where being silently-wrong costs the most. Highest leverage post-launch.
- **Cluster B · money-trust** — #223, #248, #244, #220
- **Cluster D · recovery-backend** — #217, #76, #170

### Phase 2 — Growth / retention arc (`Post-release features`)
- **Cluster C · settlement-ux** — #245 (activation) → #200 / #202 (auditable dividend) → #203 / #204 / #180 (expense trust + insights)

### Phase 3 — Multi-currency (`Post-release features`)
- **Cluster A · multi-currency** — #261 (aggregation design = the gate) → #70 / #242 fall out once a non-OMR write path exists

### Ongoing / opportunistic
- **Cluster E · schema-debt** — #71, #246 (+#219 once merged)
- **Performance (measure-first)** — #106, #113 — both blocked on a real-device `--trace-startup` / DevTools trace; not actionable without it
- **Release QA** — #40, #140 — fold #140 (offline font render + AAB size) into the next real-device pass
- **#179** — transactional FCM push (standalone feature track)

---

## The clusters

### A · Multi-currency end-to-end · `cluster:multi-currency`
**Root cause:** the aggregation layer (`paidMap`/`owedMap`/`computeGroupBalances`, and the TS `deleteGroup` `recomputeNet` oracle) sums `Decimal`s with **no currency dimension** — a mixed-currency group computes nonsense (10 USD + 10 OMR = "20"). `MoneySerializer`/`BalanceCalculator` are already per-expense-currency-correct (#47); the missing piece is one design decision: **one-currency-per-group** (simplest) vs **per-currency buckets**. No FX in scope.

| Issue | Milestone | Note |
|---|---|---|
| **#261** | Post-release features | The aggregation-design master. Decide the model + wire write paths + restore the currency picker. **Gate.** |
| #70 | Post-launch hardening | Display sites still assume OMR (3dp / literal `'OMR'`). Latent until a non-OMR write exists. |
| #242 | Post-release features | Split-preview WYSIWYG — depends on un-hardcoding `_tripCurrency`. **Gate.** |

### B · Server-side money trust boundary · `cluster:money-trust`
**Root cause:** the write/read trust boundary is thinner than the money invariants the client enforces — forged or partial data can still surface wrong or misleading money. `firestore.rules` only checks shape, not all values.

| Issue | Milestone | Note |
|---|---|---|
| #223 | Post-launch hardening | Server-side `sum==amount` within tolerance. Not a rules tweak — callable vs trigger arch decision. **Gate.** |
| #248 | Post-launch hardening | Widen edit/delete from creator-only → creator+payer+leader (rules authz). Unblocked by #247. **Gate.** |
| #244 | Post-launch hardening | Home-hero graceful-partial signal (money-safety already shipped PR #253). **Gate.** |
| #220 | Post-launch hardening | Client free-text validator + inline editor feedback (pure UX; rules half already deployed). |

### C · Cross-event settlement & event-lifecycle UX · `cluster:settlement-ux`
**Root cause:** the group→event tier costs activation tax that only pays off if the cross-event settle-up / closeout *dividend* ships — this is literally #245's "open decision." One product arc, sequenced activation → dividend → trust.

| Issue | Milestone | Note |
|---|---|---|
| #245 | Post-release features | Auto-seed a default event + skip the hub for single-event groups (activation). **Gate** (routing). |
| #200 | Post-release features | Explicit, auditable cross-event group settle-up (persist breakdown, correction flow). |
| #202 | Post-release features | Event closeout summary + shareable recap (needs an explicit event-closed state, not date-derived). |
| #203 | Post-release features | Itemized split helper (writes exact split + explanation metadata; no new algorithm). |
| #204 | Post-release features | Pre-settlement review sheet for unusual expenses (non-blocking). |
| #180 | Post-release features | Spending insights per event/group (derived, zero new listeners). **Gate** (new arithmetic). |

### D · Recovery / deletion backend completeness · `cluster:recovery-backend`
**Root cause:** the anon-recovery + account-deletion machinery has server-side completeness gaps — each a follow-up to already-shipped recovery work.

| Issue | Milestone | Note |
|---|---|---|
| #217 | Post-launch hardening | Migrate activity-log `actorId`/`metadata` oldUid→newUid (follow-up to #216; migrate-not-scrub; inert but a defect-class match). |
| #76 | Post-launch hardening | deleteAccount reaper for abandoned/timed-out deletions + `revokeRefreshTokens` before deleteUser (the one-liner is the cheap carve-out). |
| #170 | Post-launch hardening | Firestore TTL on `recoveryCleanupIntents.expiresAt` (needs `expiresAt` on the write path + rules). **Gate.** |

### E · Runtime & schema hygiene · `cluster:schema-debt`
**Root cause:** latent runtime/schema-shape debt, not user-visible, but it rots.

| Issue | Milestone | Note |
|---|---|---|
| #219 | Post-launch hardening | Node 20→22. **PR #268 open** — merge. |
| #71 | Backlog | Replace `eventId==groupId` sentinel on group settlements with explicit representation (schema migration). **Gate.** |
| #246 | Post-launch hardening | `modules.ledger` is a phantom toggle — no read path filters by it. Prefer **delete** `EventModules` (Phase-39 reality) unless a near-term feature needs it. |

### Not clustered (covered by existing labels / standalone)
| Issue | Milestone | Why no cluster |
|---|---|---|
| #40 | 1.0 release readiness | Release-process gate. Filter via `qa`+`release-blocker`. |
| #140 | Backlog | Folds into the next real-device QA pass. Filter via `qa`. |
| #106, #113 | Post-launch hardening | Perf, measure-first. Filter via `performance`. |
| #179 | Post-release features | Transactional FCM push — standalone feature, its own track. **Gate.** |
| #149 | Backlog | Design KEEP guardrail — a reference, not work. Stays open by its own acceptance criteria. |
| #251 | Backlog | Docs-only quick win (Phase 0). |

---

## Dependency graph (open work only)

```
#261 (multi-currency aggregation design) ──unblocks──▶ #70, #242
#247 (closed) ─────────────────────────────unblocks──▶ #248
#216 (closed) ─────────────────────────────follow-up─▶ #217
#245 (activation) ──makes-worth-it──▶ #200, #202   (the #245 "open decision")
#179, #223 may share a Functions trigger/callable scaffold
```

## Gate reminder

Per CLAUDE.md, every cluster issue marked **Gate** runs a fresh-context Opus subagent against the spec *before* implementation (`/run-the-gate`) — money math, `firestore.rules`/Functions auth, routing, or a read+write schema change. The non-Gate work (#220 UX, #251 docs, #246 delete, #71 is Gate, perf measurement) is exempt only where it's a one-sentence diff with no money/route/schema/rules surface.

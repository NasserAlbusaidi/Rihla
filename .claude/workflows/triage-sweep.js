export const meta = {
  name: 'triage-sweep',
  description: 'Revalidate open issues against LIVE code (still repros? severity right? secretly fixed by an adjacent merge?), then route every close verdict through an adversarial refuter before recommending it. The PICK-stage rigor guard — keeps stale, mis-prioritized, or already-fixed issues from sitting in a milestone forever, and stops a half-done issue from being closed (the #223 near-miss, applied to triage).',
  phases: [
    { title: 'Investigate', detail: 'one investigator per issue — verdict verified against live code, not issue text' },
    { title: 'Refute', detail: 'fresh skeptic tries to break each close verdict before it is recommended' },
  ],
}

// USAGE: Workflow({ name: 'triage-sweep', args: { issues: [{number, title}, ...] } })
//   or args: { issues: [70, 106, 113, ...] }. The CALLER supplies the issue list
//   (e.g. from `gh issue list --milestone "Post-launch hardening"`) so scope is
//   explicit and the run is deterministic. Each investigator fetches + verifies its
//   own issue against the tree. Any close-* verdict then goes through an independent
//   refuter before the workflow blesses it. Returns { closeCleared, closeBlocked,
//   keepOpen }. ONLY act on `closeCleared`; `closeBlocked` = refuted/unverified → human.

if (!args || !Array.isArray(args.issues) || args.issues.length === 0) {
  throw new Error('triage-sweep needs args.issues = [{number, title}, ...] (or [number, ...])')
}
const issues = args.issues.map((i) => (typeof i === 'object' ? i : { number: i, title: `#${i}` }))

// Verdicts that would CLOSE an issue — irreversible-ish (re-opening loses the thread),
// so each must survive a refuter, mirroring verified-sweep's destructive set.
const CLOSE_VERDICTS = new Set(['close-already-done', 'close-obsolete', 'close-wontfix'])

const INVESTIGATE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['number', 'title', 'verdict', 'stillRepros', 'severity', 'effort', 'gateRequired', 'evidence', 'rationale'],
  properties: {
    number: { type: 'number' },
    title: { type: 'string' },
    verdict: {
      type: 'string',
      enum: ['still-valid', 'reprioritize', 'close-already-done', 'close-obsolete', 'close-wontfix', 'needs-spec', 'blocked-by-dep'],
    },
    stillRepros: { type: 'boolean', description: 'does the described bug/gap still exist in live code on main right now' },
    severity: { type: 'string', enum: ['P0', 'P1', 'P2', 'P3', 'none'], description: 'severity AS VERIFIED against code (may differ from the issue label)' },
    effort: { type: 'string', enum: ['trivial', 'small', 'medium', 'large'] },
    gateRequired: { type: 'boolean', description: 'touches money math / firestore.rules / Functions auth / routing / schema field-name with read+write path' },
    correctedPriority: { type: 'string', description: 'if reprioritize: the corrected severity/effort and why; else empty' },
    blockingIssue: { type: 'string', description: 'if blocked-by-dep: the # it waits on; else empty' },
    evidence: { type: 'string', description: 'exact code paths:lines / grep hits / git SHAs proving the verdict — NOT a restatement of the issue text' },
    rationale: { type: 'string' },
  },
}

const REFUTE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['refuted', 'confidence', 'reason', 'evidence', 'residualWork'],
  properties: {
    refuted: { type: 'boolean', description: 'true = the close verdict does NOT hold (keep the issue open); false = verdict survives, safe to close' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    reason: { type: 'string' },
    evidence: { type: 'string', description: 'the unmet acceptance box / still-reproducing code path / live premise found — or proof none exists' },
    residualWork: { type: 'string', description: 'if refuted, the work that remains; else empty' },
  },
}

const VERIFY_MANDATE = `You are triaging open issues in the Rihla Flutter repo. This project's signature failure mode is trusting "done"/"stale"/"safe" claims that don't hold against code. Verify EVERYTHING against the ACTUAL tree (Read/grep/git/gh yourself), never the issue text or a memory note:
- "close-already-done" requires: the fix is on main AND every acceptance box of the issue is met. Half-met = NOT already-done (a half-done #223 almost got closed this way — sign-validation shipped, sum-validation never written).
- "close-obsolete" requires: proof the premise is gone (the feature was removed in a named phase/PR, or another issue supersedes it) — cite it.
- "close-wontfix" is ONLY valid when the issue's own premise is code-falsifiable. A judgment call you cannot verify (e.g. "perf is negligible" without a measurement you can't run) is NOT wontfix — return needs-spec instead.
- Any cited SHA: 'git cat-file -t <sha>' + 'git merge-base --is-ancestor <sha> main'.
evidence MUST be concrete (paths:lines, SHAs, grep hits). Return the strict schema.`

const investigatePrompt = (iss) => `${VERIFY_MANDATE}

Triage open issue #${iss.number}: ${iss.title}

1. Read it: \`gh issue view ${iss.number}\`.
2. Verify its central claim against the LIVE tree on main — open the cited files, grep the symbols, scan 'git log' for an adjacent fix that already landed. Does the bug/gap STILL exist right now? Set stillRepros.
3. Pick exactly one verdict:
   - still-valid     : repros, keep open as-is.
   - reprioritize    : repros, but the issue's stated severity/effort is wrong vs code — put the corrected values in correctedPriority.
   - close-already-done : fixed on main; cite the SHA/PR and confirm EVERY acceptance box is met.
   - close-obsolete  : premise no longer holds (feature removed / superseded) — cite proof.
   - close-wontfix   : only if the premise is code-falsifiable (not an unverifiable judgment call); else needs-spec.
   - needs-spec      : real but underspecified, or needs a measurement/decision before action.
   - blocked-by-dep  : gated by another open issue — name it in blockingIssue.
4. evidence = concrete proof (paths:lines, SHAs, grep), never the issue text restated.`

log(`Triaging ${issues.length} issue(s): ${issues.map((i) => '#' + i.number).join(', ')} → investigate, then refute every close verdict before recommending it`)

phase('Investigate')
const investigations = await parallel(
  issues.map((iss) => () =>
    agent(investigatePrompt(iss), { label: `triage:#${iss.number}`, phase: 'Investigate', schema: INVESTIGATE_SCHEMA, agentType: 'Explore' })
  )
)
const assessed = investigations.filter(Boolean)

const closeTargets = assessed.filter((a) => CLOSE_VERDICTS.has(a.verdict))
const keepOpen = assessed.filter((a) => !CLOSE_VERDICTS.has(a.verdict))
log(`${assessed.length} assessed; ${closeTargets.length} close verdict(s) → refuting before any close is recommended`)

phase('Refute')
const refutePrompt = (a) =>
  `${VERIFY_MANDATE}

A prior investigator wants to CLOSE this issue. Closing loses the thread, so your job is to REFUTE it. Default to refuted:true on ANY uncertainty — the cost of a wrong "close" is a real bug/gap silently dropped (or a half-done issue marked done); the cost of a wrong "refuted" is one extra human glance.

ISSUE: #${a.number} — ${a.title}
VERDICT: ${a.verdict} (severity=${a.severity}, effort=${a.effort}, gate=${a.gateRequired})
CLAIMED evidence: ${a.evidence}
CLAIMED rationale: ${a.rationale}

Try to break it. For close-already-done: \`gh issue view ${a.number}\`, enumerate its acceptance criteria, check EACH against code — find one unmet box and it is refuted. For close-obsolete: find one place the premise still holds in live code. For close-wontfix: show the premise is actually code-true (the issue is real) or unverifiable (should be needs-spec, not closed). Verify any SHA. Report refuted=false ONLY if you actively confirmed the close holds with your own commands.`

const refutations = await parallel(
  closeTargets.map((a) => () => agent(refutePrompt(a), { label: `refute:#${a.number}`, phase: 'Refute', schema: REFUTE_SCHEMA }))
)

const closeCleared = []
const closeBlocked = []
closeTargets.forEach((t, i) => {
  const r = refutations[i]
  if (r && r.refuted === false) closeCleared.push({ ...t, refutation: r })
  else closeBlocked.push({ ...t, refutation: r || { refuted: true, confidence: 'low', reason: 'refuter returned nothing — treated as unverified', evidence: '', residualWork: 'manual review' } })
})

log(`closeCleared=${closeCleared.length} (safe to close) | closeBlocked=${closeBlocked.length} (refuted/unverified — keep open) | keepOpen=${keepOpen.length}`)

return {
  totals: { assessed: assessed.length, closeProposed: closeTargets.length, closeCleared: closeCleared.length, closeBlocked: closeBlocked.length, keepOpen: keepOpen.length },
  closeCleared, // ONLY act on these — verdict survived an adversarial refute
  closeBlocked, // refuted or unverified → human review, do NOT close
  keepOpen,     // still-valid / reprioritize / needs-spec / blocked-by-dep (with corrected data)
}

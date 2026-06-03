export const meta = {
  name: 'verified-sweep',
  description: 'Fan out investigators over a candidate set, then adversarially refute every destructive verdict (close/delete/drop) before it is acted on — the #223 near-miss guard',
  phases: [
    { title: 'Investigate', detail: 'one investigator per cluster, verdicts verified against live code' },
    { title: 'Refute', detail: 'fresh skeptic tries to break each close/delete verdict before it executes' },
  ],
}

// USAGE: Workflow({ name: 'verified-sweep', args: { clusters: [{ label, prompt }, ...] } })
//   Each cluster.prompt describes a set of triage candidates to assess (issues, branches,
//   stashes). The investigator returns ASSESS verdicts; any verdict in `destructiveVerdicts`
//   (default: already-done / drop / safe-to-delete) then goes through an independent refuter
//   before the workflow blesses it for action. Returns { cleared, blocked, nonDestructive }.
//   ONLY act on `cleared`. `blocked` = verdict refuted or unverified → human review.

if (!args || !Array.isArray(args.clusters) || args.clusters.length === 0) {
  throw new Error('verified-sweep needs args.clusters = [{label, prompt}, ...]')
}

const DESTRUCTIVE = new Set(args.destructiveVerdicts || ['already-done', 'drop', 'safe-to-delete'])

const ASSESS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['cluster', 'candidates'],
  properties: {
    cluster: { type: 'string' },
    candidates: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'title', 'verdict', 'effort', 'risk', 'gateRequired', 'whatsLeft', 'evidence'],
        properties: {
          id: { type: 'string', description: 'issue # / branch name / stash ref' },
          title: { type: 'string' },
          verdict: { type: 'string', enum: ['sweep-now', 'quick-needs-gate', 'branch-merge', 'already-done', 'safe-to-delete', 'defer', 'drop'] },
          effort: { type: 'string', enum: ['trivial', 'small', 'medium', 'large'] },
          risk: { type: 'string', enum: ['low', 'medium', 'high'] },
          gateRequired: { type: 'boolean', description: 'touches money math / firestore.rules / Functions auth / routing / schema field-name with read+write path' },
          whatsLeft: { type: 'string', description: 'concrete remaining work, or why nothing remains' },
          evidence: { type: 'string', description: 'exact code paths / git SHAs / grep results — NOT issue-text restatement' },
        },
      },
    },
  },
}

const REFUTE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['refuted', 'confidence', 'reason', 'evidence'],
  properties: {
    refuted: { type: 'boolean', description: 'true = the destructive verdict does NOT hold (do not act); false = verdict survives, safe to act' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    reason: { type: 'string' },
    evidence: { type: 'string', description: 'the unmerged commit / unmet acceptance box / unique branch work found — or proof none exists' },
    residualWork: { type: 'string', description: 'if refuted, the work that remains; else empty' },
  },
}

const VERIFY_MANDATE = `You are triaging candidates in the Rihla Flutter repo. This project's signature failure mode is trusting "done"/"safe" claims that don't hold against code. For EVERY candidate verify against the ACTUAL tree (Read/grep/git/gh yourself), NOT issue text or branch names:
- "already-done" requires: the work is on main AND every acceptance box of the linked issue is met. Half-met = NOT already-done (it was a half-done #223 that almost got closed this way).
- "drop"/"safe-to-delete" for a branch requires: every commit unique to the branch is either on main under another SHA or genuinely obsolete. Run 'git rev-list --count main..origin/<b>' and 'git log main..origin/<b>'.
- Any cited SHA: 'git cat-file -t <sha>' + 'git merge-base --is-ancestor <sha> main'.
evidence MUST be concrete (paths:lines, SHAs, grep hits). Return strict schema.`

phase('Investigate')
const clusterResults = await parallel(
  args.clusters.map((c) => () =>
    agent(`${VERIFY_MANDATE}\n\n${c.prompt}`, { label: c.label || 'cluster', phase: 'Investigate', schema: ASSESS_SCHEMA, agentType: 'Explore' })
  )
)
const candidates = clusterResults
  .filter(Boolean)
  .flatMap((r) => (r.candidates || []).map((x) => ({ ...x, cluster: r.cluster })))

const refuteTargets = candidates.filter((c) => DESTRUCTIVE.has(c.verdict))
log(`${candidates.length} candidates; ${refuteTargets.length} destructive verdicts → refuting before any action`)

phase('Refute')
const refutePrompt = (c) =>
  `${VERIFY_MANDATE}

A prior investigator returned this DESTRUCTIVE verdict (it would trigger an irreversible action — closing an issue, deleting a branch, dropping a stash). Your job is to REFUTE it. Default to refuted:true on ANY uncertainty — the cost of a wrong "safe" is an issue closed half-done or a branch with unique work deleted; the cost of a wrong "refuted" is one extra human glance.

CANDIDATE: ${c.id} — ${c.title}
VERDICT: ${c.verdict} (effort=${c.effort}, risk=${c.risk}, gate=${c.gateRequired})
CLAIMED whatsLeft: ${c.whatsLeft}
CLAIMED evidence: ${c.evidence}

Try to break it. For "already-done": open the linked issue, enumerate its acceptance criteria, and check EACH against code — find one unmet box and it is refuted. For "drop"/"safe-to-delete": find one commit unique to the branch that is NOT on main. Verify any SHA. Report refuted=false ONLY if you actively confirmed the verdict holds with your own commands.`

const refutations = await parallel(
  refuteTargets.map((c) => () => agent(refutePrompt(c), { label: `refute:${c.id}`, phase: 'Refute', schema: REFUTE_SCHEMA }))
)

const cleared = []
const blocked = []
refuteTargets.forEach((t, i) => {
  const r = refutations[i]
  if (r && r.refuted === false) cleared.push({ ...t, refutation: r })
  else blocked.push({ ...t, refutation: r || { refuted: true, confidence: 'low', reason: 'refuter returned nothing — treated as unverified', evidence: '', residualWork: 'manual review' } })
})
const nonDestructive = candidates.filter((c) => !DESTRUCTIVE.has(c.verdict))

log(`cleared=${cleared.length} (safe to act) | blocked=${blocked.length} (refuted/unverified — DO NOT act) | nonDestructive=${nonDestructive.length}`)

return {
  totals: { candidates: candidates.length, destructive: refuteTargets.length, cleared: cleared.length, blocked: blocked.length },
  cleared,
  blocked,
  nonDestructive,
}

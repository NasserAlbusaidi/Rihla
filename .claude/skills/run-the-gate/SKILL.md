---
name: run-the-gate
description: Fresh-context spec review before implementation for Rihla money/rules/routing/schema changes. Spawns TWO parallel zero-history Opus subagents per round — a rubric reviewer (7 verification principles) and an orthogonal-axis adversary (off-map regressions, derived surfaces, l10n pairs) — applies the union of P1 findings, and re-runs until both verdicts are clean in the same round. Use before writing code that touches BalanceCalculator/MoneySerializer, firestore.rules or Cloud Functions auth, app_router.dart / deep-links / back-guards, or any field-name/schema change with both a read-path and a write-path. Use when asked to "run the Gate", "gate this spec", or "fresh-context review".
---

# Run the Gate

The in-session author cannot review the in-session author. A spec written this session carries this session's blind spots straight into the implementation. The only fix is a reviewer with **zero session history** — it starts from the code, not from your reasoning, so it structurally catches what your own checklist cannot.

This skill replaces `/codex` (retired) with a fresh-context **Opus subagent** as that reviewer.

## When this is mandatory

Run BEFORE writing code when the change touches ANY of:

- `BalanceCalculator` / money math / `MoneySerializer`
- `security/firestore.rules` or Cloud Functions auth/validation
- routing — `app_router.dart`, route tree, deep links, back guards
- a schema / field-name change with BOTH a read-path and a write-path

Outside these (a one-sentence diff, no money/route/schema/rules surface): **skip the Gate, just do it.** Don't burn a review round on a typo.

## The loop

1. **Write the spec to a file** — `docs/plans/<YYYY-MM-DD>-<topic>.md`. While writing, run the 7 verification principles yourself and report results out loud. The embedded check is the reviewer's *rubric*, not a substitute — but a first pass narrows what the reviewer hunts for.

2. **Spawn TWO reviewers in parallel** — both fresh Opus subagents with zero history, launched in a single message so they run concurrently:
   - **Rubric reviewer** — prompt: the full contents of `reviewer-prompt.md` (this skill's dir) + the absolute path to the spec file. Verifies the spec's own claims against live code.
   - **Orthogonal-axis adversary** — prompt: the full contents of `adversary-prompt.md` + the same spec path. Hunts what an on-the-map review structurally misses: regressions on coupled axes the spec doesn't cover, and derived surfaces (share cards, exports, activity rows, l10n pairs) the change silently reaches. Why two: #857 — a typography spec passed TWO single-reviewer rounds while a share-card cover-band caption needing AR translation slipped through; the builder caught it, not the Gate. A same-rubric reviewer re-walks the author's map; the adversary walks off it.
   - Both: `Agent`, `subagent_type: general-purpose`, `model: opus`. Each reads ONLY the spec + live code — neither sees this conversation NOR the other's output. That double isolation is the point; do not paste your reasoning or one verdict into the other's prompt.

3. **Apply the union of [P1]s, re-spawn.** Rewrite the spec to resolve every [P1] from BOTH reviewers. Then spawn a new **pair** — fresh `Agent` calls, NEVER `SendMessage` to continue an old one. Continuation re-imports the context you're trying to escape; each round must start from zero.

4. **Stop when a round's union has no [P1]s** — both the rubric reviewer AND the adversary must come back clean in the SAME round. ~2 rounds is typical. A 3rd round means the spec was over-scoped — split it and gate the pieces.

## Non-negotiables

- One reviewer = one fresh `Agent` call. Round 2's pair must not know round 1 existed, and neither reviewer in a round sees the other's verdict.
- A round is clean only when BOTH verdicts have zero [P1]s — a clean rubric verdict alone does not end the loop.
- Pass the spec's **file path** and make the agent read it — review the spec against code, not your summary of the spec.
- A green test suite is NOT the Gate (worked example #185 in `docs/SPEC-VERIFICATION.md`: rules suite was green while the client write violated the rule). "Tests pass" never ends a round.
- The reviewer's findings are merge/spec claims, not gospel — but [P1]s block implementation until resolved or explicitly refuted against code.
- Convergence pressure — momentum, prior approval, sycophancy — is exactly what this interrupts. Treat each round as v1.

Full reasoning + scar-tissue worked examples: `docs/SPEC-VERIFICATION.md`. Trigger rationale: **The Gate** in `CLAUDE.md`.

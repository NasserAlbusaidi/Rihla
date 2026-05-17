# Spec Verification — Full Reasoning & Worked Examples

This is the long-form companion to the **Verification principles** and **The Gate** sections in `CLAUDE.md`. CLAUDE.md carries the trigger and the imperative rules; this doc carries the *why* and the scar-tissue examples. You do not need this in context to follow the rules — read it when you want the reasoning, or when debugging why a spec slipped.

The framing principle: **the in-session author cannot review the in-session author.** Every worked example below is a logged case where the embedded checklist missed something and an independent fresh-context reviewer (codex) caught it. The checklist is the reviewer's rubric. Run the reviewer.

---

## When prompting a recon / Explore agent: demand data-flow classification

If the work touches a read-path *and* a write-path for the same data (rename, refactor, schema change, new validation layer), require the agent to classify every cited callsite:

- **INBOUND** — consumed for display / UI only. No persistence side effects.
- **OUTBOUND** — feeds a write / persistence / IPC. Format changes here leak into storage.
- **BOTH** — receives a value for display *and* feeds it back into a write. Highest-risk; treat as OUTBOUND for shape concerns.

Without this column, "render-site enumerations" miss the wire-up points where formatted-for-display strings get persisted unchanged.

**Worked example:** the v1 *former-member rendering* spec missed `SettleUpPageBody.onRecord` because the recon agent classified it as a render site. It is BOTH — the same string feeds the tile *and* the Firestore settlement create. If the BOTH classification had stayed missed, the `" (former member)"` display suffix would have been persisted into the settlement document on record, leaking a UI-only fallback into the source of truth and silently breaking name-equality checks on every later read. The fix that closed it was a `stripFormerSuffix` helper at the write boundary — but the helper only exists because the classification was corrected.

---

## While writing the spec — run these, report results out loud

Don't write "verified file paths" in your head. State, in the spec or in the conversation, what you checked and what you found.

- **Verify every concrete claim against code, not docs.** File paths, route constants, field names, test directories, npm/dart scripts. Docs drift; code is ground truth. CLAUDE.md, MEMORY.md, and inline comments are starting points, never citations. If a claim is load-bearing, `grep` or `Read` to confirm *in the moment* and say "verified" with the command run. Trusting an upstream agent's citation without re-running it is the single most common failure here.

- **Trace one read-path for every write-path.** Any data-shape mutation has consumers. "Who reads this after it changes?" must have an answer in the spec. Example: rewriting `groups/{gid}.memberIds` requires checking `groupMembersProvider` → `groupBalancesProvider` still resolves.

- **Enumerate fields from the type, not from memory.** When listing fields to scrub, migrate, or validate, open the model file and list them exhaustively. Recall is not a substitute.

- **Spell out data contracts, don't gesture at them.** "Two different shapes for the tile and the callback" is not a spec — it's an intention. The implementer needs the exact map keys, the exact callback signature, the exact prop names. Vague contracts → wrong implementations.

- **Verify arithmetic decomposition when summing across function calls.** Any time a spec writes `aggregate.X = sum(call.X)` or splits one calculation into N slices, you are asserting `X` is decomposable across the slicing. Open the function that produces `X` and read its **output-construction lines** (not the algorithm flow) to confirm `X` is built only from inputs that decompose across the slicing. Field names lie — `totalPaid` sounds decomposable, but if settlements fold into `netBalance` only, `sum(totalPaid)` silently drops settlement effects.

  **Worked example:** the v5 *former-member rendering* spec assumed `sum(eventBalances.totalPaid) - sum(eventBalances.totalOwed) = aggregate net`, but `BalanceCalculator.calculateBalances` at `expense_provider.dart:305` builds `netBalance = (totalPaid + settlementAdj) - totalOwed` — settlement adjustments live only in `netBalance`. Codex caught this as a [P1] in round 5; the in-house checklist missed it because the author read the function *flow*, not the field-*construction* contract.

- **Adversarial pass before sign-off — worked examples must test orthogonal axes.** Re-read the spec as if handed it cold, no commitment to the direction. What's vague? What's an assumption? What path doesn't exist? **Critical:** if the spec fixes bug X on axis A, the worked example must exercise axis B (or C, or D) — *not* axis A. A worked example on the same axis as the fix only proves the narrow point you already believed; it cannot catch a regression the fix introduces on a different axis.

  **Worked example:** v5 fixed a participant-set-scope bug (axis A: which UIDs are in the split set). The v5 worked example was "Orphan paid in Event A, Bob paid in Event B — Orphan not charged for Event B." Same axis as the fix. Codex's first move was to construct a worked example on axis B (settlements): "Alice settles $10 → Bob in Event A" — and the new algorithm dropped the settlement. When a fix is in flight, brainstorm the axes the spec touches (split-set, money-flow, settlements, scope, time, identity) and pick the example from the axis you did *not* just modify.

- **Distrust your own earlier claims in the same session.** The deeper a session runs, the more layered the assumptions. Re-verify load-bearing claims in the moment, not on recall. Iteration rounds (v2 → v3 → v4 → v5) create compounding momentum where each verified piece feels load-bearing for the next round; codex starts each round from zero, which is structurally why it catches what in-session verification misses. Treat each new round as v1.

---

## Before declaring ready — fresh-context review is non-optional

For any spec in a category from **The Gate** (money math, `firestore.rules`/Functions, routing, schema/data-shape with both a read and write path) — and unconditionally for anything destined for a worktree, codex-delegate execution, or another session — run `/codex` against the spec **before implementation, not after**. The Explore agent + your synthesis is the *first draft*; codex is the *first reviewer*. Without a fresh-context gap between author and reviewer, the spec ships its own author's blind spots into the implementation.

Cost: ~5–10 min and ~1.5M tokens per round. Cost of implementing a broken spec and rewriting: ≥10× that.

Apply codex findings, re-run, stop when the verdict has no [P1]s. Each round narrows the failure mode (round 1: architectural blind spots; round 2: specification ambiguity; round 3+: edge cases). Two rounds is usually enough; three signals the spec was over-scoped to start.

Convergence pressure — sycophancy, momentum, prior approval — is the failure mode this whole process exists to interrupt. A plan that "looks done" is not a plan that holds up under independent review. (See also the `feedback-spec-verification` memory artifact.)

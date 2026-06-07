<!--
Merge hygiene (CLAUDE.md → Workflow): a PR is the point where ghost-debt is
either prevented or created. Fill the linked-issue line so merge auto-closes
the issue; the repo auto-deletes this branch on merge. Don't leave orphaned
refs or stale-open issues for a later archaeology sweep.
-->

## What & why
<!-- One concern. What changed, and the reason it's worth a reviewer's time. -->

## Linked issue
<!-- Use `Closes #N` so merge auto-closes it. If the PR only PARTIALLY satisfies
     the issue, write `Refs #N` instead and say which acceptance boxes remain —
     a merged PR with unmet boxes leaves the issue OPEN, re-scoped, not closed. -->
Closes #

## Scope check
- [ ] One concern only — no bundled cleanup, opportunistic refactors, or dep bumps
- [ ] Linked issue's acceptance criteria reconciled (all met → `Closes`; partial → `Refs` + remaining boxes named)

## Gate (required if the change touches any of these — see CLAUDE.md → The Gate)
- [ ] `BalanceCalculator` / money math / `MoneySerializer`
- [ ] `security/firestore.rules` or Cloud Functions auth/validation
- [ ] routing (`app_router.dart`, deep links, back guards)
- [ ] a schema / field-name change with both a read-path and a write-path

→ If any are checked: `/run-the-gate` was run pre-implementation and the verdict has no [P1]s. Round count: ___
→ If none apply: N/A (one-sentence-diff path).

## Spec (link if Gate-category)
<!-- If this PR implements a spec that went through /run-the-gate, link it so the
     merge-time reviewer can confirm the diff didn't drift from what the Gate
     approved — un-gated scope creep, or a spec'd acceptance box left unbuilt. -->
Spec: <!-- docs/plans/<YYYY-MM-DD>-<topic>.md — or N/A -->

## Verification
- [ ] `flutter analyze` clean
- [ ] Relevant tests run + green (bug fix? the failing regression test was written first)
- [ ] Money/legal/safety code? table-driven tests cover clean / warning / error
<!-- Paste the command + result. Per the Operating Contract, verification is reported out loud, not asserted. -->

```
# analyze + test output here
```

## Security
- [ ] No hardcoded secrets, validated inputs, auth on sensitive paths, no PII in error/log surfaces

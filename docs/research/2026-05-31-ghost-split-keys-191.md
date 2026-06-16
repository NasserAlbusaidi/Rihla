# Audit finding: ghost split keys desync the ledger (#191)

**Date:** 2026-05-31
**Status:** RECOVERED audit draft — superseded by the shipped fix. Issue **#191 is CLOSED**; the `splitDistribution.keys().hasOnly(participants())` rule is live in `security/firestore.rules` and the drop-key parity semantics are documented in CLAUDE.md. Kept for provenance.
**Provenance:** originally a `/tmp/rihla_issues/02_ghost_split_keys.md` scratch draft from the pre-launch hardening audit; recovered from the session transcript after `/tmp` was cleared.
**Relates to:** #191 (this finding), #185 (sibling), `docs/plans/hardening-2026-05-31/splitdistribution-participant-keys-191-spec.md` (the implementation spec).

---

**Found by:** pre-launch hardening audit 2026-05-31 (Tier 2). Independently re-verified. **Direct sibling of #185.**

## Summary
`splitDistribution` keys outside the event participant set silently vanish from the balance, breaking ledger conservation. The rule `validExpenseSplit` checks only `splitDistribution is map` — there is **no `keys().hasOnly(participants())` constraint**, in deliberate contrast to `customSplitParticipants.hasOnly(participants())` two lines below. `BalanceCalculator` then drops the ghost key via `if (owedMap.containsKey(entry.key))` while the payer's `paidMap` keeps the full amount → `sum(owed) < amount`, payer net inflated, optimizer tells real members to overpay / leaves money unaccounted.

## Reachability
Crafted/forked client write (stock UI keys the map solely by participants). Not theft, but it silently corrupts a shared real-money ledger with no error and no fallback. The rules are the trust boundary for an anon-auth money app.

## Evidence
- `security/firestore.rules:412-417` `validExpenseSplit` — only `splitDistribution is map`; **no key-subset clause**. Contrast `:450` `customSplitParticipants.hasOnly(participants())`.
- `lib/features/ledger/providers/expense_provider.dart:144-146` `owedMap` seeded only from participants; `:178-182` `if (owedMap.containsKey(entry.key))` drops ghost keys; `:160-161` payer keeps full `expense.amount`.

## Repro
Write an expense doc directly (passing all rules): scope `global`, splitMode `shares`, amount 12.000 OMR, `splitDistribution {p1:1, gx:1}` where `gx` ∉ participants. Result: owed `p1=6.000`, `sum(owed)=6.000` vs amount 12.000 — `gx`'s 6.000 slice dropped; `p1`'s net becomes +6.000 though only 6.000 is genuinely owed.

## Suggested fix
- Rules: add `data.splitDistribution.keys().hasOnly(participants())` to `validExpenseSplit`.
- Defensive: in `BalanceCalculator`, route a dropped slice to a known participant or skip the expense with a logged anomaly so one bad doc can't silently desync the ledger.
- Failing rules-test + balance-calc test first (money code → table-driven). **Gate-required** (rules + money).

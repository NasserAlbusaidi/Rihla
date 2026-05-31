# ADR-0003 — Western numerals everywhere for non-money text

- **Status:** Accepted (2026-05-31)
- **Issue:** #145 (design review DEC-5)

## Context

In Arabic, non-money numbers mixed numeral systems on the same screen — Activity
showed `١٨ مايو` (Arabic-Indic) next to `12 ي` (Western); Ledger showed similar
mixes. Money was already consistently Western (`227.600`). The app needed one
documented rule for non-money numerals (dates, counts, relative time).

## Decision

**Western digits (0–9) for all non-money text, in every locale including Arabic.**
Money stays Western (unchanged). There is no Arabic-Indic (٠–٩) rendering path.

## Rejected alternatives

1. **Arabic-Indic for non-money** — recreates the mixed-script screens (Western
   money beside Indic dates/counts), which reads as a rendering bug rather than
   localization.
2. **Hybrid rule** (e.g. Indic dates, Western counts) — most native per element
   but the hardest to keep consistent, with no real payoff.

## Consequences

- Date / relative-time helpers (`lib/core/utils/localized_dates.dart`) and
  count-bearing ARB strings must not emit Arabic-Indic digits. `intl` under the
  `ar` locale already emits Western digits for these helpers, so the default is
  correct — the work is to *not* introduce Indic conversion.
- This governs the rendering side of BUG-8 (relative time), BUG-9 (dates), and
  BUG-10 (filter count), which adopt this rule.
- Recorded in `docs/LOCALIZATION.md` §8.4.

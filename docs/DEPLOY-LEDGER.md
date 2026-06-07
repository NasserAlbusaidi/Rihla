# Backend Deploy Ledger

Human-readable history of Firebase backend deploys (Cloud Functions + Firestore
rules + indexes) for project `rihla-safar`.

**This file is not parsed by any script.** The machine source of truth for "what
is deployed" is the moving git tag **`backend-deployed`**, advanced by
`tool/deploy_firebase_backend.sh` on a successful deploy and read by
`tool/pending_deploy.sh`. This ledger is the discoverable log of what went live
when. If a row is ever missing, `pending_deploy.sh` is still correct — only the
human history loses a line.

Append newest at the **bottom**.

| Date | Deployed SHA | What shipped | Verify |
|------|--------------|--------------|--------|
| 2026-06-06 | `e08b929` | #290 server-authoritative leaveGroup callable + `validSelfLeave` rules drop; also-shipped undeployed #170 recovery TTL + #76 deletionReaper | prod-state PASS; first server-authoritative leave live |
| 2026-06-07 | `f105862` | #318 server-authoritative `removeMember` callable (+ creator-remove rules drop), #294 member-doc lookup by `userId` field in `deleteAccount`/`cleanupAnonUidArtifacts`, #275 `cleanupAnonUidArtifacts` chunked BatchWriter (off the 500-write transaction cliff) | prod-state PASS; `removeMember` created, all 12 functions deployed |
| 2026-06-07 | `cc8c84e` | #270 server allocators (`groupNetBalance.ts` `allocateShares`/`allocateExact`/`allocatePercent`) gain the negative-value→equal-split guard — full byte-for-byte parity with the client `BalanceCalculator` (shared oracle → `deleteGroup`/`leaveGroup`/`removeMember`) | prod-state PASS; all 12 functions updated |
| 2026-06-07 | `b53433d` | #248 PR 1 (#337): expense `lastEditedBy` field rule pins (`==auth.uid`, presence-gated create / diff-gated update; `validSoftDelete` carries it). #248 PR 2 (#339): new `expenseAuditLogger` `onDocumentWritten` trigger (server-owned expense CREATE/UPDATE/soft-DELETE audit log → event `activity_logs`) + `validActivityCreate` removed (event `activity_logs` now server-only) | prod-state PASS; `expenseAuditLogger` **created**, all 13 functions deployed |
| 2026-06-07 | `786c2f1` | #248 PR 4 (#343): `firestore.rules` opens expense edit/soft-delete to **any event participant** (drop `requesterIsRecordCreator()` from `validExpenseUpdate`) AND makes the `lastEditedBy == auth.uid` pin **mandatory** on every update (was diff-gated) — closes a merge-time-Gate-refuter [P1] where omitting `lastEditedBy` let the audit trigger mis-attribute an edit to the creator. Rules-only (no function add/remove); 13 functions unchanged | prod-state PASS; rules match `main`, all 13 functions present |
| 2026-06-08 | `5eaacf7` | #261 PR-0b (#371): mixed-currency balance-gate guard. `groupNetBalance.ts recomputeNet` now returns `currencies: Set<string>` (EXPENSE-fold only, **function-scope** so cross-event mixing is caught, `toUpperCase()`-normalized so legacy `omr`/`OMR` stays one currency); `deleteGroup`/`leaveGroup`/`removeMember` reject `failed-precondition` when `currencies.size > 1`, **before** the `isZero()` gate — closes the mixed-EXPENSE-currency false-zero (`+10 OMR / −10 USD` → fake `Decimal 0`) money-loss path. Functions-only (no rules/index/function-set change) | prod-state PASS; rules already up to date, all 13 functions updated |
| 2026-06-08 | `edd6421` | #261 PR-1 (#374): `firestore.rules` make `group.currency` authoritative + immutable (Model A foundation). New `currencyMatchesGroup(d)` helper pins a money doc's `currency` to `groupData(groupId).currency` on expense **create** (unconditional), expense **update** (diff-gated — a pure soft-delete is never re-checked, so a legacy mismatched doc stays soft-deletable), and **event-settlement create** (mirrors the already-live group-settlement equality). `validCreatorMetadataUpdate` drops `currency` from its `hasOnly` allow-list → currency settable ONLY at create. Client `updateGroup(currency:)` param removed (defense-in-depth). Rules-only (no function add/remove); a tautology for every current all-OMR write, forward-enforcement once Phase 2 moves the `'OMR'` write hardcodes | prod-state PASS; rules match `main`, all 13 functions present |

<!--
Seed row reconstructed from memory on 2026-06-07. e08b929 = PR #319 merge (the
#290 deploy on 2026-06-06). No backend file changed between e08b929 and the actual
deploy commit, so it is the correct last-deployed backend marker; the
`backend-deployed` tag is seeded here.

Known pending at seed time (surfaced by tool/pending_deploy.sh): #318 removeMember
(+ rules drop) and #294 member-doc keying — these land in the NEXT ledger row when
deployed.
-->

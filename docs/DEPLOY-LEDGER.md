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

<!--
Seed row reconstructed from memory on 2026-06-07. e08b929 = PR #319 merge (the
#290 deploy on 2026-06-06). No backend file changed between e08b929 and the actual
deploy commit, so it is the correct last-deployed backend marker; the
`backend-deployed` tag is seeded here.

Known pending at seed time (surfaced by tool/pending_deploy.sh): #318 removeMember
(+ rules drop) and #294 member-doc keying — these land in the NEXT ledger row when
deployed.
-->

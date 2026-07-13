# #1216b — Bidi render isolation Implementation Plan (split from #1216 after Gate r2)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** FSI/PDI-isolate user-controlled strings wherever they are interpolated into a directional sentence that DRIVES OR CONFIRMS money or is rendered by the OS — both activity feeds, the settle-up direction sentences, and the server-built push-notification strings — so a name/description carrying an unterminated RLO/LRO (legacy data, or free text which is deliberately never tightened) cannot visually reorder the sentence around it.

**Architecture:** A 1-line client helper (`bidiIsolate`, FSI U+2068 … PDI U+2069) applied at ENUMERATED l10n-argument/render-span sites, plus a TS twin inside the notification strings builder. Isolation is DISPLAY-ONLY: it must never reach a persist, share, or derive boundary. The wrap is applied to the l10n call ARGUMENT (or span text) at each site — NEVER to the source name variable (which also feeds avatar hashing, share payloads, and callables).

**Split provenance:** #1216 spec v2 went through Gate r1+r2; both r2 reviewers independently converged on the same two P1s in this half's key enumeration — folded below (receipt line removed, five sibling keys added). The validation half is `2026-07-13-1216a-name-format-chars-validation.md` (independent files, no overlap; neither PR depends on the other). This spec still requires its own clean Gate round before implementation.

**Issue:** Closes #1216 (this is the closing half — 1216a merges as `Refs`). Gate category: Cloud Functions (notification strings) + money-confirm display surfaces. **The `functions/src` change MERGES now, DEPLOYS only at the next release ceremony (users live).**

---

## Verified context (Gate r1+r2 verified against live code @ 47d19fc3)

**Client helper:** new `lib/core/utils/bidi.dart` — write it EXACTLY as `String bidiIsolate(String s) => '\u{2068}$s\u{2069}';` (**FSI** U+2068, not LRI: first-strong keeps an Arabic name's own base direction in the RTL app; PDI U+2069). TS twin EXACTLY `'\u2068' + s + '\u2069'` (Gate r4: the earlier raw-char TS sample was itself the forbidden form — Prettier can silently strip raw invisibles, no-opping Surface 3; test assertions must use escapes too or a co-stripped test passes vacuously). Escaped forms are MANDATORY — raw invisibles are invisible in review and formatter-strippable (Gate r3). Doc: display-only; never persist; never into share/write payloads.

**Surface 1 — activity feeds** (`activity_display.dart` + `activity_row.dart`):
- `localizedGroupActivityText`/`_settlementText`: wrap the l10n args fromName/toName/eventName/memberName in `activitySettlementPaid`/`activitySettlementReceived`/`activitySettlementBetween`/`activityGroupEventCreated`/`activityGroupEventDeleted`/`activityGroupMemberRemoved`/`activityGroupExpenseAdded`/`activityGroupExpenseEdited`/`activityGroupExpenseDeleted`, AND **both** `log.description` fallback returns — the outer `_ =>` (:128) and the inner member_left branch (`memberAction=='removed'` with empty memberName, :109 — Gate r3).
- `localizedEventActivityText` (:26): wrap its `_ => log.logText` fallback return — legacy `logText` bakes in `'$actorDisplayName paid'` (`activity_log_model.dart:32-38`); used live by `activity_feed_screen.dart:232` inside the event hub.
- `activity_row.dart:79`: `text: bidiIsolate(actorName)` (covers all four feed screens).
- Do NOT touch `_metadataString` (also returns userIds compared against actorId) or the raw-name search haystacks (`activity_display.dart:229-232`).
- Accepted nit (r1): phrase search spanning static+name ("paid Ali") degrades vs the wrapped localized haystack; name-substring search survives via raw haystacks. Note in PR, don't fix.

**Surface 2 — settle-up direction sentences (r2-corrected key contract).** Wrap the NAME argument(s) — never amount/date args, never the source variable — at every call site of these THIRTEEN keys (call sites r2-verified; re-grep each key under `lib/` excluding `l10n/generated` at implementation time — the KEY LIST is the contract):

| key | r2-verified call site |
|---|---|
| `settleUpCorrectBody` | settle_up_page_body.dart:1095 (correction confirm dialog — the r1 worked example) |
| `settleUpYouOwe` | group_settlement_tile.dart:72 |
| `settleUpOwesYou` | group_settlement_tile.dart:73 |
| `settleUpOwes` | group_settlement_tile.dart:74 |
| `settleUpPays` | (re-grep; listed in ARB as "{fromName} pays {toName}") |
| `settleUpSettleAllWith` | settle_up_page_body.dart:633 |
| `settleUpMarkThisPaidBody` | record_payment_sheet.dart (~:322) |
| `settleUpRecordPartialBody` | record_payment_sheet.dart (~:326) |
| `settleUpRemainingAfter` | record_payment_sheet.dart (~:367/:375) |
| `settleUpRecordsImmediately` | record_payment_sheet.dart:215 |
| `settleUpRecordsReceivedImmediately` | record_payment_sheet.dart:208 |
| `settleUpRecordsForOthersImmediately` | record_payment_sheet.dart:210 |
| `activitySettlementBetween` et al. | covered under Surface 1 |

**INVENTORY STATUS: CLOSED (2026-07-13, author-run multi-modal recall sweeps).** After three Gate rounds each found one more site via a blind spot in the previous sweep, the author ran five INDEPENDENT recall sweeps over live code — (A) directional arrows `→`; (B) `$`-interpolations of person-locals (payer/recipient/creator/editor/actor/member/requester/shadow/joiner/from/to/other/who/person); (C) every ARB key with ≥2 placeholders of ANY name, read and classified by value; (D) name `.join()`s; (E) `TextSpan(text: <non-literal>)` carriers — and every hit is classified in the tables of this spec. Final sweep additions beyond the tables already below: `trip_receipt_format.dart:66` (`'payer before→after'`) = EXPORT-EXCLUDED (feeds the PDF receipt — a share boundary; its sibling `trip_receipt_pdf.dart:175` already strips `→` for PDF font limits, so FSI/PDI would likely render as tofu there — never wrap PDF/export text); `groupFailedRemoveMember` (ARB:1958, single name + error clause) = single-name residual; `homeGreeting` = own-name garble-self; `custom_split_sheet_itemized.dart:974` adjustment-label join = terminal-position excluded. **Reviewers: verify closure by designing your OWN recall sweeps and checking every hit lands in a table; implementer: re-run sweeps A–E and diff against the tables before writing code — a NEW hit means the inventory reopens (add + classify, don't ignore).**

**Surface 2b — RAW-INTERPOLATION direction sentences (Gate r3 adversary [P1]×2 — these are Dart `'$var'` interpolations / manual TextSpans, structurally invisible to the l10n-key contract):**
- `ledger_day_card.dart:448` — settlement row `'$payerName {ledgerPaidConnector} $recipientName'` in ONE Text paragraph + trailing RAmount: an RLO in payerName inverts who-paid-whom in the PRIMARY in-event transaction list. Wrap each name at the interpolation. Display-only (names resolved via `settlementDisplayNames`, no write path in the file — r3-verified).
- `settle_up_page_body.dart:1237/1244` (`_HistoryTile`, class ~:1036) — payer/connector/recipient as three raw TextSpans in one tree + settled RAmount (:1262). **The `payerName`/`recipientName` LOCALS (:1154/:1158) are BOTH, not display-only (r6 correction of a false r3 claim): they feed the wrap-target spans AND the :1095 dialog arg AND `_composeReceipt(...)` → `shareText` (:1352-1360) — a SHARE boundary.** Wrap ONLY at the span `text:` and the :1095 l10n arg; NEVER wrap the :1154/:1158 locals (the tempting DRY move splices FSI/PDI into the shared plaintext receipt). Negative test (c) binds to THIS tile: share the receipt from a `_HistoryTile` whose name carries an RLO, assert the shared string has no U+2066–U+2069.
- `ledger_day_card.dart:262` — expense row `'$payerName {paid} · {N} ways'` (single payer, garbles the trailing descriptor — r3 [P2]). Wrap the name.
- **Completeness sweep — THE CONTRACT (Gate r4 root-cause fix: the enumerated tables above are the verified STARTING SET; the sweep + per-hit classification is the acceptance criterion, because three Gate rounds each found sites a narrower enumeration missed):**
  1. Run THREE sweeps (r5-broadened): `grep -rnE '\$\{?[a-zA-Z]*[Nn]ame' lib --include='*.dart'`; the ARB key sweep `grep -nE '\{(payer|recipient|creator|editor|requester|shadow|joiner|[a-zA-Z]*[Nn]ame|name)\}' lib/l10n/app_en.arb` (role-named placeholders like `{payer}`/`{recipient}` carry names too — r5) then grep each key's call sites; AND the non-interpolation carriers `grep -rnE '\.name\)\.join\(|TextSpan\(text: *widget\.|TextSpan\(text: *[a-z]' lib --include='*.dart'` (join-lists and TextSpan text fields are invisible to the `$`-sweep — r5).
  2. Classify EVERY display hit by these RULES (paste the full classification table into the PR body):
     - **WRAP** — ≥2 user names in one sentence/paragraph, OR a name + an explicit money-direction verb/arrow between parties (pays/owes/paid/→/records X's payment to Y). (r5 sharpening: a SINGLE name with merely a trailing clause is NOT wrap-mandatory — the single-name residual exclusion wins there; over-wrapping stays harmless if chosen.)
     - **ALREADY-ISOLATED** — the #1066 idiom present (e.g. `_captionName`, group_settlement_tile.dart:345).
     - **STANDALONE-EXCLUDED** — a bare name in its own Text/cell (garble-self only), or terminal-position name with nothing after it.
     - **SHARE/PERSIST-EXCLUDED** — flows to shareText/clipboard/callable/write (NEVER wrap; cite the boundary).
  3. Additional r4-verified WRAP sites beyond the earlier tables: `claim_requests_section.dart:187` (`groupClaimRequestRow(requester, shadow)` — two names, confirms an IRREVERSIBLE balance merge) and `:211` (`groupClaimMergeConsequence(shadow, requester)` — sits directly above the Approve button) — the prior "claim sheets" exclusion was WRONG for the creator-side card and is hereby narrowed to the JOINER-side single-name sheet (`claim_join_views.dart:202/211`); `:117` `groupClaimApproved` snackbar (two names, post-action — wrap for uniformity); `lib/features/ledger/widgets/expense_editor/expense_provenance_byline.dart:44` (r5 path fix — note `/expense_editor/`; `editorProvenanceAddedEdited(creatorName, editorName)` — two names one Text); `lib/features/ledger/widgets/ledger_search_sheet.dart:487` (r5 [P1] — `_SettlementHit.title()` `'$payer → $recipient'`, two names + directional arrow rendered at :350; display-only, r5-verified); the event-label build in `group_settle_up_screen.dart` (`'$name — $date'`, event name + trailing date — NOTE: PR #1238 (merge queue) re-keys/moves this label resolution; branch from post-#1238 main and wrap at the CURRENT site. **Wrap the post-truncation `name`, never `rawName` (r7): #1238's grapheme-truncate `rawName.characters.take(27)` would drop a closing PDI and leak an unterminated FSI into `— $date` — the self-inflicted version of the bug being fixed. The #1238 collision test survives the wrap: `textContaining('Dinner')` matches by substring.**)
  4. Single-name-plus-trailing-static strings (`settleScopeNoteEvent`, `eventClosedBannerBy`, "Paid — let {name} know?", remove/claim confirm strings incl. `groupClaimConfirmWarning` — r5 falsification survived: leading action verb + type-to-confirm gates) are an ACCEPTED garble-adjacent residual class — exclude with that rationale in the classification table; wrapping any of them while already touching the file is fine but not required.
  5. Pre-classified r5 hits: `custom_split_sheet_itemized.dart:537` (`selected.map((p) => p.name).join(', ')` rendered at :564-565 — ≥2 names one paragraph, but set-based/order-invariant allocation in a reversible editor: wrap for uniformity OR exclude with exactly that rationale; either is acceptable, state which); `delete_group_sheet.dart:149` (`TextSpan(text: widget.groupName)` — single name, type-to-confirm-gated: excluded).
- Already-isolated precedent, leave untouched: `group_settlement_tile.dart:345` `_captionName` = the #1066 inline FSI wrap (identical idiom; its `semanticsLabel` deliberately raw). No double-wrap risk.

**EXCLUDED — share/persist boundaries (wrapping them is a P1, both r2 reviewers):**
- `settleUpReceiptLine` — its ONLY call site (settle_up_page_body.dart:1131) is inside `_composeReceipt` (:1119-1147, "Composes the plain-text receipt shared via shareText (#359)"). Share-only, never rendered as a Text widget. DO NOT WRAP.
- `settleNotifyMessageEvent`/`settleNotifyMessageGroup` (`lib/core/utils/settle_notify.dart`) — WhatsApp share strings, user-reviewed before send.
- `groupShareInviteMessage`/`Subject` — share.
- The persisted correction note is the static `settleUpCorrectionNote` (no name args) — the `settleUpCorrectBody` dialog wrap does NOT reach a persist path (r2-verified).
- TRUE standalone-Text renders: rosters, pickers, claim sheets, `ExpenseAuditDetail` (`_payerChangeRow`/`_textChangeRow` — each value in its own `Flexible(Text)`) — bidi garbles only itself there. Don't "fix".
- Considered-and-excluded (Gate r3): the #363 fan-out `settleUpDirectPayments`/`settleUpNoDirectPayments(subjectName)` (settle_up_page_body.dart:551/554) — name in terminal position, ≈ standalone class. Framing note: `settleUpYouOwe`/`settleUpOwesYou`/`settleUpOwes` (group_settlement_tile.dart:72-74) render ONLY as a `Semantics(label:)` on a zero-size widget (:281) — wrapping is harmless (Cf ignored by screen readers) and keeps the key contract uniform, but the tile's VISIBLE direction protection comes from the already-isolated `_captionName`, not these.

**Surface 3 — notification strings** (`functions/src/notifications/strings.ts`): local `const bidiIsolate = (s: string): string => '\u2068' + s + '\u2069';` applied to every user-controlled interpolant (actor, joiner, shadow, label/description, event names) in ALL body builders, BOTH locales: `settlementBody` (:39), `memberJoinBody` (:54), `expenseBody` (:69 — splices deliberately-untightened free-text description directly before the amount: the sharpest edge), `eventBody` (:92), `claimRequestBody` (:115), **`claimDecideBody` (:142 — r2 add; live at `functions/src/triggers/claimRequestNotifier.ts:142`)**. Title builders return standalone `groupLabel(groupName)` — self-contained; wrapping optional/harmless. FSI is Unicode 6.3 — honored by Android (API 19+) and iOS notification renderers; worst case on a non-conforming OEM equals today's behavior (r2-traced).

**The arg-not-var rule (r2 [P3], mandatory):** `record_payment_sheet.dart`'s `fromName`/`toName` fields (:87-88) also feed `RAvatar(name:)` color-hash (:588) and the recordSettlement callable/share paths. Wrap ONLY at the l10n call argument. **Negative tests:** (a) the `recordSettlement` payload built by the settle-up flow contains NO U+2066-U+2069 — pin the CALLABLE path, not the sheet-display arg (r6: event-scope `settle_up_screen.dart:754-755` passes `fromName: fromRawName` to the callable while `:668-669` passes `fromDisplayName` to the sheet — assert on the :754 invocation; group scope `group_settle_up_screen.dart:889-890/1004-1005`); (b) `settleNotifyMessage` (`settle_notify.dart` — exact symbol name, Gate r3) output stays raw; (c) `_composeReceipt` output stays raw.

## Non-goals

- No validator changes (that's 1216a). No free-text tightening.
- No isolation of share strings or standalone-Text renders (enumerated above).
- No goldens regeneration expectation: the wrapped chars are zero-width — if any macOS golden diffs appear, regenerate deliberately and say so in the PR (goldens are macOS-only, CI-excluded).

---

### Task 1: `bidi.dart` + unit test (RED trivial → GREEN). Commit.

### Task 2: Activity feeds (RED → GREEN)

Tests: settlement log with `fromName: 'Ali‮'` → `localizedGroupActivityText` output contains `\u2068Ali‮\u2069`; event-activity legacy `logText` fallback wrapped; actorName span wrapped (widget test on `ActivityRow`); AR-locale smoke (RTL base + wrapped Arabic name; `maxLines`/ellipsis path doesn't throw). RED first, capture output. Commit.

**Existing-test mandate (Gate r3+r4):** wrapping changes exact-match assertions pinning CURRENT output. UPDATE expectations to the wrapped form (with `\u{2068}`/`\u{2069}` escapes). NEVER "fix" by stripping FSI/PDI before asserting — normalize-then-assert defeats the pin. r4-enumerated RED set (grep tests for MORE before starting — the lib/ sweep cannot find test assertions): `test/unit/activity_display_test.dart:50/133-134/192-193/452/468` (r6: lives under test/unit/, not test/features/activity/); `record_payment_sheet_test.dart:529/564`; `ledger_split_ways_test.dart:295/304/355/402`; `ledger_screen_test.dart:289`; `group_activity_screen_test.dart:580/989/1025/1078/1152`; `cross_group_activity_screen_test.dart:456/559`. (Static-substring assertions like `textContaining('close out the balance')` stay green — the wrap is names-only.)

### Task 3: Settle-up direction sentences + Surface 2b raw interpolations (RED → GREEN)

Re-grep the 13-key contract; wrap NAME args at every call site. Then Surface 2b: wrap the enumerated raw-interpolation sites and run the completeness sweep (classification into the PR body). Tests: the correction dialog with `recipientName: 'Bob‮'` renders the FSI-wrapped name (r1 worked example); tile headline (`settleUpYouOwe`/`settleUpOwesYou`) wrapped; one record-banner case; PLUS the three negative tests (recordSettlement payload / settle-notify / receipt all raw). RED first. Commit.

### Task 4: Notification strings (RED → GREEN)

All builders incl. `claimDecideBody`, both locales. **Wrap the POST-FALLBACK locals, NEVER the raw params (r7 [P2]):** every builder derives its interpolant through fallback/trim logic first — `actorLabel()` returns `'Someone'`/`'شخص ما'` on empty (settlementBody:75, memberJoinBody:55, expenseBody:75, eventBody:97, claimRequestBody:120), and the trim-then-length idiom drops empty tails / gates possessives (expenseBody:76-77, eventBody:98-99, claimRequestBody:121-122, claimDecideBody:147-149). `.trim()` does NOT strip FSI/PDI, so wrapping a raw empty param yields `\u2068\u2069` (length 2) which defeats every empty-check: `Someone` fallback skipped, dangling ` · \u2068\u2069` separators, `\u2068\u2069's spot` possessives. Wrap the derived local at the interpolation (e.g. `${bidiIsolate(actor)}`) so `\u2068Someone\u2069` still satisfies the fallbacks. **KEEP-GREEN INVARIANTS (do NOT update these — a red here means your wrap site is wrong, not that the pin is stale):** `settlementNotifier.test.ts:136/156` (`Someone`/`شخص ما`), `eventNotifier.test.ts:203` (empty event name drops separator), `expenseNotifier.test.ts:258-259`, `claimRequestNotifier.test.ts:168`. Extend the notifier/strings tests (emulator runner: `cd functions && npm run test:emulator -- <file>`) with (a) a `'Ali‮'` actor + an RLO-bearing description asserting wrapped output, AND (b) an EMPTY-name case asserting the fallback still fires (`contains('Someone')`, no `\u2068\u2069`). RED first. Commit.

### Task 5: Full check + PR

`flutter analyze`; `flutter test` (full); `cd functions && npm run test:emulator` (full); `bash tool/check_theme_purity.sh` (widget files touched). ONE PR: summary, per-layer RED outputs, **`Closes #1216`** (this half closes it; 1216a merged/merges as Refs), `Spec: docs/plans/2026-07-13-1216b-bidi-isolation.md` (ship the spec in the branch), the ⚠️ functions-merged-NOT-deployed line, accepted residuals (share strings; phrase-search nit; standalone-Text renders). No auto-merge — lead runs /automerge.

## Acceptance

- [ ] Both activity feeds isolate every interpolated user string incl. `logText`/`description` fallbacks; actorName span wrapped.
- [ ] All 13 settle-up direction keys wrapped at every live call site, PLUS every Surface-2b raw-interpolation site and every r4 WRAP site (claim card, provenance byline, event-label build).
- [ ] The BROADENED completeness sweep ran; the PR body carries the full per-hit classification table (wrap / already-isolated / standalone-excluded / share-excluded), no hit unclassified.
- [ ] `settleUpReceiptLine`, settle-notify, invite-share, and standalone-Text renders NOT wrapped; three negative tests green (callable payload / share strings / receipt raw).
- [ ] All notification body builders (incl. `claimDecideBody`) wrap user interpolants in both locales.
- [ ] No wrapped string reaches any persist/share/derive boundary (negative tests are the pin).
- [ ] Nothing deployed; PR carries the deferred-deploy flag and `Closes #1216`.

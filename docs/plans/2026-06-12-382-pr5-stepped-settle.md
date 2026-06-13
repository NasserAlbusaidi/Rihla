# #382 PR-5 — Stepped Settle (D2) + Per-Currency Intra-Group Surfaces (D3) + "Currencies Don't Net" Explainer

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** One gesture settles a counterparty across N currency buckets as N independent append-only currency-correct settlements; every remaining one-amount intra-group balance surface renders explicit per-currency lines; a one-time explainer says why currencies never net.

**Architecture:** Pure client UI/orchestration. No schema change, no rules change, no Functions change, **no deploy**. The stepped walk loops the *existing* per-settlement machinery (sheet → validate → `awaitServerAck`-raced write → per-outcome connectivity note → event-only `ledgerRevisionProvider` bump) once per bucket; partial completion is safe by construction because each write is independent and resume = recompute from live latency-compensated streams (queued writes included), which show exactly the remaining non-zero buckets. D3 deletes the two interim selectors (`selectCurrencyBucket`/`selectNetBucket`) by converting all 6 callers + 1 direct-index surface to full bucket renders.

**Tech stack:** Flutter/Riverpod 2.x, `Decimal` money, `fake_cloud_firestore`/`mocktail` tests.

**Branch:** `feat/382-pr5-stepped-settle` in worktree `../Rihla-382-pr5`, based on `main` AFTER PR #475 (PR-4) merges. Every commit body carries `Refs #382` (partial epic delivery — NEVER `Closes`).

**Spec status vs code:** all line numbers verified against worktree `../Rihla-382-pr4` @ `06cbe797` (≡ post-#475 main for `lib/`/`test/`). Re-read each file at implementation time.

---

## Locked decisions (Gate-reviewable, with rationale)

| # | Decision | Rationale |
|---|---|---|
| L1 | **Stepped walk = sequential record sheets, one per bucket, each its own independent write.** No batch, no rollback, no auto-record-without-confirm. | Design doc D2 ("Pay 1.4 OMR" → "Pay 41 AED" → done). The sheet is the existing per-step amount-edit + #351 "doesn't move money" guardrail; removing it would bypass per-step validation. Append-only settlements cannot be rolled back, so all-or-nothing is unimplementable anyway — embrace per-step independence. |
| L2 | **Affordance appears only for counterparty pairs involving `currentUid` with ≥2 buckets.** | 1-bucket pairs are exactly the existing tile flow (redundant button). Third parties can't record (#282 gate: record affordance is debtor-or-creditor only). |
| L3 | **Cancel ("Not yet") or any per-step failure STOPS the walk.** Steps already recorded stay (append-only). Final snackbar reports `recorded k of N` (k>0) or nothing (cancel at step 1). | Don't keep pushing sheets at someone who said no. Recompute-on-reentry shows remaining buckets — the resume story. |
| L4 | **Per-step success snackbars are suppressed during a walk; ONE final snackbar** (all/partial × synced/will-sync). Per-step ERROR snackbar (existing #360 classifier) still shows, then the walk stops. | N stacked snackbars is spam; errors must stay loud per step. |
| L5 | **The walk captures its step list at tap time and does NOT recompute mid-walk.** | Step k's write touches only its own currency bucket (fold isolation verified at `expense_provider.dart:438-457` and `group_balance_provider.dart:353-378`), so steps k+1..N stay valid. Re-ENTRY recomputes (whole screen rebuilds from live providers). The trap named in scouting — a captured list *re-run after death* — cannot happen: the walk dies with the screen. |
| L6 | **Bump asymmetry preserved:** the event screen's record path bumps `ledgerRevisionProvider` per successful write (inherited — the walk calls the same record body N times); the group screen's record path must NOT bump (live-watched; pinned by `group_settle_up_screen_test.dart` asserting `revision == 0`). | CLAUDE.md invariant; pinned by tests on both sides. |
| L7 | **D3 display contract:** "settled" ⇔ **every** bucket zero. Lines = non-zero buckets, GCC-first (`sortedGccFirst`). All-zero → today's single-line settled render (fallback = group currency), byte-identical. Currency code: **≥2 lines → every line carries its code; exactly 1 line → code shown only when its currency ≠ group currency** (the PR-4 "label only foreign amounts" idiom). Captions/overlines (tri-state "they owe you / you owe / settled"): kept when all non-zero lines share one sign; **omitted when signs are mixed** (signed, toned amounts self-explain). | Single-currency groups (all prod data pre-PR-6) render byte-identically → existing tests + goldens stay green without regen (the no-op-swap proof). Mixed-sign has no honest single caption. |
| L8 | **Delete `selectCurrencyBucket` + `selectNetBucket`** after their last caller converts (verified callers: `ledger_screen.dart:156`, `group_detail_screen.dart:117`, `:908`, `event_command_center.dart:130`, `home_screen.dart:653`, `active_journeys_provider.dart:169`; zero test callers). Replace with two tested pure helpers in the same file. | The selectors are doc-declared "interim until #382 PR-5"; leaving them invites re-collapse. |
| L9 | **Explainer = inline dismissible card in `SettleUpPageBody`**, shown when `buckets.length >= 2 && !settings.currencyExplainerSeen`; flag burned ONLY on explicit "Got it" tap (the #285 `AccountBackupNudge` inline pattern, NOT the #352 modal tri-state — an inline widget is always presentable, so no null-gate needed). New `AppSettings.currencyExplainerSeen` (key `settings_currency_explainer_seen`). | Settle-up is where "simplify is broken" complaints would originate (per-bucket optimizer). One surface, one flag. |
| L10 | **Fix the dead event-route `memberId` param:** the event settle-up route (`app_router.dart:356-366`) drops `?memberId=` that `ledger_screen.dart:296-300` and `event_command_center.dart:189-195` AND `:254-255` (roster card tap) already push; the group route wires it (`:265`). Wire it identically. | Pre-existing silent bug; D2's per-person entry points are exactly these (all three push sites hit the same route — one ctor arg fixes all). |
| L11 | **No new write seams.** `SettlementService.addSettlement` / `GroupSettlementService.addGroupSettlement` unchanged (no `stageSettlement`); group walk logs one `group_settlement` activity row per step with the PR-4 `metadata.currency` stamp preserved. | The queued-path `Settlement` return value is unused today and the walk doesn't need it. Scope discipline. |
| L12 | **`awaitServerAck`'s unused `onLateError` channel stays unused.** A queued-then-rules-rejected settlement reaching only Sentry is a pre-existing gap shared with every single-write path — fixing it is a separate issue, not a PR-5 rider. | One PR does one thing. Surface as follow-up note in the PR body. |
| L13 | **Zero predicate = exact `Decimal.zero`** in both Task-2 helpers (Gate R1 P2). 5 of the 6 surfaces already use exact zero (`ledger_screen.dart:205`, `home_screen.dart:660-664`, etc.); only the event hub uses `UserBalance.isSettled`'s 0.001 tolerance (`expense_model.dart:400`). Converting the hub to the exact-zero helpers TIGHTENS its settled gate — the safe direction for a money gate, and sub-tolerance residuals shouldn't exist (the calculator closes remainders onto the alphabetically-last recipient). Task 6 must note this deliberate threshold change inline. | Tolerance in the helpers would instead LOOSEN ledger/home and break the L7 byte-identical/goldens-green claim. |

---

## Verified seam contracts (enumerated from code, not memory)

- `SettleBucket` (settle_up_page_body.dart:25-29): `({String currency, List<UserBalance> balances, List<Map<String, dynamic>> optimalSettlements})`.
- Optimizer map keys (expense_provider.dart:700-710): `'fromUserId'`, `'toUserId'`, `'fromUserName'`, `'toUserName'` (String? — `userNames?[id] ?? displayName`), `'amount'` (Decimal). No currency key — the bucket carries it.
- `onRecord` (settle_up_page_body.dart:59-68): `void Function({required Map<String,dynamic> settlement, required String fromRawName, required String toRawName, required String fromUserId, required String toUserId, required Decimal suggestedAmount, required String currency})`.
- `showRecordPaymentSheet(BuildContext, {required String currency, required String fromName, required String toName, required Decimal suggestedAmount, bool isReceiving = false})` → `RecordPaymentResult{String amount, String note, PaymentMethod method}` (method never persisted).
- `GroupBalances` (group_balance_provider.dart:86-93): `({Map<String, List<UserBalance>> balances, Map<String, Decimal> totalSpent, int eventCount, Map<String, Map<String, Map<String, Decimal>>> perEventBreakdown, Map<String, String> memberNames, Map<String, String> memberRawNames})` — perEventBreakdown is memberId → eventId → currency → net.
- `HomeGroupBalance` (group_balance_provider.dart:833-839): `userNet: Map<String, Decimal>` (currency → net), `userPerEventNet: Map<String, Map<String, Decimal>>` (eventId → currency → net), `eventCount`, `partial`, `fromAggregate`.
- `AppSettings` full field list (lib/core/models/app_settings_model.dart — NOT features/settings/): `themeMode, languageCode, currencyCode, pushNotificationsEnabled, notificationPromptSeen, emailLinkNudgeSeen, weeklyDigestEnabled, deviceName, onboardingComplete, defaultSplitMode`. New flag touches: model field+ctor+copyWith; `SettingsService` key const + `loadSettings` read-with-default + `saveCurrencyExplainerSeen`; `SettingsNotifier.setCurrencyExplainerSeen`; `settings_notifier_test.dart`.
- ARB: EN (`app_en.arb`) carries values + `@key` metadata, AR (`app_ar.arb`) values only; parity CI-enforced (`tool/check_arb_completeness.dart`); generated `lib/l10n/generated/` is committed → run `flutter gen-l10n` and commit.
- Write-path invariants at every record site: capture `ledgerRevision`(event-only)/`connectivity` notifiers BEFORE the first await; `awaitServerAck(write, skipWait: status != online)`; acked → `noteLocalWrite()`, queued → `noteQueuedWrite()`; errors → `settlementWriteErrorMessage(classifySettlementWriteError(e))`.

---

## Tasks

Order chosen so every commit leaves the tree green. Tasks 2–8 (D3) are independent of Tasks 10–13 (D2).

### Task 1: Wire `memberId` into the event settle-up route (L10)

**Files:** Modify `lib/core/router/app_router.dart:356-366`, `lib/features/ledger/screens/settle_up_screen.dart` (ctor + pass-through to `SettleUpPageBody.preSelectedMemberId`). Test: `test/features/ledger/settle_up_screen_test.dart`.

1. RED: widget test — pump `SettleUpScreen(groupId, eventId, preSelectedMemberId: 'uid-x')` with a 1-bucket fixture where uid-x is a party; assert the matching tile is highlighted (mirror the group-screen preSelectedMemberId test). Plus a router test asserting the route builder forwards `?memberId=` (extend the existing `*_navigation_test.dart` convention if a router-level probe exists; otherwise the ctor-level test suffices and the route line is covered by Task 13's flow test).
2. GREEN: add `final String? preSelectedMemberId;` to `SettleUpScreen`, pass `preSelectedMemberId: preSelectedMemberId` into `SettleUpPageBody` (`:224-250` call), and in the route builder add `preSelectedMemberId: state.uri.queryParameters['memberId']` (copy of the group route's line `:265`).
3. `flutter analyze` + run the two settle-up test files. Commit `feat(ledger): wire memberId into event settle-up route (#382 PR-5)\n\nRefs #382`.

### Task 2: Pure per-currency helpers replacing the selectors (prep for D3)

**Files:** Modify `lib/features/ledger/providers/expense_provider.dart` (add next to the selectors; deletion happens Task 9). Test: `test/unit/per_currency_display_test.dart` (new).

1. RED: unit tests for:
   ```dart
   /// Non-zero buckets, GCC-first. Empty result ⇔ settled-everywhere.
   /// "Non-zero" is EXACT `!= Decimal.zero` (L13) — no tolerance.
   List<({String currency, Decimal net})> nonZeroNetsGccFirst(Map<String, Decimal> nets);
   /// My net per currency from a bucketed balance map (absent/zero buckets dropped).
   Map<String, Decimal> myNetByCurrency(Map<String, List<UserBalance>> buckets, String? uid);
   ```
   Cases: 2-currency mixed-sign ordering (OMR before USD); all-zero → empty; uid null → empty; uid absent from a bucket → that bucket dropped; sub-0.001 residual (`0.0001`) is NON-zero (pins L13's exact predicate).
2. GREEN: implement (trivial folds over `sortedGccFirst`).
3. Commit `feat(ledger): per-currency display helpers (#382 PR-5)\n\nRefs #382`.

### Task 3: Ledger screen — per-bucket hero/roster, all-bucket settled gate, CTA un-block (MONEY-WRONG fix)

**Files:** Modify `lib/features/ledger/screens/ledger_screen.dart:141-300,355-404`, `lib/features/ledger/widgets/ledger_hero_block.dart`, `lib/features/ledger/widgets/ledger_roster_strip.dart`. Tests: `test/features/ledger/ledger_screen_test.dart` (+ overflow test stays green).

1. RED (the bug): fixture with my net zero in the group bucket ('OMR') and non-zero in 'USD' → assert the settle-up CTA is ENABLED (tap reaches `onSettleUp`) and the hero does NOT render the settled statement. Run: fails today (`isSettled` at `:205` reads one bucket; `LedgerStickyCta.onTap` is `if (!settleEnabled) return`).
2. GREEN:
   - `myNets = myNetByCurrency(data.balances, currentPid)`; `lines = nonZeroNetsGccFirst(myNets)`; `isSettled = hasExpenses && lines.isEmpty`.
   - `LedgerHeroStatement` gains a multi-line mode: render one statement line per entry in `lines` (each line = the existing single-currency prose for that bucket's kind/amount/currency); `lines.isEmpty` → existing settled statement (unchanged); exactly 1 line → byte-identical to today.
   - Roster: build `LedgerRosterPerson` entries per (person, non-zero bucket) with a per-entry `currency` field; strip renders the chip amount with its entry currency (1-bucket fixtures byte-identical). Person-tap unchanged.
   - `settleEnabled: !isSettled && hasExpenses` now means "any bucket non-zero".
3. Full ledger test dir + analyze. Commit `fix(ledger): all-bucket settled gate + per-currency hero/roster (#382 PR-5)\n\nRefs #382` (RED output pasted into PR body later).

### Task 4: Group detail — `_BalanceCard` per-currency lines (MONEY-WRONG fix)

**Files:** Modify `lib/features/groups/screens/group_detail_screen.dart:108-153,518-630`. Test: `test/features/groups/group_detail_screen_test.dart`.

1. RED: 2-bucket fixture (me zero in 'OMR', −5 in 'USD') → assert caption is NOT `groupAllSettled` and a USD RAmount renders. Fails today (`:117` selects the group bucket only).
2. GREEN: `lines = nonZeroNetsGccFirst(myNetByCurrency(balances.balances, currentUid))`. Empty → today's settled render. 1 line → today's Row, `currency: line.currency`, `showCurrency: line.currency != group.currency` (L7). ≥2 → Column of RAmount rows (size 24, sign, code on, tone per sign), caption only when uniform sign.
3. Commit `fix(groups): group hero renders every currency bucket (#382 PR-5)\n\nRefs #382`.

### Task 5: Group detail — `_MembersCard` rows + event-row `userShare` (MONEY-WRONG fixes)

**Files:** Modify `lib/features/groups/screens/group_detail_screen.dart:242-260,868-1041`. Test: `test/features/groups/group_detail_screen_test.dart`.

1. RED: member with zero 'OMR' net and non-zero 'USD' net shows `'—'` today → assert a USD RAmount renders instead. Event row whose share exists only in 'USD' shows `'—' + groupNoShare` today → assert the USD share renders.
2. GREEN: members — per-member `nonZeroNetsGccFirst` across `data.balances`; `'—'` only when empty; lines per L7 (size 14). Event rows — `perEvent[eventId]` is already `Map<currency, Decimal>`; render its non-zero entries GCC-first (size 15); `'—'` only when all zero/absent.
3. Commit `fix(groups): member + event rows render every currency bucket (#382 PR-5)\n\nRefs #382`.

### Task 6: Event command center — per-bucket hero, merged per-bucket breakdown, all-bucket state machine (MONEY-WRONG fix)

**Files:** Modify `lib/features/events/screens/event_command_center.dart:114-326,400-595,1031-1143`. Test: `test/features/events/event_command_center_test.dart`.

1. RED: 2-bucket fixture, me settled in 'OMR' owing in 'USD' → assert state ≠ settled (no `eventAllSettled`), USD amount renders in hero, breakdown row for the USD debt exists. Fails today (`_resolveState` reads the selected bucket).
2. GREEN:
   - Drop the selector: `buckets` map used directly. Settled ⇔ `nonZeroNetsGccFirst(myNetByCurrency(buckets, uid)).isEmpty`. **Deliberate threshold change (L13): this replaces `UserBalance.isSettled`'s 0.001 tolerance (`expense_model.dart:400`, used at `_resolveState` `:275`) with exact zero — the hub's settled gate tightens; comment it inline.** State machine: empty (no expenses) / settled (all buckets) / youOwed / youOwe when uniform sign; mixed signs → render per-line tones with no global overline (L7).
   - Hero: 1 line → today's size-40 render; ≥2 → stacked RAmounts (size 28).
   - Breakdown: run `calculateOptimalSettlements` once per bucket; merge rows GCC-first; `_BreakdownRow` takes per-row currency. `onSettleWith(otherUid)` unchanged (lands on the now-wired memberId).
   - Roster dots: dot iff any bucket non-zero for that person; color from the GCC-first non-zero bucket's direction (deterministic, documented inline).
   - Preserve null-tolerance while the group doc loads: the fallback currency for the all-zero/zero-state render is `group?.currency ?? bucket key when sole ?? 'OMR'` — keep the existing honest-fallback comment semantics.
3. Commit `fix(events): hub renders every currency bucket; settled = all buckets (#382 PR-5)\n\nRefs #382`.

### Task 7: Home `_GroupRow` — per-currency lines

**Files:** Modify `lib/features/home/screens/home_screen.dart:632-736`. Test: `test/features/home/home_screen_test.dart` (or the existing group-row test file).

1. RED: facade fixture with `userNet: {'OMR': 5, 'USD': -3}` → assert both RAmounts render and no tri-state caption shows (mixed sign).
2. GREEN: `lines = nonZeroNetsGccFirst(homeBalance?.userNet ?? const {})`. Empty → today's settled render (`fallbackCurrency: group.currency`). Lines → trailing Column of RAmounts (size 16 single / 14 multi, sign, code always on here — today's render already shows the code); caption per L7.
3. Commit `feat(home): group rows render every currency bucket (#382 PR-5)\n\nRefs #382`.

### Task 8: Journey ticket — per-currency lines

**Files:** Modify `lib/features/home/providers/active_journeys_provider.dart:162-188` (entry model: replace `userBalance`/`currency` with `nets: List<({String currency, Decimal net})>` **plus a retained `fallbackCurrency` field (= `group.currency`)** — the card consumes only the entry and otherwise loses its currency source for the settled zero line (Gate R1 P2); keep an `isSettled` getter ⇔ `nets.isEmpty`), `lib/features/home/widgets/journey_ticket_card.dart:114-132`. Tests: `test/features/home/active_journeys_provider_test.dart` — **the three `.userBalance` assertions at `:145/:190/:238` break on the field removal; rewrite them against `nets`** — plus the journey card test.

1. RED: per-event nets `{'OMR': 1.4, 'AED': 41}` → both amounts findable on the ticket.
2. GREEN: provider stores `nonZeroNetsGccFirst(userEventBalances[event.id] ?? const {})` (empty → settled; card renders today's single zero line with `entry.fallbackCurrency`). Card: trailing `Column(crossAxisAlignment: end)` of size-14 → 12-for-multi RAmounts. Cards may grow taller; the horizontal strip tolerates it (no fixed height).
3. Commit `feat(home): journey tickets render every currency bucket (#382 PR-5)\n\nRefs #382`.

### Task 9: Delete the interim selectors

**Files:** Modify `lib/features/ledger/providers/expense_provider.dart:738-777` (delete both selectors + their docs). Grep proof: `grep -rn "selectCurrencyBucket\|selectNetBucket" lib/ test/` → zero hits.

1. Delete; `flutter analyze` clean proves zero callers. Also sweep the seven "until #382 PR-5" comments (grep `PR-5` in lib/) — delete or rewrite each to describe the now-permanent behavior.
2. Full `flutter test`. Commit `refactor(ledger): delete interim single-bucket selectors (#382 PR-5)\n\nRefs #382`.

### Task 10: `SettleUpPageBody` — stepped pairs computation + affordance (D2 UI)

**Files:** Modify `lib/features/groups/widgets/settle_up_page_body.dart`. Test: `test/features/groups/settle_up_page_body_stepped_test.dart` (new — the repo's first 2-bucket page-body fixture).

1. RED: 2-bucket fixture where (me↔X) appears in both buckets and (me↔Y) in one → exactly one stepped card, for X, keyed `ValueKey('settle-stepped-$otherUid')`, label `settleUpSettleAllWith(X)` + joined per-step amounts caption; tapping invokes `onRecordStepped` with 2 steps in GCC-first order whose fields match the bucket suggestions; pure third-party pair (A↔B, no me) → no card; `onRecordStepped: null` → no cards at all.
2. GREEN:
   ```dart
   typedef SettleStepRequest = ({
     Map<String, dynamic> settlement, String fromRawName, String toRawName,
     String fromUserId, String toUserId, Decimal suggestedAmount, String currency,
   });
   ```
   Pure function `steppedSettlePairs({required List<SettleBucket> buckets, required String? currentUid, required Map<String,String> rawNames})` → `List<({String otherUid, String otherName, List<SettleStepRequest> steps})>` — scan each bucket's `optimalSettlements` for maps where `fromUserId == me || toUserId == me`; group by counterparty; keep groups with `length >= 2`; rawName fallback identical to `_buildTile` (`rawNames[uid] ?? stripDiscriminator(name)`). New optional `onRecordStepped` prop; cards rendered between `_SettlementIntro` and the first bucket section. Keep tile indices/keys untouched (globally-unique invariant `:109-111`).
   New l10n (EN+AR + gen-l10n): `settleUpSettleAllWith(name)`, `settleUpSettleAllWithCount(count)`.
3. Commit `feat(groups): stepped-settle affordance for multi-currency counterparties (#382 PR-5)\n\nRefs #382`.

### Task 11: Record sheet — optional step indicator

**Files:** Modify `lib/features/groups/widgets/record_payment_sheet.dart` (`String? stepLabel` → small overline above the title when non-null). Test: extend `record_payment_sheet` tests (overline renders when passed; absent by default).

l10n: `settleUpStepIndicator(current, total)` ("{current} of {total}"). Commit `feat(groups): step indicator on record-payment sheet (#382 PR-5)\n\nRefs #382`.

### Task 12: Event screen — stepped walk driver

**Files:** Modify `lib/features/ledger/screens/settle_up_screen.dart`. Test: `test/features/ledger/settle_up_screen_test.dart` + a new stepped flow test group.

1. RED (recording service double, 2-bucket fixture, both buckets me↔X):
   - happy walk: tap stepped card → sheet 1 ("1 of 2") → confirm → sheet 2 → confirm → TWO `addSettlement` calls with currencies `['OMR','USD']` (each `currency` == its bucket), `ledgerRevisionProvider` bumped **twice**, ONE final snackbar `settleUpSteppedRecordedAll(2)`, no per-step `settleUpRecorded` snackbar.
   - cancel at step 2: ONE write, final snackbar `settleUpSteppedRecordedPartial(1, 2)`.
   - write error at step 2 (`throwOnAdd` second call): ONE write, #360 error snackbar, partial snackbar, walk stopped.
   - **orthogonal axis (identity/direction):** mixed-direction pair — I owe X OMR, X owes me USD → step 1 sheet is "Mark paid", step 2 is "Mark received" (#282 `isReceiving` flips per step), writes preserve payer/recipient direction per step.
2. GREEN: refactor `_showRecordPaymentSheet`+`_recordSettlement` into a per-step driver returning an outcome (`recorded(WriteAck)` / `cancelled` / `invalid` / `failed`), with `{String? stepLabel, bool showSuccessSnackbar = true}`; single-tile path keeps today's behavior byte-identical (existing tests green unchanged). `_runSteppedSettle(steps)`: capture notifiers ONCE before the loop (#104/#412 disposal pattern); loop steps; stop per L3/L4; track `recorded`/`anyQueued`; final snackbar `settleUpSteppedRecordedAll|Partial` × `WillSync` variant when `anyQueued`.
   New l10n (EN+AR): `settleUpSteppedRecordedAll(count)`, `settleUpSteppedRecordedAllWillSync(count)`, `settleUpSteppedRecordedPartial(recorded, total)`, `settleUpSteppedRecordedPartialWillSync(recorded, total)`.
3. Commit `feat(ledger): stepped settle walk on event settle-up (#382 PR-5)\n\nRefs #382`.

### Task 13: Group screen — stepped walk driver

**Files:** Modify `lib/features/groups/screens/group_settle_up_screen.dart`. Test: `test/features/groups/group_settle_up_screen_test.dart`.

1. RED (mirror Task 12, group services double):
   - happy walk: TWO `addGroupSettlement` calls (bucket currencies), `ledgerRevisionProvider` stays **0** (L6), TWO `logGroupEvent` calls each with `metadata == {'amount': …, 'recipientId': …, 'currency': <bucket>}` (PR-4 stamp per step), one final snackbar.
   - offline walk (never-completing `Completer`, fixed pumps — NEVER `pumpAndSettle` with a pending write): both writes queue, `WillSync` final snackbar, connectivity `noteQueuedWrite` per step.
2. GREEN: same driver refactor as Task 12 applied to this screen's `_showRecordPaymentSheet`/`_recordSettlement` (keep `#282` counterparty naming + actorName-from-prefs per step).
3. Commit `feat(groups): stepped settle walk on group settle-up (#382 PR-5)\n\nRefs #382`.

### Task 14: "Currencies don't net" explainer

**Files:** Create `lib/features/groups/widgets/currency_buckets_explainer.dart`; modify `lib/core/models/app_settings_model.dart`, `lib/core/services/settings_service.dart`, `lib/core/providers/settings_provider.dart`, `lib/features/groups/widgets/settle_up_page_body.dart` (insert when `buckets.length >= 2`), `lib/features/groups/keys/group_keys.dart`, ARBs. Tests: `test/unit/settings_notifier_test.dart`, `test/features/groups/currency_buckets_explainer_test.dart` (new).

1. RED: settings tests (`currencyExplainerSeen` defaults false; setter persists across fresh container — copy the `notificationPromptSeen` pattern at `:139-170`). Widget tests: 2 buckets + unseen → card visible; "Got it" → flag persisted + card gone; 1 bucket → absent; seen → absent.
2. GREEN: flag plumbing (4 touch points per the enumerated AppSettings contract); `CurrencyBucketsExplainer` ConsumerWidget styled per `AccountBackupNudge` (icon chip + title + body + Got-it TextButton; `SizedBox.shrink` when gated).
   l10n (EN+AR): `currencyExplainerTitle` ("Each currency settles separately"), `currencyExplainerBody` (no rates invented / OMR can't cancel AED / one payment per currency), `currencyExplainerGotIt`.
3. Commit `feat(groups): one-time currencies-don't-net explainer (#382 PR-5)\n\nRefs #382`.

### Task 15: Full verification sweep

1. `flutter analyze` → clean. `flutter test` → all green (goldens untouched — single-bucket renders byte-identical, L7).
2. `grep -rn "selectCurrencyBucket\|selectNetBucket\|until #382 PR-5\|until PR-5" lib/ test/` → zero hits.
3. PR: branch → `gh pr create` with `Spec:` line pointing at this file, `Refs #382` (NOT Closes — PR-6 remains), RED outputs pasted for Tasks 3/4/5/6 (the money-wrong fixes), follow-up notes (`onLateError` gap L12; journey-card unequal heights if design review wants a cap). Then `/automerge` (Gate-category: touches `expense_provider.dart` + `app_router.dart` → review + refute).

---

## Out of scope (named, with destination)

- Rules relaxation + add-expense currency picker → **PR-6** (the flip; deploy LAST).
- `stageSettlement` / `onLateError` UI for queued-then-rejected writes → follow-up issue (pre-existing gap, L12).
- Per-currency `profile_stats_provider` work → already per-currency since #378/#385; verified untouched.
- The #366 aggregate facade / once-path → untouched (D3 reads `userNet`/`userPerEventNet` maps that are already bucketed end-to-end).

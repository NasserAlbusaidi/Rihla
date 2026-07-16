# v1.9.0 Two-Device RD-QA — live results

## 🟢 PROD SECURITY STATE — RE-ENFORCED (2026-07-12 ~16:47)
App Check restored to enforced. QA window closed.
- Reverted 13 callables to `enforceAppCheck: true` (grep-verified); deleteAccount stays false by design.
- Rebuilt (tsc clean) + `firebase deploy --only functions` exit 0, all functions "Successful update operation"; compiled joinGroupByInviteCode.js = `enforceAppCheck:true`.
- `git diff e1583501 -- functions/ security/` EMPTY → prod == enforced intent, no drift. `backend-deployed` tag still e1583501 (never moved).
- Live device re-check (B join → 403) NOT re-observed: Device B is PIN-locked. Enforcement is deterministic from deployed code for Functions v2; optional user confirm: on B, attempt to join any group → should now fail App Check.

## Cleanup left in prod (harmless throwaway QA data)
- Group `QA 1.9 0712` (d55b96c5-…) — RD-03 delete NOT completed (all balances settled, safe to delete manually on A; ⚠️ not Bite).
- Group `B-FS-Test` (b2633093-…, B creator) — created for the Firestore-write check.
- Any groups the user created during manual auth-tail testing.

---


**Build:** v1.9.0 · versionCode 36 · commit `5f9581be` · backend `e1583501`
**Devices:** A = Pixel 9 Pro XL (4C171FDAS001U0, Android 16) · B = SM-G770F (RF8N213CZWK, Android 13)
**Started:** 2026-07-12 · gitignored (real account data)

## Findings log

| ID | Cell | Sev | Status | Summary |
|----|------|-----|--------|---------|
| QA-BUG-01 | RD-01 (create form) | P1 | **#1182** logged | Create button renders centered over "New Group" title — `_CreateGroupTopBar` inner `Center` (create_group_screen.dart:440) expands full-width, defeats `AlignmentDirectional.centerEnd`. #1109 regression. screens/RD01-create-btn-centered.png |
| QA-BUG-02 | Profile → Preferences | P2 | **#1184** logged | Language + Default split value text centered mid-row (not trailing-aligned) — `_PrefRow` wraps `trailingText` in `Flexible`(flex:1) competing with `Expanded` label → 50/50 split (profile_screen.dart:1591). Only `trailingText:` rows affected. screens/QABUG-settings-centered.png |

## Known identifiers
- **A uid** = `HIvgHwjoCAdCyiay33vankSLuIF2` (founder, attests clean)
- **B uid** = `N7fTYgzpQSgRERpDpWD5QPUJuPL2` (rooted anon)
- Group **QA 1.9 0712** = `d55b96c5-849a-4913-90fb-83ae6222a905` (A creator, code 4BYEZL, shadow Layla `61886a53-…`)
- Group **B-FS-Test** = `b2633093-e38f-4da2-8e9a-d5990bfbfb87` (B creator, code G435F7) — confirms Firestore writes work on rooted B; **cleanup later**.

## To re-verify
- Group glyph persistence: RD-01 form showed **tent** selected, Firestore saved `glyph:"camera"`. Run a deterministic glyph-select test (tap known glyph → verify Firestore) before deciding if it's a bug.

## Gate cells

| Cell | Result | Evidence |
|------|--------|----------|
| RD-01 Create group | **PASS** (defect QA-BUG-01 #1182 on create form) | `groups/d55b96c5-849a-4913-90fb-83ae6222a905`, memberIds=[HIvgHwjoCAdCyiay33vankSLuIF2], activeMemberIds match, currency OMR, inviteCode 4BYEZL, isDeleted false. Group detail opens clean, 1 member, auto-seeded event present. screens/RD01-* |
| EVENT-01 auto-seed | **PASS** (implicit) | Group detail shows one auto-seeded `TRIP QA 1.9 0712` event immediately (#245) |
| RD-02 Join by code | **PASS** (App Check off) | B joined QA 1.9 0712 via deep link 4BYEZL. members/N7fTYg…=Bilal isShadow:false role:MEMBER uid-keyed; memberIds+activeMemberIds=[A,Layla-uuid,B]. Auto-uppercase works (4byezl→4BYEZL). Warm deep-link routed to Join w/ code prefilled. GROUP·3 MEMBERS. |
| NAV deep-link (warm) | PASS (prelim) | `am start` https://rihla-safar.web.app/join/4BYEZL routed to JoinGroupScreen, code prefilled. Cold NAV-01 pending. |
| MEMB-06 Add shadow | **PASS** (on A) | `addShadowMember` succeeded on A (attests), no App Check error. Firestore: shadow Layla uuid-keyed `61886a53…`, isShadow:true, userId==docid, role MEMBER; memberIds gains uuid. |
| RD-04 Two-device ledger identity | **PASS** | A added QA-coffee 1.500 OMR paid Nasser, split Nasser+Bilal (custom, Layla excluded). Expense `c4599062` amountFils 1500 categoryId food customSplitParticipants=[N,B] payer N. A shows "owed +0.750" tile Bilal→Nasser; B shows "-0.750 you owe", Nasser +0.750. Live sync, no self-owe, 3dp both. |
| RD-05 Decimal input | **PASS** | 1.500 OMR accepted, ledger + balances render 3dp on both devices (via RD-04 expense). |
| EXP (equal split repr) | note | Equal split persists scope=custom + customSplitParticipants, NO splitDistribution map (computed at read for equal — expected; splitDistribution is for exact/percent/itemized). |
| RD-06 Offline/reconnect | **PASS** (minor note) | Airplane ON: cached Home/group/insights render correct (-0.750); "You're offline — changes will sync later" strip appeared on add-expense surface within the ~60s stale-probe window (#412). Airplane OFF: strip cleared, no false-offline. NOTE: strip not seen on passive Home in first ~40s — re-confirm Home timing (likely probe window, not a regression). |

| REG-1021 Samsung back-guard | **PASS** | Home→group→on-screen Back → Home; Home→group→system Back gesture → Home (PopScope→/home fires). Earlier Play-Store exit was deep-link-join-stack artifact, not #1021. |
| SETTLE-01 Debtor records full (event) | **PASS** | B recorded full 0.750 via recordSettlement. Doc sd164a977… amountFils 750 createdBy=B payerName Bilal recipientName Nasser (server-authored) settledAt ISO. Balance → All settled 0.000. |
| SETTLE-19 WhatsApp nudge (debtor) | **PASS** (partial) | Debtor got "Recorded — send a quick heads-up?" WhatsApp nudge prefilled. (Creditor/on-behalf no-nudge pending.) |

| EXP-02 Non-divisible equal reconciles | **PASS** | 10.000/3 → 3.333/3.333/3.334 (Bilal, alphabetically-last UID N7fTYg… gets remainder), green "Adds up to OMR 10.000". |
| EXP-01 Amount zero/0.001 | **PASS** | 0 → "Amount must be greater than zero" (not created). 0.001 → saved OMR 0.001 (3dp). |
| EXP-11 Category mandatory | **PASS** | 0.001 valid + no category → "Choose a category" inline+snackbar, blocked until picked. |
| EXP-18 Soft-delete | **PASS** | Deleted 0.001 expense: ledger hides it, balance→EVEN; Firestore doc 6bf55e1e… retained isDeleted:true + deletedAt ISO (append-only). |
| NAV-09 Dirty-editor discard guard | **PASS** (partial) | Close on dirty add-expense → "Discard this expense? Keep editing/Discard". (Predictive-back gesture variant pending.) |

| EXP-04 Exact not summing blocks | **PASS** | Exact 5/10/10=25 vs 30 → red "−OMR 5.000" remainder, Apply + Add both disabled (dimmed). |
| EXP-06 Percent not 100 blocks | **PASS** (shared mechanism) | Percent TOTAL shows non-100% (+289.667%) → same disabled-Apply widget as EXP-04. |

| EXP-12 Open-edit by non-creator | **PASS** | B (non-creator, participant) edited A's expense (category Food→transport). Firestore: categoryId transport, createdBy=A (immutable), lastEditedBy=B. Used metadata edit to preserve settled balance. |

| MONEY-01 Currency picker order | **PASS** | OMR, AED, SAR, USD, EUR, GBP, QAR, KWD, BHD, JPY (GCC-first, 10), OMR pre-selected. |
| MONEY-05 Multi-currency not summed | **PASS** | USD 25 added to OMR event. Ledger: OMR 1.500 + USD 25.00 separate headers. Settle-up: distinct "OMR 0.000 total" + "USD 16.67 total" sections, no netting. USD 25/3=8.33/8.33/8.34 (Bilal remainder). |
| SETTLE-03 Over-outstanding blocked | **PASS** | Entered USD 10 > outstanding 8.34, Mark paid → no settlement doc created (Firestore still 1 OMR doc, balance intact). #1129/#1093 hole closed. Explicit error copy not confirmed (server-authoritative). |

| MEMB-07 Add-by-name creator-only | **PASS** | B (member) group settings: "Only the group creator can add or remove members", no Add action. |
| MEMB-17 Leave blocked while nonzero | **PASS** | B owes USD 8.34 → Leave → "Settle up before leaving the group." snackbar + Settle up action; B stays a member (departure fence #1144). |
| MONEY-07 Home hero per-currency | **PASS** (partial) | B home hero "Across all journeys USD -8.34" per-currency line (only USD balance; OMR settled). |
| #996 smart-forward / double-push | **PASS** | Home journey tile → event (single-push, Back→Home); GROUPS-section tile → event with group-detail ancestor materialized (Back→group detail). |

| MEMB-20 Remove blocked while nonzero | **PASS** | A removes Bilal (owes USD 8.34) → "Settle up with Bilal before removing them." snackbar + Settle up; B stays. |
| EVENT-03 Close with unsettled | **PASS** | Event settings shows "This event has unsettled balances"; Close event → confirm "spending frozen" → closed. Banner "Closed by Nasser · spending frozen". Danger Zone → Reopen. |
| EVENT-04 Add/edit blocked in closed | **PASS** | No Add pill; tapping expense → "Event closed · spending is frozen. Reopen from Settings" ErrorScaffold (not editor). Recap tab appeared on close. |

| SETTLE-11 Creditor mark received | **PASS** | A (creditor) recorded Layla→Nasser USD 8.33 via "Mark received"; USD→0.00; NO WhatsApp nudge (SETTLE-19 creditor ✓). |
| MONEY-02 Currency immutable | **PASS** | Group settings: "Currency is set when the group is created and can't be changed." |
| RD-03 Delete group | **GATES VERIFIED, cascade NOT driven** | Typed-name confirm gate + settled-balance gate both confirmed (delete blocked while shadow Layla owed USD 8.33 — user caught this; confirmed delete IS balance-gated). NEAR-MISS: adb nav landed on real group "Bite" delete dialog; typed-confirm gate BLOCKED it (Delete disabled, "QA 1.9 0712"≠"Bite"). Cancelled, Bite untouched. LESSON: never drive destructive group ops on A's real-group Home via adb. User to complete delete of QA 1.9 0712 manually (all balances now settled). |

## HANDOFF — user driving remaining steps (2026-07-12 ~16:30)
App Check STILL un-enforced (re-enforce gate at top of file). User does B-side callable steps (claims/leaves/settles need App Check OFF) + auth tail (Google/email, doesn't need App Check). Re-enforce when user says device testing done.

## Findings / to-verify (behavioral)
- **Back from group-detail on B exited app → Play Store** (not /home). Context muddied by deep-link join stack. Re-test cleanly as REG-1021 before judging. If reproduces from a normal Home→group→Back path, that's the #1021 back-guard class.

## ENVIRONMENT: Device B rooted → App Check attestation fails (403), known #1022
- A (Pixel 9 Pro XL) attests cleanly — all 13 `enforceAppCheck:true` callables work.
- B (SM-G770F, **rooted**) fails Play Integrity device-integrity → App Check backend 403 → enforced callables blocked. This is App Check **working as designed** (memory rule: never QA App Check on rooted device). NOT a v1.9.0 regression.
- Blocked-on-B: join, recordSettlement, addShadowMember, claim chain, leave/remove/deleteGroup, corrections.
- Fine-on-B: expense CRUD, group create, notif toggle, recap/export, nav/deep-links, RTL, offline, + full account tail (deleteAccount enforceAppCheck:false; sign-out/restore/link = direct FirebaseAuth SDK).

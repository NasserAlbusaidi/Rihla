# Issue 669 Doc Staleness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove stale creator-member-doc keying and OMR-only currency claims from current code comments and reference docs.

**Architecture:** This is a docs/comment-only cleanup. Runtime behavior stays unchanged: creator member docs are now keyed by `members/{uid}`, legacy creator docs and server-minted shadows can still be uuid-keyed, and money writes are per-group/per-expense currency-aware with per-currency balance buckets.

**Tech Stack:** Flutter/Dart reference comments, Firebase Functions TypeScript comments, Markdown docs.

---

### Task 1: Verify Current Contracts

**Files:**
- Read: `lib/features/groups/providers/group_provider.dart`
- Read: `security/firestore.rules`
- Read: `lib/features/groups/screens/create_group_screen.dart`
- Read: `lib/features/ledger/screens/add_expense_screen.dart`

- [x] **Step 1: Verify creator member doc keying**

Run:

```bash
nl -ba lib/features/groups/providers/group_provider.dart | sed -n '200,260p'
```

Expected: `final memberId = uid` and `collection('members').doc(memberId).set(...)`.

- [x] **Step 2: Verify member create rules**

Run:

```bash
nl -ba security/firestore.rules | sed -n '820,842p'
```

Expected: `request.resource.data.id == request.auth.uid` and `request.resource.data.userId == request.auth.uid`.

- [x] **Step 3: Verify currency write paths**

Run:

```bash
nl -ba lib/features/groups/screens/create_group_screen.dart | sed -n '58,152p'
nl -ba lib/features/ledger/screens/add_expense_screen.dart | sed -n '122,132p'
```

Expected: group create owns a create-time `_selectedCurrency`, and add-expense defaults from last-used-in-event to group default rather than hardcoding OMR.

### Task 2: Patch Stale Wording

**Files:**
- Modify: `functions/src/callables/deleteAccount.ts`
- Modify: `functions/src/callables/leaveGroup.ts`
- Modify: `functions/src/callables/removeMember.ts`
- Modify: `functions/src/callables/joinGroupByInviteCode.ts`
- Modify: `functions/src/triggers/eventNotifier.ts`
- Modify: `functions/src/triggers/expenseNotifier.ts`
- Modify: `functions/src/triggers/expenseAuditLogger.ts`
- Modify: `lib/core/utils/name_validators.dart`
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart`
- Modify: `lib/features/groups/widgets/settle_up_page_body.dart`
- Modify: `lib/features/ledger/screens/settle_up_screen.dart`
- Modify: `lib/features/settings/providers/profile_stats_provider.dart`
- Modify: `lib/features/settings/screens/profile_screen.dart`
- Modify: `lib/features/settings/README.md`
- Modify: `docs/adr/ADR-0004-membership-model.md`
- Modify: `docs/CLOUD-FUNCTIONS.md`
- Modify: `docs/PRODUCTION-READINESS.md`
- Modify: `docs/POST-LAUNCH-ROADMAP.md`
- Modify: `docs/design/group-currency.md`
- Modify: `docs/DESIGN.md`
- Modify: `docs/DEVELOPMENT.md`
- Modify: `docs/PRODUCT.md`
- Modify: `docs/ARCHITECTURE.md`

- [x] **Step 1: Update member-doc comments**

Replace live comments/docs that say creator docs are always uuid-keyed or that deleteAccount deletes only `members/{uid}` with: match by `userId` field because legacy creator docs and server-minted shadows can be uuid-keyed, while new client-created creator docs are uid-keyed.

- [x] **Step 2: Update currency docs**

Replace OMR-only, pre-#382, or uniformity-rule currency claims with: OMR is the default group currency; supported currencies are OMR, USD, EUR, GBP, SAR, AED, JPY, KWD, BHD, and QAR; balances and totals remain bucketed per currency with no FX conversion; settlements record the selected bucket currency.

### Task 3: Verify Cleanup

**Files:**
- Read: all modified files

- [x] **Step 1: Grep for stale live claims**

Run:

```bash
rg -n "OMR-only|pending #61|multi-currency lands|all live data is OMR|writes currently pin|creator docs are uuid-keyed|creator's uuid-keyed|creator doc is uuid-keyed" docs lib functions/src -S
```

Expected: no matches in current reference docs/live code comments except dated historical plans, research, or mockups.

- [x] **Step 2: Run formatting/analyze-light checks**

Run:

```bash
dart format lib/core/utils/name_validators.dart lib/features/settings/screens/profile_screen.dart
flutter analyze --no-fatal-infos
```

Expected: formatter succeeds and analyzer has no fatal diagnostics from this docs/comment-only change.

# Rihla — Comprehensive UAT Document

**Created:** 2026-04-06
**Status:** In Progress
**App Version:** v2.3 (post Groups, Events & Modules milestone)
**Test Surface:** 24 screens, 25 routes, 13 services, 14 providers

---

## How to Use This Document

Each test case has a checkbox. Mark `[x]` when verified, `[!]` for bug found, `[-]` for skipped/blocked.
Add notes inline after any finding. This document spans multiple sessions — pick up where you left off.

**Prerequisites:**
- App running on device/simulator via `flutter run --dart-define-from-file=config.json`
- At least one group with 2+ members and 1+ events with expenses
- Firebase backend accessible (online mode for initial testing)

---

## 1. Onboarding & First Launch

**Screen:** OnboardingScreen → HomeScreen
**Route:** `/onboarding` → `/home`

- [ ] Fresh install shows 3-page onboarding
- [ ] "Next" advances pages, page indicators update
- [ ] "Skip" jumps to home screen
- [ ] Completing onboarding stores preference (doesn't show again on relaunch)
- [ ] Anonymous auth session created silently (no login screen)
- [ ] Home screen loads after onboarding with empty state

---

## 2. Home Screen

**Screen:** HomeScreen
**Route:** `/home`

### Layout & Data
- [x] Header shows "Your Groups" title
- [x] Cross-group balance banner shows correct total (sum of all group balances)
- [x] Quick actions visible: Add Expense, Settle Up, Invite Friend, Activity
- [x] Group cards show: group name, member count, balance summary, latest event
- [x] Recent Activity section shows latest entries across all groups
- [x] Weekly Spending widget shows current week total
- [!] Bottom nav: Groups, Activity, Chats, Profile — all tappable **NOTE: Activity and Chats show "Coming Soon"**

### Quick Actions
- [x] "Add Expense" — navigates to expense flow (pick group → pick event → add)
- [x] "Settle Up" — navigates to settle-up flow
- [x] "Invite Friend" — opens invite/share flow
- [x] "Activity" — navigates to cross-group activity screen

### Edge Cases
- [ ] No groups state shows proper empty state with CTA
- [x] Pull-to-refresh reloads data
- [x] Group card tap navigates to group detail

---

## 3. Group Management

### 3.1 Create Group

**Screen:** CreateGroupScreen
**Route:** `/create-group`

- [x] Tap `+` button on home → slide-up transition to create group
- [x] Group name field validates (not empty)
- [x] "Your Name" field for creator's display name
- [x] Can add member names (minimum 1 besides creator)
- [x] Currency selector defaults to OMR
- [x] "Create" submits and navigates to group detail
- [x] New group appears on home screen
- [x] Invite code generated and displayed

**Known Bug — G-3:** Creator's member document is a separate write. If it fails, group exists but has no members. Verify: after creating, check group settings shows the creator as a member.

### 3.2 Join Group

**Screen:** JoinGroupScreen
**Route:** `/join-group`

- [ ] Enter invite code → finds group
- [ ] Shows group name and existing members
- [ ] Pick an unclaimed name from the member list
- [ ] Join succeeds → navigates to group detail
- [ ] Joining user appears in group members
- [ ] Balance is zero for new member

**Known Bug — G-1:** Joining the same group twice creates duplicate member docs. Test: try joining a group you're already in — should show error, not silently duplicate.

**Known Bug — G-8:** No duplicate name enforcement. Test: can two members pick the same display name?

### 3.3 Group Detail

**Screen:** GroupDetailScreen
**Route:** `/group/:gid`

- [ ] Shows group name, member list, balance summary
- [ ] Events list shows all events in group
- [ ] "Create Event" button visible
- [ ] "Settle Up" button navigates to group-level settle up
- [ ] "Activity" button navigates to group activity
- [ ] "Settings" gear icon navigates to group settings
- [ ] Balance amounts match expected (cross-check with ledger totals)

### 3.4 Group Settings

**Screen:** GroupSettingsScreen
**Route:** `/group/:gid/settings`

- [ ] Shows group name (editable?)
- [ ] Shows invite code with copy/share action
- [ ] Member list with roles
- [ ] Leave group option — shows confirmation
- [ ] Remove member option (for creator/admin)

**Known Bug — G-8 (leave):** Leaving group doesn't check outstanding balances. Test: try leaving with non-zero balance — should warn or block.

### 3.5 Group Settle Up

**Screen:** GroupSettleUpScreen
**Route:** `/group/:gid/settle-up`

- [ ] 4 tabs: You Owe, Owed to You, Between Others, History
- [ ] Summary card shows GROUP TOTAL PENDING
- [ ] "Across N events" label shows correct event count
- [ ] Settlement tiles show correct pairwise amounts
- [ ] "Record Settlement" button appears for actionable debts
- [ ] Tapping "Record Settlement" opens confirmation bottom sheet
- [ ] Bottom sheet pre-fills suggested amount (D-11)
- [ ] "Mark as Paid" records settlement
- [ ] Balance updates after settlement recorded
- [ ] All-settled state shows "All settled up" with tick icon
- [ ] History tab shows past settlements

**Known Bug — F-7 (CRITICAL):** Non-divisible splits don't zero-sum. Test: create 10.000 OMR expense split 3 ways. Check settle-up — total should be 10.000 but may show 9.999 due to rounding remainder.

### 3.6 Group Activity

**Screen:** GroupActivityScreen
**Route:** `/group/:gid/activity`

- [ ] Shows activity entries for group-level actions
- [ ] Entries include: group created, member joined, event created, group settlement
- [ ] Each entry shows actor name, action, timestamp
- [ ] Entries are in reverse chronological order

**Known Bug — G-4:** All entries show "Someone" instead of the actual user's device name. Verify: check if any entry shows a real name.

---

## 4. Event Management

### 4.1 Create Event

**Screen:** EventTypePickerScreen → CreateEventScreen
**Route:** `/group/:gid/create-event` → `/group/:gid/create-event/:type`

- [x] Event type picker shows all types (Trip, Camping, Day Out, Dinner, Custom, etc.)
- [x] Selecting type → shows create event form
- [x] Event name field validates
- [x] Participant selector shows group members (default: all selected)
- [x] "Select All" / deselect works
- [!] Start/end date pickers work **BUG: Date text is cut off from below (visual clipping)**
- [x] "Create" submits and navigates to Event Command Center
- [x] Event appears in group detail

### 4.2 Event Command Center

**Screen:** EventCommandCenter
**Route:** `/group/:gid/event/:eid`

- [x] Shows event name, type icon, dates
- [x] Module cards visible: Ledger, Gear, Logistics, Vault, Memories
- [!] Each module card shows relevant summary (expense count, gear count, etc.) **BUG: Balance card stuck loading (skeleton never resolves) after event creation. Going back causes entire app to show skeletons**
- [!] Tapping each module navigates correctly **BUG: Gear page fails to load**
- [x] Settings gear icon navigates to event settings
- [!] Activity link available **BUG: Settlement activity shows "Unknown → Unknown". Event activity page is empty (G-7 confirmed)**

### 4.3 Event Settings

**Screen:** EventSettingsScreen
**Route:** `/group/:gid/event/:eid/settings`

- [ ] Shows event details (name, type, dates)
- [ ] Edit event name
- [ ] Delete event option with confirmation
- [ ] Participant management

---

## 5. Ledger (Financial Core)

### 5.1 Add Expense

**Screen:** AddExpenseScreen
**Route:** `/group/:gid/event/:eid/ledger/add`

- [ ] Description field
- [ ] Amount field — accepts decimal input (3 decimal places for OMR)
- [ ] Payer selector — defaults to current user
- [ ] Scope selector: Global (default), Sub-Group, Personal, Custom
- [ ] Global: splits equally among all event participants
- [ ] Sub-Group: splits among selected sub-group members
- [ ] Personal: no split — only the payer is affected
- [ ] Custom: manual split among selected participants
- [ ] Category selector
- [ ] Receipt camera/upload option (OCR extraction)
- [ ] "Save" creates expense and returns to ledger
- [ ] Amount displayed correctly in ledger list

**Financial Precision Tests:**
- [ ] Enter exactly `0.001` OMR — should be accepted (minimum unit)
- [ ] Enter `99999.999` — should be accepted (large amount)
- [ ] Enter `10.000` split 3 ways — verify each person's share displays correctly
- [ ] Enter `0.010` split 3 ways — verify rounding behavior

### 5.2 Edit Expense

**Screen:** EditExpenseScreen
**Route:** `/group/:gid/event/:eid/ledger/edit/:expId`

- [ ] Pre-fills all fields from existing expense
- [ ] Can change description, amount, payer, scope
- [ ] Save updates the expense in ledger

**Known Bug — F-5:** Changing scope from subGroup to global doesn't clear `subGroupId` in Firestore. Test: create subGroup expense, edit to global, then check if the subGroup association is really gone.

### 5.3 Ledger Screen

**Screen:** LedgerScreen
**Route:** `/group/:gid/event/:eid/ledger`

- [x] SPENDING tab shows all expenses with amounts
- [!] Each expense shows: description, amount, payer name, date, scope indicator **BUG: Expense card shows "Unknown" as creator instead of actual payer name**
- [x] Expense tap opens detail/edit
- [x] Total spending displayed correctly
- [x] Soft-deleted expenses are NOT shown
- [x] Add expense FAB visible

### 5.4 Event Settle Up

**Screen:** SettleUpScreen
**Route:** `/group/:gid/event/:eid/ledger/settle-up`

- [x] Shows per-event balances (not cross-event)
- [x] Settlement suggestions are correct
- [x] "Record Settlement" flow works
- [x] After settlement, balances update
- [x] All-settled state reached when everyone is even

### 5.5 Balance Calculation Verification

**This is the most critical section. Use a calculator to verify manually.**

**Test Scenario A — Simple 2-person split:**
1. Create event with 2 participants (A, B)
2. A pays 20.000 OMR, global scope
3. Expected: A is owed 10.000, B owes 10.000
- [ ] Ledger shows 20.000 total
- [ ] Settle Up shows B → A: 10.000
- [ ] After recording settlement, balance goes to zero

**Test Scenario B — 3-person non-divisible split (tests F-7):**
1. Create event with 3 participants (A, B, C)
2. A pays 10.000 OMR, global scope
3. Expected per-person: 3.333 each (but 3.333 × 3 = 9.999, not 10.000)
- [ ] Verify: does the 0.001 remainder disappear?
- [ ] Verify: does settle-up show the correct total still outstanding?
- [ ] Verify: do net balances across all members sum to exactly zero?

**Test Scenario C — Multiple expenses, mixed payers:**
1. Event with A, B, C
2. A pays 30.000 global
3. B pays 15.000 global
4. C pays 0
5. Expected: total 45.000, each owes 15.000
   - A net: +15.000 (paid 30, owes 15)
   - B net: 0.000 (paid 15, owes 15)
   - C net: -15.000 (paid 0, owes 15)
- [ ] Settle Up shows C → A: 15.000 (single settlement)
- [ ] B has no outstanding balance

**Test Scenario D — Sub-group expense:**
1. Event with A, B, C, D
2. A pays 20.000, subGroup scope (only A, B in sub-group)
3. Expected: only A and B split — each owes 10.000
   - C and D unaffected
- [ ] Settle Up shows B → A: 10.000
- [ ] C and D have zero balance

**Test Scenario E — Cross-event group settle-up:**
1. Group with events E1 and E2
2. E1: A pays 10 (A, B, C)
3. E2: B pays 9 (A, B, C)
4. Group-level settle-up should aggregate:
   - A net: 10 - 3.333 - 3 = +3.667
   - B net: -3.333 + 9 - 3 = +2.667
   - C net: -3.333 - 3 = -6.333
- [ ] Group settle-up shows correct aggregated amounts
- [ ] Per-event breakdown matches event-level balances

---

## 6. Event Modules

### 6.1 Gear

**Screen:** GearScreen
**Route:** `/group/:gid/event/:eid/gear`

- [!] Shows gear items list **BUG: Gear page fails to load entirely**
- [-] Can add gear item (name, assigned to) — BLOCKED by load failure
- [-] Can mark item as packed/unpacked — BLOCKED
- [-] Can delete item (soft delete) — BLOCKED
- [-] Offline: gear changes sync when back online — BLOCKED

### 6.2 Logistics

**Screen:** LogisticsScreen
**Route:** `/group/:gid/event/:eid/logistics`

- [x] Shows sub-groups
- [!] Can create sub-group with members **BUG: Adding member to sub-group returns permission-denied error (Firestore rules)**
- [-] Sub-group membership correct — BLOCKED by permission error
- [-] Sub-groups available as expense scope in ledger — BLOCKED

### 6.3 Vault

**Screen:** VaultScreen
**Route:** `/group/:gid/event/:eid/vault`

- [x] Shows document list
- [!] Can upload document (max 25 MB) **BUG: File picker opens, file selected, but nothing happens — upload silently fails**
- [-] Can view/download document — BLOCKED by upload failure
- [-] Signed URL works (1-hour expiry) — BLOCKED
- [-] Can delete document — BLOCKED
- [ ] Offline banner shown when offline

### 6.4 Memories

**Screen:** MemoriesScreen
**Route:** `/group/:gid/event/:eid/memories`

- [x] Shows photo grid
- [!] Can upload photos **BUG: Upload fails with `[firebase_storage/object-not-found] No object exists at the desired reference.` — storage bucket/path misconfigured**
- [-] Photo viewer works (full-screen overlay) — BLOCKED by upload failure
- [-] Can delete memories — BLOCKED
- [ ] Offline banner shown when offline

---

## 7. Activity & Feed

### 7.1 Event Activity

**Screen:** ActivityFeedScreen
**Route:** `/group/:gid/event/:eid/activity`

**Known Bug — G-7:** `addActivityLog` is never called. This screen will likely be empty.

- [x] Navigate to event activity screen
- [x] Does it show any entries? (Expected: empty due to G-7) **CONFIRMED EMPTY — even after creating expenses and settlements**
- [-] If entries exist, verify they are correct — N/A, screen is empty

### 7.2 Cross-Group Activity

**Screen:** CrossGroupActivityScreen
**Route:** `/activity` (bottom nav)

- [ ] Shows activity from all groups
- [ ] Entries sorted by most recent first
- [ ] Each entry shows group name, action, actor, timestamp

---

## 8. Profile & Settings

**Screen:** ProfileScreen
**Route:** `/profile`

- [ ] Shows user avatar and device name
- [ ] Display name is editable
- [ ] Notification toggle works
- [ ] About section visible
- [ ] App version displayed
- [ ] Statistics section (groups count, events count, total spent)

---

## 9. Navigation & Transitions

- [x] All slide-right transitions work (module screens)
- [x] Slide-up transitions work (create group, join group)
- [x] Fade transitions work (onboarding, home)
- [!] Back button returns to correct parent screen **BUG: GoRouter "There is nothing to pop" crash in ModuleHeader back button (module_header.dart:116). Repeated taps cause cascade of GoError exceptions**
- [ ] Deep link: `/group/:gid` opens correct group
- [ ] Deep link: `/group/:gid/event/:eid/ledger` opens correct ledger
- [!] No stuck screens or navigation dead-ends **BUG: After balance card loading gets stuck, going back causes entire app to show skeletons — stuck state**

---

## 10. Offline Mode

- [ ] Enable airplane mode
- [ ] App still loads (cached data visible)
- [ ] Offline banner appears on screens
- [ ] Can browse existing groups, events, expenses
- [ ] Can add expense offline → queued for sync
- [ ] Re-enable network → data syncs
- [ ] No data loss after sync
- [ ] Connectivity indicator updates correctly

---

## 11. Error States

- [ ] Network error during group creation → shows error, doesn't corrupt state
- [ ] Invalid invite code → clear error message
- [ ] Empty expense amount → validation error
- [ ] Double-tap on "Save" → only one expense created (or at least not duplicate)
- [ ] Deleted group → home screen updates, no crash if navigating back

---

## 12. Known Bugs to Verify

These bugs were identified during code audit. Mark verified/not-reproducible/confirmed.

### Critical (P0)

| ID | Bug | How to Verify | Status |
|----|-----|---------------|--------|
| F-7 | Rounding remainder on non-divisible splits | 10.000 / 3 people → check if balances sum to 0 | [ ] |
| F-3 | `currency` hardcoded to OMR | Create expense in non-OMR group → check if currency is preserved | [ ] |
| G-7 | Event-level `addActivityLog` never called | Navigate to event activity screen → should be empty | [x] CONFIRMED — empty even after creating expenses and settlements |

### High (P1)

| ID | Bug | How to Verify | Status |
|----|-----|---------------|--------|
| G-1 | joinGroup creates duplicate member docs | Join group twice with same user → check member count | [ ] |
| G-4 | Activity shows "Someone" not device name | Check any activity entry → verify actor name | [x] CONFIRMED — "Someone joined" instead of "Nasser joined" |
| F-11 | Group settlements not in perEventBreakdown | Record group settlement → check per-event breakdown | [ ] |

### Medium (P2)

| ID | Bug | How to Verify | Status |
|----|-----|---------------|--------|
| F-1 | MoneySerializer truncates instead of rounds | Enter 0.0005 OMR expense → check stored value | [ ] |
| F-5 | Scope change doesn't clear stale fields | Edit subGroup expense to global → verify in Firestore | [ ] |
| G-8 | No duplicate name enforcement | Join group, pick already-taken name → should it block? | [ ] |
| G-2/3 | Partial write on create/join | Kill app during group creation → check data consistency | [ ] |
| F-12 | Partial loading shows stale balance | Slow network → check if balance flickers to wrong value | [ ] |
| G-9 | Empty members → infinite loading | Remove all members → does settle-up spinner forever? | [ ] |

### NEW — Discovered During UAT Session 2 (2026-04-06)

| ID | Severity | Bug | Details |
|----|----------|-----|---------|
| U-1 | ~~P0~~ P2 | Balance card stuck loading → app skeleton lock | **FIXED** — 3 deadlock paths removed in group_balance_provider.dart + error-swallowing handleError removed from expense_provider.dart. Card now shows error with refresh recovery. Root cause: Firestore permission-denied on initial load (transient, resolves on refresh) |
| U-2 | ~~P0~~ FIXED | GoRouter "nothing to pop" crash | **FIXED** — ModuleHeader now checks canPop() before calling pop(), falls back to context.go('/home') |
| U-3 | P1 | Expense card shows "Unknown" as payer | Transaction list shows "Unknown" instead of actual payer display name |
| U-4 | P1 | Settlement activity shows "Unknown → Unknown" | Activity entries for settlements don't resolve member names |
| U-5 | P1 | Gear page fails to load | Gear screen does not render — blank/error state |
| U-6 | P1 | Vault document upload silently fails | File picker opens, file selected, nothing happens — no error shown to user |
| U-7 | P1 | Memories upload fails — storage path error | `[firebase_storage/object-not-found] No object exists at the desired reference.` — bucket or path misconfigured |
| U-8 | P1 | Logistics add member — permission denied | `[cloud_firestore/permission-denied]` when adding member to sub-group — Firestore rules issue |
| U-9 | P2 | Date text clipped in event creation | Date picker display text is cut off from below (visual overflow) |
| U-10 | P2 | Activity tab and Chats tab show "Coming Soon" | Bottom nav tabs not yet implemented |

---

## 13. Stale Documentation

| File | Issue | Action |
|------|-------|--------|
| `docs/setup/push-notifications.md` | References Supabase (removed in v1.0) | Rewrite for Firebase Cloud Messaging |
| `CLAUDE.md` | Says LocalDatabase version is 5 (actually 6) | Update |
| `CLAUDE.md` | Some spacing token values outdated | Verify and update |
| `CLAUDE.md` | References Supabase in some sections | Clean up |

---

## Session Log

Track UAT progress across sessions here.

| Date | Session | Tests Completed | Bugs Found | Notes |
|------|---------|-----------------|------------|-------|
| 2026-04-06 | 1 | Automated: 883/883 pass. Code audit complete. | 19 bugs identified via code audit | Docs generated, test fix committed |
| 2026-04-06 | 2 | Sections 2-6 manual UAT. Home, Groups, Events, Ledger, Modules tested. | 10 new bugs (U-1 through U-10). G-4, G-7 confirmed. | Settle-up works. Major blockers: storage/permissions, stuck loading, "Unknown" names |
| | | | | |

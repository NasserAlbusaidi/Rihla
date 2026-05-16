# Rihla — Product Specification

> Source-of-truth product description for the v1 launch build.
> Last reconciled 2026-05-16 from the live codebase (v1.2.0+15).
> Every behaviour below is grounded in actual screens/services — no aspirational features.

---

## 1. What Rihla Is

Rihla ("journey" in Arabic) is a Splitwise-style group expense splitter organised by **groups** and **events**. A group is a persistent circle of friends; an event is a specific trip, dinner, or outing held inside that group. Expenses belong to events, balances persist at the group level across all events, and friends settle up across the entire shared history — not just within a single event.

**Core value:** Groups persist; financial history accumulates across events; settle-up is debt-minimising and works across the whole group.

**Target market:** Oman / GCC first, then global. Default currency is OMR (Omani Rial, 3-decimal precision). Money math uses the `Decimal` package — no floats anywhere.

**Tech footprint:** Flutter mobile app (`safar` package, Android `com.safar.safar`), Firebase backend (Firestore + Auth + Cloud Functions + FCM — **no Storage SDK use**), SQLite local cache for fast reads, Firestore offline persistence for write replay.

---

## 2. Identity & Auth

There is no sign-up screen and no password. The app is anonymous-by-default, with optional email-link recovery available from Profile.

- On first launch, `FirebaseConfig.ensureAnonymousSession()` creates an anonymous Firebase user. The UID is the primary identity.
- The user picks a **display name** when they create or join their first group. The name lives on each `GroupMember` row (`displayName`) and is also cached in `SharedPreferences` as `deviceName`.
- The same anonymous UID can be a `CREATOR` in some groups and a `MEMBER` in others. There is no account, no profile across groups; the display name can be different per group.
- Users may link an email from Profile and later restore access through `/recover` using Firebase email-link sign-in. If they never link an email, uninstalling or clearing app data still loses access for that device.

---

## 3. Domain Model

```
Group ──< Event ──< Expense
  │         │
  │         ╰──< Settlement (event-level)
  │
  ╰──< GroupMember (CREATOR | MEMBER)
  │
  ╰──< Settlement (group-level, cross-event)
```

### Group (`lib/features/groups/models/group_model.dart`)
- `id`, `name`, `inviteCode` (6-char), `createdBy` (creator UID), `memberIds` (array), `currency` (default `OMR`), `createdAt`.

### GroupMember
- `userId`, `displayName`, `role` ∈ `{ 'CREATOR', 'MEMBER' }`, `isShadow`, `joinedAt`.
- `isShadow` exists to support placeholder members added by the creator before they join (not exposed in v1 UI but reserved by the schema).

### Event (`lib/features/events/models/event_model.dart`)
- `id`, `name`, `type` ∈ `{ trip, camping, travel, nightDayOut, custom }`, `groupId`, `createdBy`, `participantIds`, `participantNames` (snapshot map), `modules`, optional `startDate` / `endDate` / `description`, soft-delete via `isDeleted` + `deletedAt`.
- `EventModules` previously toggled gear/logistics/vault/memories; **after the Phase 39 strip, only `ledger` remains** and it's `true` for every event type.
- Participants are a subset of the parent group's members.

### Expense (`lib/features/ledger/models/expense_model.dart`)
- `payerParticipantId`, `amount` (Decimal), `description`, `category`, `scope` ∈ `{ global, subGroup (legacy), personal, custom }`, optional `customSplitParticipants`, soft-deleted.
- Split rules:
  - **global** — split equally among all event participants.
  - **personal** — payer eats it themselves (does not redistribute).
  - **custom** — split among an explicit subset.
  - **subGroup** — legacy; back-compat falls through to global.
- Rounding: per-head share is truncated to 3 decimals; the deterministic last recipient (sorted alphabetically) absorbs the residual so `sum(shares) == amount` exactly. No rounding errors leak.

### Settlement
- A payment from one participant to another. Recorded against an event (event-level settle-up) or a group (cross-event settle-up). Soft-deleted.

---

## 4. Roles & Permissions

Two roles per group:

| Capability                       | CREATOR | MEMBER |
|----------------------------------|:-------:|:------:|
| Create event                     | ✅      | ❌     |
| Rename group                     | ✅      | ❌     |
| Remove member                    | ✅      | ❌     |
| Delete group                     | ✅      | ❌     |
| Rename event                     | ✅      | ❌     |
| Edit event dates / description   | ✅      | ❌     |
| Delete event                     | ✅      | ❌     |
| Add expense                      | ✅      | ✅     |
| Edit / delete own expense        | ✅      | ✅     |
| Settle up                        | ✅      | ✅     |
| Leave group (self)               | ✅*     | ✅     |
| View everything                  | ✅      | ✅     |

*The creator cannot leave a group while other members are present (UI surfaces this constraint in `GroupDangerSection`).

The role check pattern used throughout the app: `currentUserId == group.createdBy`. This is computed at the screen level and passed down to subwidgets — there is no global `isCreator` provider.

---

## 5. Navigation Map

The app uses GoRouter. Every route is declarative; deep links work without preloaded state. See `lib/core/router/app_router.dart`.

```
/  (splash)                         → /home if onboarded, else /onboarding
/onboarding                         (3-page first-launch flow)
/home                               (HomeScreen, wrapped in BottomNavShell)
/profile                            (ProfileScreen)
   /link-email                      (LinkEmailScreen — opt-in account recovery)
      /sent                         (LinkEmailSentScreen)
/activity                           (CrossGroupActivityScreen, also tab 1)

/recover                            (RecoverScreen — Home empty-state CTA)
   /pending                         (RecoverPendingScreen — ?email=)

/create-group                       (CreateGroupScreen)
/join-group                         (JoinGroupScreen)
/join/:code                         (deep-link entry into JoinGroupScreen)

/group/:gid                         (GroupDetailScreen)
   /settings                        (GroupSettingsScreen)
   /settle-up                       (GroupSettleUpScreen, ?memberId=)
   /activity                        (GroupActivityScreen)
   /create-event                    (EventTypePickerScreen)
   /create-event/:type              (CreateEventScreen)
   /event/:eid                      (EventCommandCenter — reachable but UI bypasses to /ledger)
      /ledger                       (LedgerScreen)        ← landing page when tapping an event card
         /add                       (AddExpenseScreen)
         /edit/:expId               (EditExpenseScreen)
         /settle-up                 (SettleUpScreen, event-level)
      /activity                     (ActivityFeedScreen, event-level)
      /settings                     (EventSettingsScreen)
```

Page transitions: module routes use Material 3 `SharedAxisTransition` (horizontal); `/onboarding`, `/home`, `/profile`, and `/activity` fade; `/create-group` and `/join-group` slide up.

> Note: `/event/:eid` (EventCommandCenter) is reachable in the router but the UI never navigates to it — event cards now jump straight to `/event/:eid/ledger`. This was intentional after Phase 39 reduced events to a single module. EventCommandCenter remains as dead-but-not-orphaned code.

---

## 6. Bottom Navigation

The home shell (`BottomNavShell`) renders three tabs. Tab state is preserved by stacking the three screens with `AnimatedOpacity` + `IgnorePointer` rather than a stateful router.

| Idx | Tab      | Screen                          |
|----:|----------|---------------------------------|
| 0   | Groups   | `HomeScreen` (dashboard)        |
| 1   | Activity | `CrossGroupActivityScreen`      |
| 2   | Profile  | `ProfileScreen`                 |

---

## 7. Screens (User-Facing Catalog)

There are 17 screens in the app. They fall into five clusters.

### 7.1 Entry & Shell

#### Splash (`/`)
Brand-coloured warm-sand frame shown for the duration of Firebase + SharedPreferences hydration. `_AuthGate` (`main.dart`) ensures a Firebase anonymous session before render and retries on `internal-error` for corrupted restored sessions. The router then redirects to `/onboarding` if `onboardingComplete` is false in `AppSettings`, otherwise to `/home`. No user interaction.

#### Home Dashboard (`/home`, tab 0)
The core landing screen. Sections (top → bottom):
1. **Greeting strip** with avatar, "Hi, {name}", and a tap target that opens `/profile`.
2. **Balance Hero Card** — aggregated net balance across all groups (you owe / you are owed).
3. **Quick Action Tray** — four buttons:
   - Add Expense (jumps to the first group's add-expense flow if one group exists; otherwise the user must pick a group first)
   - Settle Up
   - Invite Friend (share invite code via `share_plus`)
   - Activity (jumps to `/activity`)
4. **Group Cards** — one per group; shows your personal balance in that group, last activity, and member count. Tapping pushes `/group/:gid`.
5. **Recent activity strip** (last few events across all groups).
6. **Weekly spending card**.

When the user has zero groups, the dashboard shows an empty state with a "Create Group" CTA. When data is loading, a `skeletonizer` skeleton renders.

#### Profile (`/profile`, tab 2)
Sections:
- **Identity** — circular avatar with initials, current display name, tap to edit (bottom sheet).
- **Stats** — counts and totals derived from the user's groups/events.
- **Notifications** — toggles for FCM push categories.
- **Display** — theme mode (system / light / dark) — fully wired and persisted.
- **About** — version, links.
- **Support** — contact / FAQ surface.

#### Cross-Group Activity (`/activity`, tab 1)
A flat reverse-chronological feed merging activity from every group the user is in. Expense, settlement, and group-event entries are interleaved. Tapping an entry jumps to the relevant group/event. Empty state: *"No activity yet — Activity from all your groups will appear here."*

### 7.2 Group Lifecycle

#### Create Group (`/create-group`)
Two text fields (group name, your display name) and a primary button. On submit, creates the group with the current user as `CREATOR`, persists the display name to settings, and `pushReplacement`s to `/group/:gid`. The next screen surfaces the 6-character invite code with copy + share buttons.

#### Join Group (`/join-group`)
Two text fields (6-character invite code, your display name). The button is disabled until the code is exactly 6 characters. Errors map to friendly messages (`Invalid invite code`, etc.). On success, `pushReplacement`s to `/group/:gid`.

#### Group Detail (`/group/:gid`)
The hub for one group. Section order (per design lock D-04):
1. **Header** with group name and overflow menu (settings / activity).
2. **Stats grid** — total spent, your share, member count.
3. **Settle-Up CTA** — only renders when the user has a non-zero net balance in this group; jumps to `/group/:gid/settle-up`.
4. **Events** — a list of `EventCard`s, sorted most recent first. Tapping pushes `/group/:gid/event/:eid/ledger` (skipping the old EventCommandCenter hub).
5. **Members & Balances** — per-member cards showing their net position; expanding a card reveals their settlement breakdown.
6. **Recent Activity** preview (last few entries; "View all" pushes `/group/:gid/activity`).

The **FAB** ("Create event") and the **Events empty-state CTA** are visible only to the creator. Members see *"Waiting for the group creator to add the first event."*

#### Group Settings (`/group/:gid/settings`)
Three sections:
- **GroupInfoSection** — group name (editable by creator), invite code with copy button, currency display.
- **GroupMembersSection** — list of members with role badges; creator can remove non-creator members from a bottom sheet.
- **GroupDangerSection** — "Leave group" for everyone (with the creator/last-member constraint), "Delete group" for the creator.

#### Group Settle-Up (`/group/:gid/settle-up`)
Aggregates **every event's balances** in the group into one pool, runs the greedy debt-minimising optimiser, and renders the suggested transactions. Optional `?memberId` query param pre-filters to a specific counterparty. Each suggested settlement has an "Edit amount" path before recording.

#### Group Activity (`/group/:gid/activity`)
Chronological feed of every action in this group: events created/deleted, expenses added/edited/removed, settlements recorded, members joined/left. Filter chips at the top scope to: All / Events / Expenses / Settlements / Members.

### 7.3 Event Lifecycle

#### Event Type Picker (`/group/:gid/create-event`)
A grid of cards: **Trip · Camping · Travel · Night/Day Out · Custom**. Tapping pushes `/create-event/:type` with the chosen type baked into the URL. The header shows the parent group name as a subtitle.

#### Create Event (`/group/:gid/create-event/:type`)
Form sections:
- Event name.
- Optional date range picker.
- Optional description.
- **Participant picker** — pre-populated with all current group members; the creator can deselect anyone who isn't part of this event. At least one participant is required (a snackbar enforces this).
- **Save** writes the Event to Firestore, snapshots `participantNames` for offline-safe display, and `pushReplacement`s to the new event's `/ledger`.

#### Event Settings (`/group/:gid/event/:eid/settings`)
Two sections:
- **EventInfoSection** — name, start date, end date, description (creator-editable).
- **EventDangerSection** — "Delete event" (creator only; soft-delete with confirmation dialog, logs an activity entry).

#### Event Activity (`/group/:gid/event/:eid/activity`)
A scoped version of the group activity feed showing only entries tied to this specific event.

### 7.4 Ledger (the heart of the app)

#### Ledger (`/group/:gid/event/:eid/ledger`)
Single-scroll layout — there are no tabs:
1. **Dark `ModuleHeader`** with title "Ledger", subtitle = event name, and an overflow menu (`⋮`) with **Event activity** and **Event settings**.
2. **Offline banner** when applicable.
3. **`LedgerHeroCard`** — your net balance for this event, the event's total spend, expense + settlement counts, and two CTAs: **Add Expense** and **Settle Up**.
4. **TRANSACTIONS overline**.
5. **Timeline** — `FadeInList` of expenses and settlements interleaved by date desc. Each expense card shows payer, amount, description, category icon, and split scope; tapping it opens the edit screen if it's yours.

Empty state: a friendly prompt with the same Add Expense CTA from the hero card.

#### Add Expense (`/...ledger/add`)
- **Amount** — full-screen numeric keypad with `.` and backspace; validates positive Decimal.
- **Payer** — picker of event participants; defaults to the current user.
- **Description** — free text.
- **Category** — chip selection from the curated `ExpenseCategory` list.
- **Split scope** — `Global · Personal · Custom`; choosing `Custom` opens a participant multi-select.
- **Save** writes the expense, optimistically updates SQLite, enqueues a sync, and pops back to the Ledger.

#### Edit Expense (`/...ledger/edit/:expId`)
Identical form pre-populated from the existing expense. Includes a "Delete" affordance (soft-delete, logged in activity).

#### Event Settle-Up (`/...ledger/settle-up`)
Runs the greedy optimiser against this event's balances only. Renders the suggested transactions with editable amounts, requests confirmation, then records the settlement(s).

---

## 8. Settlement Optimisation

The optimiser is a **greedy minimum-transactions algorithm**:
1. Compute each participant's net position (`paid − owed`) including prior settlements.
2. Bucket into creditors (positive) and debtors (negative), sorted descending by absolute value.
3. Repeatedly match the largest creditor against the largest debtor for `min(|a|, |b|)`.
4. Stop when both buckets are empty.

This minimises the number of transactions but does not preserve "who owed whom historically." For a group of N members with non-trivial overlap, it typically produces ⌈N/2⌉ or fewer transactions.

The same optimiser runs at both event scope (`/...ledger/settle-up`) and group scope (`/group/:gid/settle-up`); the only difference is the input set of expenses + prior settlements.

---

## 9. Offline-First Behaviour

The user can launch the app, create groups, add expenses, and settle up while completely offline. The mechanics:

- **Reads** — every provider reads from a Firestore `StreamProvider`. Firestore's local persistence (`persistenceEnabled: true`, `cacheSizeBytes: CACHE_SIZE_UNLIMITED`, configured in `FirebaseConfig.initialize()` before any read/write) serves the last snapshot when offline. Selected streams (`eventExpensesProvider`, `eventSettlementsProvider`, etc.) `asyncMap` snapshots into SQLite cache repositories under `lib/core/services/cache/` for fast local random-access reads by `BalanceCalculator`.
- **Writes** — service methods call Firestore directly. The Firestore SDK persists pending mutations locally and replays them automatically on reconnect — there is no custom sync queue in this codebase.
- **Connectivity** — `ConnectivityNotifier` (`lib/core/providers/connectivity_provider.dart`) checks reachability every 60 seconds with a `Source.server` read against `inviteCodes` (a publicly-readable collection). State transitions between `online`, `offline`, and `syncing`.
- **Seed-on-entry** — opening an event eagerly subscribes to its full data (expenses, settlements, participants) so the Ledger lands hot.

The user sees an **`OfflineBanner`** at the top of every data-bound screen when `connectivityProvider` reports `offline`.

---

## 10. Activity Logging

Every state-changing action writes a `GroupActivityLog` row:
- `expense_added`, `expense_edited`, `expense_deleted`
- `settlement_recorded`, `settlement_voided`
- `event_created`, `event_renamed`, `event_deleted`
- `group_renamed`, `member_joined`, `member_removed`, `member_left`

Each entry stores: who did it (UID + display name snapshot), what happened (templated description like *"settled OMR 12.500 with Sarah"*), when, and a payload of relevant IDs. The activity feed at all three levels (cross-group, group, event) reads from this log.

---

## 11. End-to-End User Journeys

### 11.1 First-time user, creator path
1. Launches app → splash → home with empty state.
2. Taps **Create Group**, enters group name + display name.
3. Lands on Group Detail; sees an empty events list and a FAB.
4. Taps FAB → picks event type → fills form → saves.
5. Lands on the new Ledger; taps **Add Expense**, enters amount and details, saves.
6. Shares the invite code with friends.

### 11.2 Joiner path
1. Receives a 6-character invite code.
2. Launches app → home empty state → taps **Join Group**.
3. Enters code + their display name.
4. Lands on Group Detail; sees the events the creator has set up (no FAB).
5. Opens an event → sees the Ledger → adds their own expenses or settles up.

### 11.3 Settle-up path
1. User opens Group Detail, sees a non-zero personal balance + a Settle-Up CTA.
2. Taps it → group settle-up screen runs the optimiser across all events.
3. Reviews the suggested transactions, optionally edits an amount.
4. Confirms → settlements are recorded; balances re-zero where applicable.

---

## 12. Out of Scope for v1

The following were intentionally removed in Phase 39 ("Strip to Shippable") and are *not* in v1:
- Memories module (photo upload per event)
- Vault module (document upload per event)
- Logistics module (sub-groups, transport tracking)
- Gear module (packing lists)
- Multi-currency conversion (per-event currency, FX rates)
- Payment processing
- Chat / messaging tab

The Firestore schema and SQLite cache still tolerate legacy keys for these features (silent `fromMap` ignore) so existing user data does not break, but no UI exposes them. The 3-page first-launch onboarding flow (gated by `onboardingComplete` in `AppSettings`) shipped separately and *is* part of v1.

---

## 13. Known Limitations (v1)

- **Recovery is opt-in.** Users who never link an email still lose access if they uninstall or clear app data.
- **No iOS CI.** Android-only release pipeline. iOS builds are manual; iOS launch soft-deferred ~weeks behind Android Production.
- **No general multi-device account workflow.** Anonymous UIDs are device-bound unless the user has linked and restored through email-link recovery.
- **Soft-delete only** for expenses, events, groups, and settlements where supported — they remain in Firestore until retention tooling exists.
- **OMR-only.** Group `currency` field exists in the schema and the spec is locked (`docs/design/group-currency.md`), but the UI still hardcodes display formatting to OMR pending implementation.
- **Orphan anon-UID cleanup is partial.** After email-link recovery, `cleanupAnonUidArtifacts` (added in v1.2.0+15) removes most artifacts from the abandoned anon UID, but UIDs with downstream references in `memberIds` / `participantIds` remain in Firestore and require a future server-side reconciliation pass.

---

## 14. Glossary

| Term | Meaning |
|------|---------|
| **Group** | A persistent circle of friends. Has one creator, many members, an invite code. |
| **Event** | A trip, dinner, or outing inside a group. Owns the expenses and event-level settlements. |
| **Participant** | A subset of group members who are part of a specific event. |
| **Creator** | The user who created the group (or event). Has elevated permissions. |
| **Member** | Any user in a group who isn't the creator. |
| **Net balance** | `paid − owed + settlement_adjustment` for a participant within a scope. Positive = others owe you. |
| **Settle up** | Record one or more payments that bring net balances closer to zero. |
| **Soft delete** | `is_deleted = true` flag instead of row removal; preserves audit trail. |

---

*End of PRODUCT.md*

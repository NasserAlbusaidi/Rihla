# Phase 3: Events - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 03-events
**Areas discussed:** Event creation flow, Event types & templates, Event hub experience, Event timeline in group, Firestore data model, Pull-to-refresh fix, Event status/lifecycle, Offline behavior

---

## Event Creation Flow

### Entry point

| Option | Description | Selected |
|--------|-------------|----------|
| FAB on group detail | Floating action button on GroupDetailScreen — consistent with home screen FAB pattern | :heavy_check_mark: |
| Button in events section | "Create Event" button inside the empty events placeholder area | |
| Both FAB + inline button | FAB primary + "New Event" link in events section | |

**User's choice:** FAB on group detail
**Notes:** Consistent with Phase 2 home screen FAB pattern for create/join.

### Type selection UX

| Option | Description | Selected |
|--------|-------------|----------|
| Type picker first, then form | Step 1: full-screen type picker with visual cards. Step 2: form pre-filled based on type | :heavy_check_mark: |
| Single form with type dropdown | One screen with type selector at top, form below updates dynamically | |
| Bottom sheet type picker, then form | Tap FAB -> bottom sheet with type options -> selecting one opens creation form | |

**User's choice:** Type picker first, then form

### Form fields

| Option | Description | Selected |
|--------|-------------|----------|
| Name + dates only | Event name (required) and optional start/end dates. Currency from group. Participants auto-populated | :heavy_check_mark: |
| Name + dates + description | Add optional description/notes field | |
| Name + dates + budget | Add optional budget field | |

**User's choice:** Name + dates only (minimal friction)

### Participant selection model

| Option | Description | Selected |
|--------|-------------|----------|
| All members auto-added, no removal | Every group member is an event participant | |
| All members auto-added, creator can remove | Pre-populated but creator can deselect | |
| Creator picks from member list | Checkbox list, nothing pre-selected | :heavy_check_mark: |

**User's choice:** Creator picks from member list
**Notes:** Changed from recommendation. Follow-up determined: all pre-checked by default, creator deselects to exclude (best of both worlds).

### Participant picker UX

| Option | Description | Selected |
|--------|-------------|----------|
| All pre-checked, deselect to exclude | Starts with everyone selected. Creator unchecks non-joiners | :heavy_check_mark: |
| None checked, select to include | Starts empty, creator explicitly checks who's joining | |
| Creator always included, rest unchecked | Creator auto-selected and locked, others start unchecked | |

**User's choice:** All pre-checked, deselect to exclude

### Post-creation destination

| Option | Description | Selected |
|--------|-------------|----------|
| Event hub immediately | Navigate directly into event hub screen | :heavy_check_mark: |
| Back to group detail | Return to group detail where new event appears in timeline | |
| Share prompt first | Show share/invite prompt, then navigate to event hub | |

**User's choice:** Event hub immediately

### Event invite codes

| Option | Description | Selected |
|--------|-------------|----------|
| No event invite codes | Events are group-internal, only group members participate | :heavy_check_mark: |
| Events get invite codes | Each event gets a code for non-group-members | |

**User's choice:** No event invite codes

### Creation permissions

| Option | Description | Selected |
|--------|-------------|----------|
| Any member can create | Any group member can spin up an event | :heavy_check_mark: |
| Only group creator | Only CREATOR role can create events | |

**User's choice:** Any member can create

### Flow steps

| Option | Description | Selected |
|--------|-------------|----------|
| Type picker -> Form (name+dates+participants) | Two steps total | :heavy_check_mark: |
| Type picker -> Form -> Participants | Three steps | |
| You decide | Claude's discretion | |

**User's choice:** Two steps: type picker, then single form with everything

### Edit after creation

| Option | Description | Selected |
|--------|-------------|----------|
| Name and dates editable, type locked | Creator can rename and change dates, type fixed | :heavy_check_mark: |
| Everything editable | Name, dates, and type can all change | |
| Nothing editable in Phase 3 | Events immutable after creation | |

**User's choice:** Name and dates editable, type locked

### Event deletion

| Option | Description | Selected |
|--------|-------------|----------|
| Creator can delete, with confirmation | Only event creator can delete, soft delete with is_deleted flag | :heavy_check_mark: |
| No deletion in Phase 3 | Events permanent once created | |
| Any participant can delete | Any event participant can delete | |

**User's choice:** Creator can delete with confirmation (soft delete)

### Participant editing post-creation

| Option | Description | Selected |
|--------|-------------|----------|
| Creator can add/remove from group members | Event creator manages participant list from group members | :heavy_check_mark: |
| Any participant can add/remove | Open participant management | |
| No changes after creation | Participant list locked | |

**User's choice:** Creator can add/remove from group members

---

## Event Types & Templates

### Types to ship

| Option | Description | Selected |
|--------|-------------|----------|
| All five from requirements | Trip, Camping, Travel, Night/Day Out, Custom | :heavy_check_mark: |
| Subset: Trip, Camping, Night Out, Custom | Drop Travel (overlaps with Trip) | |
| Minimal: Trip, Custom only | Just two types to validate the system | |

**User's choice:** All five from requirements

### Module configuration

| Option | Description | Selected |
|--------|-------------|----------|
| Rich templates | Trip=all, Camping=ledger+gear+logistics+memories, Travel=ledger+logistics+vault+memories, Night Out=ledger, Custom=user picks | :heavy_check_mark: |
| Simplified templates | Trip/Camping/Travel=all, Night Out=ledger, Custom=picks | |
| You decide | Claude's discretion | |

**User's choice:** Rich templates

### Preset content

| Option | Description | Selected |
|--------|-------------|----------|
| Camping only | Camping gets tent, sleeping bag, cooler. Others start empty | :heavy_check_mark: |
| Camping + Trip presets | Camping gear + Trip travel essentials | |
| Presets for all trip-like types | Each type gets relevant presets | |

**User's choice:** Camping only

### Custom module picker

| Option | Description | Selected |
|--------|-------------|----------|
| Toggles on creation form | Toggle switches for each module. Ledger on by default, rest off | :heavy_check_mark: |
| Toggles with all on by default | Everything starts enabled | |
| Separate module picker screen | Full-screen picker with descriptions | |

**User's choice:** Toggles on creation form, Ledger on by default

### Type icons

| Option | Description | Selected |
|--------|-------------|----------|
| Distinct icons per type | Trip=airplane, Camping=tent, Travel=car, Night Out=moon, Custom=puzzle | :heavy_check_mark: |
| Icons on picker only | Type picker shows icons, event cards don't | |
| You decide | Claude's discretion | |

**User's choice:** Distinct icons per type, everywhere

### Type picker visual style

| Option | Description | Selected |
|--------|-------------|----------|
| Visual cards with icon + description | Cards with icon, name, description, module chips | :heavy_check_mark: |
| Simple list with icon + name | Compact list, one row per type | |
| You decide | Claude's discretion | |

**User's choice:** Visual cards with full descriptions

### Ledger always on

| Option | Description | Selected |
|--------|-------------|----------|
| Ledger always on | Every event type includes Ledger by default | :heavy_check_mark: |
| Ledger optional for Custom | Custom events can toggle Ledger off | |
| You decide | Claude's discretion | |

**User's choice:** Ledger always on

---

## Event Hub Experience

### Hub design approach

| Option | Description | Selected |
|--------|-------------|----------|
| Adapt CommandCenter for events | Refactor CommandCenter to work with both trips and events | :heavy_check_mark: |
| New EventHubScreen | Build fresh, keep CommandCenter for legacy trips | |
| Replace CommandCenter entirely | Delete and build universal hub | |

**User's choice:** Adapt CommandCenter

### Hub header

| Option | Description | Selected |
|--------|-------------|----------|
| Event name + type badge | Header shows event name large, type as small badge/chip, group name as subtitle | :heavy_check_mark: |
| Event name only | Just the event name | |
| You decide | Claude's discretion | |

**User's choice:** Event name + type badge

### Expense summary hero

| Option | Description | Selected |
|--------|-------------|----------|
| Keep expense summary | Show total spent and balance at top | :heavy_check_mark: |
| No summary until Phase 5 | Skip until cross-event financials built | |
| Simplified version | Total spent only, no balance | |

**User's choice:** Keep expense summary

### Navigation to event hub

| Option | Description | Selected |
|--------|-------------|----------|
| Tap event card in timeline | Event cards are tappable, push CommandCenter via Navigator.push | :heavy_check_mark: |
| Tap + dedicated Open button | Explicit button per card | |
| You decide | Claude's discretion | |

**User's choice:** Tap event card

### Module screen reuse

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse as-is, swap data source | Module screens unchanged, receive event ID | :heavy_check_mark: |
| Reuse UI, stub Firestore writes | Read-only/local-only in Phase 3 | |
| Full Firestore integration | Each module gets full Firestore R/W | |

**User's choice:** Reuse as-is, swap data source

### Data bridge

| Option | Description | Selected |
|--------|-------------|----------|
| Bridge: event creates Supabase trip | Firestore event + matching Supabase trip record | :heavy_check_mark: |
| Modules are placeholders | Module cards visible but "Coming soon" | |
| Full Firestore modules now | Build Firestore R/W for all modules in Phase 3 | |

**User's choice:** Bridge approach — pragmatic, functional events immediately

### Back navigation

| Option | Description | Selected |
|--------|-------------|----------|
| System back + header back arrow | Standard Flutter pattern with ModuleHeader | :heavy_check_mark: |
| Breadcrumb group name | Tappable group name as breadcrumb | |
| You decide | Claude's discretion | |

**User's choice:** System back + header back arrow

---

## Event Timeline in Group

### Display format

| Option | Description | Selected |
|--------|-------------|----------|
| Vertical list of event cards | Scrollable vertical list sorted by date | :heavy_check_mark: |
| Timeline with date markers | Visual timeline with date markers on left | |
| Horizontal carousel | Swipeable horizontal cards | |

**User's choice:** Vertical list of event cards

### Card content

| Option | Description | Selected |
|--------|-------------|----------|
| Icon + name + dates + participants + total | Full info per card | :heavy_check_mark: |
| Icon + name + dates only | Minimal info | |
| You decide | Claude's discretion | |

**User's choice:** Full info

### Past event treatment

| Option | Description | Selected |
|--------|-------------|----------|
| Subtle dimming | Reduced opacity for past events | :heavy_check_mark: |
| No visual distinction | All events look the same | |
| Past events collapsed | Hidden behind expander | |

**User's choice:** Subtle dimming

### Section UX

| Option | Description | Selected |
|--------|-------------|----------|
| Count chip + CTA empty state | "Events (3)" header + CTA empty state pointing to FAB | :heavy_check_mark: |
| No count, simple empty state | Just "Events" header | |
| You decide | Claude's discretion | |

**User's choice:** Count chip + CTA empty state

---

## Firestore Data Model

### Collection structure

| Option | Description | Selected |
|--------|-------------|----------|
| Subcollection: groups/{gid}/events | Events scoped to groups, security inherits | :heavy_check_mark: |
| Top-level events with groupId field | Enables collection group queries | |
| You decide | Claude's discretion | |

**User's choice:** Subcollection

### Participant storage

| Option | Description | Selected |
|--------|-------------|----------|
| Array field on event doc | participantIds array, same as group memberIds | :heavy_check_mark: |
| Subcollection | Each participant as separate doc | |
| Both array + subcollection | Array for security, subcollection for details | |

**User's choice:** Array field

### Read access

| Option | Description | Selected |
|--------|-------------|----------|
| Any group member can read all events | Transparency over privacy | :heavy_check_mark: |
| Only event participants can read | Private to participant list | |
| You decide | Claude's discretion | |

**User's choice:** Any group member can read

### Name storage

| Option | Description | Selected |
|--------|-------------|----------|
| Store names on event doc | participantNames map, denormalized | :heavy_check_mark: |
| Resolve from group members | Only UIDs on event, names from subcollection | |
| You decide | Claude's discretion | |

**User's choice:** Denormalized names on event doc

---

## Pull-to-Refresh Fix

| Option | Description | Selected |
|--------|-------------|----------|
| Invalidate Firestore stream provider | ref.invalidate on userGroupsProvider | :heavy_check_mark: |
| Full re-query with loading indicator | Explicit Source.server query | |
| You decide | Claude's discretion | |

**User's choice:** Invalidate provider

---

## Event Status/Lifecycle

### Status model

| Option | Description | Selected |
|--------|-------------|----------|
| Date-derived only | No status field, same as Trip model | :heavy_check_mark: |
| Explicit status enum | planning/active/completed/cancelled | |
| You decide | Claude's discretion | |

**User's choice:** Date-derived

### No-date events

| Option | Description | Selected |
|--------|-------------|----------|
| Treated as ongoing/active | Never dimmed, sorted to top | :heavy_check_mark: |
| Treated as upcoming | Sorted to top, semantically different | |
| You decide | Claude's discretion | |

**User's choice:** Ongoing/active

---

## Offline Behavior

### Caching strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Firestore offline persistence only | No SQLite for events in Phase 3 | :heavy_check_mark: |
| Firestore + SQLite dual cache | Mirror to SQLite alongside Firestore | |
| You decide | Claude's discretion | |

**User's choice:** Firestore only

### Offline creation

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, Firestore queues the write | Optimistic UI, sync on reconnect | :heavy_check_mark: |
| Block creation when offline | Require connectivity | |
| You decide | Claude's discretion | |

**User's choice:** Offline creation allowed

---

## Claude's Discretion

- Event card visual design and spacing
- Type picker card layout details
- Creation form validation UX
- Module toggle design for Custom events
- Bridge trip creation implementation
- Security rule details for events subcollection
- Camping preset gear item details
- Error handling UX

## Deferred Ideas

- Event archive/complete action
- Event notifications (ENH-04)
- Budget tracking per event
- Event description/notes field
- Non-group-member event participants
- Event duplication
- Group-level event search/filter

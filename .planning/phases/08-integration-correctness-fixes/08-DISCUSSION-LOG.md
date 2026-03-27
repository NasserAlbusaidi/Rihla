# Phase 8: Integration & Correctness Fixes - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-27
**Phase:** 08-integration-correctness-fixes
**Areas discussed:** Settle-up label format, Column rename strategy, Testing approach

---

## Settle-up Label Format

| Option | Description | Selected |
|--------|-------------|----------|
| Full event name | Show complete event name, truncate with ellipsis only if 30+ chars | ✓ |
| Type + name | Show event type prefix like 'Trip: Muscat Adventure' | |
| You decide | Claude picks based on existing UI patterns | |

**User's choice:** Full event name
**Notes:** Simple and clear approach

### Fallback for missing event name

| Option | Description | Selected |
|--------|-------------|----------|
| Fallback to event type | Show event type (e.g., 'Trip', 'Camping') when name missing | ✓ |
| Generic 'Untitled Event' | Show static fallback string | |
| You decide | Claude picks based on available data | |

**User's choice:** Fallback to event type

### Navigation from labels

| Option | Description | Selected |
|--------|-------------|----------|
| No navigation | Keep simple — just display name. Not a browsing screen | ✓ |
| Tap to navigate | Opens event's ledger for context | |

**User's choice:** No navigation

### Date alongside event name

| Option | Description | Selected |
|--------|-------------|----------|
| Name only | Keep labels clean, dates add visual noise | |
| Name + date | Helps distinguish events with similar names | ✓ |

**User's choice:** Name + date, format: "Event Name — Mar 15" (short month + day)

### Date format

| Option | Description | Selected |
|--------|-------------|----------|
| Short month + day | e.g., 'Camping Weekend — Mar 15'. Compact and readable | ✓ |
| Relative date | e.g., '2 weeks ago'. Gets vague over time | |
| Full date | e.g., 'March 15, 2026'. More formal, takes more space | |

**User's choice:** Short month + day

---

## Column Rename Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Rename in code only | Add comment noting trip_id holds eventId. No schema change, lowest risk | ✓ |
| Full SQLite migration | Bump schema version, rename column. Cleaner but requires migration | |
| You decide | Claude picks based on risk vs clarity tradeoff | |

**User's choice:** Rename in code only

### Clarity approach

| Option | Description | Selected |
|--------|-------------|----------|
| Comment only | Add clear comment at each usage site | ✓ |
| String constant | Define constant like kEventIdColumn = 'trip_id' with doc comment | |

**User's choice:** Comment only

### Audit scope

| Option | Description | Selected |
|--------|-------------|----------|
| Fix only the flagged one | Only the one identified in milestone audit | |
| Quick audit of related code | Scan BalanceCacheRepository and CacheService for similar mismatches | ✓ |

**User's choice:** Quick audit of related code

### If more mismatches found

| Option | Description | Selected |
|--------|-------------|----------|
| Fix if found | Fix any mismatches found during audit in this phase | ✓ |
| Note as tech debt | Log others for a future phase | |

**User's choice:** Fix if found

---

## Testing Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Unit + widget tests | Unit for cache/provider fixes, widget for settle-up UI | ✓ |
| Unit tests only | Test provider swap and cache fix in isolation | |
| Full regression suite | Unit + widget + integration tests. Most thorough | |

**User's choice:** Unit + widget tests

### Widget test coverage

| Option | Description | Selected |
|--------|-------------|----------|
| Both paths | Test event name display AND fallback to event type | ✓ |
| Happy path only | Just verify event names display | |

**User's choice:** Both paths

### Provider swap verification

| Option | Description | Selected |
|--------|-------------|----------|
| Verify non-empty list | Assert ExpenseScope.custom returns participants (proves the fix) | ✓ |
| Just verify provider reference | Test correct provider is referenced | |

**User's choice:** Verify non-empty list

---

## Claude's Discretion

- How to pass event name map to GroupSettleUpScreen
- Date formatting utility choice
- Comment wording for column mismatch

## Deferred Ideas

None

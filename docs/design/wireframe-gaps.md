# Wireframe Gaps

Backend assumptions made by the hi-fi wireframes that are not currently implemented.
Review each item and decide: implement it, simplify it, or remove the wireframe element.

---

## Status legend
- `DECIDE` — needs a call before implementation begins
- `SKIP-V1` — already confirmed cut from v1 (phase 39)
- `EASY` — small delta, can implement now
- `APPROVED` — decision made, cleared to build

---

## Screens confirmed CUT from v1 (phase 39)

| Screen | Status | Notes |
|--------|--------|-------|
| Onboarding (Brand / How-it-works / Setup) | SKIP-V1 | Phase 39 removed from v1 scope |
| Memories + MemoryDetail | SKIP-V1 | Phase 39 removed from v1 scope |
| Vault + VaultAdd | SKIP-V1 | Phase 39 removed from v1 scope |
| Logistics + LogisticsAdd | SKIP-V1 | Phase 39 removed from v1 scope |

---

## Feature gaps

### 1. Home — aggregate balance across all groups
**Wireframe:** "Across all journeys" hero card with a net balance, a sage/rust split bar showing "owed to you" vs "you owe", and a total amount owed.  
**Backend:** Per-group balances exist via `BalanceCalculator`. No aggregate cross-group view is implemented.  
**Decision needed:** Implement cross-group aggregation query, or simplify hero card to show only group count + last activity?

---

### 2. Profile — stats counters
**Wireframe:** 3-stat grid: "14 Trips this year", "3 Active groups", "$8.4k Settled lifetime".  
**Backend:** No analytics table. These require either: (a) count queries over trips/participants/settlements, or (b) a denormalized stats table updated on write.  
**Decision needed:** Implement live count queries, add a stats table, or drop the stat grid and show a simpler profile card?

---

### 3. Profile — email + handle + QR profile card
**Wireframe:** Profile card shows email address (`sam@example.com`), an `@handle` chip, and a QR code that deeplinks to the user's profile.  
**Backend:** App uses anonymous Firebase Auth. v1.2 added optional email-link recovery, so `linkedEmail` can live on `AppSettings` (SharedPreferences) when set — but there is no global username or profile document. `displayName` is stored per-group on `groups/{gid}/members/{uid}`.  
**Decision needed:** Surface the linked email (when present) on the profile card and add an optional `@handle` for sharing, or keep the profile card display-name-only and only show the email inside the linked-email section?

---

### 4. Activity feed — "Mentions you" filter chip
**Wireframe:** Activity filter row includes a "Mentions you" chip alongside All/Expenses/Settlements/Edits.  
**Backend:** No mention/tagging system exists in the Firestore activity-log subcollections.  
**Decision needed:** Drop the "Mentions you" chip from the filter row (activity feed still works without it), or implement a mention system?

---

### 5. Mark Paid — payment method + confirmation flow
**Wireframe:** Bottom sheet has Cash / Bank transfer / Other chips, plus "Alex will be notified and asked to confirm" copy implying a push notification confirmation round-trip.  
**Backend:** Settlement documents (Firestore subcollections under `groups/{gid}/events/{eid}/settlements` and `groups/{gid}/settlements`) record amounts but have no `payment_method` field and no confirmation state. Settlements are **append-only** (B3), so any confirmation flow needs to be additive (new doc) rather than mutating. FCM infrastructure exists but no confirmation flow is wired.  
**Decision needed:** Add `payment_method` enum column to settlements + a `confirmed_at` field + send FCM on mark-paid, or simplify to one-tap mark paid with no method/confirmation?

---

### 6. Event settle-up — "Was N payments" optimization savings chip
**Wireframe:** Sub-header shows "Was 7 payments" chip alongside the actual transfer count, surfacing how many transactions the algorithm eliminated.  
**Backend:** `BalanceCalculator` runs the greedy min-transactions algorithm but doesn't return the pre-optimization edge count.  
**Decision needed:** Expose pre-optimization count from `BalanceCalculator` and show the chip, or drop the "Was N payments" chip?

---

### 7. Group/trip delete — 30-day soft retention
**Wireframe:** Delete confirmation copy: "A copy is kept for 30 days in case you change your mind."  
**Backend:** Events and groups already use `isDeleted` + `deletedAt` for soft-delete, but there is no retention-window cleanup. Settlements are append-only; expenses are soft-deleted indefinitely.  
**Decision needed:** Implement a 30-day retention window for groups/events (requires a scheduled Cloud Function on Blaze), or change the confirmation copy to "This is permanent"?

---

### 8. Event settings — "Auto-include all" toggle
**Wireframe:** Settings screen has a "Splits & defaults" section with an "Auto-include all" toggle that automatically adds new group members to all future expenses in the event.  
**Backend:** No such flag exists on the event document. New participants are not auto-added to existing expenses.  
**Decision needed:** Add `auto_include_all` boolean to the event/trip row and implement the fan-out logic on participant add, or drop the toggle from Event Settings?

---

### 9. Event cover — generative scenery keyed to event "kind"
**Wireframe:** Event type picker has kinds (TRIP/CAMPING/TRAVEL/NIGHTOUT/CUSTOM) and event covers use generative SVG landscape scenes (marrakech/lisbon/hokkaido variants referenced in wireframe comments).  
**Backend:** Events store `type` (`EventType` enum: trip/camping/travel/nightDayOut/custom). The `CoverArt` shared widget already renders a procedural ticket-stub illustration keyed off event type + id. No generative scenery beyond that is currently implemented.  
**Decision needed:** Extend `CoverArt` with kind-specific scenery variants, or keep the ticket-stub aesthetic and call this gap closed?

---

### 10. Group identity — glyph picker
**Wireframe:** CreateGroup has a glyph picker with 6 specific Unicode symbols (⛺ ⌂ ↗ ✦ ◐ ⌘) as the group's avatar glyph.  
**Backend:** Groups have no dedicated `glyph` field; the group avatar today is rendered procedurally from `groupAvatarSlot(groupId)` + initials via `RAvatar`.  
**Decision needed:** Add `glyph` column to groups table and implement the picker UI, or use the group name initial as the avatar?

---

### 11. Join group — QR scan
**Wireframe:** JoinGroup screen has a "scan QR code" option alongside manual code entry.  
**Status:** QR **generation** shipped in v1.2 (T3.J/T3.K — `qr_invite_sheet.dart`, `profile_qr_sheet.dart`, deep-link `/join/:code` route). QR **scanning** is still not implemented.  
**Decision needed:** Add a camera scanner (`mobile_scanner` package) for joining, or rely on tap-the-QR-link UX via deep links?

---

### 12. Currency display — wireframes use USD ($)
**Wireframe:** All amounts displayed with `$` prefix and 2 decimal places (e.g., `$124.50`).  
**Backend:** App is OMR-first with 3 decimal places (`OMR 124.500`). Multi-currency is supported; per-group base currency is stored.  
**Impact:** Purely presentational — the wireframe is a US-market mockup. Implementation should use the group's `base_currency` and `AppFormatters.currency()`. No backend change needed.  
**Decision needed:** None — display OMR as designed; wireframe dollar amounts are placeholder data only.

---

### 13. EventHub — "Day X of Y" badge
**Wireframe:** A card overlapping the cover shows "Day 3 of 7" based on the current date vs. event start/end dates.  
**Backend:** Event start/end dates are stored. This is pure date math: `(now - startDate).inDays + 1` / `(endDate - startDate).inDays + 1`.  
**Status:** EASY — no backend change needed, implement during EventHub screen work.

---

### 14. Home — horizontal "journey ticket" cards
**Wireframe:** Home hero section has horizontally scrollable styled "ticket" cards (torn-edge aesthetic, event cover thumbnail, group name, date range, your balance on that trip).  
**Backend:** Groups + events exist. Cross-joining group → active event → your balance requires joining providers not currently exposed as a combined stream.  
**Decision needed:** Implement a combined `activeJourneysProvider` that aggregates group + event + balance, or simplify to a plain list of groups without the ticket card aesthetic?

---

## Summary

| # | Gap | Effort | Status |
|---|-----|--------|--------|
| 1 | Aggregate balance across groups | Medium | DECIDE |
| 2 | Profile stats counters | Medium | DECIDE |
| 3 | Profile email/handle/QR | Medium | DECIDE |
| 4 | Activity "Mentions you" filter | Low | DECIDE |
| 5 | Mark Paid payment method + confirmation | High | DECIDE |
| 6 | Settle-up "Was N payments" chip | Low | DECIDE |
| 7 | 30-day soft delete for groups/trips | High | DECIDE |
| 8 | Event "Auto-include all" toggle | Medium | DECIDE |
| 9 | Generative event cover per kind | Medium | DECIDE |
| 10 | Group glyph picker | Low | DECIDE |
| 11 | QR scan for invite codes (generation shipped in v1.2; scan still gap) | Medium | DECIDE |
| 12 | Currency display (USD → OMR) | None | No action needed |
| 13 | EventHub "Day X of Y" badge | Low | EASY |
| 14 | Home journey ticket cards | Medium | DECIDE |
| — | Onboarding screens | — | SKIP-V1 |
| — | Memories screens | — | SKIP-V1 |
| — | Vault screens | — | SKIP-V1 |
| — | Logistics screens | — | SKIP-V1 |

# Wireframe Gaps

Backend assumptions made by the hi-fi wireframes that are not currently implemented.
Review each item and decide: implement it, simplify it, or remove the wireframe element.

---

## Status legend

- `DECIDE` - needs a call before implementation begins
- `SKIP-V1` - already confirmed cut from v1 (phase 39)
- `EASY` - small delta, can implement now
- `IMPLEMENTED` - current app already covers this wireframe assumption
- `SIMPLIFIED` - current app intentionally uses a simpler v1 behavior
- `PARTIAL` - UI exists, but backend or full behavior is still missing
- `APPROVED` - decision made, cleared to build

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

### 1. Home - aggregate balance across all groups

**Wireframe:** "Across all journeys" hero card with a net balance, a sage/rust split bar showing "owed to you" vs "you owe", and a total amount owed.
**Current app:** Implemented via `crossGroupBalanceProvider` and `BalanceHeroCard`.
**Status:** IMPLEMENTED.

---

### 2. Profile - stats counters

**Wireframe:** 3-stat grid: "14 Trips this year", "3 Active groups", "$8.4k Settled lifetime".
**Current app:** Implemented via `profileStatsProvider` and the profile stats section.
**Status:** IMPLEMENTED.

---

### 3. Profile - email + handle + QR profile card

**Wireframe:** Profile card shows email address (`sam@example.com`), an `@handle` chip, and a QR code that deeplinks to the user's profile.
**Current app:** Profile UI shows display name, a derived handle, and a QR action placeholder. There is still no linked email backend or shareable profile deep link in v1.
**Decision needed:** Keep the v1 placeholder until account recovery/profile linking ships, or remove the QR action entirely.
**Status:** PARTIAL.

---

### 4. Activity feed - "Mentions you" filter chip

**Wireframe:** Activity filter row includes a "Mentions you" chip alongside All/Expenses/Settlements/Edits.
**Backend:** No mention/tagging system exists in activity logs.
**Decision needed:** Drop the "Mentions you" chip from the filter row, or implement a mention system?

---

### 5. Mark Paid - payment method + confirmation flow

**Wireframe:** Bottom sheet has Cash / Bank transfer / Other chips, plus "Alex will be notified and asked to confirm" copy implying a push notification confirmation round-trip.
**Backend:** `settlements` records the settlement but has no `payment_method` field and no confirmation state. FCM infrastructure exists but no confirmation flow is wired.
**Decision needed:** Add `payment_method` enum + `confirmedAt` field + send FCM on mark-paid, or simplify to one-tap mark paid with no method/confirmation?

---

### 6. Event settle-up - "Was N payments" optimization savings chip

**Wireframe:** Sub-header shows "Was 7 payments" chip alongside the actual transfer count, surfacing how many transactions the algorithm eliminated.
**Backend:** `BalanceCalculator` runs the greedy min-transactions algorithm but does not return the pre-optimization edge count.
**Decision needed:** Expose pre-optimization count from `BalanceCalculator` and show the chip, or drop the "Was N payments" chip?

---

### 7. Group/event delete - 30-day soft retention

**Wireframe:** Delete confirmation copy: "A copy is kept for 30 days in case you change your mind."
**Current app:** Delete confirmations use permanent-delete copy. Events have soft-delete fields, but there is no user-facing 30-day restore workflow.
**Decision needed:** Add 30-day restore/cleanup as a future recovery feature, or keep permanent-delete copy.
**Status:** SIMPLIFIED.

---

### 8. Event settings - "Auto-include all" toggle

**Wireframe:** Settings screen has a "Splits & defaults" section with an "Auto-include all" toggle that automatically adds new group members to all future expenses in the event.
**Backend:** No such flag exists on the event. New participants are not auto-added to existing expenses.
**Decision needed:** Add `autoIncludeAll` boolean to the event and implement fan-out logic on participant add, or drop the toggle from Event Settings?

---

### 9. Event cover - generative scenery keyed to event kind

**Wireframe:** Event type picker has kinds (TRIP/CAMPING/TRAVEL/NIGHTOUT/CUSTOM) and event covers use generative SVG landscape scenes.
**Current app:** Implemented as procedural `CoverArt.forEventType(...)` keyed by `EventType`, used in event covers and journey tickets.
**Status:** IMPLEMENTED.

---

### 10. Group identity - glyph picker

**Wireframe:** CreateGroup has a glyph picker with 6 specific symbols as the group's avatar glyph.
**Current app:** CreateGroup has the six-symbol glyph picker in the UI. Persistence should be confirmed before relying on glyphs across devices.
**Decision needed:** Verify whether the selected glyph is persisted on the group model; if not, add persistence or treat it as local-only.
**Status:** PARTIAL.

---

### 11. Join group - QR scan

**Wireframe:** JoinGroup screen has a "scan QR code" option alongside manual code entry.
**Backend:** Invite codes exist. No QR generation or scanning is implemented.
**Decision needed:** Implement QR code generation + camera scan, or drop QR and keep manual code entry only?

---

### 12. Currency display - wireframes use USD ($)

**Wireframe:** All amounts displayed with `$` prefix and 2 decimal places.
**Backend:** App is OMR-first with 3 decimal places. Multi-currency metadata exists; formatting should keep using `AppFormatters.currency()`.
**Impact:** Purely presentational - the wireframe is placeholder market data.
**Decision needed:** None - display OMR as designed; wireframe dollar amounts are placeholder data only.

---

### 13. EventHub - "Day X of Y" badge

**Wireframe:** A card overlapping the cover shows "Day 3 of 7" based on the current date vs. event start/end dates.
**Current app:** Implemented in `EventCommandCenter` when today's date falls inside the event date range.
**Status:** IMPLEMENTED.

---

### 14. Home - horizontal "journey ticket" cards

**Wireframe:** Home hero section has horizontally scrollable styled "ticket" cards with event cover thumbnail, group name, date range, and your balance on that trip.
**Current app:** Implemented via `activeJourneysProvider` and `JourneyTicketCard`.
**Status:** IMPLEMENTED.

---

## Summary

| # | Gap | Effort | Status |
|---|-----|--------|--------|
| 1 | Aggregate balance across groups | Medium | IMPLEMENTED |
| 2 | Profile stats counters | Medium | IMPLEMENTED |
| 3 | Profile email/handle/QR | Medium | PARTIAL |
| 4 | Activity "Mentions you" filter | Low | DECIDE |
| 5 | Mark Paid payment method + confirmation | High | DECIDE |
| 6 | Settle-up "Was N payments" chip | Low | DECIDE |
| 7 | 30-day soft delete retention | High | SIMPLIFIED |
| 8 | Event "Auto-include all" toggle | Medium | DECIDE |
| 9 | Generative event cover per kind | Medium | IMPLEMENTED |
| 10 | Group glyph picker | Low | PARTIAL |
| 11 | QR scan for invite codes | Medium | DECIDE |
| 12 | Currency display (USD -> OMR) | None | No action needed |
| 13 | EventHub "Day X of Y" badge | Low | IMPLEMENTED |
| 14 | Home journey ticket cards | Medium | IMPLEMENTED |
| - | Onboarding screens | - | SKIP-V1 |
| - | Memories screens | - | SKIP-V1 |
| - | Vault screens | - | SKIP-V1 |
| - | Logistics screens | - | SKIP-V1 |

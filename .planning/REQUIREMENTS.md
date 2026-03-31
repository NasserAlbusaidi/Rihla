# Requirements: Rihla v2.1 — Home Screen Completion

**Defined:** 2026-03-31
**Core Value:** Groups persist across events and accumulate financial history — friends settle up across trips, not just within one.

## v2.1 Requirements

Requirements for home screen completion. Each maps to roadmap phases.

### Quick Actions

- [ ] **ACT-01**: "Invite Friend" button opens a share sheet with a group invite code (currently navigates to join-group screen)
- [ ] **ACT-02**: When user has multiple groups, "Invite Friend" shows a group picker before sharing
- [ ] **ACT-03**: "Activity" button navigates to a cross-group activity view (currently tries to scroll but silently fails)

### Group Cards

- [ ] **CARD-01**: Group card shows visual differentiation between groups (color accent, event count, or member indicators)
- [ ] **CARD-02**: Group card displays richer context — last event name, recent activity hint, or total group spend

### Chart

- [ ] **CHRT-01**: Weekly spending chart shows amount labels on bars or Y-axis so values are readable
- [ ] **CHRT-02**: Chart title explicitly says "Weekly Spending" with currency context instead of just "This Week"

### Layout

- [ ] **LAYT-01**: Dashboard has improved visual density — tighter spacing, less dead whitespace between sections
- [ ] **LAYT-02**: Group list section has a clear header and visual separation from quick actions and activity

## Future Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Broken Pages

- **ERR-01**: Fix all placeholder/erroring screens across the app (MemoryDetail, EventActivity)
- **ERR-02**: Wire up BottomNavShell Activity/Chats/Profile tabs

### User Identity

- **USER-01**: Fix expense attribution — app doesn't know current user in some areas
- **USER-02**: Fix settle-up screen — wrong person shown as payer/receiver

### Event Management

- **EVNT-01**: Add event edit/delete UI (service methods exist, no UI caller)

### Cleanup

- **CLEAN-01**: Fix remaining 16 inline Color(0xFF...) literals
- **CLEAN-02**: Remove dead code (StaggeredGrid, domain aliases, orphaned logistics hero card)

## Out of Scope

| Feature | Reason |
|---------|--------|
| New modules or features | This milestone is fix + polish only |
| Backend/Firestore schema changes | Home screen uses existing data — no new collections |
| Bottom nav tab screens (Activity, Chats, Profile) | Separate milestone — larger scope |
| Dark mode | Doubles visual work; earthy palette is light-themed |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ACT-01 | Phase 23 | Pending |
| ACT-02 | Phase 23 | Pending |
| ACT-03 | Phase 23 | Pending |
| CARD-01 | Phase 24 | Pending |
| CARD-02 | Phase 24 | Pending |
| CHRT-01 | Phase 24 | Pending |
| CHRT-02 | Phase 24 | Pending |
| LAYT-01 | Phase 24 | Pending |
| LAYT-02 | Phase 24 | Pending |

**Coverage:**
- v2.1 requirements: 9 total
- Mapped to phases: 9
- Unmapped: 0

---
*Requirements defined: 2026-03-31*
*Last updated: 2026-03-31 after roadmap creation*

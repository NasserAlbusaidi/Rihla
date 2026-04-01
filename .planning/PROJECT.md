# Rihla v2 — Groups & Events

## What This Is

Rihla is a Flutter mobile app for group coordination and event planning with a warm, richly designed visual identity. Users create or join persistent groups (friend circles, travel crews), then spin up events inside those groups — trips, camping weekends, day outs, dinners, or custom events. Each event type comes with a template that unlocks relevant modules and pre-fills content. The app tracks finances at both the event level and the group level, maintaining running balances across all events.

## Core Value

Groups persist across events and accumulate financial history — friends settle up across trips, not just within one.

## Requirements

### Validated

- ✓ Offline-first with Firestore built-in persistence + SQLite balance cache — v1.0 Phase 4
- ✓ Expense tracking with Decimal precision (OMR, 3 decimal places) — pre-v1.0
- ✓ Balance calculation across four scopes (global, subGroup, personal, custom) — pre-v1.0
- ✓ Settlement optimization (greedy min-transactions) — pre-v1.0
- ✓ Gear checklist with assignment and priority — v1.0 Phase 11
- ✓ Sub-group logistics (car assignments, capacity) — v1.0 Phase 12
- ✓ Name-based members (no profile table joins) — pre-v1.0
- ✓ Anonymous auth via Firebase — v1.0 Phase 1
- ✓ Activity feed per event — pre-v1.0
- ✓ Document vault with signed URLs — pre-v1.0
- ✓ Trip memories (photo/media uploads) — pre-v1.0
- ✓ Onboarding flow — pre-v1.0
- ✓ FCM push notifications — pre-v1.0
- ✓ Multi-currency support — pre-v1.0
- ✓ Persistent groups — create/join a group, reuse across events — v1.0 Phase 2
- ✓ Group dashboard — member list, running balances across all events, group stats — v1.0 Phase 5
- ✓ Cross-event balance tracking — net balances accumulate at the group level — v1.0 Phase 5
- ✓ Event types with templates — Trip, Camping, Travel, Night/Day Out, Custom — v1.0 Phase 3
- ✓ Template-driven modules — event type controls which modules appear — v1.0 Phase 3
- ✓ Template presets — camping adds tent/sleeping bag to gear — v1.0 Phase 3
- ✓ Custom events — user picks modules manually, no preset content — v1.0 Phase 3
- ✓ Supabase → Firestore migration — supabase_flutter fully removed, Firebase-only — v1.0 Phase 7
- ✓ Firestore security rules — replace RLS with path-based Firestore rules — v1.0 Phase 1
- ✓ Firestore realtime listeners — replace unreliable Supabase Realtime — v1.0 Phase 4
- ✓ Strict test coverage — 80%+ coverage, CI-enforced, 767 tests — v1.0 Phase 6 + v2.0
- ✓ Event timeline in group — chronological list of past/upcoming events — v1.0 Phase 3
- ✓ Cross-event settle-up with optimization — v1.0 Phase 5
- ✓ Group activity log — v1.0 Phase 5
- ✓ ThemeExtension design token system with warm earthy palette — v2.0 Phase 15
- ✓ WCAG AA contrast on all text-on-background combinations — v2.0 Phase 15
- ✓ Stitch-based screen mockups for key screens — v2.0 Phase 16
- ✓ CI lint blocking hardcoded Color(0xFF...) values — v2.0 Phase 15
- ✓ Semantic Key test identifiers (rename-resilient test suite) — v2.0 Phase 14
- ✓ Single-scroll home dashboard with balance hero and quick actions — v2.0 Phase 18
- ✓ Cross-group balance on home screen — v2.0 Phase 18
- ✓ GoRouter subroutes for all event screens — v2.0 Phase 19
- ✓ 2-tap access to any module screen — v2.0 Phase 18
- ✓ Skeleton loading states across all screens — v2.0 Phase 17
- ✓ Contextual empty states with CTA — v2.0 Phase 18
- ✓ Group detail with type-specific event cards — v2.0 Phase 20
- ✓ Event hub with earthy design language — v2.0 Phase 20
- ✓ Ledger card-style expense rows — v2.0 Phase 21
- ✓ All module screens redesigned — v2.0 Phase 21
- ✓ Form flows use new design language — v2.0 Phase 21
- ✓ Onboarding + splash with earthy aesthetics — v2.0 Phase 21
- ✓ Haptic feedback on write actions — v2.0 Phase 22
- ✓ M3 motion patterns (ContainerTransform, SharedAxis, FadeThrough) — v2.0 Phase 22
- ✓ Reusable animation components (FadeInList, TapBounce, SkeletonLoader) — v2.0 Phase 17
- ✓ Animated balance counters — v2.0 Phase 22
- ✓ Grain/texture overlays + AppColors deleted — v2.0 Phase 22
- ✓ Quick action buttons correctly wired (Invite Friend → share sheet, Activity → cross-group screen) — v2.1 Phase 23
- ✓ Cross-group activity screen — v2.1 Phase 23
- ✓ 0-groups edge case SnackBar feedback — v2.1 Phase 23

### Active

- [ ] Improve group card visual distinction — richer cards, less flat
- [ ] Clarify "This Week" chart — axis labels, clear what it measures
- [ ] Reduce dashboard empty feel — better visual density and content layout

## Current Milestone: v2.1 Home Screen Completion

**Goal:** Fix all broken actions, improve visual density, and polish the home dashboard

**Target features:**
- Fix "Invite Friend" button (wired to join-group instead of invite/share)
- Fix "Activity" quick-action button (dead tap)
- Improve group card visual distinction (richer cards, less flat)
- Clarify the "This Week" chart (axis labels, what it measures)
- Reduce empty feel — better visual density and content layout

### Out of Scope

- Chat/messaging — high complexity, not core to coordination value
- OAuth/social login — anonymous auth works, adding login adds friction
- Web app — mobile-first, Flutter only
- Payment processing beyond Thawani — OMR-focused market
- AI/ML features — keep it simple and focused
- Dark mode — doubles visual work; earthy palette is inherently light-themed; ship polished light first
- Rive animations — start with Lottie/SVG; Rive adds complexity without clear value
- Per-user theme customization — fractures visual identity; earthy palette IS the brand
- Animated backgrounds/parallax — high battery drain, 30fps risk on mid-range Android
- Bottom tab bar (StatefulShellRoute) — single-hierarchy data model doesn't map to parallel tabs
- Riverpod 3.x upgrade — separate milestone; compounding risk with other migrations

## Context

- **Codebase**: 29,489 LOC Dart across ~130 files, feature-first architecture
- **Architecture**: Riverpod 2.x, GoRouter declarative routing (all screens URL-addressable), SQLite offline cache, Firebase Firestore backend
- **Backend**: Firebase-only — firebase_core 4.x, cloud_firestore 6.x, firebase_auth 6.x, firebase_storage 13.x. Anonymous auth
- **Data layer**: FirestoreRepository base class → 9 services. asyncMap SQLite side-write pipeline. BalanceCacheRepository for fast local balance queries
- **Design system**: ThemeExtension-based warm earthy palette (terracotta, sand, olive). AppColorTokens/AppSpacingTokens/AppShadowTokens. WCAG AA verified. CI lint enforces token usage
- **Navigation**: GoRouter with 23 route constants, OpenContainer/SharedAxis/FadeThrough M3 transitions
- **Financial precision**: All money math uses `Decimal` package, stored as integer fils in Firestore via MoneySerializer. Currency is OMR (3 decimal places)
- **Testing**: 767 tests, 80%+ coverage CI-enforced, fake_cloud_firestore for integration tests, semantic Key identifiers for rename resilience
- **User base**: Small, Oman-focused. Anonymous auth (no user accounts)
- **v1.0 shipped**: 2026-03-28 — groups, events, cross-event financials, full Firestore migration
- **v2.0 shipped**: 2026-03-31 — complete UI/UX overhaul with earthy design system, M3 motion, haptics

## Constraints

- **Tech stack**: Flutter + Firebase (Firestore, Auth, FCM, Storage). Keep SQLite for fast local reads
- **Testing**: TDD mandatory. 80%+ coverage. No shipping without tests
- **Financial precision**: Decimal package for all money. OMR 3 decimal places. No floating point
- **Offline-first**: App must work without connectivity. Firestore offline persistence + SQLite cache
- **Migration complete**: Supabase fully removed (v1.0 Phase 7). Firebase-only
- **Anonymous auth**: Keep frictionless entry. Firebase anonymous auth
- **Design system**: All colors via AppColorTokens. CI blocks hardcoded Color(0xFF...) literals

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Groups wrap trips (not replace) | Preserves existing trip experience, adds layer on top | ✓ Validated v1.0 |
| Firestore over Realtime DB | Better querying, offline support, scales well | ✓ Validated v1.0 |
| Both event-level and group-level ledger | Cross-event balances are the killer feature | ✓ Validated v1.0 |
| Keep SQLite alongside Firestore | Fast local reads, existing offline architecture works well | ✓ Validated v1.0 |
| Integer subunits for Firestore money | Store amounts as integer fils/cents, not strings or floats | ✓ Validated v1.0 |
| Abandon old trip data (D-01) | Recovery flow adds scope without user value; users start fresh | ✓ Decided v1.0 |
| asyncMap SQLite side-write | Keep SQLite in sync via Firestore snapshot pipeline | ✓ Validated v1.0 |
| Riverpod 2.x (defer 3.x) | Breaking changes compound risk with Firestore migration | ✓ Validated — stable through 2 milestones |
| ThemeExtension token system | Typed tokens over raw static constants; enables future theme switching | ✓ Validated v2.0 — CI-enforced, 0 hardcoded colors |
| Earthy palette (terracotta/sand/olive) | Warm, distinctive identity replacing generic neon-mint | ✓ Validated v2.0 — WCAG AA compliant |
| Dashboard-first home screen | Single-scroll with balance hero, quick actions, group cards | ✓ Validated v2.0 — 2-tap access to any module |
| OpenContainer over GoRouter for transitions | M3 ContainerTransform requires widget-level navigation | ✓ Validated v2.0 — URL desync accepted for animation quality |
| AppColors deletion | Clean break from legacy; all refs migrated to token system | ✓ Validated v2.0 — 1,375 refs migrated, class deleted |
| No bottom tab bar | Single-hierarchy data model (Group→Event→Module) | ✓ Validated v2.0 — content surfacing via dashboard |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-31 after v2.1 milestone start — Home Screen Completion*

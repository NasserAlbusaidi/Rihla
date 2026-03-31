# Milestones

## v2.0 Major UI/UX Overhaul (Shipped: 2026-03-31)

**Phases:** 9 | **Plans:** 28 | **Tasks:** 46
**Timeline:** 4 days (2026-03-28 → 2026-03-31)
**Codebase:** 29,489 LOC Dart | 767 tests | 80%+ coverage | 190 commits
**Files changed:** 254 (+40,967 / -5,648)

**Delivered:** Transformed Rihla from a functional but visually barren app into a richly designed experience with warm earthy aesthetics, flatter navigation, M3 motion patterns, and haptic feedback — while deleting the entire legacy color system.

**Key accomplishments:**

1. **Design token system** — ThemeExtension-based warm earthy palette (terracotta, sand, olive) with WCAG AA verification; CI lint blocks hardcoded colors; 1,375 AppColors refs migrated and class deleted
2. **Rename-resilient test suite** — Semantic Key identifiers across all tests; renaming any UI label causes zero cascade failures (verified: Ledger→Treasury, 0 failures across 767 tests)
3. **Single-scroll home dashboard** — Balance hero with cross-group net amount, quick-action tray, inline group cards with OpenContainer transitions, weekly spending chart
4. **GoRouter navigation overhaul** — All 22 Navigator.push calls replaced with GoRouter subroutes; every screen URL-addressable; deep links work without pre-loaded objects
5. **Complete screen redesign** — All 6 module screens, forms, onboarding, and splash redesigned with card-based layouts, illustrated empty states, dark ModuleHeaders
6. **M3 motion & polish** — ContainerTransform, SharedAxis, FadeThrough transitions; haptic feedback on write actions; grain textures; animated balance counters

**Tech debt carried forward:**

- 16 inline `Color(0xFF...)` literals in feature screens (gradient colors need token extraction)
- MemoryDetail and EventActivity routes are placeholder Scaffolds
- BottomNavShell Activity/Chats/Profile tabs show "Coming soon" placeholder
- StaggeredGrid widget tested but unused; domain aliases dead code
- Logistics hero card file orphaned (screen inlines equivalent)

---

## v1.0 Groups, Events & Cross-Event Financials (Shipped: 2026-03-28)

**Phases:** 13 | **Plans:** 43 | **Tasks:** 78
**Timeline:** 91 days (2025-12-27 → 2026-03-28)
**Codebase:** 24,895 LOC Dart | 624 tests | 80%+ coverage | 411 commits

**Delivered:** Evolved the Rihla trip-planning app into a persistent group coordination platform with cross-event financial tracking, while fully migrating the backend from Supabase to Firebase Firestore.

**Key accomplishments:**

1. **Firebase backend migration** — Supabase fully removed; all reads/writes through Firestore with security rules (22 JS tests), offline persistence, and realtime listeners
2. **Persistent groups** — Create/join groups with invite codes; groups persist across events and app restarts; groups-first home screen
3. **Typed events with templates** — 5 event types (Trip, Camping, Travel, Night/Day Out, Custom) with template-driven module selection and gear presets
4. **Cross-event financials** — Group-level running balances across all events, cross-event settle-up with optimization, group spending stats and activity log
5. **FirestoreRepository architecture** — Single Firestore contact point for all 9 services, asyncMap SQLite side-write pipeline, BalanceCacheRepository for fast local reads
6. **80%+ test coverage** — CI-enforced coverage gate, offline scenario tests, Firestore model round-trip tests, exhaustive BalanceCalculator tests across all 4 scopes

**Tech debt carried forward:**

- Event edit/delete UI deferred (EventService methods exist but no UI caller)
- Category CRUD stubs (custom categories deferred)
- Nyquist validation gaps on 9 phases (documentation, not functional)

---

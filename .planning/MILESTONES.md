# Milestones

## v2.3 Groups, Events & Modules (Shipped: 2026-04-05)

**Phases completed:** 14 phases, 30 plans, 52 tasks

**Key accomplishments:**

- 10 remaining test files migrated to find.byKey(), CI regression warning added at baseline 135, and rename resilience verified: Ledger→Treasury rename causes zero test failures across 624 tests
- All 4 home screen quick actions fixed: Invite Friend now opens native share sheet with invite code, Activity navigates to new CrossGroupActivityScreen, 0-groups shows SnackBar for group-dependent actions
- 1. [Rule 1 - Bug] Test assertions written for RED then fixed for GREEN
- WeeklySpendingCard updated with 'Weekly Spending (OMR)' title and per-bar amount labels (toStringAsFixed(1)); dashboard spacing tightened to 12dp; 'Your Groups (N)' section header added above group list.
- ProfileKeys
- AppRoutes.settings → AppRoutes.profile
- TDD GREEN phase: Three section widgets (Notifications, About, Support) implemented and wired into ProfileScreen — all 8 Phase 26 tests pass, 812 total tests green
- TDD RED phase: 8 failing widget tests for notification toggle, version tile, feedback, licenses, and coffee-tip sections with MockNotificationService and FCM-safe provider overrides
- appBootstrapProvider wired into SafarApp.build() so push notification toggle triggers FCM initialize/removeToken
- GroupDetailScreen refactored: invite code removed, provider rebuilds isolated via Consumer, gradient settle-up CTA, FAB/settings icon token fix, 16dp padding, EmptyStateView for activity
- GroupDetailScreen completed with pull-to-refresh, FadeInList staggered event entrance, inline error state with retry, and GroupMemberBalanceCard visual polish using design tokens
- One-liner:
- One-liner:
- TDD Wave 0 — 16 skip-annotated test stubs establish Phase 30 behavioral contract across settle-up tabs, activity date grouping, filter chips, and logGroupEvent call verification
- Balance direction label (You owe/Owed to you/Settled) on GroupStatsGrid YOUR BALANCE tile, plus 4 new logGroupEvent call sites for event_created, member_joined, and member_left (leave + remove paths)
- 1. [Rule 1 - Bug] Duplicate key declarations in group_keys.dart
- One-liner:
- 1. [Rule 1 - Bug] Test expectation corrected for description null-guard
- EventInfoSection
- One-liner:
- One-liner:
- One-liner:
- One-liner:
- Ledger test suite fixed to compile against LedgerScreen(groupId:, eventId:) constructor with eventDetailProvider overrides; 8 tests pass including 2 new visual requirement tests
- SettleUpScreen gets dark ModuleHeader with event subtitle and SkeletonLoader; EditExpenseScreen loading state gets ModuleHeader + SkeletonLoader; WCAG section headers fixed
- Dark ModuleHeader added to AddExpenseScreen and three CircularProgressIndicator loading states replaced with SkeletonLoader.card() across the ledger add-expense flow
- Two TDD RED-state test stubs asserting OfflineBanner renders in VaultScreen and MemoriesScreen bodies (Wave 0 before implementation)
- 1. [Rule 1 - Bug] Fixed pre-existing EdgeInsets.fromLTRB const lint in VaultScreen

---

## v2.1 Home Screen Completion (Shipped: 2026-04-01)

**Phases:** 2 | **Plans:** 3 | **Tasks:** 4
**Timeline:** 1 day (2026-03-31 → 2026-04-01)
**Codebase:** ~30,000 LOC Dart | 789 tests | 80%+ coverage
**Files changed:** 10 source files (+1,342 / -145)

**Delivered:** Fixed all broken home screen quick actions and improved visual density — group cards now have colored accent strips and event context, charts show readable labels, and the dashboard has tighter spacing with a clear group list header.

**Key accomplishments:**

1. **Quick action fixes** — Invite Friend opens native share sheet with invite code (group picker for multi-group users), Activity navigates to new CrossGroupActivityScreen, 0-groups edge cases show SnackBar feedback
2. **Group card enrichment** — 4dp earthy accent strip (hash-based color per group) and event context line showing last event name with relative timestamp
3. **Chart clarity** — WeeklySpendingCard title updated to "Weekly Spending (OMR)" with per-bar amount labels
4. **Dashboard density** — Spacing tightened to 12dp between sections, "Your Groups (N)" header added above group list

**Tech debt carried forward:**

- `group_card.dart` slot 4 (#7C6E5A) accent color has no AppColorTokens equivalent (plan-sanctioned)
- `home_screen.dart:146` uses string literal `/activity` instead of AppRoutes constant
- Phase 23 Nyquist validation missing (Phase 24 compliant)

---

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

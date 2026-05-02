# UI/UX Thorough Overhaul — Design Document

Date: 2026-03-06
Branch: feature/creative-overhaul
Approach: Layered (Foundation → Screens → Interactions)

## Goal

Same visual direction, higher craft. Refine the Neo-Outdoor design system, fix inconsistencies across all screens, add missing UX patterns (offline, search, validation), and polish interactions to premium quality.

## Layer 1: Foundation — Design System Refinement

### 1.1 Theme Refinements

- Introduce muted mint variant for surfaces/backgrounds; keep bright mint (#13EC92) for CTAs and accents only
- Standardize spacing scale: 8, 12, 16, 20, 24, 32
- Unify border radius: 12px (small), 16px (medium), 20px (large)
- Formalize elevation into 3 levels: flat, raised, floating
- Standardize button height to 52px

### 1.2 Extracted Components

| Component | Source Screens | Purpose |
|-----------|---------------|---------|
| `ModuleHeader` | Gear, Vault, Logistics, Activity, Ledger | Dark gradient header with back button, title, optional actions |
| `AppTabBar` | Ledger, Logistics | Gradient pill indicator, consistent styling |
| `AppFormField` | Login, Create Trip, Add/Edit Expense | Consistent input styling, real-time validation support |
| `OfflineBanner` | All screens | Slim amber banner below app bar when offline |
| `EmptyStateView` | Gear, Vault, Activity, Ledger | Icon + message + optional CTA button |
| `SearchFilterBar` | Gear, Vault, Activity | Expandable search input with optional filter chips |

### 1.3 Missing UX Patterns

- Offline indicator: slim amber banner, auto-dismiss on reconnect
- Real-time form validation: debounced on-change
- Contextual empty states: every empty state gets a CTA
- Fix 2 async BuildContext issues in command_center.dart

## Layer 2: Screens — User Journey Order

### 2.1 Onboarding
- Keep animated blobs and dark immersive feel
- Add color transition on page indicators matching each page's accent
- Add haptic feedback on page swipe
- Use standardized LoadingButton for CTA

### 2.2 Login / Auth
- Keep glassmorphism container
- Swap to AppFormField with real-time validation (email format, password strength)
- Add shake animation on validation error
- Apply glassmorphism to forgot/reset password screens (currently plain light bg)

### 2.3 Home Screen
- Tighten trip card internal spacing to new scale
- Invite code badge: add visible copy icon hint
- Completed trips: subtle overlay treatment instead of just opacity
- Bento buttons: same height/radius from foundation
- Add OfflineBanner
- Improve empty state with inviting CTA

### 2.4 Command Center
- Extract top bar to ModuleHeader
- Refine SmartModuleCard spacing to new scale
- Add staggered entrance animations on module cards
- Fix 2 use_build_context_synchronously issues
- Add OfflineBanner

### 2.5 Ledger
- Replace default TabBar with AppTabBar (gradient pill)
- Tighten transaction card spacing and shadows
- Balance tooltips: swipe-to-dismiss
- Add SearchFilterBar (filter by payer, date, scope)
- Fix unnecessary ! in settle_up_screen.dart:361
- Add step progress indicator to Add Expense flow

### 2.6 Gear
- Apply ModuleHeader
- Refine progress card with new radius/shadow
- Add SearchFilterBar (status filter + name search)
- Empty state: CTA focuses add-item input

### 2.7 Vault
- Apply ModuleHeader
- Add SearchFilterBar for document name
- Empty state: CTA triggers upload action
- Document cards: file type icon (PDF, image, etc.)

### 2.8 Logistics
- Apply ModuleHeader
- Migrate custom tab bar to shared AppTabBar
- Match avatar styling with home screen

### 2.9 Activity Feed
- Apply ModuleHeader
- Add connecting line between timeline cards
- Add SearchFilterBar (activity type filter)
- Improve empty state messaging

### 2.10 Settings
- Add subtle section headers for grouping
- Theme toggle: visual preview cards (light/dark thumbnails)
- Avatar selector: increase size, add selected ring
- Show app version + build number

### 2.11 Global
- OfflineBanner on all screens
- Consistent page transitions (slide-right for push, slide-up for modals)
- Haptic feedback on all tab switches, toggles, destructive actions

## Layer 3: Interactions — Polish & Accessibility

### 3.1 Animations
- Standardize transitions: slide-right (push), slide-up (sheets/modals), fade (tabs)
- Staggered fadeIn + slideY on all list screens
- Scale bounce (0.95 -> 1.0) on successful actions
- Horizontal shake on validation failures
- Crossfade between tab content

### 3.2 Haptics
- Light: tab switches, toggles, chips, clipboard copy
- Medium: button presses, card taps, swipe actions
- Heavy: destructive confirmations, successful settlements

### 3.3 Accessibility
- Semantic labels on icon-only buttons, status badges, progress indicators
- Contrast audit: mint-on-white and white-on-dark meet WCAG AA (4.5:1)
- Logical tab order in forms, focus trapping in modals
- Minimum 44x44px touch targets on all interactive elements
- Respect MediaQuery.disableAnimations for reduced motion preference

### 3.4 Edge Cases
- Forms scroll to keep active field above keyboard
- Long text truncates with ellipsis (trip names, descriptions, member names)
- Debounce navigation pushes to prevent double-push
- Pull-to-refresh on all list screens

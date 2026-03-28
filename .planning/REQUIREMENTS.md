# Requirements: Rihla v2.0 — Major UI/UX Overhaul

**Defined:** 2026-03-28
**Core Value:** Groups persist across events and accumulate financial history — friends settle up across trips, not just within one.

## v2.0 Requirements

Requirements for the UI/UX overhaul. Each maps to roadmap phases.

### Design Foundation

- [ ] **FOUND-01**: App uses a ThemeExtension-based design token system with warm earthy palette (terracotta, sand, olive) replacing all hardcoded AppColors references
- [ ] **FOUND-02**: All text-on-background color combinations meet WCAG AA contrast ratios (4.5:1 body text, 3:1 large text/icons)
- [ ] **FOUND-03**: Screen mockups for key screens (Home, Group Detail, Event Hub) are designed in Stitch and serve as visual specification
- [ ] **FOUND-04**: CI lint rule prevents new hardcoded `Color(0xFF...)` values outside the token system
- [x] **FOUND-05**: Test suite uses semantic Key identifiers instead of find.text() for structural assertions, preventing cascade failures during UI changes

### Navigation & Home

- [ ] **NAV-01**: Home screen shows a single-scroll dashboard with balance hero, inline group cards, quick-action tray, and recent activity
- [ ] **NAV-02**: User can see their net cross-group balance (color-coded green/red/gray) on the home screen without tapping into any group
- [ ] **NAV-03**: All event-level screens are accessible via GoRouter subroutes, replacing Navigator.push with context.push
- [ ] **NAV-04**: User can reach any module screen within 2 taps from the home dashboard
- [ ] **NAV-05**: All data-fetching screens show skeleton loading states instead of spinners or blank screens
- [ ] **NAV-06**: All empty screens show contextual illustrations with a single clear CTA explaining what to do next

### Screen Redesign

- [ ] **SCRN-01**: Group detail screen shows event cards with type-specific color accents, inline financial summaries, and past/upcoming visual distinction
- [ ] **SCRN-02**: Event hub (CommandCenter) uses the new design language with earthy palette and improved information density
- [ ] **SCRN-03**: Ledger screen uses card-style expense rows with color-coded balance displays
- [ ] **SCRN-04**: Gear, Logistics, Vault, Memories, and Activity screens are redesigned with the new design tokens
- [ ] **SCRN-05**: Create/join group, create event, add expense, and settings flows use the new design language
- [ ] **SCRN-06**: Onboarding flow and splash screen reflect the new visual identity with warm earthy aesthetics

### Visual Polish

- [ ] **PLSH-01**: Primary write actions (add expense, record settlement, join group) provide haptic feedback
- [ ] **PLSH-02**: Screen transitions use M3 motion patterns (ContainerTransform, SharedAxis) instead of basic slide animations
- [ ] **PLSH-03**: Reusable animation components (fade-in lists, staggered grids, tap bounce) exist as shared library widgets
- [ ] **PLSH-04**: Balance amounts animate on update with smooth counter transitions
- [ ] **PLSH-05**: Cards and surfaces use subtle grain/texture overlays and soft gradients for visual warmth

## Future Requirements

### Dark Mode (deferred)

- **DARK-01**: App supports a dark theme variant of the earthy palette
- **DARK-02**: Theme follows device system setting automatically

### Advanced Animations (deferred)

- **ANIM-01**: Empty states use Rive interactive state machine animations
- **ANIM-02**: Onboarding uses Rive-powered interactive illustrations

## Out of Scope

| Feature | Reason |
|---------|--------|
| Dark mode | Doubles visual work; earthy palette is inherently light-themed; ship polished light first |
| Rive animations | Start with Lottie/SVG; Rive adds complexity without clear value for v2.0 |
| Per-user theme customization | Fractures visual identity; earthy palette IS the brand |
| Animated backgrounds/parallax | High battery drain, 30fps risk on mid-range Android |
| Bottom tab bar (StatefulShellRoute) | Single-hierarchy data model doesn't map to parallel tabs; content surfacing achieves flatter nav |
| Backend/logic changes | Pure visual + navigation overhaul; all services, providers, financial calculations untouched |
| Riverpod 3.x upgrade | Separate milestone; compounding risk with visual migration |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01 | Phase 15 | Pending |
| FOUND-02 | Phase 15 | Pending |
| FOUND-03 | Phase 16 | Pending |
| FOUND-04 | Phase 15 | Pending |
| FOUND-05 | Phase 14 | Complete |
| NAV-01 | Phase 18 | Pending |
| NAV-02 | Phase 18 | Pending |
| NAV-03 | Phase 19 | Pending |
| NAV-04 | Phase 18 | Pending |
| NAV-05 | Phase 17 | Pending |
| NAV-06 | Phase 18 | Pending |
| SCRN-01 | Phase 20 | Pending |
| SCRN-02 | Phase 20 | Pending |
| SCRN-03 | Phase 21 | Pending |
| SCRN-04 | Phase 21 | Pending |
| SCRN-05 | Phase 21 | Pending |
| SCRN-06 | Phase 21 | Pending |
| PLSH-01 | Phase 22 | Pending |
| PLSH-02 | Phase 22 | Pending |
| PLSH-03 | Phase 17 | Pending |
| PLSH-04 | Phase 22 | Pending |
| PLSH-05 | Phase 22 | Pending |

**Coverage:**
- v2.0 requirements: 22 total
- Mapped to phases: 22
- Unmapped: 0

---
*Requirements defined: 2026-03-28*
*Last updated: 2026-03-28 — traceability mapped after roadmap creation (Phases 14-22)*

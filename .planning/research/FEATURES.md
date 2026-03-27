# Feature Research: UI/UX Overhaul

**Domain:** Group coordination and social finance app — visual design, navigation, information architecture
**Researched:** 2026-03-28
**Confidence:** HIGH for navigation patterns (strong market evidence), HIGH for loading/empty states (NN/G + industry consensus), MEDIUM for earthy/textured visual direction (trend-driven, subjective), MEDIUM for micro-interaction specifics (Flutter implementation details vary)

---

## Context: What This Research Is For

This research specifically addresses the v2.0 milestone goal: transform Rihla from functional but visually barren into eye-catching and richly designed. The existing FEATURES.md (2026-03-26) covers the functional feature landscape. This document covers the *UI/UX design features* — what the interface needs to do, look like, and feel like, as observed in best-in-class comparables.

**Comparables studied:** Splitwise, Tricount, TripIt, Airbnb, Venmo, Revolut, Discord, Linear

---

## Table Stakes

Features users expect in any polished group app in 2026. Missing these makes the app feel unfinished, untrustworthy, or amateur.

### Home Screen

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Balance summary visible on home screen without tapping | Users open the app to check "what do I owe" — that answer must be instant | LOW | Venmo and Revolut both surface the primary number on first load. Splitwise buries it under a tab. |
| Group list on home screen | Users have 2-5 active groups; scanning them is the second most common action | LOW | Currently exists but reportedly barren — needs visual weight via card treatment |
| Recent activity inline on home screen | Users want to see "what just happened" without navigating away | MEDIUM | Revolut's home feed pattern; Discord's channel badge pattern. One scroll handles everything. |
| Quick action for "add expense" reachable from home | The primary write action must never be more than one tap away | LOW | Splitwise's floating "+" is correct. FAB or bottom-center button, always visible. |
| Upcoming event surface on home screen | Users coming back after a few days want to see "what's happening next" | MEDIUM | TripIt shows upcoming trip prominently on home. Applicable to group events. |

### Navigation

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Bottom navigation bar (4-5 tabs, thumb zone) | Industry standard since 2018. Hamburger menus killed session time (Redbooth: -65% DAU when they moved away from tabs) | LOW | Currently missing a persistent bottom nav. Navigation is primarily `Navigator.push` stacks. |
| Key content reachable in 2 taps or fewer | Users abandon 3-4 tap depth. Confirmed by every navigation study since 2020. | HIGH | This is a structural change, not just cosmetic. Requires rethinking CommandCenter architecture. |
| Visible back affordance on deep screens | Users pushed into a screen stack expect clear escape routes | LOW | Already using slide transitions via AppPageRoute. Ensure back button / swipe-back is always obvious. |
| Consistent navigation patterns across all screens | Inconsistent nav creates user anxiety ("am I lost?") | MEDIUM | CommandCenter currently mixes GoRouter top-level with Navigator.push sub-screens. Users notice. |

### Visual Design

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Consistent color system (design tokens, not one-off hex) | Apps that feel "premium" have systematic color use, not ad-hoc choices | MEDIUM | Stitch-first workflow addresses this. Design tokens must be the ground truth. |
| Cards with visible elevation or border separation | Content cards need to visually separate from background | LOW | Currently too much flat whitespace. Shadows or border differentiation is expected. |
| Readable typography hierarchy | H1/H2/body/caption must be clearly different in weight and size | LOW | Typography scale needs audit. "Barren" look often comes from uniform type weights. |
| Color-coded financial states | Green = you are owed, Red = you owe, Gray = settled. Universal fintech convention. | LOW | Splitwise, Venmo, and every banking app uses this pattern. Violating it confuses users. |
| Iconography that matches the app's tone | System icons (Material/Cupertino) look generic; custom or themed icons signal quality | MEDIUM | Can be addressed with a custom icon set or a carefully chosen icon library. |

### Loading States

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Skeleton screens instead of spinners for content loads | Skeletons are perceived as ~3x faster than spinners (NN/G research). "500ms spinner feels slow; 500ms skeleton feels fast." | MEDIUM | Applicable to: home screen, group dashboard, expense lists, activity feed. Not for form submissions. |
| Spinner acceptable for form submissions and payments | Short blocking actions (submit, save, settle up) warrant a spinner because layout preview is irrelevant | LOW | Keep spinner for: saving expense, recording settlement, joining group. |
| No blank screens during load | White flash before content is a quality signal failure. Something must always be showing. | LOW | Shimmer animation on skeleton prevents blank-screen perception. |

### Empty States

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Illustrated empty state with a single clear CTA | Empty screens with just "No expenses yet" and no further guidance read as broken | LOW | Pattern: illustration + 1-line headline + 1 CTA button. NN/G: "Different contexts need different empty states." |
| Context-specific empty state copy | "Your group has no events yet — create the first one" is better than generic "Nothing here" | LOW | Each empty state should know WHY it is empty and what the user should do next. |
| Empty states as onboarding moments | First-time users land on empty screens. These are the most important onboarding surface in the app. | MEDIUM | Airbnb uses first-run empty states to explain value and prime the first action. |

---

## Differentiators

Features that would set Rihla apart visually from Splitwise, Tricount, and generic expense apps. These are competitive advantages in the UI layer specifically.

### Home Screen — Rich Dashboard

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Single-scroll home with bento-grid group cards | Instead of a plain list, group cards show inline balance, member count, last event — users get an overview in one scroll | MEDIUM | Bento grid is the dominant 2026 layout pattern. Avoids the "boring list" problem. Each card is a mini-dashboard. |
| Balance hero widget at top of home | A prominent visual element showing net balance (overall: you are owed X / you owe X) above the fold, before any scrolling | LOW | Revolut does this with balance front-and-center. Venmo does it with the payment amount. For Rihla it's the net across all groups. |
| Active event surface on home | The currently active or most recent event floats to the top of home with key state: next expense, next logistics item | MEDIUM | TripIt surfaces upcoming trip. Rihla should surface active event with a mini-card showing "3 unpaid expenses, leaves in 2 days." |
| Quick-action tray on home | Row of circular quick-action buttons: Add Expense, Settle Up, Invite Member, View Activity — no navigation needed | LOW | Revolut uses this exact pattern. Reduces primary task depth to 1 tap. |
| Recent activity inline (collapsed, expandable) | Last 3-5 group activities shown on home, expandable to full feed. "Sara settled with Ahmed — 2h ago" | MEDIUM | Discord shows unread badges; Venmo shows recent feed on home. Users feel the app is alive. |

### Visual Identity — Warm & Earthy

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Terracotta / sand / olive palette with tokenized design system | Earthy tones are the dominant 2025-2026 direction. Competitors (Splitwise: blue/white, Tricount: blue/white) use clinical palettes. Rihla can own warmth. | MEDIUM | Not just color choices — needs systematic application: backgrounds, cards, accents, icons all harmonize. |
| Grain / texture overlays on key surfaces | Paper-texture or grain overlays on backgrounds and cards add tactile warmth. 2026 trend: "tactile rebellion" against flat sterility. | MEDIUM | Implemented in Flutter via CustomPaint or a semi-transparent PNG overlay. Low performance cost. |
| Organic shapes for illustrations and empty states | Rounded, blob-like illustration shapes feel human and warm vs. geometric clipart | MEDIUM | Empty state illustrations should use this style consistently. Can use Rive for animated versions. |
| Soft gradients on cards and section backgrounds | "Soft Gradients 2.0" — subtle airy blends, not loud rainbow effects. Applied to group cards, balance hero, event cards. | LOW | Pure Flutter LinearGradient / RadialGradient. Near-zero complexity. Huge visual lift. |

### Event Cards — Rich Visual Treatment

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Event cards with type-specific color or icon accent | Camping trip = olive/green accent, city break = terracotta, night out = deeper tone. Instant visual scanning. | LOW | Color per event type is already differentiated in the data model. Rendering it in UI is straightforward. |
| Inline financial summary on event cards | "Total: OMR 340.000 | Your share: OMR 85.000 | 2 unsettled" — all visible on the card without tapping | MEDIUM | Requires surfacing pre-computed balance data. BalanceCacheRepository already has this; rendering is new. |
| Past vs. upcoming visual distinction | Upcoming events have full color; past events have a muted/desaturated treatment | LOW | CSS-style opacity or saturation filter. Signals temporal state at a glance. |
| Member avatar row on event cards | Small circular initials/avatar row showing who is in the event | LOW | Initials-based avatar (no photos needed). Adds human social signal to the card. |

### Micro-interactions and Polish

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Haptic feedback on primary actions (expense added, settlement recorded) | Coordinated visual + haptic = premium feel. iOS Light impact on confirmation, Medium on settlement. | LOW | Flutter: `HapticFeedback.lightImpact()`. One-liner per action. High perceived quality lift. |
| Animated balance number on update | When balance changes after adding expense, number animates (counting up/down). Signals data freshness. | MEDIUM | Flutter `AnimatedSwitcher` or `TweenAnimationBuilder` on the balance Text widget. |
| Rive animations for empty states and onboarding | Rive: 60fps, ~2KB files, state machines for interactive onboarding, idle animations for empty states. Outperforms Lottie on every metric (60fps vs 17fps, 2KB vs 24KB). | MEDIUM | Use Rive for: empty state idle loops, onboarding step illustrations, success/completion moments. Use shimmer for loading. |
| Swipe-to-settle gesture on balance rows | Swipe right on a balance item to initiate settle-up — matches iOS native patterns (swipe-to-delete, etc.) | MEDIUM | Flutter `Dismissible` widget. Reduces settle-up flow to 1 gesture instead of tap → form → confirm. |
| Spring physics on card interactions | Card presses and list scrolling feel snappy with spring physics rather than linear easing | LOW | Flutter `SpringDescription` in animation controllers, or use `AnimatedPhysicalModel`. |

### Navigation Improvements

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Persistent bottom nav with 4 tabs: Home, Groups, Activity, Profile | Single pattern to replace current hybrid GoRouter + Navigator.push maze. Every screen is max 2 taps from home. | HIGH | Structural. Requires rethinking which screens are "top level" vs. "pushed". |
| Group dashboard with inline tab bar (not separate screens) | Event timeline, balances, and members as tabs inside the group screen — not separate Navigator pushes | MEDIUM | Currently each module pushes to a new screen. Tab bar keeps context, reduces back-button presses. |
| Swipeable event module tabs inside CommandCenter | Left-right swipe between Ledger / Gear / Logistics / Vault instead of card-tap → push → back loop | MEDIUM | Replace the CommandCenter module card grid with a tab bar or horizontal swiper at the top. |
| Contextual "Add" button per screen | "Add expense" when on ledger tab, "Add gear item" when on gear tab — no disambiguation needed | LOW | FAB icon changes contextually. Reduces cognitive load and tap count. |

---

## Anti-Features

Design choices that seem appealing but create problems in the context of a group coordination finance app.

| Anti-Feature | Why Requested | Why Problematic | Alternative |
|--------------|---------------|-----------------|-------------|
| Dark mode support | Users want it, designers love it | Doubles all visual work (every color token needs a dark variant). Rihla's earthy warm palette is inherently light-themed. Dark mode would require an entirely different palette and is out of scope. | Ship a polished light theme completely. Dark mode is a future milestone if user demand warrants it. |
| Fully custom animations for all transitions | "Make it feel premium" | Custom page transitions add hundreds of KB to app size, break platform back-gesture conventions, and take weeks to test across devices. They also fight Riverpod's async data loading timing. | Use AppPageRoute (existing slide-right) for consistency. Add micro-interactions at the component level, not the navigation level. |
| Inline photo/avatar uploads on group cards | "Personal touch" | Camera/gallery picker is a permission flow. Group cards are used for quick scanning, not for personal expression. Adding avatars adds latency to card renders. Rihla uses name-based members, not profiles. | Use initials-based avatar system (color-coded by name hash). Zero permissions, instant render, still humanizing. |
| Per-user theme customization | "Let users pick their colors" | Fractures the visual identity. The earthy palette IS the brand. Customization means every screenshot looks different, making the app feel inconsistent. | One well-designed theme with careful color choices. Customization is for productivity apps, not social coordination apps. |
| Animated background / parallax header | Common in travel apps (TripIt, Airbnb) | High battery drain on scroll. Flutter's parallax effects can drop to 30fps on mid-range Android. The earthy textural richness achieves warmth without animation cost. | Static grain/texture overlays. Soft gradients. These are perceived as richer than animated backgrounds but cost near-zero CPU. |
| Real-time balance animation on every expense add | "Users want to see balances update live" | Constant re-renders of animated balance numbers across all group members simultaneously is expensive. Firestore snapshots already trigger re-renders — animating them all creates jank. | Animate the single balance number the user is directly interacting with. Background updates render without animation. |
| Tab bars with 6+ tabs | "Expose all features" | Tabs beyond 5 become unreadable on small screens. The "More" overflow tab pattern (Splitwise currently does this) buries content. | Hard limit: 4 tabs on bottom nav. Module access within events stays in the swipeable tab bar (3-4 modules), not the main nav. |
| Infinite scroll on activity feed | "Social media feel" | Expense apps are used for reference (scroll back to find a specific expense), not passive consumption. Infinite scroll removes the ability to bookmark position. NN/G: infinite scroll works for passive consumption, fails for reference lookup. | Paginated "Load more" with a clear position indicator. Users can orient themselves in the activity history. |
| Splash screen with logo animation | "Polish" | Adds perceived startup time. Users interpret the animation as loading delay even if the app is ready. | No splash screen, or a near-instant one-frame splash. Fast startup IS the UX. |

---

## Feature Dependencies

```
Design token system (Stitch → tokens → Flutter)
    └──required by──> All visual changes (palette, typography, spacing)
                          └──required by──> Everything else in this milestone

Bottom navigation (structural change)
    └──required by──> Flat navigation (2-tap depth goal)
                          └──required by──> Swipeable event module tabs
                          └──required by──> Group dashboard inline tabs
                          └──required by──> Contextual FAB per tab

Balance hero widget (home screen)
    └──depends on──> BalanceCacheRepository (exists)
    └──enhances──> Quick-action tray (home)
                      └──depends on──> Bottom nav being present (context clear)

Skeleton loading screens
    └──independent of──> Visual redesign
    └──required before──> Removing current spinner-everywhere pattern

Empty state illustrations
    └──depends on──> Rive integration (for animated versions)
    └──or──> Static illustration asset system (simpler)

Event cards with inline balance
    └──depends on──> BalanceCacheRepository (exists)
    └──depends on──> Design token system (for type-specific colors)

Micro-interactions (haptic, spring, animated numbers)
    └──independent of──> Navigation restructure
    └──enhances──> All primary actions (add expense, settle up)
```

### Dependency Notes

- **Design token system is the prerequisite for everything.** Without systematic tokens, every screen change is a one-off. With tokens, changing the palette touches everything at once.
- **Bottom nav restructure conflicts with existing GoRouter + Navigator.push hybrid.** These must be redesigned together. Doing visual polish before navigation architecture is waste — screens will be rebuilt anyway.
- **Rive integration is optional.** Empty states work as static illustrations. Rive is a differentiator, not a gate. Do static first, add Rive animations as a polish pass.
- **Skeleton screens are independent** of visual redesign. They can be built screen by screen in any order and are high-value with low risk.

---

## MVP Definition for This Milestone

### Phase 1 — Foundation (must ship before anything else)

- [ ] Design token system via Stitch — palette, typography, spacing all tokenized. This is the multiplier.
- [ ] Bottom navigation bar (4 tabs) replacing current implicit navigation
- [ ] Skeleton loading screens on all data-fetching screens (home, group dashboard, ledger)
- [ ] Context-specific empty states with illustrated design on all 6 main empty screens (home/groups, events, expenses, gear, activity, members)

### Phase 2 — Home Screen Redesign (highest user-facing impact)

- [ ] Balance hero widget (net balance, color-coded green/red)
- [ ] Rich group cards with inline balance, member count, last activity
- [ ] Quick-action tray (Add Expense, Settle Up, Invite, Activity)
- [ ] Recent activity section (last 5 items, collapsed by default)

### Phase 3 — Event and Group Screen Redesign

- [ ] Group dashboard inline tab bar (Events | Balances | Members)
- [ ] Swipeable module tabs inside CommandCenter (Ledger | Gear | Logistics | Vault)
- [ ] Event cards with type-specific color accent and inline financial summary
- [ ] Contextual FAB per active tab

### Phase 4 — Polish Pass

- [ ] Haptic feedback on all primary write actions
- [ ] Animated balance counter on update
- [ ] Grain/texture overlay on backgrounds
- [ ] Soft gradient treatment on group and event cards
- [ ] Spring physics on card presses
- [ ] Swipe-to-settle gesture on balance rows

### Defer

- [ ] Rive animations (use static illustrations to ship; add Rive later)
- [ ] Dark mode (out of scope for this milestone per PROJECT.md)
- [ ] Per-user customization

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Design token system (Stitch) | HIGH | MEDIUM | P1 |
| Bottom navigation bar | HIGH | HIGH | P1 |
| Skeleton loading screens | HIGH | MEDIUM | P1 |
| Empty states with illustration + CTA | HIGH | LOW | P1 |
| Balance hero widget | HIGH | LOW | P1 |
| Rich group cards (inline balance + members) | HIGH | MEDIUM | P1 |
| Quick-action tray on home | HIGH | LOW | P1 |
| Event type color accents | MEDIUM | LOW | P2 |
| Group dashboard inline tabs | HIGH | MEDIUM | P2 |
| Swipeable module tabs in CommandCenter | HIGH | MEDIUM | P2 |
| Inline financial summary on event cards | MEDIUM | MEDIUM | P2 |
| Contextual FAB | MEDIUM | LOW | P2 |
| Recent activity on home | MEDIUM | MEDIUM | P2 |
| Haptic feedback | MEDIUM | LOW | P2 |
| Grain/texture overlays | MEDIUM | LOW | P2 |
| Soft gradient on cards | MEDIUM | LOW | P2 |
| Animated balance counter | LOW | MEDIUM | P3 |
| Spring physics on cards | LOW | LOW | P3 |
| Swipe-to-settle gesture | MEDIUM | MEDIUM | P3 |
| Rive animations (empty states / onboarding) | MEDIUM | HIGH | P3 |
| Member avatar row on cards | LOW | LOW | P3 |

**Priority key:**
- P1: Gate on visual redesign — without these, the overhaul is not done
- P2: High value, achievable within the milestone
- P3: Polish pass — ship if time allows, defer otherwise

---

## Competitor Feature Analysis

| UI Feature | Splitwise | Tricount | TripIt | Airbnb | Rihla Current | Rihla Target |
|------------|-----------|----------|--------|--------|---------------|--------------|
| Balance on home screen | Tab-buried | No home widget | N/A | N/A | Missing | Hero widget, above fold |
| Group cards with inline data | Name only, no balance | Name only | N/A | Rich imagery | Name only, flat list | Balance + members + last activity |
| Navigation depth to expenses | 3 taps | 2 taps | N/A | 2 taps | 3-4 taps | 2 taps max |
| Bottom navigation | 5 tabs | 4 tabs | 4 tabs | 4 tabs | None (Navigator.push) | 4 tabs |
| Loading states | Spinners | Spinners | Spinners | Skeleton | Spinners/blank | Skeleton shimmer |
| Empty states | Minimal copy | Minimal copy | Illustrated | Illustrated + CTA | Generic | Illustrated + context-specific CTA |
| Visual palette | Clinical blue/white | Clinical blue/white | Dark/navy | Photo-led white | Minimal/generic | Warm earthy (terracotta, sand, olive) |
| Card richness | Flat list rows | Flat list rows | Image hero cards | Photo cards with trust badges | Flat | Bento-style with gradient + type color |
| Micro-interactions | Minimal | None | Minimal | Fluid, spring-physics | Minimal | Haptic + animated numbers + spring |
| Quick actions | FAB only | FAB only | None | Bottom action tray | FAB (CommandCenter) | Home-level quick-action tray |
| Event type visual distinction | None | None | Category icons | Category filter | None | Per-type color accent on card |

Key observation: **Splitwise and Tricount are functionally mature but visually stagnant.** Both use clinical blue/white palettes, flat list views, and spinners everywhere. Their navigation is marginally better than Rihla's current state, but neither has attempted the warm, dense, richly designed aesthetic Rihla is targeting. This is a real market gap.

Airbnb is the reference bar for card richness and loading state quality. Revolut is the reference bar for balance display and quick actions. Neither is a direct competitor, which means Rihla can adopt their best patterns without looking derivative.

---

## Dependency on Existing Screens

All screens are affected, ordered by implementation risk:

| Screen | Change Scope | Structural Change Required | Notes |
|--------|--------------|---------------------------|-------|
| HomeScreen | High — complete redesign | YES — add balance hero, group cards, quick-action tray, activity section | Currently just a group list. Becomes the single-scroll dashboard. |
| GroupDashboardScreen | High — layout restructure | YES — replace separate screens with inline tab bar | EventTimeline, BalanceSummary, MemberList become tabs, not pushes. |
| CommandCenter | High — navigation restructure | YES — replace module card grid with swipeable tabs | Core UX change: module selection becomes tab, not card → push. |
| LedgerScreen | Medium — visual polish | NO — content stays, treatment changes | Card-style expense rows, skeleton loading, color-coded balances. |
| GearScreen | Medium — visual polish | NO | Skeleton, checklist item styling. |
| LogisticsScreen | Medium — visual polish | NO | Car card treatment. |
| OnboardingScreen | Medium — illustration upgrade | NO — content stays | Replace current illustrations or text with Rive/custom illustrations in earthy style. |
| SettingsScreen | Low — cosmetic | NO | Apply design tokens, no structural change. |
| VaultScreen | Low — cosmetic | NO | Card treatment for documents. |
| MemoriesScreen | Low — cosmetic | NO | Photo grid already has natural richness; mainly apply design tokens. |

---

## Sources

- [Splitwiser UI/UX Case Study — UX Planet](https://uxplanet.org/splitwiser-the-all-new-splitwise-mobile-app-redesign-ui-ux-case-study-4d3c0313ae6f) — navigation critique, balance display patterns
- [Design Critique: Splitwise (Mobile App) — IXD@Pratt 2026](https://ixd.prattsi.org/2026/02/design-critique-splitwise-mobile-app/) — navigation depth issues, "Plus N other balances" pattern critique
- [Splitwise Redesign case study — Snowdog](https://www.snow.dog/blog/case-study-redesigning-the-splitwise-app-design-team-day) — what users find confusing about current navigation
- [Airbnb UX Secrets — Design Bootcamp](https://medium.com/design-bootcamp/airbnbs-secret-to-seamless-ux-f7caf7cc9b23) — card design, trust badges, prioritization philosophy, "utility and delight are not opposites"
- [Revolut product breakdown — Medium](https://medium.com/@donnachadh.mullen1/my-favorite-product-9677ae071d63) — home screen balance hero, widget customization, Stories card pattern
- [Venmo UX Case Study — Usability Geek](https://usabilitygeek.com/ux-case-study-venmo-app/) — activity feed layout, social payment design
- [Fintech design guide 2026 — Eleken](https://www.eleken.co/blog-posts/modern-fintech-design-guide) — financial summary display, light theme as default for trust
- [Empty State UX best practices — Eleken](https://www.eleken.co/blog-posts/empty-state-ux) — illustrated empty states, context-specific copy, single CTA rule
- [Empty State UI Pattern — Mobbin](https://mobbin.com/glossary/empty-state) — industry standard for structure: illustration + headline + CTA
- [Skeleton Screens 101 — NN/G](https://www.nngroup.com/articles/skeleton-screens/) — skeleton vs. spinner authority, "500ms skeleton feels fast"
- [Mobile Navigation UX Best Practices 2026 — Design Studio](https://www.designstudiouiux.com/blog/mobile-navigation-ux/) — 3-5 tab rule, thumb-zone ergonomics
- [Bottom Tab Bar Navigation — UX Planet](https://uxplanet.org/bottom-tab-bar-navigation-design-best-practices-48d46a3b0c36) — Redbooth 65% DAU lift with bottom nav
- [Lottie vs Rive — Callstack](https://www.callstack.com/blog/lottie-vs-rive-optimizing-mobile-app-animation) — Rive: 60fps vs Lottie 17fps, 2KB vs 24KB, state machines
- [Mobile UX design examples that convert 2025 — Eleken](https://www.eleken.co/blog-posts/mobile-ux-design-examples) — Discord layered interface pattern, Venmo social feed
- [Fintech UX best practices for mobile 2025 — ProCreator](https://procreator.design/blog/best-fintech-ux-practices-for-mobile-apps/) — action-oriented dashboards, color-coded financial states
- [Texture warmth 2026 graphic design trends — Creative Bloq](https://www.creativebloq.com/design/graphic-design/texture-warmth-and-tactile-rebellion-the-big-graphic-design-trends-for-2026) — tactile rebellion, humanized digital interfaces
- [Best 8 mobile app color scheme trends 2026 — Envato](https://elements.envato.com/learn/color-scheme-trends-in-mobile-app-design) — earthy warm neutrals, bento grid layouts, Soft Gradients 2.0
- [Mobile app micro-interactions Flutter 2025 — Medium](https://medium.com/@flutter-app/animations-micro-interactions-in-flutter-make-your-ui-delightful-592fb9da6e11) — TweenAnimationBuilder, spring physics in Flutter
- [Haptic feedback guide 2025 — Saropa](https://saropa-contacts.medium.com/2025-guide-to-haptics-enhancing-mobile-ux-with-tactile-feedback-676dd5937774) — coordinated visual + haptic feedback strategy
- [Google Stitch 2026 complete guide — NxCode](https://www.nxcode.io/resources/news/google-stitch-complete-guide-vibe-design-2026) — Stitch design token import/export, Flutter code output
- [Stitch + Flutter build workflow 2026 — DEV](https://dev.to/safiullahkorai/how-flutter-developers-can-use-stitch-to-build-client-apps-faster-in-2026-32g) — practical Stitch → Flutter workflow
- [Infinite scrolling: when to use it — NN/G](https://www.nngroup.com/articles/infinite-scrolling-tips/) — fails for reference lookup; paginated load-more recommended for expense history
- [Best group travel planning apps 2025 — Plan Harmony](https://www.planharmony.com/blog/best-travel-planning-apps-for-groups-in-2025-plan-harmony-vs-tripit-vs-wanderlog/) — TripIt, Wanderlog navigation critique

---

*Feature research for: UI/UX overhaul of group coordination and social finance app*
*Researched: 2026-03-28*

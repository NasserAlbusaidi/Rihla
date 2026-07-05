## shared/ — Reusable UI Components

### widgets/
- **cover_art.dart**: `CoverArt` procedural two-band landscape (sky/sun/ridge/land) for event/group covers. Palette via `forEventType(EventType)` or `fromSeed(String)`.
- **r_amount.dart**: Money display with Spline Sans Mono tabular figures and currency-aware decimal places. Reach for this before raw `Text` for any monetary value.
- **r_avatar.dart**: `RAvatar` initials stamp with a deterministic per-name colour from an 8-pair journal-stamp palette (`h*31+c` hash → slots 0-7). Also exports `RAvatarStack` (overlapping avatars + `+N` overflow).
- **wordmark_logo.dart**: Rihla wordmark for splash + brand surfaces.
- **module_header.dart**: Gradient module top bar (back + title + action icons).
- **section_header.dart**: Small uppercase mono caption (e.g. "GROUPS") with an optional action link ("See all").
- **offline_banner.dart**: Connectivity banner (watches `connectivityProvider`).
- **empty_state_view.dart**: Placeholder for empty lists with optional CTA.
- **loading_button.dart**: Button with loading spinner state.
- **skeleton_loader.dart**: Named-factory skeleton layouts (`expenseList`, `eventCard`, `groupList`, `dashboardHero`, `generic`, …).
- **skeleton_primitives.dart**: Reusable skeleton shapes used by the loaders above.
- **grain_overlay.dart**: Subtle noise texture overlay (`assets/textures/grain.png`).
- **directional_icon.dart**: `DirectionalIcon` — horizontally mirrors an icon when ambient Directionality is RTL. Use for navigational arrows/chevrons (Iconsax glyphs don't auto-flip in Arabic).

### animations/
- **tap_bounce.dart**: Tap feedback bounce.

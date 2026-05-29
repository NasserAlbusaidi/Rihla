## shared/ — Reusable UI Components

### widgets/
- **cover_art.dart**: Procedural ticket-stub illustration used as the cover for events and group cards. Layout-aware (generates a stable composition from id + type).
- **r_amount.dart**: Money display with Geist Mono tabular figures and currency-aware decimal places. Reach for this before raw `Text` for any monetary value.
- **r_avatar.dart**: Initials avatar with a stable per-id slot colour (FNV-like hash → `cat1`–`cat6` palette).
- **wordmark_logo.dart**: Rihla wordmark for splash + brand surfaces.
- **module_header.dart**: Gradient module top bar (back + title + action icons).
- **section_header.dart**: Italic Instrument Serif section heading.
- **offline_banner.dart**: Connectivity banner (watches `connectivityProvider`).
- **empty_state_view.dart**: Placeholder for empty lists with optional CTA.
- **loading_button.dart**: Button with loading spinner state.
- **skeleton_loader.dart**: Named-factory skeleton layouts (`expenseList`, `eventCard`, `groupList`, `dashboardHero`, `generic`, …).
- **skeleton_primitives.dart**: Reusable skeleton shapes used by the loaders above.
- **grain_overlay.dart**: Subtle noise texture overlay (`assets/textures/grain.png`).
- **initials_circle.dart**: Legacy avatar circle (prefer `RAvatar` for new code).

### animations/
- **fade_in_list.dart**: Staggered fade-in for list items.
- **staggered_grid.dart**: Staggered grid animation.
- **tap_bounce.dart**: Tap feedback bounce.
- **animations.dart**: Barrel export.

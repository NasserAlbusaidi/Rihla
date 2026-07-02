## home/ — Dashboard & Navigation

- **providers/dashboard_providers.dart**: crossGroupActivityProvider — merges per-group activity across all groups, newest first (enriched with groupName), capped at `kCrossGroupActivityMergedCap` (30). Each group contributes up to `kCrossGroupActivityPerGroupLimit` (15) via `groupActivityProvider` (in group_balance_provider.dart), so the Activity tab's filter chips operate on a real window rather than a 5-item cache. The home RECENTLY section is unaffected — it slices `take(3)`. (Cross-group balance lives in groups/providers/group_balance_provider.dart; there is no weekly-spending provider.)
- **screens/home_screen.dart**: Groups-first dashboard with greeting strip, BalanceHeroCard, ACTIVE JOURNEYS strip (JourneyTicketCard), GROUPS list, and a RECENTLY top-3 activity section
- **screens/cross_group_activity_screen.dart**: Reverse-chronological cross-group activity timeline (tab 1)
- **widgets/bottom_nav_shell.dart**: 3-tab nav — Groups (HomeScreen), Activity (CrossGroupActivityScreen), Profile (ProfileScreen). Tab state preserved via Stack + AnimatedOpacity + IgnorePointer; not GoRouter-driven.
- **widgets/balance_hero_card.dart**: Aggregated net balance across all groups
- **widgets/activity_row.dart**, **journey_ticket_card.dart**, **group_glyph.dart** (plus balance_hero_card.dart and bottom_nav_shell.dart above)

## home/ — Dashboard & Navigation

- **providers/dashboard_providers.dart**: crossGroupActivityProvider — merges the 5 most recent activity entries across all groups, newest first (enriched with groupName). (Cross-group balance lives in groups/providers/group_balance_provider.dart; there is no weekly-spending provider.)
- **screens/home_screen.dart**: Groups-first dashboard with greeting strip, BalanceHeroCard, ACTIVE JOURNEYS strip (JourneyTicketCard), GROUPS list, and a RECENTLY top-3 activity section
- **screens/cross_group_activity_screen.dart**: Reverse-chronological cross-group activity timeline (tab 1)
- **widgets/bottom_nav_shell.dart**: 3-tab nav — Groups (HomeScreen), Activity (CrossGroupActivityScreen), Profile (ProfileScreen). Tab state preserved via Stack + AnimatedOpacity + IgnorePointer; not GoRouter-driven.
- **widgets/balance_hero_card.dart**: Aggregated net balance across all groups
- **widgets/activity_row.dart**, **journey_ticket_card.dart**, **group_glyph.dart** (plus balance_hero_card.dart and bottom_nav_shell.dart above)

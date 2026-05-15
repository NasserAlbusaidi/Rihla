## home/ — Dashboard & Navigation

- **providers/dashboard_providers.dart**: Computed cross-group balance, weekly spending, recent activity summaries
- **screens/home_screen.dart**: Groups-first dashboard with greeting, balance hero, quick actions, group cards, recent activity, weekly spending chart
- **screens/cross_group_activity_screen.dart**: Reverse-chronological cross-group activity timeline (tab 1)
- **widgets/bottom_nav_shell.dart**: 3-tab nav — Groups (HomeScreen), Activity (CrossGroupActivityScreen), Profile (ProfileScreen). Tab state preserved via Stack + AnimatedOpacity + IgnorePointer; not GoRouter-driven.
- **widgets/balance_hero_card.dart**: Aggregated net balance across all groups
- **widgets/quick_action_tray.dart**, **weekly_spending_card.dart**, **activity_row.dart**, **journey_ticket_card.dart**

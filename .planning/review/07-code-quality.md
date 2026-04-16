# Code Quality & Cleanup — LOW

**9/11 FIXED | 2 remaining (larger scope)**

## ~~26. ~750 Lines of Dead Code~~ FIXED

Deleted 8 dead files (~1750 lines): event_spending_hero, timeline_card, photo_grid, unassigned_pool, transaction_list, member_balances_section, spending_summary_section, settings_keys. Removed dead GearStats class and LogisticsKeys.unassignedPool key.

## ~~27. 50+ debugPrint Statements in Production~~ FIXED

72 total: 32 verbose trace logs removed entirely, 40 service error logs gated behind `kDebugMode`. Zero unguarded `debugPrint` calls remain in production code.

## ~~28. Swallowed Exceptions~~ FIXED

All service-level catches now log with `kDebugMode` and `rethrow` (fixed in debugPrint cleanup session). The 2 remaining truly empty catch blocks (`local_database.dart` migration, `settle_up_screen.dart` Firebase UID) now have explanatory comments. Screen-level catches for activity logging are intentionally non-blocking (documented with comments). 63 catch blocks audited total.

## ~~29. Accessibility Gaps~~ PARTIALLY FIXED

- ~~Back buttons 44x44dp~~ FIXED — bumped to 48x48dp in both `_LightBackButton` and `_DarkBackButton`
- `textMuted` (#9CA3AF) fails WCAG AA at 2.86:1 on white — STILL OPEN (codebase-wide, ~100 usages)
- ~~Missing `Semantics` on `SmartModuleCard`, `DotStepIndicator`~~ FIXED — added semantic labels

## ~~30. AppShadowTokens Allocates on Every Access~~ FIXED

Changed `static get standard` → `static final standard`. Single allocation.

## 31. Spacing Tokens Dead Infrastructure — STILL OPEN

`AppSpacingTokens.standard` exists but every widget hardcodes raw numbers.

## ~~32. Hardcoded Colors Outside Token System~~ PARTIALLY FIXED

Replaced hardcoded defaults with token references in `error_widgets.dart` (warning color) and `dot_step_indicator.dart` (focusBorderWarm). Remaining: `const` maps in `event_type_config.dart` and `group_card.dart` (cannot reference ThemeExtension — already have inline comments mapping to tokens), `app_theme.dart` dark theme colors (#17), `onboarding_screen.dart` gradients, `app_router.dart` splash background.

## 33. Test Coverage Gaps — STILL OPEN

Zero tests for: `firebase_config.dart`, `notification_service.dart`, `cache_service.dart`, `thawani_service.dart`, `receipt_service.dart`, `ocr_service.dart`, vault/memories/logistics providers, `onboarding_screen.dart`, router redirects. Zero error path tests. Zero security rule tests.

## ~~34. App Still Says "Safar"~~ FIXED

Changed `title: 'Safar'` → `title: 'Rihla'` in main.dart.

## ~~35. CLAUDE.md radiusSmall Mismatch~~ FIXED

Updated CLAUDE.md to `radiusSmall=8` (matches code).

## ~~36. GoRouter Version Mismatch~~ FIXED

Updated CLAUDE.md to `go_router: ^13.2.0` (matches pubspec.yaml).

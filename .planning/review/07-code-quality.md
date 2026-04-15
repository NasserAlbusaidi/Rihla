# Code Quality & Cleanup — LOW

**6/11 FIXED | 5 remaining (larger scope)**

## ~~26. ~750 Lines of Dead Code~~ FIXED

Deleted 8 dead files (~1750 lines): event_spending_hero, timeline_card, photo_grid, unassigned_pool, transaction_list, member_balances_section, spending_summary_section, settings_keys. Removed dead GearStats class and LogisticsKeys.unassignedPool key.

## ~~27. 50+ debugPrint Statements in Production~~ FIXED

72 total: 32 verbose trace logs removed entirely, 40 service error logs gated behind `kDebugMode`. Zero unguarded `debugPrint` calls remain in production code.

## 28. 16 Swallowed Exceptions — STILL OPEN

`catch (_) { }` in 16 locations. Some completely empty (`local_database.dart:430`, `settle_up_screen.dart:179`).

## 29. Accessibility Gaps — STILL OPEN

- Back buttons 44x44dp (below 48dp WCAG minimum)
- `textMuted` (#9CA3AF) fails WCAG AA at 2.86:1 on white
- Missing `Semantics` on `SmartModuleCard`, `DotStepIndicator`

## ~~30. AppShadowTokens Allocates on Every Access~~ FIXED

Changed `static get standard` → `static final standard`. Single allocation.

## 31. Spacing Tokens Dead Infrastructure — STILL OPEN

`AppSpacingTokens.standard` exists but every widget hardcodes raw numbers.

## 32. Hardcoded Colors Outside Token System — STILL OPEN

15+ instances of `Color(0xFF...)` in `dot_step_indicator.dart`, `app_router.dart`, `error_widgets.dart`, `app_theme.dart`, `onboarding_screen.dart`.

## 33. Test Coverage Gaps — STILL OPEN

Zero tests for: `firebase_config.dart`, `notification_service.dart`, `cache_service.dart`, `thawani_service.dart`, `receipt_service.dart`, `ocr_service.dart`, vault/memories/logistics providers, `onboarding_screen.dart`, router redirects. Zero error path tests. Zero security rule tests.

## ~~34. App Still Says "Safar"~~ FIXED

Changed `title: 'Safar'` → `title: 'Rihla'` in main.dart.

## ~~35. CLAUDE.md radiusSmall Mismatch~~ FIXED

Updated CLAUDE.md to `radiusSmall=8` (matches code).

## ~~36. GoRouter Version Mismatch~~ FIXED

Updated CLAUDE.md to `go_router: ^13.2.0` (matches pubspec.yaml).

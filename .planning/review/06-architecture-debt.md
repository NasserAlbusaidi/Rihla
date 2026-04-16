# Architecture & Design Debt — MEDIUM

**1/6 FIXED | 1 partial | 3 deferred (large refactors) | 1 theoretical (no active callers)**

## 15. God Screens — STILL OPEN

All five still exceed 600 lines:

| File | Lines | Status |
|------|-------|--------|
| `group_settle_up_screen.dart` | 990 | Still open |
| `edit_expense_screen.dart` | 799 | Still open |
| `gear_screen.dart` | 731 | Still open |
| `logistics_screen.dart` | 690 | Still open |
| `create_event_screen.dart` | 690 | Still open (defensible — well-structured) |

## 16. Provider Watch Explosion on Dashboard — STILL OPEN

Home screen creates O(G x E) Firestore listeners. `weeklyGroupSpendingProvider` loads ALL expenses to filter for current week client-side.

## 17. Broken Dark Theme — PARTIALLY FIXED (foundation in place)

`AppColorTokens.dark` static instance now defined in `color_tokens.dart` with Slate-based dark palette. `darkTheme` in `app_theme.dart` now references `AppColorTokens.dark` throughout instead of `AppColorTokens.light`. Extensions registered in darkTheme. 5 tests added.

**Still open:** Widget-level migration. 898 direct `AppColorTokens.light` calls across the codebase still render light colors regardless of theme. Full dark-mode support requires migrating widgets to `context.colors` — a separate milestone.

## 18. CacheService God Class — STILL OPEN

660 lines, all static. Duplicated by `balance_cache_repository.dart` with different conflict strategies.

## ~~19. Stale SQLite Cache~~ FIXED

`cacheExpenses` and `cacheSettlements` now delete all rows for the eventId before batch-inserting the fresh set from Firestore. Ghost rows from server-side deletes no longer persist.

## 22. `copyWith` Cannot Clear Optional Fields — DEFERRED (no active callers)

`startDate ?? this.startDate` pattern in event/gear/expense models prevents clearing fields back to null. Grep confirms no callsite currently passes explicit null — theoretical debt only. Fix with sentinel pattern when a caller needs it.

## Files Involved

- `lib/features/groups/screens/group_settle_up_screen.dart`
- `lib/features/ledger/screens/edit_expense_screen.dart`
- `lib/features/gear/screens/gear_screen.dart`
- `lib/features/logistics/screens/logistics_screen.dart`
- `lib/features/home/screens/home_screen.dart`
- `lib/core/theme/app_theme.dart`
- `lib/core/services/cache_service.dart`
- `lib/core/services/balance_cache_repository.dart`
- `lib/features/events/models/event_model.dart`
- `lib/features/gear/models/gear_item_model.dart`

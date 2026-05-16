# lib/core/ — Core Infrastructure

## config/

- **app_metadata.dart**: App branding (`visibleAppName: 'Rihla'`), version metadata from `package_info_plus`. Class: `AppMetadata`, Provider: `appMetadataProvider`. Factory constructors: `fromPackageInfo()`, `fallback()`.
- **firebase_config.dart**: Firebase initialization with Firestore offline persistence (unlimited cache). Anonymous auth via `ensureAnonymousSession()` (waits for auth state restoration before creating new session). Static accessors: `FirebaseConfig.auth`, `FirebaseConfig.firestore`.

## router/

- **app_router.dart**: GoRouter declarative routing. Route constants in `AppRoutes` class. Routes: splash (`/`, redirects to `/home`), home, profile, account recovery, activity, create-group, join-group, invite join (`/join/:code`), group detail with nested settings, settle-up, activity, and create-event routes, plus event hub routes for ledger, activity, and settings. Ledger has nested add/edit/settle-up. Provider: `routerProvider`. Pages use `CustomTransitionPage` with shared-axis or route-specific transitions.

## theme/

- **app_theme.dart**: Material 3 `ThemeData` (light mode). Typography: Geist (sans), Geist Mono (tabular figures, money), Instrument Serif italic (display + section headers) via `google_fonts`. Registers `AppColorTokens`, `AppSpacingTokens`, `AppShadowTokens` as `ThemeExtension`s. Class: `AppTheme`.
- **tokens/color_tokens.dart**: `AppColorTokens extends ThemeExtension<AppColorTokens>` — Saffron palette: paper background, saffron primary, sage success, rust error, success/error/disabled/focus states, `moduleLedger` accent (the only colored module post-Phase 39), category + avatar slot colours, header gradient colors. Singleton: `AppColorTokens.light`.
- **tokens/spacing_tokens.dart**: `AppSpacingTokens extends ThemeExtension<AppSpacingTokens>` — `space4` through `space32`, border radii (`radiusSmall`, `radiusMedium`, `radiusLarge`), `buttonHeight`. Singleton: `AppSpacingTokens.standard`.
- **tokens/shadow_tokens.dart**: `AppShadowTokens extends ThemeExtension<AppShadowTokens>` — three elevation levels: `flat` (none), `raised` (subtle), `floating` (modal). Gray-900 base. Singleton: `AppShadowTokens.standard`.
- **tokens/domain_aliases.dart**: `BuildContext` extension methods for terse token access: `context.colors`, `context.spacing`, `context.shadows`. Uses `Theme.of(this).extension<T>()!`.
- **error_widgets.dart**: `NetworkErrorWidget` — reusable error state widget with factory constructors: `loadingError()`, `offline()`. Retry callback support. Uses Iconsax icons.

## models/

- **app_settings_model.dart**: `AppSettings` — immutable settings model (theme, language, currency, push notifications, device name). `AppThemeMode` enum (`light`, `dark`, `system`). `copyWith()` for updates. Default currency: OMR.

## providers/

- **app_bootstrap_provider.dart**: `appBootstrapProvider` — syncs notification opt-in/out state. Listens to `settingsProvider.pushNotificationsEnabled` and initializes/removes FCM token accordingly.
- **connectivity_provider.dart**: `connectivityProvider` (`StateNotifierProvider<ConnectivityNotifier, ConnectivityStatus>`). Enum: `online`, `offline`, `syncing`. Checks connectivity every 60s by pinging Firestore (`inviteCodes` collection, `Source.server`).
- **settings_provider.dart**: `sharedPreferencesProvider` (must be overridden in `main()`), `settingsServiceProvider`, `settingsProvider` (`StateNotifierProvider<SettingsNotifier, AppSettings>`). `SettingsNotifier` exposes setters for theme, language, currency, push notifications, device name. Device name changes propagate to Firestore group member records.

## services/

- **firestore_repository.dart**: `FirestoreRepository` — abstract base for all Firestore services. Production constructor uses `FirebaseConfig.firestore`; test constructor accepts `FakeFirebaseFirestore`. Helper: `eventSubcollection(groupId, eventId, module)` returns `groups/{groupId}/events/{eventId}/{module}`.
- **local_database.dart**: `LocalDatabase` — SQLite offline cache via sqflite. DB: `safar_cache.db`, **version 8**. Tables: `trips`, `expenses`, `settlements`, `gear_items` (legacy, retained for SQLite compatibility), `participants`, `sub_groups`, `sub_group_members`, `activity_logs`, `categories`, `groups`, `group_members`, `group_ledger`. Singleton with `Completer`-guarded initialization.
### Domain Cache Repositories (`services/cache/`)

Each file owns SQLite I/O for one domain of the local cache (`safar_cache.db` v8). Instance-based, provided via Riverpod.

- **expense_cache_repository.dart**: `ExpenseCacheRepository` — ghost-row-free write via delete-all-for-event + batch insert. Consumed by `eventExpensesProvider.asyncMap` side-write (D-15).
- **settlement_cache_repository.dart**: `SettlementCacheRepository` — same delete-then-insert pattern as expenses.
- **trip_cache_repository.dart**: `TripCacheRepository` — upsert + cascading delete across 9 related tables in one transaction.
- **participant_cache_repository.dart**: `ParticipantCacheRepository` — delete-all + batch-insert.
- **activity_log_cache_repository.dart**: `ActivityLogCacheRepository` — delete-all + batch-insert, 50-row read cap.
- **category_cache_repository.dart**: `CategoryCacheRepository` — delete-all + batch-insert.
- **group_cache_repository.dart**: `GroupCacheRepository` — upsert + explicit cascade delete for groups and group_members.
- **money_serializer.dart**: `MoneySerializer` — `Decimal` to/from integer subunits for Firestore storage. Currency scale map: OMR/KWD/BHD = 1000, USD/EUR/GBP/SAR/AED/QAR = 100, JPY = 1. Methods: `toSubunits()`, `fromSubunits()`. Only used at the Firestore read/write boundary.
- **haptic_service.dart**: `HapticService` — static methods wrapping Flutter `HapticFeedback`. Patterns: `lightClick()`, `success()` (double medium tap), `warning()` (heavy), `selection()`, `medium()`.
- **notification_service.dart**: `NotificationService` — FCM push notifications. `NotificationStatus` enum (`off`, `enabled`, `permissionDenied`, `error`). Handles permission requests, token save/refresh/remove to Firestore `fcm_tokens`. Providers: `notificationServiceProvider`, `notificationStatusProvider`.
- **settings_service.dart**: `SettingsService` — SharedPreferences persistence layer for `AppSettings`. Keys: `settings_theme`, `settings_language`, `settings_currency`, `settings_push_notifications`, `settings_device_name`. Methods: `loadSettings()`, individual save methods.

## types/

- **event_ref.dart**: `typedef EventRef = ({String groupId, String eventId})` — record type used as family parameter for all event-scoped Riverpod providers.

## utils/

- **formatters.dart**: `AppFormatters` — currency formatting (`formatOMR`, `formatCurrency` with multi-currency support), date formatting (`formatShortMonthDay`, `formatRelativeDate`). `CurrencyConfig` class maps currency codes to symbols and decimal places.

## keys/

- **shared_keys.dart**: `SharedKeys` — abstract final class of semantic `Key` constants for testing and accessibility. Covers: ModuleHeader, OfflineBanner, EmptyStateView, GroupBalanceHero, InviteCodeDisplay, AppTabBar (parameterized), LoadingButton (parameterized).

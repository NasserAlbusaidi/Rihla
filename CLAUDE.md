# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Rihla ("Journey") is a Flutter mobile app for group trip planning. Package name is `safar`, Android ID is `com.safar.safar`. Backend is Supabase (PostgreSQL, Realtime, Storage, Auth). The app supports offline-first operation with SQLite caching and a sync queue.

## Essential Commands

```bash
# Install dependencies
flutter pub get

# Run the app (config.json at root is required)
flutter run --dart-define-from-file=config.json

# Run all tests
flutter test

# Run specific test file
flutter test test/unit/balance_calculations_test.dart

# Run tests in a directory
flutter test test/unit/

# Static analysis
flutter analyze

# Build release Android
flutter build appbundle --release --obfuscate --split-debug-info=./build/app/outputs/symbols --dart-define-from-file=config.json
```

Compile-time config is injected via `--dart-define-from-file=config.json` and read with `const String.fromEnvironment(...)`. The `config.json` contains `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SENTRY_DSN`.

Firebase is also configured for push notifications (FCM). Platform config files: `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`.

## Architecture

### Feature-First Structure

Each feature under `lib/features/` is self-contained with `models/`, `providers/`, `screens/`, `services/`, and optionally `widgets/`. There is no shared repository abstraction — services interact directly with Supabase.

Features: `auth`, `trip`, `ledger`, `gear`, `logistics`, `vault`, `activity`, `home`, `settings`, `memories`, `onboarding`.

### State Management: Riverpod 2.x

Providers are defined manually (not code-gen). Key provider patterns:
- `StreamProvider` / `StreamProvider.family` for real-time Supabase subscriptions
- `StateNotifierProvider` for complex state (settings, connectivity)
- `FutureProvider` for one-shot async reads
- `Provider.family` for services and derived state

Every major data stream follows **cache-on-success + fallback-to-cache-on-error**: data is cached to SQLite on fetch, and served from cache when offline.

### Routing: Mixed

- **GoRouter** handles top-level routes: `/home`, `/create-trip`, `/join-trip`, `/settings`, `/onboarding`
- **CommandCenter** (the per-trip hub) and all feature screens below it use `Navigator.push` — they are NOT in GoRouter. This is intentional but means deep linking doesn't reach trip sub-screens.

### Navigation Flow

```
HomeScreen (/home, GoRouter)
  → tap trip card → Navigator.push(CommandCenter)
    → CommandCenter shows module cards: Ledger, Gear, Logistics, Vault, Activity, Memories
      → each module pushed via Navigator.push (using AppPageRoute for slide transitions)
```

### Offline / Sync

- `LocalDatabase` (Sqflite): `safar_cache.db` with tables `trips`, `expenses`, `gear_items`, `settlements`, `sync_queue`
- `CacheService`: static methods for batch cache read/write and sync queue management
- `SyncService`: uploads pending queue to Supabase, downloads fresh data. `fullSync()` = upload + download
- `ConnectivityProvider`: checks online status every 60 seconds via Supabase query

### Shared Widgets (`lib/shared/widgets/`)

Reusable UI components used across features:
- `ModuleHeader` — dark gradient header replacing per-screen duplicates
- `AppTabBar` — unified tab bar with gradient pill indicator
- `OfflineBanner` — connectivity indicator (watches `connectivityProvider`)
- `EmptyStateView` — consistent empty states with optional CTA
- `SearchFilterBar` — expandable search + filter chips
- `SmartModuleCard` — module cards for CommandCenter
- `LoadingButton` / `SkeletonLoader` — loading states

### Design Tokens (`lib/core/theme/app_theme.dart`)

Spacing constants (`space4`–`space32`), border radii (`radiusSmall=12`, `radiusMedium=16`, `radiusLarge=20`), elevation shadows (`shadowFlat`, `shadowRaised`, `shadowFloating`), and `buttonHeight=52`. 
### Page Transitions (`lib/core/utils/page_transitions.dart`)

`AppPageRoute` (slide-right) and `AppBottomSheetRoute` (slide-up) replace raw `MaterialPageRoute` across all navigation.

### Financial Calculations

All money math uses the `Decimal` package (not `double`). Currency is OMR (Omani Rial, 3 decimal places). `BalanceCalculator` in ledger handles four expense scopes: `global`, `subGroup`, `personal`, `custom`. Settlement optimization uses a greedy min-transactions algorithm.

## Key Technical Details

- **Soft deletes**: Expenses, gear items, and settlements use `is_deleted` + `deleted_at` flags. Hard deletes only on trips (cascade) and documents.
- **Shadow profiles**: Non-app participants supported via `shadow_profiles` table — trip leaders can add members who don't have accounts.
- **Trip modules**: Each trip has a `TripModules` object controlling which features appear in CommandCenter (docs, gear, itinerary, logistics).
- **Document storage**: `trip-documents` Supabase bucket. Signed URLs with 1-hour expiry, cached locally. Max 25 MB per file.
- **Memories storage**: `trip-memories` Supabase bucket for trip photo/media uploads.
- **Thawani payments**: `thawani_payment` package for Omani payment processing. Note: `Product` class needs separate import from `thawani_payment/models/products.dart`; `onCreate` expects `Create` type.
- **Onboarding**: 3-page PageView stored in SharedPreferences via `onboardingCompleteProvider`. Router redirect reads `valueOrNull` synchronously — override with `overrideWith((ref) => true)` in tests, not async.
- **Multi-currency**: Trips can have a base currency. Expenses support automatic conversion using live rates or manual overrides.
- **Push notifications**: Firebase Cloud Messaging (FCM). Token storage in `fcm_tokens` table.
- **Auth**: Supabase anonymous sign-in (`signInAnonymously()`). No login screen — session created silently on first launch via `SupabaseConfig.ensureAnonymousSession()`. All RLS policies work because `auth.uid()` is valid for anonymous users. No email/password, no password reset.

## Database

28 SQL migrations in `supabase/migrations/`. Core tables: `trips`, `participants`, `expenses`, `settlements`, `gear_items`, `documents`, `sub_groups`, `sub_group_members`, `profiles`, `shadow_profiles`, `trip_activity_logs`, `trip_memories`, `payment_tracking`. All tables use RLS; the helper function `is_trip_member(trip_uuid)` (SECURITY DEFINER) prevents RLS recursion.

## Testing

- `test/unit/` — pure logic tests (BalanceCalculator, AppFormatters)
- `test/features/` — widget tests (CommandCenter, Ledger)
- `test/integration/` — E2E widget test with mocked Riverpod providers
- Mocking uses `mocktail`
- Integration tests override providers to avoid real Supabase calls
- CommandCenter tests require `tripMemoriesProvider` override
- Ledger tests require `tripTransactionActivityProvider` override
- Label references in tests: `'SPENDING'` (not `'TREASURY'`), `'Ledger'` (not `'Audit Log'`)

## CI/CD

GitHub Actions workflow (`.github/workflows/release_android.yml`): manual dispatch or `v*` tag push. Runs tests then builds and uploads AAB to Google Play alpha track. Required secrets: `KEYSTORE_BASE64`, `KEY_PROPERTIES`, `CONFIG_JSON`, `GOOGLE_PLAY_JSON_KEY`. No iOS CI — iOS builds are manual.

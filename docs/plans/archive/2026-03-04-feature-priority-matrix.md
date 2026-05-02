# Feature Priority Matrix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add multi-currency support, receipt OCR, enhanced export/reporting, and push notifications to the Rihla travel expense app.

**Architecture:** Four features implemented in dependency order. Multi-currency first (foundational — changes formatters and models used everywhere), then receipt OCR (enhances expense creation), export improvements (leverages currency changes), and push notifications last (standalone Firebase integration). All features follow existing Riverpod + Supabase patterns.

**Tech Stack:** Flutter/Riverpod, Supabase (Postgres + Edge Functions + Storage), google_mlkit_text_recognition, firebase_core/firebase_messaging, pdf/csv packages (existing).

---

## Feature 1: Multi-Currency Support

### Task 1: Update currency formatter to be currency-aware

**Files:**
- Modify: `lib/core/utils/formatters.dart`
- Modify: `lib/core/models/app_settings_model.dart`

**Step 1:** Read `lib/core/utils/formatters.dart` and `lib/core/models/app_settings_model.dart` to understand current implementation.

**Step 2:** Add a currency config map and update `formatOMR` → `formatCurrency` in `formatters.dart`:

```dart
/// Currency display configurations
static const Map<String, ({String symbol, int decimals, bool symbolBefore})> _currencyConfig = {
  'OMR': (symbol: 'OMR', decimals: 3, symbolBefore: false),
  'USD': (symbol: '\$', decimals: 2, symbolBefore: true),
  'EUR': (symbol: '€', decimals: 2, symbolBefore: true),
  'GBP': (symbol: '£', decimals: 2, symbolBefore: true),
  'AED': (symbol: 'AED', decimals: 2, symbolBefore: false),
  'SAR': (symbol: 'SAR', decimals: 2, symbolBefore: false),
};

/// Format amount with the given currency code
static String formatCurrency(Decimal amount, String currencyCode) {
  final config = _currencyConfig[currencyCode] ?? _currencyConfig['OMR']!;
  final formatted = amount.toStringAsFixed(config.decimals);
  return config.symbolBefore
      ? '${config.symbol}$formatted'
      : '$formatted ${config.symbol}';
}

/// Legacy helper - uses OMR (keep for backward compatibility during migration)
static String formatOMR(Decimal amount) => formatCurrency(amount, 'OMR');
```

**Step 3:** Run `flutter analyze` — expect 0 new errors (formatOMR still exists).

**Step 4:** Run `flutter test` — all 15 tests should pass.

---

### Task 2: Add currency to Trip model and Supabase schema

**Files:**
- Create: `supabase/migrations/20260304000001_add_trip_currency.sql`
- Modify: `lib/features/trip/models/trip_model.dart`

**Step 1:** Read `lib/features/trip/models/trip_model.dart` and `supabase/migrations/` directory to understand patterns.

**Step 2:** Create the migration file:

```sql
-- Add currency column to trips table
ALTER TABLE trips ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'OMR';

-- Add comment for documentation
COMMENT ON COLUMN trips.currency IS 'ISO 4217 currency code for this trip';
```

**Step 3:** Add `currency` field to Trip model in `trip_model.dart`:
- Add field: `final String currency;`
- Add to constructor with default `'OMR'`
- Add to `fromJson`: `currency: json['currency'] as String? ?? 'OMR'`
- Add to `toJson`: `'currency': currency`
- Add to `copyWith`

**Step 4:** Run `flutter analyze` and `flutter test`.

---

### Task 3: Wire currency through expense display

**Files:**
- Modify: `lib/features/ledger/models/expense_model.dart`
- Modify: `lib/features/ledger/screens/ledger_screen.dart`
- Modify: `lib/features/ledger/screens/add_expense_screen.dart`

**Step 1:** Read `lib/features/ledger/models/expense_model.dart` — note it has `formattedAmount` getter using `AppFormatters.formatOMR()`.

**Step 2:** Update `Expense.formattedAmount` to accept currency:
- Can't easily pass currency to a getter, so add a method:
  ```dart
  String formattedAmountIn(String currencyCode) =>
      AppFormatters.formatCurrency(amount, currencyCode);
  ```
- Keep `formattedAmount` as-is for backward compatibility (will remove later).

**Step 3:** In `ledger_screen.dart`, wherever `expense.formattedAmount` is used, replace with `expense.formattedAmountIn(widget.trip.currency)`. Search for all occurrences of `formattedAmount` and `formatOMR` in the file.

**Step 4:** In `add_expense_screen.dart`, update the amount display header to show the trip's currency symbol instead of hardcoded 'OMR'. The trip is passed as `widget.tripId` — you'll need to also pass the currency or read it from the trip provider.

**Step 5:** Run `flutter analyze` and `flutter test`.

---

### Task 4: Update balance display and settlements with currency

**Files:**
- Modify: `lib/features/ledger/screens/settle_up_screen.dart`
- Modify: `lib/features/ledger/providers/expense_provider.dart` (balance calculator)
- Modify: `lib/features/home/screens/command_center.dart`

**Step 1:** Search all files for `formatOMR` and `OMR` string literals: `grep -rn "formatOMR\|'OMR'" lib/`

**Step 2:** In `settle_up_screen.dart`, replace all `formatOMR` calls with `formatCurrency(amount, trip.currency)`. The settle up screen needs access to the trip — check if it already receives it or if you need to add it.

**Step 3:** In `command_center.dart`, the `_buildModuleList` method shows balance summaries with OMR formatting. Update to use `trip.currency`.

**Step 4:** Run `flutter analyze` and `flutter test`.

---

### Task 5: Update trip creation to include currency picker

**Files:**
- Modify: `lib/features/trip/screens/create_trip_screen.dart`

**Step 1:** Read `create_trip_screen.dart` to understand the trip creation flow.

**Step 2:** Add a currency dropdown/selector to the create trip form. Use the supported currencies list from `AppSettings.supportedCurrencies`. Default to the user's setting from `settingsProvider`.

**Step 3:** Pass the selected currency when creating the trip via the trip service.

**Step 4:** Run `flutter analyze` and `flutter test`.

---

### Task 6: Update export service with currency

**Files:**
- Modify: `lib/features/trip/services/trip_export_service.dart`

**Step 1:** Read `trip_export_service.dart` — note hardcoded 'OMR' references in PDF and CSV headers.

**Step 2:** Update `exportAndSharePDF` and `exportAndShareCSV` to accept a `currency` parameter (from trip.currency). Replace all hardcoded 'OMR' with the currency parameter and use `AppFormatters.formatCurrency()`.

**Step 3:** Update callers in `command_center.dart` to pass `trip.currency`.

**Step 4:** Run `flutter analyze` and `flutter test`.

---

### Task 7: Multi-currency verification

**Step 1:** Run `grep -rn "OMR" lib/` — verify no more hardcoded OMR references remain except in the currency config map and the legacy `formatOMR` helper.

**Step 2:** Run `flutter analyze` — 0 new errors.

**Step 3:** Run `flutter test` — all tests pass. Update any test that checks for "OMR" formatted strings.

---

## Feature 2: Receipt OCR

### Task 8: Add ML Kit dependency and create OCR service

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/core/services/ocr_service.dart`

**Step 1:** Add to pubspec.yaml dependencies:
```yaml
google_mlkit_text_recognition: ^0.14.0
```
Run `flutter pub get`.

**Step 2:** Create `lib/core/services/ocr_service.dart`:

```dart
import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:decimal/decimal.dart';

class OcrResult {
  final Decimal? amount;
  final String? description;
  final String rawText;

  const OcrResult({this.amount, this.description, required this.rawText});
}

class OcrService {
  static final _textRecognizer = TextRecognizer();

  /// Extract text from an image file and attempt to parse expense data
  static Future<OcrResult> extractFromImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognized = await _textRecognizer.processImage(inputImage);
    final rawText = recognized.text;

    // Try to find the largest decimal number (likely the total)
    final amountRegex = RegExp(r'(\d{1,6}[.,]\d{2,3})');
    final matches = amountRegex.allMatches(rawText).toList();

    Decimal? amount;
    if (matches.isNotEmpty) {
      // Take the largest number found (usually the total)
      final amounts = matches
          .map((m) => Decimal.tryParse(m.group(1)!.replaceAll(',', '.')))
          .whereType<Decimal>()
          .toList()
        ..sort((a, b) => b.compareTo(a));
      amount = amounts.isNotEmpty ? amounts.first : null;
    }

    // Try to find a merchant/store name (first line that isn't a number)
    String? description;
    final lines = rawText.split('\n').where((l) => l.trim().isNotEmpty).toList();
    for (final line in lines) {
      if (!RegExp(r'^\d').hasMatch(line.trim()) && line.trim().length > 2) {
        description = line.trim();
        break;
      }
    }

    return OcrResult(amount: amount, description: description, rawText: rawText);
  }

  static void dispose() {
    _textRecognizer.close();
  }
}
```

**Step 3:** Run `flutter analyze` — should have 0 errors.

---

### Task 9: Add receipt image capture and upload to Supabase Storage

**Files:**
- Create: `lib/core/services/receipt_storage_service.dart`

**Step 1:** Check if Supabase Storage bucket exists. If not, we'll create it via migration or manually. Create the storage service:

```dart
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../config/supabase_config.dart';

class ReceiptStorageService {
  static const _bucketName = 'receipts';

  /// Upload receipt image and return the public URL
  static Future<String?> uploadReceipt({
    required File imageFile,
    required String tripId,
    required String expenseId,
  }) async {
    try {
      final ext = imageFile.path.split('.').last;
      final fileName = '${const Uuid().v4()}.$ext';
      final storagePath = '$tripId/$fileName';

      await SupabaseConfig.client.storage
          .from(_bucketName)
          .upload(storagePath, imageFile);

      final publicUrl = SupabaseConfig.client.storage
          .from(_bucketName)
          .getPublicUrl(storagePath);

      return publicUrl;
    } catch (e) {
      return null;
    }
  }
}
```

**Step 2:** Create Supabase migration for the storage bucket:

```sql
-- Create receipts storage bucket (run via Supabase Dashboard > Storage > New Bucket)
-- Name: receipts
-- Public: true
-- File size limit: 10MB
-- Allowed MIME types: image/jpeg, image/png, image/webp
```

**Step 3:** Run `flutter analyze`.

---

### Task 10: Integrate OCR into add expense flow

**Files:**
- Modify: `lib/features/ledger/screens/add_expense_screen.dart`

**Step 1:** Read the current receipt capture code in `add_expense_screen.dart` (search for `_receiptPath`, `_pickReceiptImage`, `_isUploadingReceipt`).

**Step 2:** Update the receipt capture flow:
1. When user picks/captures a receipt image, run OCR immediately
2. Show a bottom sheet with extracted data: "Found: [amount] — [description]"
3. User can tap "Use Amount" to auto-fill the amount field
4. User can tap "Use Description" to auto-fill description
5. Store the image path for upload on expense save

**Step 3:** After the expense is saved (in the `_saveExpense` method), upload the receipt image to Supabase Storage and update the expense's `receipt_url`.

**Step 4:** Run `flutter analyze` and `flutter test`.

---

### Task 11: Add receipt preview to expense detail

**Files:**
- Modify: `lib/features/ledger/screens/ledger_screen.dart`

**Step 1:** In the expense detail/card view, if `expense.receiptUrl` is not null, show a small receipt icon indicator.

**Step 2:** When tapped, show a full-screen image viewer (use `showDialog` with `InteractiveViewer` wrapping `Image.network(expense.receiptUrl!)`).

**Step 3:** Run `flutter analyze`.

---

### Task 12: OCR verification

**Step 1:** Run `flutter analyze` — 0 new errors.

**Step 2:** Run `flutter test` — all tests pass.

---

## Feature 3: Enhanced Export & Reporting

### Task 13: Add per-participant spending breakdown to PDF

**Files:**
- Modify: `lib/features/trip/services/trip_export_service.dart`

**Step 1:** Read the current `exportAndSharePDF` method in `trip_export_service.dart`.

**Step 2:** After the participants table, add a new section "Spending by Category":
- Group expenses by categoryName
- For each category: show total amount, percentage of total, and per-participant breakdown
- Use a simple bar representation or table format

**Step 3:** Add a "Spending by Member" section:
- For each participant: list their expenses with category and amount
- Show subtotal per person

**Step 4:** Run `flutter analyze`.

---

### Task 14: Add date range filter to export

**Files:**
- Modify: `lib/features/trip/services/trip_export_service.dart`
- Modify: `lib/features/home/screens/command_center.dart`

**Step 1:** Add optional `startDate` and `endDate` parameters to both `exportAndSharePDF` and `exportAndShareCSV`.

**Step 2:** When dates are provided, filter expenses to only include those within the range. Add a "Report Period" line in the PDF header.

**Step 3:** In `command_center.dart`, before calling export, show a date range picker dialog:
```dart
Future<DateTimeRange?> _pickExportDateRange() async {
  return showDateRangePicker(
    context: context,
    firstDate: trip.startDate ?? DateTime(2020),
    lastDate: trip.endDate ?? DateTime.now(),
    initialDateRange: DateTimeRange(
      start: trip.startDate ?? DateTime.now().subtract(Duration(days: 30)),
      end: trip.endDate ?? DateTime.now(),
    ),
  );
}
```

**Step 4:** Run `flutter analyze` and `flutter test`.

---

### Task 15: Export verification

**Step 1:** Run `flutter analyze` — 0 new errors.

**Step 2:** Run `flutter test` — all pass.

---

## Feature 4: Push Notifications

### Task 16: Add Firebase dependencies and configure

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/build.gradle.kts`
- Create/Modify: `android/app/google-services.json` (from Firebase Console)
- Modify: `ios/Runner/Info.plist`

**Step 1:** The user must create a Firebase project and download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) from the Firebase Console. Place them in the correct directories.

**Step 2:** Add to pubspec.yaml:
```yaml
firebase_core: ^3.12.1
firebase_messaging: ^15.2.4
```

**Step 3:** Add Firebase plugin to `android/app/build.gradle.kts`:
```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")  // Add this
}
```

**Step 4:** Add to `android/build.gradle.kts` (project-level) dependencies:
```kotlin
buildscript {
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
    }
}
```

**Step 5:** Run `flutter pub get` — verify no dependency conflicts.

---

### Task 17: Create notification service

**Files:**
- Create: `lib/core/services/notification_service.dart`

**Step 1:** Create the notification service:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Initialize FCM and request permissions
  static Future<void> initialize() async {
    // Request permission (iOS)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // Get FCM token and store it
      final token = await _messaging.getToken();
      if (token != null) {
        await _storeFcmToken(token);
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen(_storeFcmToken);
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background/terminated messages
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
  }

  /// Store FCM token in Supabase for the current user
  static Future<void> _storeFcmToken(String token) async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    await SupabaseConfig.client.from('user_fcm_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': _getPlatform(),
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id, token');
  }

  static String _getPlatform() {
    // Simplified — use Platform.isIOS / Platform.isAndroid
    return 'android'; // Replace with actual detection
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    // Show in-app notification banner
    // Will be handled by the UI layer
  }

  static void _handleMessageTap(RemoteMessage message) {
    // Navigate to relevant screen based on message data
    // e.g., message.data['trip_id'] → navigate to trip
  }

  /// Remove FCM token on logout
  static Future<void> removeToken() async {
    final token = await _messaging.getToken();
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (token != null && userId != null) {
      await SupabaseConfig.client
          .from('user_fcm_tokens')
          .delete()
          .eq('user_id', userId)
          .eq('token', token);
    }
  }
}
```

**Step 2:** Run `flutter analyze`.

---

### Task 18: Create Supabase migration for FCM tokens

**Files:**
- Create: `supabase/migrations/20260304000002_add_fcm_tokens.sql`

**Step 1:** Create migration:

```sql
-- FCM token storage for push notifications
CREATE TABLE IF NOT EXISTS user_fcm_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token text NOT NULL,
    platform text NOT NULL DEFAULT 'android',
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(user_id, token)
);

-- Index for looking up tokens by user
CREATE INDEX idx_fcm_tokens_user_id ON user_fcm_tokens(user_id);

-- RLS
ALTER TABLE user_fcm_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own tokens"
    ON user_fcm_tokens
    FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
```

---

### Task 19: Initialize Firebase in main.dart and wire to auth

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/features/auth/providers/auth_provider.dart`

**Step 1:** In `main.dart`, add Firebase initialization after Supabase init:
```dart
await Firebase.initializeApp();
await NotificationService.initialize();
```

**Step 2:** In the auth provider, on logout, call `NotificationService.removeToken()`.

**Step 3:** In the auth provider, on login success, call `NotificationService.initialize()` to register the token.

**Step 4:** Run `flutter analyze` and `flutter test`.

---

### Task 20: Create Supabase Edge Function for sending notifications

**Files:**
- Create: `supabase/functions/send-notification/index.ts`

**Step 1:** Create the Edge Function that listens to database changes and sends FCM notifications:

```typescript
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'

serve(async (req) => {
  const { record, type, table } = await req.json()

  // Determine notification based on event
  let title = ''
  let body = ''
  let tripId = ''
  let targetUserIds: string[] = []

  if (table === 'expenses' && type === 'INSERT') {
    title = 'New Expense Added'
    body = `${record.description} - ${record.amount}`
    tripId = record.trip_id
    // Get all trip participants except the payer
    // ... query participants table
  }

  if (table === 'settlements' && type === 'INSERT') {
    title = 'Settlement Recorded'
    body = `A payment of ${record.amount} was recorded`
    tripId = record.trip_id
  }

  // Get FCM tokens for target users
  // Send via Firebase Admin SDK
  // Return response
})
```

**Note:** This task requires Firebase Admin SDK setup and Supabase webhook configuration. The user will need to:
1. Set up Firebase Admin credentials as Supabase secrets
2. Create database webhooks pointing to this Edge Function
3. Test end-to-end

**Step 2:** Document the setup steps in a README section.

---

### Task 21: Wire notification toggle in settings

**Files:**
- Modify: `lib/features/settings/screens/settings_screen.dart`

**Step 1:** The settings screen already has a notification toggle. Wire it to actually enable/disable notifications:
- On enable: call `NotificationService.initialize()`
- On disable: call `NotificationService.removeToken()`
- Persist the preference via `SharedPreferences`

**Step 2:** Run `flutter analyze`.

---

### Task 22: Final verification

**Step 1:** Run `flutter analyze` — 0 new errors beyond pre-existing.

**Step 2:** Run `flutter test` — all tests pass.

**Step 3:** Run `flutter build appbundle --dart-define-from-file=config.json` — builds successfully.

**Step 4:** Verify on simulator: create a trip with non-OMR currency, add expense with receipt, export PDF, check notifications toggle.

# Name-Based Trip Members Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make trip members name-based (Splid-style) — creator adds names, picks theirs, joiners pick an unclaimed name. Add device name setting. Replace `profiles` table joins with participant `display_name`.

**Architecture:** Trip creation inserts unclaimed participants (user_id=null, display_name set). Creator and joiners claim a participant by writing their anonymous auth.uid() to user_id. All Supabase queries that join `profiles` for display names switch to reading `participants.display_name` directly.

**Tech Stack:** Flutter, Riverpod 2.x, Supabase, SharedPreferences, GoRouter

---

### Task 1: Add Device Name to Settings

**Files:**
- Modify: `lib/core/models/app_settings_model.dart`
- Modify: `lib/core/services/settings_service.dart`
- Modify: `lib/core/providers/settings_provider.dart`
- Modify: `lib/features/settings/screens/settings_screen.dart`

**Step 1: Add `deviceName` field to AppSettings**

In `lib/core/models/app_settings_model.dart`, add `deviceName` field:

```dart
class AppSettings {
  final AppThemeMode themeMode;
  final String languageCode;
  final String currencyCode;
  final bool pushNotificationsEnabled;
  final String deviceName;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.languageCode = 'en',
    this.currencyCode = 'OMR',
    this.pushNotificationsEnabled = false,
    this.deviceName = '',
  });
```

Update `copyWith` to include `deviceName`:

```dart
AppSettings copyWith({
  AppThemeMode? themeMode,
  String? languageCode,
  String? currencyCode,
  bool? pushNotificationsEnabled,
  String? deviceName,
}) {
  return AppSettings(
    themeMode: themeMode ?? this.themeMode,
    languageCode: languageCode ?? this.languageCode,
    currencyCode: currencyCode ?? this.currencyCode,
    pushNotificationsEnabled: pushNotificationsEnabled ?? this.pushNotificationsEnabled,
    deviceName: deviceName ?? this.deviceName,
  );
}
```

**Step 2: Add persistence to SettingsService**

In `lib/core/services/settings_service.dart`, add key and methods:

```dart
static const String _deviceNameKey = 'settings_device_name';
```

In `loadSettings()`, add:
```dart
final deviceName = _prefs.getString(_deviceNameKey) ?? '';
```
And pass `deviceName: deviceName` to the AppSettings constructor.

Add save method:
```dart
Future<void> saveDeviceName(String name) async {
  await _prefs.setString(_deviceNameKey, name);
}
```

**Step 3: Add setter to SettingsNotifier**

In `lib/core/providers/settings_provider.dart`, add:

```dart
Future<void> setDeviceName(String name) async {
  await _service.saveDeviceName(name);
  state = state.copyWith(deviceName: name);
}
```

**Step 4: Add device name field to Settings screen**

In `lib/features/settings/screens/settings_screen.dart`, add a "Your Name" item to the preferences section that opens an edit dialog. Use the same pattern as the existing currency/language/theme dialogs.

Add to `_buildPreferencesSection` before the Currency item:

```dart
_buildSettingsItem(
  icon: Iconsax.user,
  title: 'Your Name',
  subtitle: settings.deviceName.isEmpty ? 'Not set' : settings.deviceName,
  onTap: () => _showDeviceNameDialog(),
),
```

Add `_showDeviceNameDialog` method:

```dart
void _showDeviceNameDialog() {
  final controller = TextEditingController(
    text: ref.read(settingsProvider).deviceName,
  );
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Your Name'),
      content: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          hintText: 'e.g. Ahmed',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            ref.read(settingsProvider.notifier).setDeviceName(
              controller.text.trim(),
            );
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
```

**Step 5: Update home screen to use device name**

In `lib/features/home/screens/home_screen.dart`, import settings_provider and read device name for the header greeting instead of hardcoded 'Traveler':

```dart
final deviceName = ref.watch(settingsProvider).deviceName;
final displayName = deviceName.isEmpty ? 'Traveler' : deviceName;
```

**Step 6: Verify it compiles**

Run: `flutter analyze`

**Step 7: Commit**

```bash
git add lib/core/models/app_settings_model.dart lib/core/services/settings_service.dart lib/core/providers/settings_provider.dart lib/features/settings/screens/settings_screen.dart lib/features/home/screens/home_screen.dart
git commit -m "feat: add device name setting with home screen greeting"
```

---

### Task 2: Update Create Trip — Add Member Names

**Files:**
- Modify: `lib/features/trip/screens/create_trip_screen.dart`
- Modify: `lib/features/trip/providers/trip_provider.dart` (TripService.createTrip)

**Step 1: Add member name input to CreateTripScreen**

In `lib/features/trip/screens/create_trip_screen.dart`:

Add state fields:
```dart
final List<String> _memberNames = [];
final _memberController = TextEditingController();
int? _creatorIndex;
```

Add a "Members" section after the modules section. It should have:
- A text field + add button to add member names to `_memberNames`
- A list of added names, each with a delete button and a radio button to select "This is me"
- Pre-populate with device name from settings if set
- Validation: at least one member, creator must select their name

**Step 2: Update TripService.createTrip to accept member names**

In `lib/features/trip/providers/trip_provider.dart`, change `createTrip` signature to:

```dart
Future<Trip?> createTrip({
  required String name,
  required List<String> memberNames,
  required int creatorIndex,
  TripModules modules = const TripModules(),
  DateTime? startDate,
  DateTime? endDate,
}) async {
```

After creating the trip, instead of inserting a single participant, insert all members:

```dart
// Insert all members as participants
for (int i = 0; i < memberNames.length; i++) {
  final isCreator = i == creatorIndex;
  await _client.from('participants').insert({
    'trip_id': trip.id,
    'user_id': isCreator ? userId : null,
    'role': isCreator ? 'LEADER' : 'MEMBER',
    'display_name': memberNames[i],
  });
}
```

**Step 3: Update CreateTripScreen._createTrip() call**

Pass `memberNames` and `creatorIndex` to `tripService.createTrip()`.

**Step 4: Verify it compiles**

Run: `flutter analyze`

**Step 5: Commit**

```bash
git add lib/features/trip/screens/create_trip_screen.dart lib/features/trip/providers/trip_provider.dart
git commit -m "feat: name-based trip creation with member names and creator selection"
```

---

### Task 3: Update Join Trip — Pick Unclaimed Name

**Files:**
- Modify: `lib/features/trip/screens/join_trip_screen.dart`
- Modify: `lib/features/trip/providers/trip_provider.dart` (TripService.joinTrip)

**Step 1: Split joinTrip into two steps**

In `lib/features/trip/providers/trip_provider.dart`, add a method to find unclaimed participants:

```dart
/// Find trip and return unclaimed participant names
Future<({Trip trip, List<Participant> unclaimed})?> findTripForJoin(String inviteCode) async {
  _ref.read(tripLoadingProvider.notifier).state = true;
  _ref.read(tripErrorProvider.notifier).state = null;

  try {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    final tripData = await _client
        .from('trips')
        .select()
        .eq('invite_code', inviteCode.toUpperCase())
        .maybeSingle();

    if (tripData == null) {
      throw Exception('Trip not found. Please check the invite code.');
    }

    final trip = Trip.fromJson(tripData);

    // Check if already a participant
    final existing = await _client
        .from('participants')
        .select('id')
        .eq('trip_id', trip.id)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      _ref.read(tripLoadingProvider.notifier).state = false;
      _ref.read(currentTripProvider.notifier).state = trip;
      return null; // Already a member — caller should navigate directly
    }

    // Get unclaimed participants
    final participantsData = await _client
        .from('participants')
        .select()
        .eq('trip_id', trip.id)
        .isFilter('user_id', null);

    final unclaimed = participantsData
        .map((json) => Participant.fromJson(json))
        .toList();

    _ref.read(tripLoadingProvider.notifier).state = false;
    return (trip: trip, unclaimed: unclaimed);
  } catch (e) {
    _ref.read(tripErrorProvider.notifier).state = e.toString();
    _ref.read(tripLoadingProvider.notifier).state = false;
    return null;
  }
}

/// Claim a participant name in a trip
Future<Trip?> claimParticipant(String tripId, String participantId) async {
  _ref.read(tripLoadingProvider.notifier).state = true;
  _ref.read(tripErrorProvider.notifier).state = null;

  try {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    await _client
        .from('participants')
        .update({'user_id': userId})
        .eq('id', participantId);

    final trip = await getTripById(tripId);
    _ref.read(tripLoadingProvider.notifier).state = false;
    _ref.read(currentTripProvider.notifier).state = trip;
    return trip;
  } catch (e) {
    _ref.read(tripErrorProvider.notifier).state = e.toString();
    _ref.read(tripLoadingProvider.notifier).state = false;
    return null;
  }
}
```

**Step 2: Redesign JoinTripScreen for two-step flow**

In `lib/features/trip/screens/join_trip_screen.dart`:

After entering the invite code and finding the trip, show a second view with the trip name and a list of unclaimed names as selectable cards. User taps their name → `claimParticipant()` is called → navigate to home.

Add state:
```dart
Trip? _foundTrip;
List<Participant>? _unclaimedNames;
```

Flow:
1. Enter code → tap "Find Trip" → calls `findTripForJoin()`
2. If unclaimed names returned, show name picker view
3. If null returned (already member), navigate to home
4. If no unclaimed names, show "All names have been claimed" message
5. User picks a name → calls `claimParticipant()` → navigate to home

**Step 3: Keep the old joinTrip method for backward compatibility but mark deprecated**

The old `joinTrip` method that auto-adds can stay but won't be called from the UI anymore.

**Step 4: Verify it compiles**

Run: `flutter analyze`

**Step 5: Commit**

```bash
git add lib/features/trip/screens/join_trip_screen.dart lib/features/trip/providers/trip_provider.dart
git commit -m "feat: join trip flow — pick unclaimed name instead of auto-add"
```

---

### Task 4: Replace Profiles Joins with Participant Display Names

**Files:**
- Modify: `lib/features/trip/providers/trip_provider.dart` (2 queries)
- Modify: `lib/features/ledger/providers/expense_provider.dart` (2 queries)
- Modify: `lib/features/ledger/services/settlement_service.dart` (2 queries)
- Modify: `lib/features/vault/providers/document_provider.dart` (1 query)
- Modify: `lib/features/memories/services/memory_service.dart` (2 queries)
- Modify: `lib/features/gear/providers/gear_provider.dart` (1 query)
- Modify: `lib/features/activity/services/activity_service.dart` (3 queries)
- Modify: `lib/core/services/sync_service.dart` (1 query)
- Modify: `lib/features/logistics/providers/sub_group_provider.dart` (2 queries)
- Modify: `lib/features/trip/providers/shadow_provider.dart` (3 queries)

**Step 1: Update participant queries — remove `profiles!user_id` joins**

For queries that select `*, profiles!user_id(display_name, avatar_url)` from `participants`, change to just `*`. The `Participant.fromJson` already reads `display_name` directly from the participant row (line 238 of trip_model.dart: `json['display_name'] as String?`), falling back to the profiles join. With name-based members, `display_name` is always set on the participant.

Files to change (replace `'*, profiles!user_id(display_name, avatar_url)'` with `'*'`):
- `trip_provider.dart` lines 74, 338
- `shadow_provider.dart` lines 52, 116, 133
- `sub_group_provider.dart` lines 39, 213 (nested: `participants!participant_id(*, profiles!user_id(...))` → `participants!participant_id(*)`)

**Step 2: Update expense/settlement queries — nested profiles joins**

For queries that join through `participants` to `profiles`, simplify:
- `expense_provider.dart` line 35: change `participants!payer_participant_id(*, profiles!user_id(display_name, avatar_url))` → `participants!payer_participant_id(*)`
- `expense_provider.dart` line 71: same pattern for settlements
- `settlement_service.dart` lines 52, 91: same pattern

**Step 3: Update document/memory queries — `profiles!uploader_id` joins**

These join `profiles` directly (not through `participants`). For now, these need a different approach — the uploader is identified by `auth.uid()` which maps to a `participants.user_id` in the trip. We need to resolve the name by looking up the participant.

For `document_provider.dart` line 40: change `'*, profiles!uploader_id(display_name)'` → `'*'`. The document model will need to resolve uploader name from participants separately, or we can accept that uploader name won't display for now (minor — documents show filename, not uploader).

For `memory_service.dart` lines 19, 88: same approach — remove profiles join, accept that uploader name resolution needs a participant lookup.

**Step 4: Update activity service — `profiles!actor_id` and `.from('profiles')` queries**

`activity_service.dart` has three patterns:
- Line 111: `'*, actor:profiles!actor_id(display_name, avatar_url)'` — change to `'*'` and resolve actor name from participants
- Lines 37, 82: `.from('profiles').select().inFilter('id', actorIds)` — change to look up participants by user_id instead

For lines 37 and 82, change from:
```dart
.from('profiles')
.select('id, display_name, avatar_url')
.inFilter('id', actorIds)
```
to:
```dart
.from('participants')
.select('user_id, display_name')
.eq('trip_id', tripId)
.inFilter('user_id', actorIds)
```

**Step 5: Update sync_service.dart**

Line 117: `'*, payer_profile:profiles!payer_id(display_name), recipient_profile:profiles!recipient_id(display_name)'` — this uses `payer_id`/`recipient_id` which reference `auth.users` directly. Change to join through participants instead, or simplify to `'*'` and resolve names client-side from the participants list.

**Step 6: Verify it compiles**

Run: `flutter analyze`

**Step 7: Run tests**

Run: `flutter test`

**Step 8: Commit**

```bash
git add -A
git commit -m "refactor: replace profiles table joins with participant display_name lookups"
```

---

### Task 5: Update Home Screen Greeting with Device Name

**Files:**
- Already done in Task 1, Step 5

This task is handled as part of Task 1. No additional work needed.

---

### Task 6: Final Verification & Docs

**Step 1: Run full analysis**

Run: `flutter analyze`
Expected: 0 errors

**Step 2: Run all tests**

Run: `flutter test`
Expected: All tests pass

**Step 3: Update CLAUDE.md**

Update the Key Technical Details section:
- Remove shadow profiles reference (all members are name-based now)
- Add note about name-based members and device name setting
- Update routing to note join-trip has two-step flow

**Step 4: Commit**

```bash
git add -A
git commit -m "docs: update CLAUDE.md for name-based members"
```

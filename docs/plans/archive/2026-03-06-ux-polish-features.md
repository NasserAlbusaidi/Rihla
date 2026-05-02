# UX Polish Features Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add five delightful UX polish features — pull-to-refresh, empty state actions, haptic code input, skeleton loading, and animated numbers — to make Rihla feel premium.

**Architecture:** All changes are additive modifications to existing screens. No new services or providers needed. Skeleton loading requires a new shared widget and the `shimmer` package. Animated numbers use Flutter's built-in `TweenAnimationBuilder`. Each task is independent and can be verified in isolation.

**Tech Stack:** Flutter, Riverpod 2.x, flutter_animate, shimmer (new dependency), HapticService (existing)

---

### Task 1: Pull-to-Refresh on Gear Screen

**Files:**
- Modify: `lib/features/gear/screens/gear_screen.dart:135-166`

**Context:** The gear screen uses `tripGearProvider(widget.trip.id)` (a StreamProvider). When data loads, it calls `_buildContent(items, currentUserId)` which returns a Column with a progress card and a ListView. We need to wrap the ListView in a RefreshIndicator. The empty state doesn't need pull-to-refresh (nothing to refresh).

**Step 1: Wrap the ListView in RefreshIndicator**

In `_buildContent`, change the `ListView.builder` to be wrapped in a `RefreshIndicator`:

```dart
// In _buildContent method, replace lines 149-166:
return Column(
  children: [
    _buildProgressCard(stats),
    Expanded(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(tripGearProvider(widget.trip.id));
        },
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          itemCount: filteredItems.length + 1, // +1 for AddItemInput
          itemBuilder: (context, index) {
            if (index == 0) return _buildAddItemInput();
            return _buildGearItemCard(
              filteredItems[index - 1],
              currentUserId,
            );
          },
        ),
      ),
    ),
  ],
);
```

**Step 2: Run tests**

Run: `flutter test`
Expected: All 16 tests pass (no gear screen widget tests exist, so this is a regression check)

**Step 3: Commit**

```bash
git add lib/features/gear/screens/gear_screen.dart
git commit -m "feat: add pull-to-refresh on gear screen"
```

---

### Task 2: Pull-to-Refresh on Logistics Screen

**Files:**
- Modify: `lib/features/logistics/screens/logistics_screen.dart:237-251`

**Context:** Logistics uses `tripSubGroupsProvider(widget.trip.id)`. The `_buildGroupList` method returns a Column with an unassigned pool and a ListView. We need to wrap the ListView in a RefreshIndicator. Note: logistics is a `ConsumerStatefulWidget` so we use `ref.invalidate(...)` directly.

**Step 1: Wrap the ListView in RefreshIndicator**

In `_buildGroupList`, wrap the ListView:

```dart
// Replace _buildGroupList method body (when groups is not empty):
return Column(
  children: [
    _buildUnassignedPool(groups, type),
    Expanded(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(tripSubGroupsProvider(widget.trip.id));
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: groups.length,
          itemBuilder: (context, index) => _buildGroupCard(groups[index]),
        ),
      ),
    ),
  ],
);
```

**Step 2: Run tests**

Run: `flutter test`
Expected: All 16 tests pass

**Step 3: Commit**

```bash
git add lib/features/logistics/screens/logistics_screen.dart
git commit -m "feat: add pull-to-refresh on logistics screen"
```

---

### Task 3: Empty State Action Button on Vault Screen

**Files:**
- Modify: `lib/features/vault/screens/vault_screen.dart:151-222`

**Context:** The vault empty state (`_buildEmptyState`) already has a beautiful gradient icon and copy. We need to add a button that triggers the same `_uploadDocument` action as the FAB. The method signature is `_buildEmptyState(BuildContext context, WidgetRef ref)` — both context and ref are available.

**Step 1: Add upload button to empty state**

After the description text (line ~218), add:

```dart
const SizedBox(height: 28),
SizedBox(
  height: 48,
  child: ElevatedButton.icon(
    onPressed: () => _uploadDocument(context, ref),
    icon: const Icon(Iconsax.document_upload, size: 18),
    label: const Text('Upload Document'),
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
    ),
  ),
).animate().fadeIn(delay: 200.ms),
```

Note: This requires the `flutter_animate` import which is already present at line 2.

**Step 2: Run tests**

Run: `flutter test`
Expected: All 16 tests pass

**Step 3: Commit**

```bash
git add lib/features/vault/screens/vault_screen.dart
git commit -m "feat: add upload button to vault empty state"
```

---

### Task 4: Empty State Action Button on Gear Screen

**Files:**
- Modify: `lib/features/gear/screens/gear_screen.dart:169-213`

**Context:** The gear empty state already includes the `_buildAddItemInput()` widget at the bottom (line 208). This is already an action! But it's squeezed at the bottom of an empty state. Let's improve it by adding a more prominent CTA label above it.

**Step 1: Add a CTA label above the add-item input**

Replace the empty state section between the description text and the add-item input:

```dart
const SizedBox(height: 12),
Text(
  'ADD YOUR FIRST ITEM',
  style: TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w900,
    color: AppColors.textSecondary,
    letterSpacing: 1.2,
  ),
).animate().fadeIn(delay: 350.ms),
const SizedBox(height: 16),

// Add item input
_buildAddItemInput().animate().fadeIn(delay: 400.ms),
```

This replaces the existing `const SizedBox(height: 32)` and `_buildAddItemInput()` at lines 205-208.

**Step 2: Run tests**

Run: `flutter test`
Expected: All 16 tests pass

**Step 3: Commit**

```bash
git add lib/features/gear/screens/gear_screen.dart
git commit -m "feat: add CTA label to gear empty state"
```

---

### Task 5: Haptic Feedback on Join Trip Code Input

**Files:**
- Modify: `lib/features/trip/screens/join_trip_screen.dart:213-253`

**Context:** The join trip screen has a 6-character code input field using `TextFormField` with a `maxLength: 6`. We need to:
1. Add a listener to `_codeController` that fires `HapticService.lightClick()` on each character typed
2. Fire `HapticService.success()` when the 6th character is entered

The screen already imports `flutter/services.dart` (line 2). We need to add the `HapticService` import and set up a listener in `initState`.

**Step 1: Add haptic import and listener**

Add import at top of file (after line 8):
```dart
import '../../../core/services/haptic_service.dart';
```

The class is already a `ConsumerStatefulWidget` with `dispose` for `_codeController`. Add `initState`:

```dart
@override
void initState() {
  super.initState();
  _codeController.addListener(_onCodeChanged);
}

void _onCodeChanged() {
  final text = _codeController.text;
  if (text.isNotEmpty) {
    if (text.length == 6) {
      HapticService.success();
    } else {
      HapticService.lightClick();
    }
  }
}
```

Update `dispose` to remove listener:
```dart
@override
void dispose() {
  _codeController.removeListener(_onCodeChanged);
  _codeController.dispose();
  super.dispose();
}
```

**Step 2: Run tests**

Run: `flutter test`
Expected: All 16 tests pass

**Step 3: Commit**

```bash
git add lib/features/trip/screens/join_trip_screen.dart
git commit -m "feat: add haptic feedback to join trip code input"
```

---

### Task 6: Create Skeleton Loading Widget

**Files:**
- Create: `lib/shared/widgets/skeleton_loader.dart`

**Context:** We need a reusable shimmer-based skeleton loader that can mimic different content layouts. The `shimmer` package provides a shimmer effect. We'll create a composable widget with static factory methods for common patterns (card list, document list, etc.).

**Step 1: Add shimmer dependency**

Run: `flutter pub add shimmer`

**Step 2: Create the skeleton loader widget**

Create `lib/shared/widgets/skeleton_loader.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/app_theme.dart';

/// Reusable skeleton loading placeholders
class SkeletonLoader extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const SkeletonLoader({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  /// Skeleton for gear/expense list items
  factory SkeletonLoader.cardList({int count = 5}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        child: _SkeletonCard(height: 72),
      ),
    );
  }

  /// Skeleton for document list items
  factory SkeletonLoader.documentList({int count = 4}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: _SkeletonCard(height: 80),
      ),
    );
  }

  /// Skeleton for logistics groups
  factory SkeletonLoader.groupList({int count = 3}) {
    return SkeletonLoader(
      itemCount: count,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: _SkeletonCard(height: 120),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surfaceLight,
      highlightColor: AppColors.surface,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 12),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double height;

  const _SkeletonCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}
```

**Step 3: Run tests**

Run: `flutter test`
Expected: All 16 tests pass (new widget, no tests broken)

**Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/shared/widgets/skeleton_loader.dart
git commit -m "feat: add shimmer skeleton loader widget"
```

---

### Task 7: Replace CircularProgressIndicator with Skeleton Loaders

**Files:**
- Modify: `lib/features/gear/screens/gear_screen.dart:50`
- Modify: `lib/features/vault/screens/vault_screen.dart:35`
- Modify: `lib/features/logistics/screens/logistics_screen.dart:58`

**Context:** Each of these files has a `loading: () => const Center(child: CircularProgressIndicator())` line in their `.when()` call. Replace each with the appropriate skeleton loader.

**Step 1: Add import and replace loading state in gear_screen.dart**

Add import:
```dart
import '../../../shared/widgets/skeleton_loader.dart';
```

Replace line 50:
```dart
// Old:
loading: () => const Center(child: CircularProgressIndicator()),
// New:
loading: () => SkeletonLoader.cardList(),
```

**Step 2: Add import and replace loading state in vault_screen.dart**

Add import:
```dart
import '../../../shared/widgets/skeleton_loader.dart';
```

Replace line 35:
```dart
// Old:
loading: () => const Center(child: CircularProgressIndicator()),
// New:
loading: () => SkeletonLoader.documentList(),
```

**Step 3: Add import and replace loading state in logistics_screen.dart**

Add import:
```dart
import '../../../shared/widgets/skeleton_loader.dart';
```

Replace line 58:
```dart
// Old:
loading: () => const Center(child: CircularProgressIndicator()),
// New:
loading: () => SkeletonLoader.groupList(),
```

**Step 4: Run tests**

Run: `flutter test`
Expected: All 16 tests pass

**Step 5: Commit**

```bash
git add lib/features/gear/screens/gear_screen.dart lib/features/vault/screens/vault_screen.dart lib/features/logistics/screens/logistics_screen.dart
git commit -m "feat: replace spinners with skeleton loaders on gear, vault, logistics"
```

---

### Task 8: Animated Number Transitions on CommandCenter

**Files:**
- Modify: `lib/features/home/screens/command_center.dart:697-705`

**Context:** The expense summary hero card in CommandCenter displays `totalExpenses` as a formatted currency string at line 698. We'll wrap this in a `TweenAnimationBuilder<double>` that animates from 0 to the total, formatting at each frame. The balance text (net owed/owing) at line 710 should also animate.

**Important:** `Decimal` can't be directly tweened, so we convert to `double` for the animation and format with the `Decimal` constructor at each frame. For display purposes this is fine — the authoritative value remains `Decimal`.

**Step 1: Replace static total with animated total**

Replace the total expenses `Text` widget (around line 697-705):

```dart
TweenAnimationBuilder<double>(
  tween: Tween<double>(begin: 0, end: totalExpenses.toDouble()),
  duration: const Duration(milliseconds: 800),
  curve: Curves.easeOutCubic,
  builder: (context, value, child) {
    return Text(
      AppFormatters.formatCurrency(
        Decimal.parse(value.toStringAsFixed(3)),
        trip.currency,
      ),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 28,
        fontWeight: FontWeight.w900,
        letterSpacing: -1,
      ),
    );
  },
),
```

**Step 2: Replace static balance with animated balance**

Replace the net balance `Text` widget (around line 708-723). The `isOwed` boolean and prefix are already computed. Wrap just the Text:

```dart
if (net != Decimal.zero)
  TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: net.abs().toDouble()),
    duration: const Duration(milliseconds: 800),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) {
      final formatted = AppFormatters.formatCurrency(
        Decimal.parse(value.toStringAsFixed(3)),
        trip.currency,
      );
      return Text(
        isOwed
            ? 'Settlements pending: +$formatted'
            : 'Pending payment: -$formatted',
        style: TextStyle(
          color: isOwed
              ? AppColors.mint.withValues(alpha: 0.8)
              : AppColors.rose.withValues(alpha: 0.8),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      );
    },
  ),
```

**Step 3: Run tests**

Run: `flutter test`
Expected: All 16 tests pass

**Step 4: Commit**

```bash
git add lib/features/home/screens/command_center.dart
git commit -m "feat: add animated number transitions on spending card"
```

---

## Summary

| Task | Feature | Files Modified | Risk |
|------|---------|---------------|------|
| 1 | Pull-to-refresh: Gear | gear_screen.dart | Low |
| 2 | Pull-to-refresh: Logistics | logistics_screen.dart | Low |
| 3 | Empty state action: Vault | vault_screen.dart | Low |
| 4 | Empty state CTA: Gear | gear_screen.dart | Low |
| 5 | Haptic code input | join_trip_screen.dart | Low |
| 6 | Skeleton loader widget | NEW: skeleton_loader.dart | Low |
| 7 | Replace spinners | gear, vault, logistics | Low |
| 8 | Animated numbers | command_center.dart | Medium |

**Total estimated tasks:** 8 tasks, ~25 steps

**Dependencies:** Task 7 depends on Task 6 (skeleton widget must exist before it's used). All other tasks are independent and can be parallelized.

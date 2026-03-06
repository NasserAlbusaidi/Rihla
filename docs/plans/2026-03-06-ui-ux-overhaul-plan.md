# UI/UX Thorough Overhaul — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refine every screen in Rihla to higher craft with consistent design system, missing UX patterns, and polished interactions.

**Architecture:** Three-layer approach — Foundation (theme + shared components), Screens (apply to all 11 screens in user-journey order), Interactions (animations, haptics, accessibility). Each layer builds on the previous.

**Tech Stack:** Flutter 3.41, Riverpod 2.x, flutter_animate, iconsax, shimmer, google_fonts

---

## Layer 1: Foundation

### Task 1: Theme Constants & Refinements

**Files:**
- Modify: `lib/core/theme/app_theme.dart`

**Step 1: Add spacing and radius constants to AppColors**

Add these constants to the `AppColors` class:

```dart
// Spacing scale
static const double space4 = 4;
static const double space8 = 8;
static const double space12 = 12;
static const double space16 = 16;
static const double space20 = 20;
static const double space24 = 24;
static const double space32 = 32;

// Border radius scale
static const double radiusSmall = 12;
static const double radiusMedium = 16;
static const double radiusLarge = 20;

// Elevation levels
static List<BoxShadow> get shadowFlat => [];

static List<BoxShadow> get shadowRaised => [
  BoxShadow(
    color: const Color(0xFF0F172A).withValues(alpha: 0.03),
    blurRadius: 10,
    offset: const Offset(0, 4),
  ),
  BoxShadow(
    color: const Color(0xFF0F172A).withValues(alpha: 0.02),
    blurRadius: 4,
    offset: const Offset(0, 2),
  ),
];

static List<BoxShadow> get shadowFloating => [
  BoxShadow(
    color: const Color(0xFF0F172A).withValues(alpha: 0.06),
    blurRadius: 24,
    offset: const Offset(0, 8),
  ),
  BoxShadow(
    color: const Color(0xFF0F172A).withValues(alpha: 0.03),
    blurRadius: 10,
    offset: const Offset(0, 4),
  ),
];

// Muted mint for surfaces (not CTAs)
static const Color mintSurface = Color(0xFFECFDF5); // Emerald 50
static const Color mintSurfaceDark = Color(0xFF064E3B); // Emerald 900

// Standard button height
static const double buttonHeight = 52;

// Dark header gradient (reusable)
static const LinearGradient darkHeaderGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
);
```

**Step 2: Update existing theme references**

- Change `cardShadow` to delegate to `shadowRaised`
- Change `cardShadowLarge` to delegate to `shadowFloating`
- Update `cardTheme` borderRadius to use `radiusLarge`
- Update button padding vertical to achieve `buttonHeight` (52px)
- Update `inputDecorationTheme` borderRadius from 20 to `radiusLarge`
- Update `chipTheme` borderRadius from 12 to `radiusSmall`
- Update `snackBarTheme` borderRadius from 16 to `radiusMedium`
- Update `dialogTheme` borderRadius from 24 to `radiusLarge` + 4
- Update `bottomSheetTheme` borderRadius from 32 to 28

**Step 3: Run tests to verify nothing breaks**

Run: `flutter test`
Expected: All 16 tests pass

**Step 4: Commit**

```bash
git add lib/core/theme/app_theme.dart
git commit -m "refactor: add spacing/radius/elevation constants to theme"
```

---

### Task 2: ModuleHeader Shared Widget

**Files:**
- Create: `lib/shared/widgets/module_header.dart`

**Step 1: Create ModuleHeader widget**

This replaces the dark gradient header pattern duplicated in Gear, Vault, Logistics, Activity, and Ledger screens. Current pattern (from gear_screen.dart:62-110, vault_screen.dart:62-80, etc.) uses:
- Container with `LinearGradient([0xFF0F172A, 0xFF1E293B])`
- SafeArea(bottom: false)
- Padding fromLTRB(24, 12, 24, 32)
- Back button in white/5% alpha container with 14px radius
- Title text (trip name small, screen title large)
- Optional action buttons on the right

```dart
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/theme/app_theme.dart';

class ModuleHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? bottom;

  const ModuleHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.darkHeaderGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppColors.space24, AppColors.space12, AppColors.space24, AppColors.space32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _BackButton(onTap: () => Navigator.of(context).pop()),
                  if (actions != null) Row(children: actions!),
                ],
              ),
              const SizedBox(height: AppColors.space20),
              if (subtitle != null) ...[
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.5),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: AppColors.space4),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              if (bottom != null) ...[
                const SizedBox(height: AppColors.space16),
                bottom!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppColors.radiusSmall + 2),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Icon(Iconsax.arrow_left, color: Colors.white, size: 20),
      ),
    );
  }
}
```

**Step 2: Run analyze**

Run: `flutter analyze`
Expected: No new errors

**Step 3: Commit**

```bash
git add lib/shared/widgets/module_header.dart
git commit -m "feat: add ModuleHeader shared widget for dark gradient headers"
```

---

### Task 3: AppTabBar Shared Widget

**Files:**
- Create: `lib/shared/widgets/app_tab_bar.dart`

**Step 1: Create AppTabBar widget**

Unifies the tab bar styling. Logistics has a custom gradient indicator; Ledger uses default Material. This creates one source of truth.

```dart
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/haptic_service.dart';

class AppTabBar extends StatelessWidget {
  final TabController controller;
  final List<String> tabs;
  final Color? activeColor;

  const AppTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? AppColors.primary;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppColors.space24,
        vertical: AppColors.space12,
      ),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppColors.radiusMedium),
      ),
      child: TabBar(
        controller: controller,
        onTap: (_) => HapticService.selection(),
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.85)],
          ),
          borderRadius: BorderRadius.circular(AppColors.radiusSmall),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        tabs: tabs.map((t) => Tab(text: t)).toList(),
      ),
    );
  }
}
```

**Step 2: Commit**

```bash
git add lib/shared/widgets/app_tab_bar.dart
git commit -m "feat: add AppTabBar shared widget with gradient pill indicator"
```

---

### Task 4: OfflineBanner Shared Widget

**Files:**
- Create: `lib/shared/widgets/offline_banner.dart`

**Step 1: Create OfflineBanner widget**

Reads `connectivityProvider` and shows a slim amber banner when offline, auto-hides when back online. Uses `AnimatedSize` for smooth show/hide.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/connectivity_provider.dart';

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectivityProvider);
    final isOffline = status == ConnectivityStatus.offline;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: isOffline
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppColors.space16,
                vertical: AppColors.space8,
              ),
              color: AppColors.warning.withValues(alpha: 0.12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off_rounded, size: 16, color: AppColors.warning),
                  const SizedBox(width: AppColors.space8),
                  Text(
                    'You\'re offline — changes will sync later',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
```

**Step 2: Commit**

```bash
git add lib/shared/widgets/offline_banner.dart
git commit -m "feat: add OfflineBanner widget for connectivity status"
```

---

### Task 5: EmptyStateView Shared Widget

**Files:**
- Create: `lib/shared/widgets/empty_state_view.dart`

**Step 1: Create EmptyStateView widget**

Replaces ad-hoc empty states across screens with a consistent component that always includes a CTA.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';

class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColors.textMuted;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppColors.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppColors.radiusLarge),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(height: AppColors.space20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppColors.space8),
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppColors.space24),
              SizedBox(
                height: AppColors.buttonHeight,
                child: ElevatedButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).scale(
      begin: const Offset(0.95, 0.95),
      end: const Offset(1, 1),
      duration: 400.ms,
    );
  }
}
```

**Step 2: Commit**

```bash
git add lib/shared/widgets/empty_state_view.dart
git commit -m "feat: add EmptyStateView shared widget with CTA support"
```

---

### Task 6: SearchFilterBar Shared Widget

**Files:**
- Create: `lib/shared/widgets/search_filter_bar.dart`

**Step 1: Create SearchFilterBar widget**

Expandable search input with optional filter chips. Used by Gear, Vault, Activity.

```dart
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/haptic_service.dart';

class SearchFilterBar extends StatefulWidget {
  final ValueChanged<String> onSearchChanged;
  final List<String>? filters;
  final String? activeFilter;
  final ValueChanged<String?>? onFilterChanged;
  final String hintText;

  const SearchFilterBar({
    super.key,
    required this.onSearchChanged,
    this.filters,
    this.activeFilter,
    this.onFilterChanged,
    this.hintText = 'Search...',
  });

  @override
  State<SearchFilterBar> createState() => _SearchFilterBarState();
}

class _SearchFilterBarState extends State<SearchFilterBar> {
  bool _isExpanded = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppColors.space24),
      child: Column(
        children: [
          // Search row
          Row(
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  height: _isExpanded ? 44 : 0,
                  child: _isExpanded
                      ? TextField(
                          controller: _controller,
                          onChanged: widget.onSearchChanged,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: widget.hintText,
                            prefixIcon: const Icon(Iconsax.search_normal, size: 18),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppColors.space16,
                              vertical: AppColors.space12,
                            ),
                            suffixIcon: _controller.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () {
                                      _controller.clear();
                                      widget.onSearchChanged('');
                                    },
                                  )
                                : null,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: AppColors.space8),
              GestureDetector(
                onTap: () {
                  HapticService.lightClick();
                  setState(() => _isExpanded = !_isExpanded);
                  if (!_isExpanded) {
                    _controller.clear();
                    widget.onSearchChanged('');
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _isExpanded ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                    border: Border.all(
                      color: _isExpanded ? AppColors.primary.withValues(alpha: 0.3) : AppColors.borderLight,
                    ),
                  ),
                  child: Icon(
                    _isExpanded ? Icons.close : Iconsax.search_normal,
                    size: 18,
                    color: _isExpanded ? AppColors.primary : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),

          // Filter chips
          if (widget.filters != null && widget.filters!.isNotEmpty) ...[
            const SizedBox(height: AppColors.space8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.filters!.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppColors.space8),
                itemBuilder: (context, index) {
                  final filter = widget.filters![index];
                  final isActive = filter == widget.activeFilter;
                  return ChoiceChip(
                    label: Text(filter),
                    selected: isActive,
                    onSelected: (_) {
                      HapticService.selection();
                      widget.onFilterChanged?.call(isActive ? null : filter);
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

**Step 2: Run analyze and test**

Run: `flutter analyze && flutter test`
Expected: No new errors, all 16 tests pass

**Step 3: Commit**

```bash
git add lib/shared/widgets/search_filter_bar.dart
git commit -m "feat: add SearchFilterBar shared widget with expandable search and chips"
```

---

## Layer 2: Screens

### Task 7: Fix Command Center Async Context Bugs

**Files:**
- Modify: `lib/features/home/screens/command_center.dart:1180,1242`

**Step 1: Fix the two `use_build_context_synchronously` warnings**

At line 1180, the code calls `ScaffoldMessenger.of(context)` after an async gap without checking `mounted`. The existing `if (context.mounted)` check at line 1220 shows the pattern is partially applied. Fix line 1180 by adding a mounted check before the initial snackbar too — OR restructure to capture ScaffoldMessenger before the await.

Best approach: capture the messenger before the async calls.

At the top of `_exportPDF`, before any await:
```dart
final messenger = ScaffoldMessenger.of(context);
```

Then replace all `ScaffoldMessenger.of(context)` calls in the method with `messenger`.

Do the same for any other method that has the same issue around line 1242.

**Step 2: Fix settle_up_screen unnecessary `!`**

In `settle_up_screen.dart:361`, remove the `!` from `ref!` since ref is already non-null in that context.

**Step 3: Run analyze**

Run: `flutter analyze`
Expected: Warnings for `use_build_context_synchronously` and `unnecessary_non_null_assertion` are gone

**Step 4: Commit**

```bash
git add lib/features/home/screens/command_center.dart lib/features/ledger/screens/settle_up_screen.dart
git commit -m "fix: async BuildContext safety and unnecessary null assertion"
```

---

### Task 8: Apply ModuleHeader to All Feature Screens

**Files:**
- Modify: `lib/features/gear/screens/gear_screen.dart`
- Modify: `lib/features/vault/screens/vault_screen.dart`
- Modify: `lib/features/logistics/screens/logistics_screen.dart`
- Modify: `lib/features/activity/screens/activity_feed_screen.dart`
- Modify: `lib/features/ledger/screens/ledger_screen.dart`

**Step 1: Replace each screen's `_buildHeader` method**

In each file:
1. Import `import '../../../shared/widgets/module_header.dart';`
2. Replace the `_buildHeader(context)` call with `ModuleHeader(...)` using the screen's title and trip name
3. Delete the `_buildHeader` method
4. Pass any screen-specific action buttons via the `actions` parameter
5. For screens with tab bars (Ledger, Logistics), pass `bottom: AppTabBar(...)` or keep tab bar separate below header

Example for Gear:
```dart
ModuleHeader(
  title: 'Gear',
  subtitle: widget.trip.name.toUpperCase(),
  actions: [/* filter toggle if any */],
),
```

**Step 2: Run tests**

Run: `flutter test`
Expected: All tests pass

**Step 3: Commit**

```bash
git add lib/features/gear/screens/gear_screen.dart lib/features/vault/screens/vault_screen.dart lib/features/logistics/screens/logistics_screen.dart lib/features/activity/screens/activity_feed_screen.dart lib/features/ledger/screens/ledger_screen.dart
git commit -m "refactor: replace duplicate dark headers with ModuleHeader widget"
```

---

### Task 9: Apply AppTabBar to Ledger and Logistics

**Files:**
- Modify: `lib/features/ledger/screens/ledger_screen.dart`
- Modify: `lib/features/logistics/screens/logistics_screen.dart`

**Step 1: Replace tab bars**

In both files:
1. Import `import '../../../shared/widgets/app_tab_bar.dart';`
2. Replace the existing `TabBar(...)` widget with `AppTabBar(controller: _tabController, tabs: _tabs)`
3. For Logistics, remove the custom tab bar styling code
4. For Ledger, the default Material TabBar is replaced with the gradient pill style

**Step 2: Run analyze and test**

Run: `flutter analyze && flutter test`
Expected: Clean

**Step 3: Commit**

```bash
git add lib/features/ledger/screens/ledger_screen.dart lib/features/logistics/screens/logistics_screen.dart
git commit -m "refactor: replace tab bars with shared AppTabBar widget"
```

---

### Task 10: Apply OfflineBanner to Key Screens

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart`
- Modify: `lib/features/home/screens/command_center.dart`
- Modify: `lib/features/ledger/screens/ledger_screen.dart`

**Step 1: Add OfflineBanner below headers**

In each file:
1. Import `import '../../../shared/widgets/offline_banner.dart';`
2. Add `const OfflineBanner()` in the Column, immediately after the header widget and before the Expanded content area

For home_screen.dart, place it after the header and before the Expanded trips list.
For command_center.dart, place it after the top bar.
For ledger_screen.dart, place it after the header.

**Step 2: Run tests**

Run: `flutter test`
Expected: All pass

**Step 3: Commit**

```bash
git add lib/features/home/screens/home_screen.dart lib/features/home/screens/command_center.dart lib/features/ledger/screens/ledger_screen.dart
git commit -m "feat: add OfflineBanner to home, command center, and ledger"
```

---

### Task 11: Replace Empty States with EmptyStateView

**Files:**
- Modify: `lib/features/gear/screens/gear_screen.dart`
- Modify: `lib/features/vault/screens/vault_screen.dart`
- Modify: `lib/features/activity/screens/activity_feed_screen.dart`
- Modify: `lib/features/home/screens/home_screen.dart`

**Step 1: Replace each ad-hoc empty state**

In each file:
1. Import `import '../../../shared/widgets/empty_state_view.dart';`
2. Replace inline empty state widgets with `EmptyStateView(...)`:

Gear:
```dart
EmptyStateView(
  icon: Iconsax.bag_2,
  title: 'No gear yet',
  message: 'Add items your group needs to bring',
  actionLabel: 'Add Item',
  onAction: () => _focusAddItem(),
  iconColor: AppColors.amber,
)
```

Vault:
```dart
EmptyStateView(
  icon: Iconsax.document,
  title: 'No documents yet',
  message: 'Upload tickets, bookings, or any trip files',
  actionLabel: 'Upload',
  onAction: () => _uploadDocument(context, ref),
  iconColor: AppColors.indigo,
)
```

Activity:
```dart
EmptyStateView(
  icon: Iconsax.activity,
  title: 'No activity yet',
  message: 'Actions from your trip will appear here',
  iconColor: AppColors.sky,
)
```

Home (no trips):
```dart
EmptyStateView(
  icon: Iconsax.map,
  title: 'No trips yet',
  message: 'Create a trip or join one with an invite code',
  actionLabel: 'Create Trip',
  onAction: () => context.go('/create-trip'),
  iconColor: AppColors.primary,
)
```

**Step 2: Run tests**

Run: `flutter test`
Expected: All pass

**Step 3: Commit**

```bash
git add lib/features/gear/screens/gear_screen.dart lib/features/vault/screens/vault_screen.dart lib/features/activity/screens/activity_feed_screen.dart lib/features/home/screens/home_screen.dart
git commit -m "refactor: replace ad-hoc empty states with EmptyStateView widget"
```

---

### Task 12: Add SearchFilterBar to Gear and Vault

**Files:**
- Modify: `lib/features/gear/screens/gear_screen.dart`
- Modify: `lib/features/vault/screens/vault_screen.dart`

**Step 1: Add search state and widget to Gear**

In `_GearScreenState`:
1. Add `String _searchQuery = '';` and `String? _statusFilter;`
2. Add `SearchFilterBar` between header and content list
3. Filter gear items by search query (match against item name) and status filter
4. Filters: `['All', 'Unclaimed', 'Claimed', 'Packed']`

**Step 2: Add search to Vault**

In VaultScreen (convert to ConsumerStatefulWidget if needed for search state):
1. Add `String _searchQuery = '';`
2. Add `SearchFilterBar` between header and document list
3. Filter documents by name match

**Step 3: Run tests**

Run: `flutter test`
Expected: All pass

**Step 4: Commit**

```bash
git add lib/features/gear/screens/gear_screen.dart lib/features/vault/screens/vault_screen.dart
git commit -m "feat: add search and filter to Gear and Vault screens"
```

---

### Task 13: Home Screen Refinements

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart`

**Step 1: Refine trip card details**

- Replace hardcoded spacing values with `AppColors.space*` constants
- Invite code badge: add a small copy icon (`Iconsax.copy`, size 12) next to the code text to hint at the long-press behavior
- Completed trips: instead of just `opacity: 0.7`, add a semi-transparent overlay with a checkmark badge in the corner
- Bento grid buttons: ensure both "Create Trip" and "Join Trip" use `AppColors.buttonHeight` and `AppColors.radiusMedium`

**Step 2: Add staggered animation timing**

Review existing stagger animation. Ensure delay per item is `100.ms * index` with max cap at 500ms total.

**Step 3: Run tests**

Run: `flutter test`
Expected: All pass

**Step 4: Commit**

```bash
git add lib/features/home/screens/home_screen.dart
git commit -m "refactor: refine home screen trip cards, spacing, and completed state"
```

---

### Task 14: Command Center Staggered Animations

**Files:**
- Modify: `lib/features/home/screens/command_center.dart`

**Step 1: Add staggered entrance to module cards**

Where SmartModuleCards are built in the list, wrap each one with:
```dart
.animate()
  .fadeIn(delay: (100 * index).ms, duration: 400.ms)
  .slideY(begin: 0.1, end: 0, delay: (100 * index).ms, duration: 400.ms)
```

**Step 2: Update spacing to use theme constants**

Replace hardcoded padding/margin values with `AppColors.space*` where they match the scale.

**Step 3: Commit**

```bash
git add lib/features/home/screens/command_center.dart
git commit -m "feat: add staggered entrance animations and consistent spacing to command center"
```

---

### Task 15: Settings Screen Refinements

**Files:**
- Modify: `lib/features/settings/screens/settings_screen.dart`

**Step 1: Add section headers**

Group settings into labeled sections with subtle dividers:
- "Profile" section (avatar, display name)
- "Preferences" section (theme, notifications)
- "About" section (version, support)

Each section header:
```dart
Padding(
  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
  child: Text(
    'PROFILE',
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.textMuted,
      letterSpacing: 1,
    ),
  ),
),
```

**Step 2: Avatar selector refinement**

- Increase avatar icon container from current size to 56x56
- Add a primary-colored ring around the selected avatar
- Add haptic feedback on avatar selection

**Step 3: Show build number**

Add at the bottom of the screen:
```dart
Text('Version ${AppMetadata.version} (${AppMetadata.buildNumber})')
```

**Step 4: Commit**

```bash
git add lib/features/settings/screens/settings_screen.dart
git commit -m "refactor: add section headers, avatar refinements, and build info to settings"
```

---

### Task 16: Auth Screen Refinements

**Files:**
- Modify: `lib/features/auth/screens/login_screen.dart`
- Modify: `lib/features/auth/screens/forgot_password_screen.dart`
- Modify: `lib/features/auth/screens/reset_password_screen.dart`

**Step 1: Add real-time validation to login**

In login_screen.dart, add `autovalidateMode: AutovalidateMode.onUserInteraction` to the Form widget. This validates fields as the user types rather than only on submit.

**Step 2: Add shake animation on error**

When auth fails, wrap the form container with a shake animation:
```dart
.animate(target: _hasError ? 1 : 0)
  .shakeX(hz: 4, amount: 6, duration: 400.ms)
```

Add a `bool _hasError = false;` state variable, set it true on auth failure, reset on next input change.

**Step 3: Apply consistent styling to forgot/reset password**

Review forgot_password_screen.dart and reset_password_screen.dart. If they use plain light backgrounds, apply the same dark immersive container style from the login screen (dark background, glassmorphism form card), OR at minimum ensure they use the same `AppFormField`/input styling and border radius constants.

**Step 4: Commit**

```bash
git add lib/features/auth/screens/login_screen.dart lib/features/auth/screens/forgot_password_screen.dart lib/features/auth/screens/reset_password_screen.dart
git commit -m "feat: real-time validation, error shake, and consistent auth styling"
```

---

## Layer 3: Interactions

### Task 17: Consistent Page Transitions

**Files:**
- Create: `lib/core/utils/page_transitions.dart`

**Step 1: Create reusable transition builders**

```dart
import 'package:flutter/material.dart';

class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    );
  }
}

class AppBottomSheetRoute<T> extends MaterialPageRoute<T> {
  AppBottomSheetRoute({required super.builder, super.settings});

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    );
  }
}
```

**Step 2: Apply to Navigator.push calls**

In command_center.dart and other files that use `Navigator.push(MaterialPageRoute(...))`, replace with `Navigator.push(AppPageRoute(...))`.

For bottom sheet style navigations (like edit_expense_sheet), use `AppBottomSheetRoute`.

**Step 3: Commit**

```bash
git add lib/core/utils/page_transitions.dart lib/features/home/screens/command_center.dart
git commit -m "feat: add consistent slide page transitions"
```

---

### Task 18: Haptic Feedback Consistency

**Files:**
- Modify: `lib/features/ledger/screens/ledger_screen.dart`
- Modify: `lib/features/gear/screens/gear_screen.dart`
- Modify: `lib/features/settings/screens/settings_screen.dart`
- Modify: `lib/features/home/screens/home_screen.dart`
- Modify: `lib/features/home/screens/command_center.dart`

**Step 1: Audit and add missing haptics**

Add `HapticService` calls where missing:
- `HapticService.selection()` — tab switches (already handled in AppTabBar), toggle switches, chip selections
- `HapticService.lightClick()` — card taps, copy-to-clipboard
- `HapticService.medium()` — button presses that trigger navigation
- `HapticService.warning()` — delete confirmations, destructive actions
- `HapticService.success()` — successful expense creation, settlement, document upload

Go through each screen, find interactive elements, and add the appropriate haptic call.

**Step 2: Commit**

```bash
git add -A
git commit -m "feat: consistent haptic feedback across all interactive elements"
```

---

### Task 19: Staggered List Animations

**Files:**
- Modify: `lib/features/vault/screens/vault_screen.dart`
- Modify: `lib/features/activity/screens/activity_feed_screen.dart`
- Modify: `lib/features/ledger/screens/ledger_screen.dart`

**Step 1: Add staggered entrance to all list screens**

In each ListView.builder, wrap items with:
```dart
.animate()
  .fadeIn(delay: (50 * index).ms.clamp(Duration.zero, 500.ms), duration: 300.ms)
  .slideY(begin: 0.05, end: 0, delay: (50 * index).ms.clamp(Duration.zero, 500.ms))
```

Cap the stagger at 500ms so lists with many items don't take forever to appear.

**Step 2: Commit**

```bash
git add lib/features/vault/screens/vault_screen.dart lib/features/activity/screens/activity_feed_screen.dart lib/features/ledger/screens/ledger_screen.dart
git commit -m "feat: staggered entrance animations on all list screens"
```

---

### Task 20: Accessibility Pass

**Files:**
- Modify: Multiple screen files

**Step 1: Add Semantics to icon-only buttons**

Wrap all icon-only buttons (back buttons, action buttons, filter toggles) with `Semantics(label: '...', button: true, child: ...)` or use `Tooltip` wrapper.

Key locations:
- ModuleHeader back button: `Semantics(label: 'Go back', ...)`
- Home screen settings button: `Semantics(label: 'Settings', ...)`
- Search toggle in SearchFilterBar: `Semantics(label: 'Toggle search', ...)`
- FABs in Vault/Gear: already labeled via Flutter's built-in FAB semantics

**Step 2: Ensure minimum touch targets**

Audit all GestureDetector/InkWell wrappers. Any interactive element smaller than 44x44 should be wrapped in a `SizedBox(width: 44, height: 44)` or use `MaterialButton` with minimum size constraint.

**Step 3: Add reduced motion support**

In files that use `flutter_animate`, check `MediaQuery.disableAnimations`:
```dart
final reduceMotion = MediaQuery.of(context).disableAnimations;
```

For key animations, skip them when `reduceMotion` is true. This can be done with `.animate(autoPlay: !reduceMotion)`.

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: accessibility improvements — semantics, touch targets, reduced motion"
```

---

### Task 21: Edge Cases

**Files:**
- Modify: Multiple screen files

**Step 1: Keyboard scroll behavior**

In screens with forms (login, create trip, add expense), ensure `SingleChildScrollView` wraps the form content so the active field scrolls above the keyboard. Add `padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)` if not already present.

**Step 2: Text overflow protection**

Audit trip card titles, expense descriptions, and member names. Ensure all use `maxLines` + `overflow: TextOverflow.ellipsis`. Key locations:
- Home screen trip card title
- Ledger expense card description
- Command center trip name
- Member names in logistics cards

**Step 3: Navigation debounce**

In `SmartModuleCard`'s `_PressableWrapper`, add a debounce flag to prevent double-push:
```dart
bool _isNavigating = false;
// In onTapUp:
if (_isNavigating) return;
_isNavigating = true;
widget.onTap();
Future.delayed(const Duration(milliseconds: 500), () => _isNavigating = false);
```

**Step 4: Pull-to-refresh on remaining screens**

Add `RefreshIndicator` to Gear, Vault, and Logistics screens (Activity already has it). Wrap the list content and invalidate the relevant provider on refresh.

**Step 5: Run all tests**

Run: `flutter test`
Expected: All 16 tests pass

**Step 6: Run analyze**

Run: `flutter analyze`
Expected: Fewer issues than before (the 2 warnings and deprecated usage should be reduced)

**Step 7: Commit**

```bash
git add -A
git commit -m "fix: keyboard scroll, text overflow, nav debounce, pull-to-refresh"
```

---

## Final Verification

### Task 22: Full Verification Pass

**Step 1: Run complete test suite**

Run: `flutter test`
Expected: All tests pass

**Step 2: Run static analysis**

Run: `flutter analyze`
Expected: Significant reduction in issues (target: only the `unnecessary_underscores` infos remain)

**Step 3: Hot restart the app and visually verify**

Run: `flutter run --dart-define-from-file=config.json`

Verify each screen in order:
1. Onboarding — animations, page indicators
2. Login — form validation on type, error shake
3. Home — trip cards, offline banner, empty state
4. Command Center — module cards animate in, offline banner
5. Ledger — AppTabBar, search, empty state
6. Gear — ModuleHeader, search/filter, empty state
7. Vault — ModuleHeader, search, empty state with CTA
8. Logistics — ModuleHeader, AppTabBar
9. Activity — ModuleHeader, staggered list
10. Settings — section headers, avatar ring, build info

# Command Center Redesign + Empty States

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the Command Center from a static grid into a minimal vertical layout with smart contextual prompts, and add purposeful empty states to each module screen.

**Architecture:** Replace the 2x2 `GridView` module tiles with vertical `SmartModuleCard` widgets that show live data summaries or contextual nudges based on module state. Cards dynamically reorder by relevance. Each feature screen gets a standardized empty state widget with explanation + CTA.

**Tech Stack:** Flutter, Riverpod (existing providers), flutter_animate, Iconsax

---

### Task 1: Create SmartModuleCard widget

**Files:**
- Create: `lib/shared/widgets/smart_module_card.dart`

**Step 1: Create the SmartModuleCard widget**

A reusable card widget that renders differently based on whether the module has data:

```dart
class SmartModuleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description; // What this module does (for empty state)
  final Color color;
  final VoidCallback onTap;
  final String? summaryText; // e.g. "5 expenses · You owe 12.500"
  final String? actionText; // e.g. "Tap to add your first expense"
  final int priority; // For sorting: higher = shows first
  final bool isEmpty;
}
```

Layout:
- Horizontal card: icon on left (40x40 rounded container), title + summary/nudge on right
- When `isEmpty`: show description text + subtle action nudge
- When has data: show summaryText with live stats
- Consistent height ~72px, full-width
- Border: 1.5px borderLight, 24px radius
- Tap navigates to module

**Step 2: Verify widget renders in isolation**

Create a simple test or preview in DevTools to confirm both empty and data states render correctly.

---

### Task 2: Build module data summarizers

**Files:**
- Modify: `lib/features/home/screens/command_center.dart`

**Step 1: Create summary text builders for each module**

Add helper methods that take provider data and return summary strings:

- **Ledger:** `"5 expenses · You owe 12.500 OMR"` or `"3 expenses · All settled"` or `null` (empty)
- **Logistics:** `"2 cars · 1 room · 3 unassigned"` or `null`
- **Gear:** `"12 items · 4 unclaimed · 8 packed"` or `null`
- **Vault:** `"3 documents uploaded"` or `null`

Each returns `null` when the module has no data, which triggers the empty/nudge state.

**Step 2: Create priority calculator**

Priority rules (higher number = shows first):
- Module has unsettled balances → priority 100
- Module has unclaimed gear → priority 80
- Module has unassigned logistics members → priority 70
- Module has data but no action needed → priority 50
- Module is empty → priority 10

---

### Task 3: Replace module grid with vertical card list

**Files:**
- Modify: `lib/features/home/screens/command_center.dart`

**Step 1: Replace `_buildModuleGrid` with `_buildModuleList`**

Remove the `GridView.count` and replace with a `Column` of `SmartModuleCard` widgets:

```dart
Widget _buildModuleList(BuildContext context, WidgetRef ref, Trip trip) {
  // Build list of SmartModuleCard configs
  // Sort by priority (highest first)
  // Return Column with 12px spacing between cards
}
```

**Step 2: Wire up providers**

Each module card watches its relevant provider:
- Ledger: `tripExpensesProvider(trip.id)` + `tripBalancesProvider(trip.id)`
- Logistics: `tripSubGroupsProvider(trip.id)`
- Gear: `tripGearProvider(trip.id)`
- Vault: `tripDocumentsProvider(trip.id)`

Only render cards for enabled modules (`trip.modules.docs`, `.gear`, `.logistics`). Ledger is always shown.

**Step 3: Update section header**

Change "MODULES" header to remove the grid icon, keep the label.

**Step 4: Verify**

Run `flutter analyze`. Hot reload and verify the new layout on simulator.

---

### Task 4: Add contextual nudge messages

**Files:**
- Modify: `lib/features/home/screens/command_center.dart`

**Step 1: Define nudge messages per module**

Empty state nudges (shown when module has no data):
- **Ledger:** `"Track shared expenses and split costs fairly"`
- **Logistics:** `"Organize cars, rooms, and teams for your group"`
- **Gear:** `"Create a shared packing list and claim items"`
- **Vault:** `"Store tickets, permits, and trip documents"`

Action nudges (shown when attention needed):
- **Ledger (owes money):** `"You have unsettled balances"`
- **Gear (unclaimed items):** `"X items still need someone to bring them"`
- **Logistics (unassigned):** `"X members haven't been assigned yet"`

**Step 2: Style nudge text**

- Empty nudge: `textSecondary` color, 13px, w600
- Action nudge: module `color`, 13px, w700
- Summary text: `textPrimary`, 13px, w700

---

### Task 5: Redesign Ledger empty state

**Files:**
- Modify: `lib/features/ledger/screens/ledger_screen.dart`

**Step 1: Replace inline empty text with purposeful empty state**

Replace the current `'No transactions yet'` text container with:
- Icon: `Iconsax.wallet_3` in 80x80 rounded container with primary light background
- Headline: `"No Expenses Yet"`
- Description: `"Add your first expense to start tracking costs and splitting them with your group."`
- CTA: Prominent "Add Expense" button that triggers the add expense flow

Use `flutter_animate` for fadeIn + scale on the icon.

---

### Task 6: Redesign Logistics empty state

**Files:**
- Modify: `lib/features/logistics/screens/logistics_screen.dart`

**Step 1: Improve existing empty state**

The current logistics empty state is decent but missing a CTA button. Add:
- A prominent "Add [Car/Room]" button below the description text
- Match the style of the gear screen empty state (which already has an input field)

---

### Task 7: Improve Activity Feed empty state

**Files:**
- Modify: `lib/features/activity/screens/activity_feed_screen.dart`

**Step 1: Enhance the "SIGNAL LOST" empty state**

Add a description that explains what the activity feed shows:
- Update description to: `"Activity will appear here as your group adds expenses, claims gear, and makes changes."`
- Add `flutter_animate` fadeIn animations matching other empty states

---

### Task 8: Clean up and verify

**Files:**
- Modify: `lib/features/home/screens/command_center.dart` (remove old `_ModuleTile` class)

**Step 1: Remove dead code**

Delete the `_ModuleTile` widget class and the old `_buildModuleGrid` method since they're replaced.

**Step 2: Full verification**

Run:
- `flutter analyze` - should pass with same 15 pre-existing issues
- `flutter test` - all tests should still pass
- Visual check on simulator: navigate through all screens confirming empty states and data states render correctly

---

## Smoke Test Checklist

After implementation, verify:
- [ ] Command Center shows vertical cards instead of grid
- [ ] Cards with data show summary text (expenses count, balance, gear progress)
- [ ] Empty module cards show contextual nudge messages
- [ ] Cards reorder by priority (action-needed modules float to top)
- [ ] Tapping each card navigates to correct module screen
- [ ] Ledger empty state shows "Add Expense" CTA
- [ ] Logistics empty state shows "Add Car/Room" CTA
- [ ] Activity feed empty state has improved description
- [ ] Vault empty state unchanged (already good)
- [ ] Gear empty state unchanged (already good)
- [ ] FAB still works for quick expense add
- [ ] Preparation hero and expense summary hero unchanged
- [ ] All animations smooth, no overflow errors

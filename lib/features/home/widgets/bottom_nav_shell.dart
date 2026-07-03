import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import 'package:haptic_feedback/haptic_feedback.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../features/settings/screens/profile_screen.dart';
import '../../../shared/widgets/grain_overlay.dart';
import '../../groups/providers/group_provider.dart';
import '../keys/home_keys.dart';
import '../providers/activity_unread_provider.dart';
import '../screens/cross_group_activity_screen.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import 'add_expense_fab.dart';

/// Bottom navigation shell for the home dashboard.
///
/// Wraps the dashboard content in a 3-tab bottom navigation bar:
/// Groups, Activity, Profile.
///
/// The Groups tab (index 0) shows the provided [child] widget.
/// Activity shows the cross-group activity feed; Profile shows settings.
///
/// Uses Stack + AnimatedOpacity for M3 FadeThrough tab switching while
/// preserving all tab widget state (Phase 22 P03, D-07).
/// IgnorePointer prevents interaction with invisible tabs.
///
/// NOTE: GoRouter is NOT used for tab navigation per RESEARCH Pitfall 3.
/// Phase 19 will wire real GoRouter routes for non-Groups tabs.
class BottomNavShell extends ConsumerStatefulWidget {
  /// The dashboard content shown on the Groups tab.
  final Widget child;

  /// Optional key forwarded to the inner [Scaffold] for widget testing.
  final Key? scaffoldKey;

  const BottomNavShell({super.key, required this.child, this.scaffoldKey});

  @override
  ConsumerState<BottomNavShell> createState() => _BottomNavShellState();
}

class _BottomNavShellState extends ConsumerState<BottomNavShell> {
  int _currentIndex = 0;
  final Set<int> _visited = {0};

  /// Centralizes both tab-switch side effects — the #808 PR2 seen-stamp (tab
  /// 1 only) and the #113 lazy-build visited set — so a programmatic select
  /// (via [BottomNavTabScope]) behaves identically to a direct nav-bar tap.
  void _selectTab(int i) {
    if (i == 1) {
      ref.read(activitySeenProvider.notifier).markSeenNow();
    }
    setState(() {
      _currentIndex = i;
      _visited.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    // #807: hide the FAB on the zero-groups empty state (it would duplicate
    // the empty state's own "create group" CTA). valueOrNull shows the FAB
    // through loading/error; the cold-start authStateChanges race can still
    // emit a transient AsyncData([]) (#647 — settled data, not loading), so a
    // user WITH groups may see the FAB hidden for a sub-second beat until the
    // real snapshot lands. Benign for a FAB — do NOT reuse this read as a
    // safety gate (see outgoingShellProvablyEmpty for the real pattern).
    final groups = ref.watch(userGroupsProvider).valueOrNull;
    final hasNoGroups = groups != null && groups.isEmpty;
    return BottomNavTabScope(
      selectTab: _selectTab,
      child: Scaffold(
        key: widget.scaffoldKey,
        backgroundColor: context.colors.scaffoldBackground,
        body: _buildBody(context),
        // #364: money CTA on Groups/Activity only — Profile is settings.
        floatingActionButton: _currentIndex == 2 || hasNoGroups
            ? null
            : const AddExpenseFab(),
        bottomNavigationBar: _buildNavBar(context),
      ),
    );
  }

  Widget _buildTab(int index) {
    switch (index) {
      case 0:
        return widget.child;
      case 1:
        return const CrossGroupActivityScreen();
      case 2:
        return const ProfileScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildBody(BuildContext context) {
    return GrainOverlay(
      opacity: 0.035,
      child: Stack(
        children: List.generate(3, (index) {
          // Lazy-build (#113): don't construct a tab's subtree until it has
          // been visited at least once. Once visited it stays mounted so
          // AnimatedOpacity preserves its state across tab switches.
          if (!_visited.contains(index)) {
            return const SizedBox.shrink();
          }
          return AnimatedOpacity(
            duration: context.motion.standard,
            curve: context.motion.curveStandard,
            opacity: index == _currentIndex ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: index != _currentIndex,
              child: _buildTab(index),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNavBar(BuildContext context) {
    final hasUnreadActivity = ref.watch(activityUnreadProvider);
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: context.colors.bottomNavBackground,
        indicatorColor: context.colors.selectionFill,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTypography.sans(
              color: context.colors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            );
          }
          return AppTypography.sans(
            color: context.colors.bottomNavInactiveIcon,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          );
        }),
      ),
      child: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          try {
            Haptics.vibrate(HapticsType.selection);
          } catch (_) {}
          _selectTab(i);
        },
        height: 72,
        elevation: 8,
        destinations: [
          NavigationDestination(
            icon: Icon(
              Iconsax.people,
              color: context.colors.bottomNavInactiveIcon,
              key: HomeKeys.bottomNavGroups,
            ),
            selectedIcon: Icon(Iconsax.people5, color: context.colors.primary),
            label: context.l10n.homeBottomNavGroups,
          ),
          NavigationDestination(
            icon: Badge(
              key: HomeKeys.activityUnreadBadge,
              isLabelVisible: hasUnreadActivity,
              smallSize: 8,
              backgroundColor: context.colors.primary,
              child: Icon(
                Iconsax.activity,
                color: context.colors.bottomNavInactiveIcon,
                key: HomeKeys.bottomNavActivity,
              ),
            ),
            selectedIcon: Icon(
              Iconsax.activity5,
              color: context.colors.primary,
            ),
            label: context.l10n.homeBottomNavActivity,
          ),
          NavigationDestination(
            icon: Icon(
              Iconsax.profile_circle,
              color: context.colors.bottomNavInactiveIcon,
              key: HomeKeys.bottomNavProfile,
            ),
            selectedIcon: Icon(
              Iconsax.profile_circle5,
              color: context.colors.primary,
            ),
            label: context.l10n.homeBottomNavProfile,
          ),
        ],
      ),
    );
  }
}

/// Programmatic tab-select channel for descendants of [BottomNavShell]
/// (#818 Wave 5.2) — lets a widget inside the Groups tab's subtree (e.g. the
/// home top-bar bell) select another tab without the shell exposing its
/// `_currentIndex` state to a provider or routing through GoRouter.
///
/// [selectTab] runs the SAME side effects as a direct nav-bar tap
/// (`_BottomNavShellState._selectTab`): the seen-stamp on tab 1 and the
/// lazy-build visited set.
///
/// [maybeOf] uses `getElementForInheritedWidgetOfExactType` rather than
/// `dependOnInheritedWidgetOfExactType` — callers look this up inside `onTap`
/// callbacks, not `build`, so no build-time dependency should be registered.
class BottomNavTabScope extends InheritedWidget {
  const BottomNavTabScope({
    super.key,
    required this.selectTab,
    required super.child,
  });

  final void Function(int index) selectTab;

  static BottomNavTabScope? maybeOf(BuildContext context) =>
      context
              .getElementForInheritedWidgetOfExactType<BottomNavTabScope>()
              ?.widget
          as BottomNavTabScope?;

  @override
  bool updateShouldNotify(BottomNavTabScope oldWidget) => false;
}

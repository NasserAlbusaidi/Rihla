import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:haptic_feedback/haptic_feedback.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../features/settings/screens/profile_screen.dart';
import '../../../shared/widgets/grain_overlay.dart';
import '../keys/home_keys.dart';
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
class BottomNavShell extends StatefulWidget {
  /// The dashboard content shown on the Groups tab.
  final Widget child;

  /// Optional key forwarded to the inner [Scaffold] for widget testing.
  final Key? scaffoldKey;

  const BottomNavShell({super.key, required this.child, this.scaffoldKey});

  @override
  State<BottomNavShell> createState() => _BottomNavShellState();
}

class _BottomNavShellState extends State<BottomNavShell> {
  int _currentIndex = 0;
  final Set<int> _visited = {0};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: widget.scaffoldKey,
      backgroundColor: context.colors.scaffoldBackground,
      body: _buildBody(context),
      // #364: money CTA on Groups/Activity only — Profile is settings.
      floatingActionButton:
          _currentIndex == 2 ? null : const AddExpenseFab(),
      bottomNavigationBar: _buildNavBar(context),
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
          setState(() {
            _currentIndex = i;
            _visited.add(i);
          });
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
            icon: Icon(
              Iconsax.activity,
              color: context.colors.bottomNavInactiveIcon,
              key: HomeKeys.bottomNavActivity,
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

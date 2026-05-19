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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: widget.scaffoldKey,
      backgroundColor: context.colors.scaffoldBackground,
      body: _buildBody(),
      bottomNavigationBar: _buildNavBar(context),
    );
  }

  Widget _buildBody() {
    final tabs = [
      widget.child,
      const CrossGroupActivityScreen(),
      const ProfileScreen(),
    ];
    return GrainOverlay(
      opacity: 0.035,
      child: Stack(
        children: List.generate(tabs.length, (index) {
          return AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            opacity: index == _currentIndex ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: index != _currentIndex,
              child: tabs[index],
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
            return TextStyle(
              color: context.colors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: AppTypography.sansFamily,
            );
          }
          return TextStyle(
            color: context.colors.bottomNavInactiveIcon,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontFamily: AppTypography.sansFamily,
          );
        }),
      ),
      child: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          try {
            Haptics.vibrate(HapticsType.selection);
          } catch (_) {}
          setState(() => _currentIndex = i);
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

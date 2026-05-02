import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../features/settings/screens/profile_screen.dart';
import '../../../shared/widgets/grain_overlay.dart';
import '../keys/home_keys.dart';
import '../screens/cross_group_activity_screen.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

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
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (i) => setState(() => _currentIndex = i),
      backgroundColor: context.colors.bottomNavBackground,
      selectedItemColor: context.colors.bottomNavActiveIcon,
      unselectedItemColor: context.colors.bottomNavInactiveIcon,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
      elevation: 8,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Iconsax.people, key: HomeKeys.bottomNavGroups),
          label: 'Groups',
        ),
        BottomNavigationBarItem(
          icon: Icon(Iconsax.activity, key: HomeKeys.bottomNavActivity),
          label: 'Activity',
        ),
        BottomNavigationBarItem(
          icon: Icon(Iconsax.profile_circle, key: HomeKeys.bottomNavProfile),
          label: 'Profile',
        ),
      ],
    );
  }
}

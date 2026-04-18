import 'package:flutter/material.dart';
import '../../core/keys/shared_keys.dart';
import '../../core/services/haptic_service.dart';
import '../../core/theme/tokens/domain_aliases.dart';

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
    final color = activeColor ?? context.colors.primary;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: context.spacing.space24,
        vertical: context.spacing.space12,
      ),
      padding: EdgeInsets.all(context.spacing.space4),
      decoration: BoxDecoration(
        color: context.colors.inputFill,
        borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
      ),
      child: TabBar(
        controller: controller,
        onTap: (_) => HapticService.selection(),
        indicator: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(context.spacing.radiusSmall),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: context.colors.textSecondary,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        tabs: tabs
            .map((t) => Tab(key: SharedKeys.appTabBarTab(t), text: t))
            .toList(),
      ),
    );
  }
}

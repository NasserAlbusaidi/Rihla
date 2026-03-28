import 'package:flutter/material.dart';
import '../../core/keys/shared_keys.dart';
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
        tabs: tabs
            .map((t) => Tab(key: SharedKeys.appTabBarTab(t), text: t))
            .toList(),
      ),
    );
  }
}

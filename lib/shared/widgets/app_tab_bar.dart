import 'package:flutter/material.dart';
import '../../core/keys/shared_keys.dart';
import '../../core/services/haptic_service.dart';
import '../../core/theme/tokens/color_tokens.dart';

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
    final color = activeColor ?? AppColorTokens.light.primary;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 12,
      ),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColorTokens.light.inputFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: controller,
        onTap: (_) => HapticService.selection(),
        indicator: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
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
        unselectedLabelColor: AppColorTokens.light.textMuted,
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

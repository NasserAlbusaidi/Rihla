import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/theme/tokens/domain_aliases.dart';

/// A dot-based step/page indicator widget with terracotta accent.
///
/// Supports three dot states:
/// - **Completed** (index < currentStep, showCheckmarks=true): filled circle with check icon
/// - **Active** (index == currentStep): filled circle
/// - **Upcoming** (index > currentStep): outlined ring
///
/// Used in:
/// - Add Expense multi-step flow (showCheckmarks=true, D-27)
/// - Onboarding page indicator (showCheckmarks=false, D-29)
class DotStepIndicator extends StatelessWidget {
  final int stepCount;
  final int currentStep; // 0-indexed

  /// Optional override for the active/filled dot color. When null, defaults
  /// to the current theme's focusBorderWarm (terracotta in light, its dark
  /// counterpart in dark) — resolved inside [build] so the default is
  /// theme-aware.
  final Color? activeColor;
  final bool showCheckmarks; // true for Add Expense steps, false for onboarding pages

  const DotStepIndicator({
    super.key,
    required this.stepCount,
    required this.currentStep,
    this.activeColor,
    this.showCheckmarks = true,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedActive = activeColor ?? context.colors.focusBorderWarm;
    return Semantics(
      label: 'Step ${currentStep + 1} of $stepCount',
      child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(stepCount, (index) {
        if (showCheckmarks && index < currentStep) {
          // Complete step: filled circle with check
          return _buildDot(context, filled: true, isCheck: true, active: resolvedActive);
        } else if (index == currentStep) {
          // Active step: filled circle
          return _buildDot(context, filled: true, isCheck: false, active: resolvedActive);
        } else {
          // Upcoming step: outlined ring
          return _buildDot(context, filled: false, isCheck: false, active: resolvedActive);
        }
      }),
    ),
    );
  }

  Widget _buildDot(BuildContext context,
      {required bool filled, required bool isCheck, required Color active}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space4),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? active : Colors.transparent,
          border: filled ? null : Border.all(color: active, width: 1.5),
        ),
        child: isCheck
            ? const Icon(Iconsax.tick_circle, size: 8, color: Colors.white)
            : null,
      ),
    );
  }
}

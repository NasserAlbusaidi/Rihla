import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/theme/app_theme.dart';

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
  final Color activeColor;
  final bool showCheckmarks; // true for Add Expense steps, false for onboarding pages

  const DotStepIndicator({
    super.key,
    required this.stepCount,
    required this.currentStep,
    this.activeColor = AppColors.terracotta,
    this.showCheckmarks = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(stepCount, (index) {
        if (showCheckmarks && index < currentStep) {
          // Complete step: filled circle with check
          return _buildDot(filled: true, isCheck: true, index: index);
        } else if (index == currentStep) {
          // Active step: filled circle
          return _buildDot(filled: true, isCheck: false, index: index);
        } else {
          // Upcoming step: outlined ring
          return _buildDot(filled: false, isCheck: false, index: index);
        }
      }),
    );
  }

  Widget _buildDot({required bool filled, required bool isCheck, required int index}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? activeColor : Colors.transparent,
          border: filled ? null : Border.all(color: activeColor, width: 1.5),
        ),
        child: isCheck
            ? const Icon(Iconsax.tick_circle, size: 8, color: Colors.white)
            : null,
      ),
    );
  }
}

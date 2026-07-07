import 'package:flutter/material.dart';

import '../../core/theme/tokens/domain_aliases.dart';

/// Loading button widget with animated state
class LoadingButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;
  final IconData? icon;
  final Gradient? gradient;

  const LoadingButton({
    super.key,
    required this.onPressed,
    required this.isLoading,
    required this.label,
    this.icon,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    // #1026: a disabled button (not loading) must read as inactive. The outer
    // container carries the fill (the inner ElevatedButton is transparent), so
    // without this it kept the bright primary/gradient and the label fell back
    // to Material's low-contrast default disabled foreground. Loading keeps the
    // primary fill (the spinner sits on it) and is not treated as disabled.
    final bool disabled = onPressed == null && !isLoading;
    return Container(
      height: context.spacing.buttonHeight,
      decoration: BoxDecoration(
        gradient: disabled ? null : gradient,
        color: disabled
            ? context.colors.disabled
            : (gradient == null ? context.colors.primary : null),
        borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: context.colors.textOnPrimary,
          disabledForegroundColor: context.colors.disabledText,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: context.colors.textOnPrimary,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon),
                    SizedBox(width: context.spacing.space8),
                  ],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

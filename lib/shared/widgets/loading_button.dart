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
    return Container(
      height: context.spacing.buttonHeight,
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? context.colors.primary : null,
        borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
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

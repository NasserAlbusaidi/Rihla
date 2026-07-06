import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';

class CardShell extends StatelessWidget {
  const CardShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardSurface,
        borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: child,
    );
  }
}

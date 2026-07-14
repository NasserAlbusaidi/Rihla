import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../shared/widgets/directional_icon.dart';

class GhostIcon extends StatelessWidget {
  const GhostIcon({
    super.key,
    required this.icon,
    required this.onTap,
    this.matchTextDirection = false,
    this.semanticLabel,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool matchTextDirection;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget result = InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(
        width: 44,
        height: 44,
        child: matchTextDirection
            ? DirectionalIcon(icon, size: 20, color: colors.textPrimary)
            : Icon(icon, size: 20, color: colors.textPrimary),
      ),
    );
    if (semanticLabel != null) {
      result = Semantics(button: true, label: semanticLabel, child: result);
    }
    return result;
  }
}

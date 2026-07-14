import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

/// One icon+label chip in the "How" control. Selected → saffron selection fill
/// + primary border/icon; otherwise the neutral input surface.
class ModeChip extends StatelessWidget {
  const ModeChip({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // #1067 §4: the opaque wrapper supplies the 44dp hit floor; the
        // widthFactor keeps this Wrap child intrinsic-width and its painted
        // pill vertically compact.
        child: SizedBox(
          height: 44,
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 14, 8),
              decoration: BoxDecoration(
                color: selected ? colors.selectionFill : colors.inputFill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? colors.primary : colors.rule,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected
                        ? colors.primaryDark
                        : colors.textSecondary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: AppTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

/// Generic inline segmented control matching the signed-off #485 mockup. Equal
/// weight per segment; the active one lifts onto the card surface.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colors.inputFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.rule),
        ),
        child: Row(
          children: [
            for (final (optValue, label) in options)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: optValue == value,
                  label: label,
                  onTap: enabled ? () => onChanged(optValue) : null,
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: enabled ? () => onChanged(optValue) : null,
                    // #1077 §4: the opaque wrapper supplies the 44dp hit
                    // floor (mirrors _ModeChip); Center keeps the painted
                    // pill at its compact vertical-8 padding while the
                    // infinite width still fills the equal-weight segment.
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: optValue == value
                                ? colors.cardSurface
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: optValue == value
                                ? context.shadows.raised
                                : null,
                          ),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.sans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: optValue == value
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

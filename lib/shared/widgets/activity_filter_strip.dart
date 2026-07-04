import 'package:flutter/material.dart';

import '../../core/services/haptic_service.dart';
import '../../core/theme/tokens/domain_aliases.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../animations/tap_bounce.dart';

/// One selectable option in an [ActivityFilterStrip].
class ActivityFilterOption<T> {
  const ActivityFilterOption({required this.value, required this.label, this.key});

  final T value;
  final String label;
  final Key? key;
}

/// Horizontal scrolling strip of pill filter chips.
///
/// Visuals lifted verbatim from the `_FilterStrip`/`_Chip` pair in
/// `group_activity_screen.dart`. Re-tapping the already-active option is a
/// total no-op — no haptic, no [onChange] call.
class ActivityFilterStrip<T> extends StatelessWidget {
  const ActivityFilterStrip({
    super.key,
    required this.options,
    required this.current,
    required this.onChange,
  });

  final List<ActivityFilterOption<T>> options;
  final T current;
  final ValueChanged<T> onChange;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: context.spacing.space32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
        children: [
          for (final opt in options) ...[
            _Chip(
              chipKey: opt.key,
              label: opt.label,
              active: current == opt.value,
              onTap: () {
                if (opt.value == current) return;
                HapticService.selection();
                onChange(opt.value);
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.chipKey,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final Key? chipKey;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TapBounce(
      key: chipKey,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? colors.textPrimary : colors.cardSoft,
          borderRadius: BorderRadius.circular(context.spacing.radiusPill),
          border: Border.all(
            color: active ? colors.textPrimary : colors.rule,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.sans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? colors.scaffoldBackground : colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

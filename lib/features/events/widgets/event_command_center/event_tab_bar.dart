import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../keys/event_keys.dart';
import '../../screens/event_command_center.dart';

class EventTabBar extends StatelessWidget {
  const EventTabBar({
    super.key,
    required this.active,
    required this.showRecap,
    required this.onSelect,
  });

  final EventTab active;
  final bool showRecap;
  final ValueChanged<EventTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tabs = <({EventTab tab, Key key, String label})>[
      (
        tab: EventTab.expenses,
        key: EventKeys.tabExpenses,
        label: context.l10n.eventTabExpenses,
      ),
      (
        tab: EventTab.settleUp,
        key: EventKeys.tabSettleUp,
        label: context.l10n.eventTabSettleUp,
      ),
      (
        tab: EventTab.activity,
        key: EventKeys.tabActivity,
        label: context.l10n.eventTabActivity,
      ),
      if (showRecap)
        (
          tab: EventTab.recap,
          key: EventKeys.tabRecap,
          label: context.l10n.eventTabRecap,
        ),
    ];

    return Container(
      key: EventKeys.tabBar,
      height: 44,
      margin: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 10),
      // #1067 §4: the Stack separates the 44dp hit layer from the compact
      // painted track. The old 3dp inset remains visual, not a hit constraint.
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            top: 3,
            bottom: 3,
            child: DecoratedBox(
              key: const Key('event_tab_bar_track'),
              decoration: BoxDecoration(
                color: colors.cardSoft,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colors.border, width: 0.5),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Row(
              children: [
                for (final t in tabs)
                  Expanded(
                    child: _TabButton(
                      key: t.key,
                      label: t.label,
                      active: t.tab == active,
                      onTap: () => onSelect(t.tab),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // #1067 §4: the opaque hit box reaches 44dp while the full-width
        // painted pill stays at its deliberately compact intrinsic height.
        child: SizedBox(
          height: 44,
          child: Center(
            child: SizedBox(
              width: double.infinity,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? colors.cardSurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: active ? context.shadows.raised : null,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

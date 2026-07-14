import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/r_icon_button.dart';
import '../../keys/event_keys.dart';
import '../../models/event_model.dart';
import '../../utils/event_display.dart';
import 'balance_block.dart';
import 'compact_amounts.dart';
import 'hub_state.dart';
import 'trip_progress_line.dart';

class EventHeader extends StatelessWidget {
  const EventHeader({
    super.key,
    required this.event,
    required this.collapsed,
    required this.state,
    required this.lines,
    required this.hasExpenses,
    required this.onBack,
    required this.onSearch,
    required this.onSettings,
    required this.onViewRecap,
  });

  final Event event;
  final bool collapsed;
  final HubState state;
  final List<({String currency, Decimal net})> lines;
  final bool hasExpenses;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final VoidCallback onViewRecap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // #789: "Day N of M" for a live, multi-day trip — suppressed once closed.
    final day = event.isClosed
        ? null
        : liveTripDay(event.startDate, event.endDate, DateTime.now());
    final dayLabel = day == null
        ? null
        : context.l10n.eventDayOf(day.currentDay, day.totalDays);
    final showRecapLink = !event.isClosed && hasExpenses;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 0),
          child: Row(
            children: [
              RIconButton(
                icon: Iconsax.arrow_left,
                matchTextDirection: true,
                semanticLabel: context.l10n.commonBack,
                onTap: onBack,
              ),
              SizedBox(width: context.spacing.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.displayOf(
                        context,
                        fontSize: 20,
                        color: colors.textPrimary,
                        height: 1.1,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              // #1028: under unavailable/pending the lines may be non-empty
              // WRONG nets (ledgerViewProvider folds an errored stream to
              // []) — never render them compactly either.
              if (collapsed &&
                  lines.isNotEmpty &&
                  state != HubState.unavailable &&
                  state != HubState.pending)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6, end: 2),
                  child: CompactAmounts(lines: lines),
                ),
              RIconButton(
                key: EventKeys.searchButton,
                icon: Iconsax.search_normal,
                tooltip: context.l10n.ledgerSearchExpensesTooltip,
                onTap: onSearch,
              ),
              RIconButton(
                key: EventKeys.settingsButton,
                icon: Iconsax.setting_2,
                semanticLabel: context.l10n.ledgerEventSettingsTooltip,
                onTap: onSettings,
              ),
            ],
          ),
        ),
        // The balance block collapses on scroll, handing the list its space
        // back; the compact amount above stands in while collapsed.
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: AlignmentDirectional.topCenter,
            child: collapsed
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      20,
                      10,
                      20,
                      4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        BalanceBlock(state: state, lines: lines),
                        const SizedBox(height: 6),
                        TripProgressLine(
                          dayLabel: dayLabel,
                          showRecap: showRecapLink,
                          onViewRecap: onViewRecap,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

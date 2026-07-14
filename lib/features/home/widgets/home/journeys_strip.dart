import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../providers/active_journeys_provider.dart';
import '../journey_ticket_card.dart';

class JourneysStrip extends StatelessWidget {
  const JourneysStrip({super.key, required this.journeysAsync});
  final AsyncValue<List<ActiveJourneyEntry>> journeysAsync;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return journeysAsync.when(
      data: (entries) {
        if (entries.isEmpty) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
              decoration: BoxDecoration(
                color: colors.cardSoft,
                borderRadius: BorderRadius.circular(context.spacing.radiusCard),
                border: Border.all(color: colors.rule, width: 0.5),
              ),
              child: Row(
                children: [
                  Icon(
                    Iconsax.calendar_1,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.l10n.homeNoUpcomingJourneys,
                      style: AppTypography.sans(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                // #626: isolate each card's procedural cover + frosted
                // date-pill blur raster — the strip is an eager Row in a
                // SingleChildScrollView, which adds no per-child boundary.
                RepaintBoundary(
                  child: JourneyTicketCard(
                    entry: entries[i],
                    // Deliberately SINGLE push (#996): an event-intent tap —
                    // Back returns here, not to the group overview. Don't
                    // "fix" this into the group-row double-push.
                    onTap: () => context.push(
                      '/group/${entries[i].groupId}/event/${entries[i].eventId}',
                    ),
                  ),
                ),
                if (i < entries.length - 1)
                  SizedBox(width: context.spacing.space12),
              ],
            ],
          ),
        );
      },
      loading: () => SizedBox(
        height: 200,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
          child: Container(
            decoration: BoxDecoration(
              color: colors.cardSoft,
              borderRadius: BorderRadius.circular(context.spacing.radiusCard),
            ),
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

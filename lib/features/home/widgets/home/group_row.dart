import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../shared/widgets/r_amount.dart';
import '../../../../shared/widgets/skeleton_loader.dart';
import '../../../groups/models/group_model.dart';
import '../../../groups/providers/group_balance_provider.dart';
import '../../../ledger/providers/expense_provider.dart';
import '../../keys/home_keys.dart';
import '../group_glyph.dart';

class GroupRow extends ConsumerWidget {
  const GroupRow({
    super.key,
    required this.group,
    required this.onTap,
    required this.isLast,
    this.isPlaceholder = false,
  });

  final Group group;
  final VoidCallback onTap;
  final bool isLast;

  /// A skeleton stub row (fake `sk1`/`sk2` gid). It must NOT watch the balance
  /// facade — that family is keyed by gid, so watching it with a sentinel id
  /// opens a real `groups/sk1/aggregates/balance` listen that fails
  /// PERMISSION_DENIED and (non-autoDispose) leaks for the session (#1017).
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    // #366: source-agnostic facade — the server aggregate when online, the
    // #104 once-path otherwise. The facade slices by the current uid itself.
    // #1017: placeholder rows render as loading without watching (see field).
    final balanceAsync = isPlaceholder
        ? const AsyncValue<HomeGroupBalance>.loading()
        : ref.watch(homeGroupBalanceProvider(group.id));
    final memberCount = group.memberIds.length;
    // #997: a loading/errored facade has no reliable event count or money —
    // rendering "0 events · settled" from the default would be a false
    // negative. Only a resolved AsyncValue (data, even if partial) drives the
    // subtitle event count and the trailing amount/caption below.
    final isLoading = balanceAsync.isLoading && !balanceAsync.hasValue;
    final isError = balanceAsync.hasError && !balanceAsync.hasValue;
    final homeBalance = isLoading || isError ? null : balanceAsync.valueOrNull;
    final subtitle = homeBalance == null
        ? context.l10n.homeGroupSubtitlePending(memberCount)
        : context.l10n.homeGroupSubtitle(memberCount, homeBalance.eventCount);

    // Every non-zero bucket renders as its own line, GCC-first, each labeled
    // with its own currency (honest — D11). Settled ⇔ every bucket zero or
    // the map is empty (D10).
    final lines = nonZeroNetsGccFirst(
      homeBalance?.userNet ?? const <String, Decimal>{},
    );
    final allPositive =
        lines.isNotEmpty && lines.every((l) => l.net > Decimal.zero);
    final allNegative =
        lines.isNotEmpty && lines.every((l) => l.net < Decimal.zero);
    // L7: tri-state caption only when all non-zero lines share one sign;
    // mixed signs → omitted (signed, toned amounts self-explain).
    final String? balanceCaption = lines.isEmpty
        ? context.l10n.homeSettled
        : allPositive
        ? context.l10n.homeTheyOweYou
        : allNegative
        ? context.l10n.homeYouOwe
        : null;

    final Widget trailing;
    if (isLoading) {
      trailing = KeyedSubtree(
        key: HomeKeys.groupRowBalanceSkeleton,
        child: SkeletonLoader.trailingBalance(),
      );
    } else if (isError) {
      trailing = Row(
        key: HomeKeys.groupRowBalanceError,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Iconsax.warning_2, size: 14, color: colors.warning),
          SizedBox(width: context.spacing.space4),
          Flexible(
            child: Text(
              context.l10n.homeBalanceUnavailable,
              textAlign: TextAlign.end,
              style: AppTypography.sans(fontSize: 11, color: colors.textSecondary),
            ),
          ),
        ],
      );
    } else {
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lines.isEmpty)
            RAmount(
              value: Decimal.zero,
              currency: group.currency,
              size: 16,
            )
          else
            for (var i = 0; i < lines.length; i++)
              Padding(
                padding: EdgeInsetsDirectional.only(top: i == 0 ? 0 : 2),
                child: RAmount(
                  value: lines[i].net,
                  currency: lines[i].currency,
                  size: lines.length == 1 ? 16 : 14,
                  sign: true,
                ),
              ),
          if (balanceCaption != null) ...[
            const SizedBox(height: 2),
            Text(
              balanceCaption,
              style: AppTypography.sans(fontSize: 11, color: colors.textSecondary),
            ),
          ],
          // #997/#244: the facade resolved but dropped some money (a
          // per-event read failed) — the numbers above are a partial sum,
          // not the full picture. Row is too narrow for the hero's full
          // homeBalanceIncompleteNotice sentence, hence the short row key.
          if (homeBalance?.partial ?? false) ...[
            const SizedBox(height: 2),
            Row(
              key: HomeKeys.groupRowBalanceIncomplete,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Iconsax.warning_2, size: 11, color: colors.warning),
                SizedBox(width: context.spacing.space4),
                Text(
                  context.l10n.homeGroupBalanceIncomplete,
                  style: AppTypography.sans(
                    fontSize: 10,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GroupGlyph(
                  name: group.name,
                  glyph: group.glyph,
                  inkIndex: group.inkIndex,
                ),
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.sans(
                          fontSize: 12,
                          color: colors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
            if (!isLast) ...[
              const SizedBox(height: 14),
              Container(height: 0.5, color: colors.rule),
            ],
          ],
        ),
      ),
    );
  }
}

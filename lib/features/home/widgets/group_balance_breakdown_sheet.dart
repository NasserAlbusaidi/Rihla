import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../groups/models/group_model.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../../ledger/providers/expense_provider.dart' show nonZeroNetsGccFirst;
import '../keys/home_keys.dart';

typedef _GroupBalanceEntry = ({
  Group group,
  List<({String currency, Decimal net})> lines,
});

/// Per-group balance breakdown opened from the balance hero's tap
/// (friction #4 / PR-5 §3 — the hero previously only scrolled to the
/// journeys strip, discarding the money intent).
///
/// One row per group with a non-zero net, one [RAmount] per non-zero
/// CURRENCY bucket (#382 — amounts in different currencies are NEVER
/// summed, so a two-currency group renders two `RAmount`s). Tapping a row
/// pushes the group's settle-up screen WITHOUT a `memberId` — the hero net
/// is not member-specific (a real per-member preselect would need a
/// per-member hero row, which doesn't exist yet; job-4 tap count honestly
/// stays 4, see the spec's O3 correction).
class GroupBalanceBreakdownSheet extends ConsumerWidget {
  const GroupBalanceBreakdownSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const GroupBalanceBreakdownSheet(),
    );
  }

  void _openSettleUp(BuildContext context, String groupId) {
    HapticService.lightClick();
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push('/group/$groupId/settle-up');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(userGroupsProvider);

    Widget body;
    if (groupsAsync.hasError) {
      body = _Message(text: context.l10n.settleUpCouldNotLoadBalances);
    } else if (!groupsAsync.hasValue) {
      body = const _Loading();
    } else {
      // #366: source-agnostic facade, same read as the home groups list
      // (`home_screen.dart` `_GroupRow`) and the journeys strip
      // (`active_journeys_provider.dart:313`) — no new provider.
      final entries = <_GroupBalanceEntry>[];
      for (final group in groupsAsync.value!) {
        final userNet =
            ref.watch(homeGroupBalanceProvider(group.id)).valueOrNull?.userNet ??
            const <String, Decimal>{};
        final lines = nonZeroNetsGccFirst(userNet);
        if (lines.isNotEmpty) {
          entries.add((group: group, lines: lines));
        }
      }
      body = entries.isEmpty
          ? _EmptyBody(text: context.l10n.heroBreakdownEmpty)
          : _RowsList(
              entries: entries,
              onTapGroup: (groupId) => _openSettleUp(context, groupId),
            );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Padding(
          key: HomeKeys.heroBreakdownSheet,
          padding: EdgeInsetsDirectional.only(
            start: context.spacing.space24,
            end: context.spacing.space24,
            top: context.spacing.space16,
            bottom: context.spacing.space16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.heroBreakdownTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              SizedBox(height: context.spacing.space8),
              Flexible(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowsList extends StatelessWidget {
  const _RowsList({required this.entries, required this.onTapGroup});

  final List<_GroupBalanceEntry> entries;
  final ValueChanged<String> onTapGroup;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      itemCount: entries.length,
      separatorBuilder: (_, _) =>
          Container(height: 0.5, color: context.colors.rule),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _GroupBalanceRow(
          group: entry.group,
          lines: entry.lines,
          onTap: () => onTapGroup(entry.group.id),
        );
      },
    );
  }
}

/// Same shape as `home_screen.dart` `_GroupRow`'s trailing column: one
/// [RAmount] per non-zero currency bucket, plus the tri-state caption
/// reusing `homeTheyOweYou`/`homeYouOwe`/`homeSettled` — mixed signs across
/// a group's own buckets omit the caption (L7), matching the groups list.
class _GroupBalanceRow extends StatelessWidget {
  const _GroupBalanceRow({
    required this.group,
    required this.lines,
    required this.onTap,
  });

  final Group group;
  final List<({String currency, Decimal net})> lines;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final allPositive =
        lines.isNotEmpty && lines.every((l) => l.net > Decimal.zero);
    final allNegative =
        lines.isNotEmpty && lines.every((l) => l.net < Decimal.zero);
    final String? caption = lines.isEmpty
        ? context.l10n.homeSettled
        : allPositive
        ? context.l10n.homeTheyOweYou
        : allNegative
        ? context.l10n.homeYouOwe
        : null;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ),
            SizedBox(width: context.spacing.space12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
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
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    style: AppTypography.sans(
                      fontSize: 11,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.space24),
      child: Text(
        text,
        style: TextStyle(color: context.colors.textSecondary),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.space24),
      child: Text(
        text,
        style: TextStyle(color: context.colors.textSecondary),
      ),
    );
  }
}

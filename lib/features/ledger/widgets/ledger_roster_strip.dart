import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../groups/services/member_name_resolver.dart';

/// Roster strip state.
///   live    — show signed amounts (sage positive, rust negative)
///   settled — show "EVEN" chips
///   empty   — dimmed avatars with dashed em-dash chips
enum LedgerRosterState { live, settled, empty }

/// One person's roster row data — their OWN standing vs the event (#998).
///
/// `signedAmount` is the member's event net, same convention as the hero's
/// "You" line — NOT a pairwise you↔them amount:
///   positive → the group owes them OMR X.XXX (sage)
///   negative → they owe the group OMR X.XXX (rust)
///   zero     → they're settled
class LedgerRosterPerson {
  const LedgerRosterPerson({
    required this.participantId,
    required this.displayName,
    required this.signedAmount,
    this.currency,
  });

  final String participantId;
  final String displayName;
  final Decimal signedAmount;

  /// This entry's bucket currency (#382 PR-5) — the screen emits one entry
  /// per (person, non-zero bucket). Null → the strip-level fallback currency.
  final String? currency;
}

class LedgerRosterStrip extends StatelessWidget {
  const LedgerRosterStrip({
    super.key,
    required this.state,
    required this.others,
    required this.currency,
    required this.currentUserDisplayName,
    this.onPersonTap,
  });

  final LedgerRosterState state;
  final List<LedgerRosterPerson> others;
  final String currency;
  final String currentUserDisplayName;
  final ValueChanged<LedgerRosterPerson>? onPersonTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 128,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
        children: [
          _YouAnchor(displayName: currentUserDisplayName),
          for (final p in others) ...[
            const SizedBox(width: 18),
            _RosterTile(
              person: p,
              state: state,
              currency: currency,
              onTap: onPersonTap == null ? null : () => onPersonTap!(p),
            ),
          ],
        ],
      ),
    );
  }
}

class _YouAnchor extends StatelessWidget {
  const _YouAnchor({required this.displayName});
  final String displayName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              RAvatar(name: displayName, size: 44),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: colors.textPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.scaffoldBackground,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    context.l10n.ledgerYou,
                    style: AppTypography.sans(
                      fontSize: 8,
                      color: colors.scaffoldBackground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.ledgerYou,
          style: AppTypography.sans(
            fontSize: 11,
            color: colors.ink2,
            fontWeight: FontWeight.w500,
            height: 1.2,
          ),
        ),
        SizedBox(height: context.spacing.space4),
        Text(
          '—',
          style: AppTypography.mono(
            fontSize: 10,
            // textMuted-decorative-justified: anchor em-dash is a structural placeholder under "You", not a functional label.
            color: colors.textMuted,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _RosterTile extends StatelessWidget {
  const _RosterTile({
    required this.person,
    required this.state,
    required this.currency,
    this.onTap,
  });

  final LedgerRosterPerson person;
  final LedgerRosterState state;
  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isEmpty = state == LedgerRosterState.empty;
    final isSettled = state == LedgerRosterState.settled;

    return Opacity(
      opacity: isEmpty ? 0.55 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RAvatar(name: person.displayName, size: 44),
              const SizedBox(height: 6),
              Text(
                _shortName(person.displayName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.sans(
                  fontSize: 11,
                  color: colors.ink2,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              _Chip(
                person: person,
                state: state,
                currency: currency,
                isEmpty: isEmpty,
                isSettled: isSettled,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _shortName(String full) {
    // #289: collapse to first name but keep the ` (#…)` discriminator so two
    // same-named members stay distinct in the roster.
    return MemberNameResolver.compactDisambiguated(full.trim());
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.person,
    required this.state,
    required this.currency,
    required this.isEmpty,
    required this.isSettled,
  });

  final LedgerRosterPerson person;
  final LedgerRosterState state;
  final String currency;
  final bool isEmpty;
  final bool isSettled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (isEmpty) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space8,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: colors.rule2, width: 1),
          borderRadius: BorderRadius.circular(context.spacing.radiusPill),
        ),
        child: Text(
          '—',
          style: AppTypography.mono(
            fontSize: 9.5,
            // textMuted-decorative-justified: empty-state chip em-dash signals "no value yet"; not a functional amount.
            color: colors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (isSettled || person.signedAmount == Decimal.zero) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space8,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: colors.cardSoft,
          borderRadius: BorderRadius.circular(context.spacing.radiusPill),
        ),
        child: Text(
          context.l10n.ledgerEven,
          style: AppTypography.caption(
            context,
            fontSize: 9.5,
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      );
    }
    final positive = person.signedAmount > Decimal.zero;
    final bg = positive
        ? colors.success.withValues(alpha: 0.18)
        : colors.error.withValues(alpha: 0.16);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.space8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(context.spacing.radiusPill),
      ),
      // #569: never wrap a long signed-balance string to a second line (it blew
      // the strip's fixed 102px band by ~3px on large / 3-decimal multi-currency
      // balances). Shrink-to-fit keeps every digit visible instead of clipping.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: RAmount(
          value: person.signedAmount,
          currency: person.currency ?? currency,
          size: 9.5,
          sign: true,
          // Text-safe tones + undimmed decimals + full-size sign: at 9.5px
          // over the tinted pill, the surface sage/rust tones, the 0.7-alpha
          // decimal fade, AND the 0.42×/0.78-alpha sign prefix all fall below
          // legibility — every glyph renders full-strength successText/
          // errorText and the sign keeps full size (the only non-color
          // polarity cue), matching the pre-RAmount hand-rolled chip.
          tone: positive ? AmountTone.sageText : AmountTone.rustText,
          dimDecimals: false,
          fullSizeSign: true,
          showCurrency: false,
          weight: FontWeight.w600,
        ),
      ),
    );
  }
}

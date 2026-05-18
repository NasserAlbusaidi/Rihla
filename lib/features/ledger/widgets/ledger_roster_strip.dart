import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/r_avatar.dart';

/// Roster strip state.
///   live    — show signed amounts (sage positive, rust negative)
///   settled — show "EVEN" chips
///   empty   — dimmed avatars with dashed em-dash chips
enum LedgerRosterState { live, settled, empty }

/// One person's roster row data — from the *current user's* perspective.
///
/// `signedAmount`:
///   positive → "they owe you OMR X.XXX" (sage)
///   negative → "you owe them OMR X.XXX" (rust)
///   zero     → settled with them
class LedgerRosterPerson {
  const LedgerRosterPerson({
    required this.participantId,
    required this.displayName,
    required this.signedAmount,
  });

  final String participantId;
  final String displayName;
  final Decimal signedAmount;
}

class LedgerRosterStrip extends StatelessWidget {
  const LedgerRosterStrip({
    super.key,
    required this.state,
    required this.others,
    required this.currentUserDisplayName,
    this.onPersonTap,
  });

  final LedgerRosterState state;
  final List<LedgerRosterPerson> others;
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
        const SizedBox(height: 4),
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
  const _RosterTile({required this.person, required this.state, this.onTap});

  final LedgerRosterPerson person;
  final LedgerRosterState state;
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
    final trimmed = full.trim();
    final spaceIdx = trimmed.indexOf(' ');
    return spaceIdx == -1 ? trimmed : trimmed.substring(0, spaceIdx);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.person,
    required this.state,
    required this.isEmpty,
    required this.isSettled,
  });

  final LedgerRosterPerson person;
  final LedgerRosterState state;
  final bool isEmpty;
  final bool isSettled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: colors.rule2, width: 1),
          borderRadius: BorderRadius.circular(9999),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: colors.cardSoft,
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          context.l10n.ledgerEven,
          style: AppTypography.mono(
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
    final fg = positive ? colors.successText : colors.errorText;
    final prefix = positive ? '+' : '−';
    final abs = person.signedAmount.abs().toStringAsFixed(3);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        '$prefix$abs',
        style: AppTypography.mono(
          fontSize: 9.5,
          color: fg,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

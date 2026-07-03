part of 'custom_split_sheet.dart';

// ───────────────────────── sheet chrome: header + footer
//
// The fixed top header (title + bill total) and the bottom footer with its
// reconcile/status pill. A part-of the custom_split_sheet library, so these
// widgets stay private and share the entry file's imports. Pure presentation:
// _StatusPill only reads pre-computed remainder props from the sheet state —
// no allocation lives here.

// ───────────────────────────────────────────────────────────────── header

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.total,
    required this.currency,
  });

  final String title;
  final Decimal total;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.customSplitHow,
            style: AppTypography.displayOf(
              context,
              fontSize: 26,
              color: colors.textPrimary,
              height: 1.15,
            ),
          ),
          SizedBox(height: context.spacing.space4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$title · ',
                style: AppTypography.sans(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
              RAmount(
                value: total,
                currency: currency,
                size: 12,
                weight: FontWeight.w600,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── footer

class _Footer extends StatelessWidget {
  const _Footer({
    required this.itemized,
    required this.mode,
    required this.total,
    required this.currency,
    required this.exactSum,
    required this.exactRemainder,
    required this.percentSum,
    required this.percentRemainder,
    required this.itemizedSum,
    required this.itemizedRemainder,
    required this.canApply,
  });

  final bool itemized;
  final SplitMode mode;
  final Decimal total;
  final String currency;
  final Decimal exactSum;
  final Decimal exactRemainder;
  final Decimal percentSum;
  final Decimal percentRemainder;
  final Decimal itemizedSum;
  final Decimal itemizedRemainder;
  final bool canApply;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.space24,
        spacing.space12,
        spacing.space24,
        spacing.space16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            // Itemized's footer reads "Items match total"; the modes read "TOTAL".
            itemized
                ? context.l10n.itemizedItemsMatchTotal
                : context.l10n.customSplitTotal,
            style: AppTypography.caption(
              context,
              fontSize: 10,
              letterSpacing: 1.5,
              color: colors.textSecondary,
            ),
          ),
          Flexible(
            child: Row(
              key: const Key('split_sheet_footer'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _StatusPill(
                  itemized: itemized,
                  mode: mode,
                  canApply: canApply,
                  exactRemainder: exactRemainder,
                  percentRemainder: percentRemainder,
                  itemizedRemainder: itemizedRemainder,
                  currency: currency,
                ),
                const SizedBox(width: 10),
                RAmount(value: _displaySum(), currency: currency, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Decimal _displaySum() {
    if (itemized) return itemizedSum;
    switch (mode) {
      case SplitMode.equally:
      case SplitMode.shares:
        return total;
      case SplitMode.exact:
        return exactSum;
      case SplitMode.percent:
        return total; // Percent mode shows the trip total alongside the % status pill
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.itemized,
    required this.mode,
    required this.canApply,
    required this.exactRemainder,
    required this.percentRemainder,
    required this.itemizedRemainder,
    required this.currency,
  });

  final bool itemized;
  final SplitMode mode;
  final bool canApply;
  final Decimal exactRemainder;
  final Decimal percentRemainder;
  final Decimal itemizedRemainder;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (text, color) = _statusFor(context, colors);
    return Text(
      text,
      // #144: money status ('−OMR 2.500') stays LTR even in Arabic so the
      // sign / code / amount don't reorder.
      textDirection: TextDirection.ltr,
      style: AppTypography.mono(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }

  (String, Color) _statusFor(BuildContext context, dynamic colors) {
    if (itemized) {
      // Reconciled: amounts add up AND every row has an assignee (canApply).
      if (canApply) return ('✓', colors.success as Color);
      // Otherwise surface the remaining gap to the bill total (rust).
      final abs = itemizedRemainder.abs();
      final formatted = AppFormatters.formatCurrency(abs, currency);
      return (context.l10n.itemizedAmountLeft(formatted), colors.error as Color);
    }
    switch (mode) {
      case SplitMode.equally:
      case SplitMode.shares:
        return ('100 %', colors.success as Color);
      case SplitMode.exact:
        if (canApply) return ('100 %', colors.success as Color);
        final r = exactRemainder;
        final sign = r > Decimal.zero ? '−' : '+';
        final abs = r.abs();
        final formatted = AppFormatters.formatCurrency(abs, currency);
        return (
          '$sign$formatted',
          colors.error as Color,
        );
      case SplitMode.percent:
        if (canApply) return ('100 %', colors.success as Color);
        final r = percentRemainder;
        final sign = r > Decimal.zero ? '−' : '+';
        return ('$sign${r.abs().toString()} %', colors.error as Color);
    }
  }
}

part of 'custom_split_sheet.dart';

// ───────────────────────── per-mode input controls
//
// _Editor switches on the active SplitMode to render the read-only equal
// readout, the shares stepper, or the exact/percent number input. It binds the
// TextEditingControllers it RECEIVES from _CustomSplitSheetState — it never
// constructs or disposes them. A part-of the custom_split_sheet library.
// NOTE: _EqualReadout holds a display-only per-head division; equal mode is not
// persisted (distribution: null), so do not "tidy" or re-quantize its math.

class _Editor extends StatelessWidget {
  const _Editor({
    required this.mode,
    required this.total,
    required this.currency,
    required this.shares,
    required this.participantId,
    required this.totalShares,
    required this.exactCtrl,
    required this.percentCtrl,
    required this.onSharesChanged,
    required this.onAmountChanged,
    required this.equalCount,
  });

  final SplitMode mode;
  final Decimal total;
  final String currency;
  final Map<String, int> shares;
  final String participantId;
  final int totalShares;
  final TextEditingController? exactCtrl;
  final TextEditingController? percentCtrl;
  final VoidCallback onSharesChanged;
  final VoidCallback onAmountChanged;
  final int equalCount;

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case SplitMode.equally:
        return _EqualReadout(
          total: total,
          currency: currency,
          equalCount: equalCount,
        );
      case SplitMode.shares:
        return _SharesStepper(
          value: shares[participantId] ?? 0,
          onChanged: (next) {
            shares[participantId] = next;
            onSharesChanged();
          },
        );
      case SplitMode.exact:
        return _NumberInput(
          key: Key('split_exact_$participantId'),
          controller: exactCtrl!,
          suffix: currency,
          decimalDigits: AppFormatters.currencyConfig[currency]?.decimals ?? 3,
          onChanged: onAmountChanged,
        );
      case SplitMode.percent:
        return _NumberInput(
          key: Key('split_percent_$participantId'),
          controller: percentCtrl!,
          suffix: '%',
          decimalDigits: 3,
          onChanged: onAmountChanged,
        );
    }
  }
}

class _EqualReadout extends StatelessWidget {
  const _EqualReadout({
    required this.total,
    required this.currency,
    required this.equalCount,
  });

  final Decimal total;
  final String currency;
  final int equalCount;

  @override
  Widget build(BuildContext context) {
    final share = equalCount == 0
        ? Decimal.zero
        : (total / Decimal.fromInt(equalCount)).toDecimal(
            scaleOnInfinitePrecision: 3,
          );
    final pct = equalCount == 0 ? 0 : (100 / equalCount);
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: context.spacing.space8,
            vertical: context.spacing.space4,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: colors.rule2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${pct.round()} %',
            style: AppTypography.mono(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
        SizedBox(height: context.spacing.space4),
        RAmount(
          value: share,
          currency: currency,
          size: 11,
          weight: FontWeight.w500,
        ),
      ],
    );
  }
}

class _SharesStepper extends StatelessWidget {
  const _SharesStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 44,
      child: Stack(
        children: [
          PositionedDirectional(
            start: 0,
            end: 0,
            top: 4,
            bottom: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.rule2),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: 44,
            child: _StepperButton(
              icon: Icons.remove,
              enabled: value > 0,
              visualAlignment: AlignmentDirectional.centerStart,
              onTap: () {
                HapticService.selection();
                onChanged((value - 1).clamp(0, 99));
              },
            ),
          ),
          PositionedDirectional(
            start: 36,
            top: 0,
            bottom: 0,
            width: context.spacing.space32,
            child: Center(
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: AppTypography.mono(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
          PositionedDirectional(
            start: 64,
            top: 0,
            bottom: 0,
            width: 44,
            child: _StepperButton(
              icon: Icons.add,
              enabled: value < 99,
              onTap: () {
                HapticService.selection();
                onChanged((value + 1).clamp(0, 99));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.visualAlignment = Alignment.center,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final AlignmentGeometry visualAlignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Align(
        alignment: visualAlignment,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 16,
            color: enabled ? colors.textPrimary : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _NumberInput extends StatelessWidget {
  const _NumberInput({
    super.key,
    required this.controller,
    required this.suffix,
    required this.decimalDigits,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String suffix;
  final int decimalDigits;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
        inputFormatters: [
          LocalizedDecimalTextInputFormatter(decimalDigits: decimalDigits),
        ],
        style: AppTypography.mono(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
        decoration: InputDecoration(
          suffixText: suffix,
          suffixStyle: AppTypography.mono(
            fontSize: 12,
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: context.spacing.space8,
            vertical: context.spacing.space8,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.rule2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.primary, width: 1.2),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.rule2),
          ),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

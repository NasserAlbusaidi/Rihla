import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/models/split_mode.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/localized_decimal_input.dart';
import '../../../core/utils/split_mode_display_name.dart';
import '../../../shared/widgets/r_amount.dart';

export '../../../core/models/split_mode.dart' show SplitMode;

/// Result returned by [showCustomSplitSheet]. `distribution` is null when
/// [mode] is [SplitMode.equally] — the legacy equal split path in
/// `BalanceCalculator` handles that case, so we deliberately do NOT persist a
/// distribution map for it.
class SplitResult {
  const SplitResult({required this.mode, required this.distribution});

  final SplitMode mode;
  final Map<String, Decimal>? distribution;
}

/// Bottom-sheet split editor. Supports four modes:
///   - [SplitMode.equally]: read-only equal share preview.
///   - [SplitMode.shares]: integer stepper per participant (weighted).
///   - [SplitMode.exact]: per-participant exact amount inputs; sum must
///     match [total] within 0.001.
///   - [SplitMode.percent]: per-participant percent inputs; sum must reach
///     100 within 0.001.
///
/// Returns `null` on cancel/dismiss, or a [SplitResult] when Apply is tapped.
Future<SplitResult?> showCustomSplitSheet(
  BuildContext context, {
  required String title,
  required Decimal total,
  required String currency,
  required List<SplitParticipant> participants,
  SplitMode initialMode = SplitMode.equally,
  Map<String, Decimal>? initialDistribution,
}) {
  return showModalBottomSheet<SplitResult>(
    context: context,
    backgroundColor: context.colors.scaffoldBackground,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => CustomSplitSheet(
      title: title,
      total: total,
      currency: currency,
      participants: participants,
      initialMode: initialMode,
      initialDistribution: initialDistribution,
    ),
  );
}

class SplitParticipant {
  const SplitParticipant({required this.id, required this.name, this.role});

  final String id;
  final String name;

  /// Optional small caption shown next to the name (e.g. "You", "Paid").
  final String? role;
}

class CustomSplitSheet extends StatefulWidget {
  const CustomSplitSheet({
    super.key,
    required this.title,
    required this.total,
    required this.currency,
    required this.participants,
    this.initialMode = SplitMode.equally,
    this.initialDistribution,
  });

  final String title;
  final Decimal total;
  final String currency;
  final List<SplitParticipant> participants;
  final SplitMode initialMode;
  final Map<String, Decimal>? initialDistribution;

  @override
  State<CustomSplitSheet> createState() => _CustomSplitSheetState();
}

class _CustomSplitSheetState extends State<CustomSplitSheet> {
  static final Decimal _tolerance = Decimal.parse('0.001');
  static final Decimal _hundred = Decimal.fromInt(100);

  late SplitMode _mode;

  // Per-mode state. Each map is keyed by participant id.
  late Map<String, int> _shares;
  late Map<String, TextEditingController> _exactCtrls;
  late Map<String, TextEditingController> _percentCtrls;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _initShares();
    _initExact();
    _initPercent();
  }

  @override
  void dispose() {
    for (final c in _exactCtrls.values) {
      c.dispose();
    }
    for (final c in _percentCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _initShares() {
    _shares = {
      for (final p in widget.participants) p.id: _readInitialShare(p.id) ?? 1,
    };
  }

  void _initExact() {
    _exactCtrls = {
      for (final p in widget.participants)
        p.id: TextEditingController(text: _readInitialExact(p.id)),
    };
  }

  void _initPercent() {
    _percentCtrls = {
      for (final p in widget.participants)
        p.id: TextEditingController(text: _readInitialPercent(p.id)),
    };
  }

  int? _readInitialShare(String id) {
    if (widget.initialMode != SplitMode.shares) return null;
    final v = widget.initialDistribution?[id];
    if (v == null) return null;
    return v.toBigInt().toInt();
  }

  String _readInitialExact(String id) {
    if (widget.initialMode != SplitMode.exact) return '';
    final v = widget.initialDistribution?[id];
    if (v == null) return '';
    return _formatPlainDecimal(v);
  }

  String _readInitialPercent(String id) {
    if (widget.initialMode != SplitMode.percent) return '';
    final v = widget.initialDistribution?[id];
    if (v == null) return '';
    return _formatPlainDecimal(v);
  }

  static String _formatPlainDecimal(Decimal v) {
    final s = v.toString();
    if (!s.contains('.')) return s;
    // Trim trailing zeros so "1.000" → "1" and "12.500" → "12.5".
    var trimmed = s.replaceFirst(RegExp(r'0+$'), '');
    if (trimmed.endsWith('.')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  // ───────────────────────────────────────────────────── live computations

  Decimal get _exactSum {
    var sum = Decimal.zero;
    for (final c in _exactCtrls.values) {
      final v = Decimal.tryParse(c.text);
      if (v != null) sum += v;
    }
    return sum;
  }

  Decimal get _percentSum {
    var sum = Decimal.zero;
    for (final c in _percentCtrls.values) {
      final v = Decimal.tryParse(c.text);
      if (v != null) sum += v;
    }
    return sum;
  }

  int get _totalShares => _shares.values.fold(0, (acc, v) => acc + v);

  Decimal get _exactRemainder => widget.total - _exactSum;

  Decimal get _percentRemainder => _hundred - _percentSum;

  bool get _canApply {
    if (widget.participants.isEmpty) return false;
    switch (_mode) {
      case SplitMode.equally:
        return true;
      case SplitMode.shares:
        return _totalShares > 0;
      case SplitMode.exact:
        return _exactRemainder.abs() <= _tolerance;
      case SplitMode.percent:
        return _percentRemainder.abs() <= _tolerance;
    }
  }

  // ───────────────────────────────────────────────────── apply

  void _apply() {
    HapticService.medium();
    final result = _buildResult();
    Navigator.of(context).pop(result);
  }

  SplitResult _buildResult() {
    switch (_mode) {
      case SplitMode.equally:
        return const SplitResult(mode: SplitMode.equally, distribution: null);
      case SplitMode.shares:
        return SplitResult(
          mode: SplitMode.shares,
          distribution: {
            for (final p in widget.participants)
              p.id: Decimal.fromInt(_shares[p.id] ?? 0),
          },
        );
      case SplitMode.exact:
        return SplitResult(
          mode: SplitMode.exact,
          distribution: {
            for (final p in widget.participants)
              p.id:
                  Decimal.tryParse(_exactCtrls[p.id]?.text ?? '') ??
                  Decimal.zero,
          },
        );
      case SplitMode.percent:
        return SplitResult(
          mode: SplitMode.percent,
          distribution: {
            for (final p in widget.participants)
              p.id:
                  Decimal.tryParse(_percentCtrls[p.id]?.text ?? '') ??
                  Decimal.zero,
          },
        );
    }
  }

  // ───────────────────────────────────────────────────── build

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: spacing.space12),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.rule2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: spacing.space12),
            _Header(
              title: widget.title,
              total: widget.total,
              currency: widget.currency,
            ),
            SizedBox(height: spacing.space16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.space24),
              child: _ModeSegmented(
                mode: _mode,
                onChanged: (next) {
                  HapticService.selection();
                  setState(() => _mode = next);
                },
              ),
            ),
            SizedBox(height: spacing.space16),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: spacing.space24),
                child: _ModeBody(
                  key: ValueKey(_mode),
                  mode: _mode,
                  participants: widget.participants,
                  total: widget.total,
                  currency: widget.currency,
                  shares: _shares,
                  exactCtrls: _exactCtrls,
                  percentCtrls: _percentCtrls,
                  totalShares: _totalShares,
                  onSharesChanged: () => setState(() {}),
                  onAmountChanged: () => setState(() {}),
                ),
              ),
            ),
            _Footer(
              mode: _mode,
              total: widget.total,
              currency: widget.currency,
              exactSum: _exactSum,
              exactRemainder: _exactRemainder,
              percentSum: _percentSum,
              percentRemainder: _percentRemainder,
              canApply: _canApply,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.space24,
                0,
                spacing.space24,
                spacing.space20,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colors.rule2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          context.l10n.customSplitCancel,
                          style: AppTypography.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        key: const Key('split_sheet_apply'),
                        onPressed: _canApply ? _apply : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.textOnPrimary,
                          disabledBackgroundColor: colors.primary.withValues(
                            alpha: 0.35,
                          ),
                          disabledForegroundColor: colors.textOnPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          context.l10n.customSplitApply,
                          style: AppTypography.sans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: colors.textOnPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
            style: AppTypography.display(
              fontSize: 26,
              color: colors.textPrimary,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 4),
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

// ───────────────────────────────────────────────────────────── segmented

class _ModeSegmented extends StatelessWidget {
  const _ModeSegmented({required this.mode, required this.onChanged});

  final SplitMode mode;
  final ValueChanged<SplitMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final m in SplitMode.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(m),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: m == mode ? colors.cardSurface : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: m == mode ? context.shadows.raised : null,
                  ),
                  child: Text(
                    splitModeDisplayName(m, context.l10n),
                    style: AppTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: m == mode
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────── mode body

class _ModeBody extends StatelessWidget {
  const _ModeBody({
    super.key,
    required this.mode,
    required this.participants,
    required this.total,
    required this.currency,
    required this.shares,
    required this.exactCtrls,
    required this.percentCtrls,
    required this.totalShares,
    required this.onSharesChanged,
    required this.onAmountChanged,
  });

  final SplitMode mode;
  final List<SplitParticipant> participants;
  final Decimal total;
  final String currency;
  final Map<String, int> shares;
  final Map<String, TextEditingController> exactCtrls;
  final Map<String, TextEditingController> percentCtrls;
  final int totalShares;
  final VoidCallback onSharesChanged;
  final VoidCallback onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < participants.length; i++)
            _ParticipantRow(
              participant: participants[i],
              mode: mode,
              total: total,
              currency: currency,
              shares: shares,
              totalShares: totalShares,
              exactCtrl: exactCtrls[participants[i].id],
              percentCtrl: percentCtrls[participants[i].id],
              showDivider: i < participants.length - 1,
              onSharesChanged: onSharesChanged,
              onAmountChanged: onAmountChanged,
              equalCount: participants.length,
            ),
        ],
      ),
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.mode,
    required this.total,
    required this.currency,
    required this.shares,
    required this.totalShares,
    required this.exactCtrl,
    required this.percentCtrl,
    required this.showDivider,
    required this.onSharesChanged,
    required this.onAmountChanged,
    required this.equalCount,
  });

  final SplitParticipant participant;
  final SplitMode mode;
  final Decimal total;
  final String currency;
  final Map<String, int> shares;
  final int totalShares;
  final TextEditingController? exactCtrl;
  final TextEditingController? percentCtrl;
  final bool showDivider;
  final VoidCallback onSharesChanged;
  final VoidCallback onAmountChanged;
  final int equalCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: showDivider ? colors.rule : Colors.transparent,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Avatar(name: participant.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        participant.name,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (participant.role != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        participant.role!,
                        style: AppTypography.sans(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                if (mode == SplitMode.equally || mode == SplitMode.shares)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progressValue,
                        minHeight: 4,
                        backgroundColor: colors.rule,
                        valueColor: AlwaysStoppedAnimation(colors.primary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 124,
            child: _Editor(
              mode: mode,
              total: total,
              currency: currency,
              shares: shares,
              participantId: participant.id,
              totalShares: totalShares,
              exactCtrl: exactCtrl,
              percentCtrl: percentCtrl,
              onSharesChanged: onSharesChanged,
              onAmountChanged: onAmountChanged,
              equalCount: equalCount,
            ),
          ),
        ],
      ),
    );
  }

  double get _progressValue {
    switch (mode) {
      case SplitMode.equally:
        if (equalCount == 0) return 0;
        return 1 / equalCount;
      case SplitMode.shares:
        if (totalShares == 0) return 0;
        return (shares[participant.id] ?? 0) / totalShares;
      case SplitMode.exact:
      case SplitMode.percent:
        return 0;
    }
  }
}

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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        const SizedBox(height: 4),
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
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.rule2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(
            icon: Icons.remove,
            enabled: value > 0,
            onTap: () {
              HapticService.selection();
              onChanged((value - 1).clamp(0, 99));
            },
          ),
          SizedBox(
            width: 32,
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
          _StepperButton(
            icon: Icons.add,
            enabled: value < 99,
            onTap: () {
              HapticService.selection();
              onChanged((value + 1).clamp(0, 99));
            },
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
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          size: 16,
          color: enabled ? colors.textPrimary : colors.textSecondary,
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
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

// ─────────────────────────────────────────────────────────────── footer

class _Footer extends StatelessWidget {
  const _Footer({
    required this.mode,
    required this.total,
    required this.currency,
    required this.exactSum,
    required this.exactRemainder,
    required this.percentSum,
    required this.percentRemainder,
    required this.canApply,
  });

  final SplitMode mode;
  final Decimal total;
  final String currency;
  final Decimal exactSum;
  final Decimal exactRemainder;
  final Decimal percentSum;
  final Decimal percentRemainder;
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
            context.l10n.customSplitTotal,
            style: AppTypography.mono(
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
                  mode: mode,
                  canApply: canApply,
                  exactRemainder: exactRemainder,
                  percentRemainder: percentRemainder,
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
    required this.mode,
    required this.canApply,
    required this.exactRemainder,
    required this.percentRemainder,
    required this.currency,
  });

  final SplitMode mode;
  final bool canApply;
  final Decimal exactRemainder;
  final Decimal percentRemainder;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (text, color) = _statusFor(colors);
    return Text(
      text,
      style: AppTypography.mono(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }

  (String, Color) _statusFor(dynamic colors) {
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
          (r > Decimal.zero ? colors.error : colors.error) as Color,
        );
      case SplitMode.percent:
        if (canApply) return ('100 %', colors.success as Color);
        final r = percentRemainder;
        final sign = r > Decimal.zero ? '−' : '+';
        return ('$sign${r.abs().toString()} %', colors.error as Color);
    }
  }
}

// ───────────────────────────────────────────────────────────────── avatar

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.selectionFill,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '·',
        style: AppTypography.sans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.primary,
        ),
      ),
    );
  }
}

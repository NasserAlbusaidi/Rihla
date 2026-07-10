import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/localized_decimal_input.dart';

class AmountHero extends StatelessWidget {
  const AmountHero({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.amount,
    required this.currency,
    required this.onChanged,
    required this.onTap,
    this.errorText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String amount;
  final String currency;
  final ValueChanged<String> onChanged;
  final VoidCallback onTap;

  /// #1080: persistent field-associated validation error. Non-null turns the
  /// underline into the error color and renders the message under it; the
  /// parent clears it on the next amount edit.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final parts = amount.split('.');
    final whole = parts.first.isEmpty ? '0' : parts.first;
    final rawFraction = parts.length > 1 ? parts.last : '';
    final decimals = AppFormatters.currencyConfig[currency]?.decimals ?? 3;
    // Pad the DISPLAYED fraction to the currency's precision so the live field
    // matches the 3dp shown in the saved expense and summaries (#156). This is
    // display-only: the parsed/persisted Decimal comes from the (transparent)
    // controller, never this string, so padding here cannot change the written
    // value. The untouched default '0' stays a clean unpadded 'OMR 0'.
    final fraction = (amount != '0' && decimals > 0)
        ? '.${rawFraction.padRight(decimals, '0')}'
        : (rawFraction.isEmpty ? '' : '.$rawFraction');
    final colors = context.colors;

    // The label color is deliberately darker than textSecondary — at fontSize
    // 10 with extra letter spacing it can otherwise blend into the cream
    // background on iOS.
    final labelColor = colors.textPrimary.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Forced LTR like the amount Row below — otherwise the composite
              // 'المبلغ · OMR' inherits the ambient RTL and scrambles (#150).
              // Excluded from semantics: the transparent TextField below
              // carries this label as its accessible name (#871) — announcing
              // the caption too would read the name twice.
              ExcludeSemantics(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    context.l10n.editorAmountLabel(currency),
                    style: AppTypography.caption(
                      context,
                      fontSize: 10,
                      letterSpacing: 1.6,
                      color: labelColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              SizedBox(height: context.spacing.space12),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(bottom: context.spacing.space12),
                      child: Text(
                        currency,
                        style: AppTypography.mono(
                          fontSize: 20,
                          color: colors.textSecondary,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      whole,
                      style: AppTypography.mono(
                        fontSize: 64,
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w500,
                        height: 1.05,
                      ),
                    ),
                    if (fraction.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: context.spacing.space8,
                        ),
                        child: Text(
                          fraction,
                          style: AppTypography.mono(
                            fontSize: 28,
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: 120,
                height: 2,
                decoration: BoxDecoration(
                  color: errorText != null ? colors.error : colors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (errorText != null)
                Padding(
                  padding: EdgeInsets.only(top: context.spacing.space8),
                  child: Text(
                    errorText!,
                    textAlign: TextAlign.center,
                    style: AppTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.errorText,
                    ),
                  ),
                ),
            ],
          ),
          Positioned.fill(
            // MergeSemantics folds the label onto the TextField's own
            // semantics node, so TalkBack/VoiceOver announce the name ON the
            // edit box (WCAG 4.1.2, #871) — a plain Semantics wrapper would
            // leave the input itself unnamed. The visible caption above is
            // ExcludeSemantics'd to avoid a double announcement.
            child: MergeSemantics(
              child: Semantics(
                label: context.l10n.editorAmountLabel(currency),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onTap: onTap,
                  onChanged: onChanged,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  // The transparent overlay field only types digits; disabling
                  // interactive selection stops iOS selection handles from sticking
                  // over the amount label (#150). Programmatic select-default-zero
                  // still works (it sets controller.selection directly).
                  enableInteractiveSelection: false,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [
                    LocalizedDecimalTextInputFormatter(
                      decimalDigits:
                          AppFormatters.currencyConfig[currency]?.decimals ?? 3,
                    ),
                  ],
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.transparent),
                  cursorColor: Colors.transparent,
                  decoration: const InputDecoration(
                    filled: false,
                    fillColor: Colors.transparent,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
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

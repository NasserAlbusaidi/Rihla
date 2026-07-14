import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../keys/event_keys.dart';

class AddExpenseFab extends StatelessWidget {
  const AddExpenseFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: EventKeys.addExpenseFab,
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [colors.primary, colors.primaryDark],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: context.shadows.floating,
          ),
          padding: const EdgeInsetsDirectional.fromSTEB(16, 13, 18, 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Iconsax.add, size: 18, color: colors.textOnPrimary),
              const SizedBox(width: 6),
              Text(
                context.l10n.eventAddExpense,
                style: AppTypography.sans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: colors.textOnPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

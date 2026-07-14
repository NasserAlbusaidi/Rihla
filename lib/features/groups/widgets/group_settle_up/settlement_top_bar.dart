import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:go_router/go_router.dart';
import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../shared/widgets/directional_icon.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';

class SettlementTopBar extends StatelessWidget {
  const SettlementTopBar({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 20, 8),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                tooltip: l10n.commonBack,
                icon: const DirectionalIcon(Iconsax.arrow_left_2, size: 20),
                color: context.colors.textPrimary,
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/group/$groupId');
                  }
                },
              ),
            ),
            Text(
              l10n.settleUpTitle,
              style: AppTypography.sans(
                color: context.colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

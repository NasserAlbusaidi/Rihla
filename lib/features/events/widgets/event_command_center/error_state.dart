import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../shared/widgets/empty_state_view.dart';

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(context.spacing.space24),
          child: EmptyStateView(
            icon: Iconsax.warning_2,
            title: context.l10n.eventLoadFailedTitle,
            message: context.l10n.activityLoadFailedMessage,
            actionLabel: context.l10n.commonRetry,
            onAction: onRetry,
          ),
        ),
      ),
    );
  }
}

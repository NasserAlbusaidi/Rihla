import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../shared/widgets/empty_state_view.dart';

class NotFoundState extends StatelessWidget {
  const NotFoundState({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(context.spacing.space24),
          child: EmptyStateView(
            icon: Iconsax.box_remove,
            title: context.l10n.groupNotFoundTitle,
            message: context.l10n.groupNotFoundMessage,
            actionLabel: context.l10n.groupBackHome,
            onAction: () => GoRouter.of(context).go('/home'),
          ),
        ),
      ),
    );
  }
}

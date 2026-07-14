import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/extensions/build_context_l10n.dart';
import '../../core/theme/tokens/domain_aliases.dart';
import 'empty_state_view.dart';

/// Terminal "no access" state (#358/#1207/#1237): a Firestore permission-denied
/// on a group/event read means the caller was removed / lost access. No Retry
/// (retrying just re-denies) — only a Home CTA. Reuses the groupNoAccess* copy
/// (event access IS group membership; no event-specific ARB keys).
class NoAccessView extends StatelessWidget {
  const NoAccessView({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(context.spacing.space24),
          child: EmptyStateView(
            icon: Iconsax.lock,
            title: context.l10n.groupNoAccessTitle,
            message: context.l10n.groupNoAccessMessage,
            actionLabel: context.l10n.groupBackHome,
            onAction: () => GoRouter.of(context).go('/home'),
          ),
        ),
      ),
    );
  }
}

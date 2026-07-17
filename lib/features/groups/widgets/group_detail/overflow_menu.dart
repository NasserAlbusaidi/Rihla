import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';

class OverflowMenu extends StatelessWidget {
  const OverflowMenu({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: PopupMenuButton<String>(
          tooltip: context.l10n.groupMoreTooltip,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(spacing.radiusLarge),
          ),
          offset: const Offset(0, 44),
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          splashRadius: 24,
          onSelected: (key) {
            switch (key) {
              case 'settings':
                GoRouter.of(context).push('/group/$groupId/settings');
              case 'activity':
                GoRouter.of(context).push('/group/$groupId/activity');
            }
          },
          child: Center(
            child: Material(
              color: colors.cardSurface.withValues(alpha: 0.94),
              shape: const CircleBorder(),
              elevation: 1,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(Iconsax.more, size: 18, color: colors.textPrimary),
              ),
            ),
          ),
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Iconsax.setting_2, size: 16, color: colors.textPrimary),
                  const SizedBox(width: 10),
                  Text(context.l10n.groupSettings),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'activity',
              child: Row(
                children: [
                  Icon(Iconsax.activity, size: 16, color: colors.textPrimary),
                  const SizedBox(width: 10),
                  Text(context.l10n.groupActivity),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

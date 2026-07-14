import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/theme/tokens/typography_tokens.dart';
import '../../keys/home_keys.dart';

class GreetingStrip extends StatelessWidget {
  const GreetingStrip({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? context.l10n.homeGoodMorning
        : hour < 17
        ? context.l10n.homeGoodAfternoon
        : context.l10n.homeGoodEvening;
    return Padding(
      key: HomeKeys.yourGroupsHeader,
      padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 0),
      child: Text(
        context.l10n.homeGreeting(greeting, name).toUpperCase(),
        style: AppTypography.caption(
          context,
          fontSize: 10,
          color: colors.textSecondary,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

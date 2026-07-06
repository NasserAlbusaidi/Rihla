import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/loading_button.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../keys/group_keys.dart';
import '../models/claim_models.dart';

/// #278 PR9 — "Is one of these you?" claim picker. Shown on the join screen when
/// the entered invite code resolves a group that still has unclaimed placeholder
/// ("shadow") members. Tapping a name opens the permanent-confirmation sheet;
/// "No, I'm new" falls back to a normal join.
class ClaimPickerView extends StatelessWidget {
  const ClaimPickerView({
    super.key,
    required this.shadows,
    required this.busy,
    required this.onPick,
    required this.onImNew,
  });

  final List<UnclaimedShadow> shadows;
  final bool busy;
  final ValueChanged<UnclaimedShadow> onPick;
  final VoidCallback onImNew;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      key: GroupKeys.claimPicker,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.groupClaimPickerTitle,
          style: AppTypography.displayOf(
            context,
            fontSize: 26,
            color: colors.textPrimary,
            height: 1.1,
          ),
        ),
        SizedBox(height: context.spacing.space8),
        Text(
          context.l10n.groupClaimPickerSubtitle,
          style: AppTypography.sans(
            fontSize: 13,
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
        SizedBox(height: context.spacing.space20),
        for (final shadow in shadows) ...[
          _ShadowTile(
            shadow: shadow,
            enabled: !busy,
            onTap: () => onPick(shadow),
          ),
          SizedBox(height: context.spacing.space8),
        ],
        SizedBox(height: context.spacing.space12),
        TextButton(
          key: GroupKeys.claimImNewButton,
          onPressed: busy ? null : onImNew,
          child: Text(context.l10n.groupClaimImNew),
        ),
      ],
    );
  }
}

class _ShadowTile extends StatelessWidget {
  const _ShadowTile({
    required this.shadow,
    required this.enabled,
    required this.onTap,
  });

  final UnclaimedShadow shadow;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.cardSoft,
      borderRadius: BorderRadius.circular(context.spacing.radiusCard),
      child: InkWell(
        key: GroupKeys.claimShadowTile(shadow.shadowMemberId),
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(context.spacing.radiusCard),
        child: Padding(
          padding: EdgeInsets.all(context.spacing.space16),
          child: Row(
            children: [
              RAvatar(size: 36, name: shadow.displayName),
              SizedBox(width: context.spacing.space12),
              Expanded(
                child: Text(
                  shadow.displayName,
                  style: AppTypography.sans(
                    fontSize: 16,
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// #278 PR9 — the post-request waiting state. The claim is pre-join (D8): the
/// requester is NOT yet a member; the creator's approval performs the re-key. The
/// requester polls their status with "Check again" (no auto-poll timer — P9-2).
class ClaimWaitingView extends StatelessWidget {
  const ClaimWaitingView({
    super.key,
    required this.shadowName,
    required this.busy,
    required this.onCheckAgain,
  });

  final String shadowName;
  final bool busy;
  final VoidCallback onCheckAgain;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      key: GroupKeys.claimWaiting,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.hourglass_top, size: 44, color: colors.textSecondary),
        SizedBox(height: context.spacing.space16),
        Text(
          context.l10n.groupClaimWaitingTitle,
          textAlign: TextAlign.center,
          style: AppTypography.displayOf(
            context,
            fontSize: 24,
            color: colors.textPrimary,
          ),
        ),
        SizedBox(height: context.spacing.space8),
        Text(
          context.l10n.groupClaimWaitingBody(shadowName),
          textAlign: TextAlign.center,
          style: AppTypography.sans(
            fontSize: 14,
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
        SizedBox(height: context.spacing.space24),
        LoadingButton(
          key: GroupKeys.claimCheckAgainButton,
          isLoading: busy,
          onPressed: busy ? null : onCheckAgain,
          label: context.l10n.groupClaimCheckAgain,
        ),
      ],
    );
  }
}

/// #278 PR9 — the hard, irreversible-by-design confirmation (D3). Resolves to
/// `true` only on an explicit affirmative tap; `false`/`null` on cancel/dismiss.
Future<bool?> showClaimConfirmSheet(
  BuildContext context, {
  required String name,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.scaffoldBackground,
    builder: (sheetContext) {
      final colors = sheetContext.colors;
      return Padding(
        key: GroupKeys.claimConfirmSheet,
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              sheetContext.l10n.groupClaimConfirmTitle(name),
              style: AppTypography.displayOf(
                sheetContext,
                fontSize: 22,
                color: colors.textPrimary,
              ),
            ),
            SizedBox(height: sheetContext.spacing.space12),
            Text(
              sheetContext.l10n.groupClaimConfirmWarning(name),
              style: AppTypography.sans(
                fontSize: 14,
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
            SizedBox(height: sheetContext.spacing.space24),
            FilledButton(
              key: GroupKeys.claimConfirmButton,
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                // design-token-justified: white foreground on the rust
                // destructive claim-confirm CTA — no textOnError token exists.
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => Navigator.of(sheetContext).pop(true),
              child: Text(sheetContext.l10n.groupClaimConfirmCta(name)),
            ),
            SizedBox(height: sheetContext.spacing.space8),
            TextButton(
              key: GroupKeys.claimConfirmCancel,
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: Text(sheetContext.l10n.commonCancel),
            ),
          ],
        ),
      );
    },
  );
}

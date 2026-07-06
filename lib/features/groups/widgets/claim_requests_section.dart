import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/firebase_functions_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/directional_icon.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/durable_credential_sheet.dart';
import '../keys/group_keys.dart';
import '../models/claim_models.dart';
import '../providers/claim_provider.dart';
import 'settings_section_header.dart';

/// #278 PR9 — the creator's approve/decline surface for pending placeholder
/// ("shadow") claim requests. Creator-only: a non-creator never even queries
/// (the underlying `listGroupClaimRequests` callable is creator-gated and would
/// permission-deny). Hidden entirely when there are no pending requests (P9-1).
class ClaimRequestsSection extends ConsumerWidget {
  const ClaimRequestsSection({
    super.key,
    required this.groupId,
    required this.isCreator,
  });

  final String groupId;
  final bool isCreator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isCreator) return const SizedBox.shrink();

    final requestsAsync = ref.watch(groupClaimRequestsProvider(groupId));
    return requestsAsync.maybeWhen(
      data: (requests) {
        final pending =
            requests.where((r) => r.status == 'pending').toList(growable: false);
        if (pending.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(bottom: context.spacing.space12),
          child: Column(
            key: GroupKeys.claimRequestsSection,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsSectionHeader(title: context.l10n.groupClaimRequestsTitle),
              const SizedBox(height: 6),
              for (var i = 0; i < pending.length; i++) ...[
                if (i > 0) SizedBox(height: context.spacing.space8),
                _ClaimRequestRow(groupId: groupId, request: pending[i]),
              ],
            ],
          ),
        );
      },
      // A transient load/error stays quiet — never blocks the settings screen.
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _ClaimRequestRow extends ConsumerStatefulWidget {
  const _ClaimRequestRow({required this.groupId, required this.request});

  final String groupId;
  final GroupClaimRequest request;

  @override
  ConsumerState<_ClaimRequestRow> createState() => _ClaimRequestRowState();
}

class _ClaimRequestRowState extends ConsumerState<_ClaimRequestRow> {
  bool _busy = false;
  // Which button the creator pressed — drives the inline spinner so feedback
  // lands on the tapped control, not both.
  bool _approving = false;

  Future<void> _decide(bool approve) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _approving = approve;
    });
    // D6-R: an anonymous creator can SEE requests but the server rejects an
    // anonymous decide — pre-empt with the link sheet. Placed after the busy
    // guard (no double-sheet on double-tap) with an explicit reset on cancel
    // (the finally below is unreachable from this early return).
    if (!ref.read(isDurableUserProvider)) {
      final linked = await showDurableCredentialSheet(context);
      if (!linked || !mounted) {
        if (mounted) setState(() => _busy = false);
        return;
      }
    }
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final req = widget.request;
    try {
      final result = await ref
          .read(firebaseFunctionsServiceProvider)
          .decideClaimRequest(
            groupId: widget.groupId,
            requestId: req.requestId,
            approve: approve,
          );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.status == 'claimed'
                ? l10n.groupClaimApproved(
                    req.requesterDisplayName,
                    req.shadowDisplayName,
                  )
                : l10n.groupClaimRequestDeclined,
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      // `internal` = a retryable post-commit/TOCTOU error (D9) — NEVER read as
      // success; the request stays pending and the creator can approve again.
      final message = e.code == 'internal'
          ? l10n.groupClaimApproveError
          : (e.message ?? l10n.groupClaimApproveError);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.groupClaimApproveError)),
      );
    } finally {
      // Refresh so an approved/declined request drops off the list.
      ref.invalidate(groupClaimRequestsProvider(widget.groupId));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final colors = context.colors;
    final spacing = context.spacing;

    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(spacing.radiusLarge),
        boxShadow: context.shadows.raised,
      ),
      padding: EdgeInsets.all(spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity-merge visual: the joiner takes over the placeholder's spot.
          Row(
            children: [
              RAvatar(size: 34, name: req.requesterDisplayName),
              SizedBox(width: spacing.space8),
              DirectionalIcon(
                Iconsax.arrow_right_3,
                size: 18,
                color: colors.textSecondary,
              ),
              SizedBox(width: spacing.space8),
              RAvatar(size: 34, name: req.shadowDisplayName),
              const Spacer(),
              _PendingBadge(label: context.l10n.groupClaimPendingBadge),
            ],
          ),
          SizedBox(height: spacing.space12),
          Text(
            context.l10n.groupClaimRequestRow(
              req.requesterDisplayName,
              req.shadowDisplayName,
            ),
            style: AppTypography.sans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          SizedBox(height: spacing.space8),
          // Spell out the irreversible balance merge before the creator acts —
          // mirrors the warning the joiner saw on the claim-confirm sheet.
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: spacing.space12,
              vertical: spacing.space8,
            ),
            decoration: BoxDecoration(
              color: colors.cardSoft,
              borderRadius: BorderRadius.circular(spacing.radiusMedium),
            ),
            child: Text(
              context.l10n.groupClaimMergeConsequence(
                req.shadowDisplayName,
                req.requesterDisplayName,
              ),
              style: AppTypography.sans(
                fontSize: 12.5,
                color: colors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
          SizedBox(height: spacing.space12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: GroupKeys.claimDecline(req.requestId),
                  onPressed: _busy ? null : () => _decide(false),
                  child: _busy && !_approving
                      ? const _ButtonSpinner()
                      : Text(context.l10n.groupClaimDecline),
                ),
              ),
              SizedBox(width: spacing.space8),
              Expanded(
                child: FilledButton(
                  key: GroupKeys.claimApprove(req.requestId),
                  onPressed: _busy ? null : () => _decide(true),
                  child: _busy && _approving
                      ? const _ButtonSpinner()
                      : Text(context.l10n.groupClaimApprove),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Neutral "Pending" pill — matches the member list's "Not joined yet" shadow
/// badge so the claim card reads as part of the same surface.
class _PendingBadge extends StatelessWidget {
  const _PendingBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 3, 8, 3),
      decoration: BoxDecoration(
        color: context.colors.cardSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.colors.rule2),
      ),
      child: Text(
        label,
        style: AppTypography.sans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

/// Small inline spinner sized to sit inside a button without resizing it.
class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 16,
      width: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

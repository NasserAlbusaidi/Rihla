import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/firebase_functions_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
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
              Container(
                decoration: BoxDecoration(
                  color: context.colors.cardSurface,
                  borderRadius:
                      BorderRadius.circular(context.spacing.radiusLarge),
                  boxShadow: context.shadows.raised,
                ),
                padding:
                    EdgeInsets.symmetric(horizontal: context.spacing.space16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < pending.length; i++) ...[
                      if (i > 0)
                        Container(height: 0.5, color: context.colors.rule),
                      _ClaimRequestRow(groupId: groupId, request: pending[i]),
                    ],
                  ],
                ),
              ),
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

  Future<void> _decide(bool approve) async {
    if (_busy) return;
    setState(() => _busy = true);
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
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.groupClaimRequestRow(
              req.requesterDisplayName,
              req.shadowDisplayName,
            ),
            style: AppTypography.sans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: context.spacing.space8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: GroupKeys.claimDecline(req.requestId),
                onPressed: _busy ? null : () => _decide(false),
                child: Text(context.l10n.groupClaimDecline),
              ),
              SizedBox(width: context.spacing.space8),
              FilledButton(
                key: GroupKeys.claimApprove(req.requestId),
                onPressed: _busy ? null : () => _decide(true),
                child: Text(context.l10n.groupClaimApprove),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

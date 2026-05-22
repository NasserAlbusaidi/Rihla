import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../models/account_job_status.dart';
import '../providers/account_job_coordinator_provider.dart';

class AccountJobOverlay extends ConsumerWidget {
  const AccountJobOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountJobCoordinatorProvider);
    final job = state.activeJob;

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(ignoring: state.isBlocking, child: child),
        if (job != null && state.isBlocking)
          _BlockingJobPanel(job: job, blockedDeepLink: state.blockedDeepLink),
      ],
    );
  }
}

class _BlockingJobPanel extends ConsumerWidget {
  const _BlockingJobPanel({required this.job, required this.blockedDeepLink});

  final AccountJobStatusSnapshot job;
  final bool blockedDeepLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l10n = context.l10n;
    final title = switch (job.kind) {
      AccountJobKind.recoveryCleanup => l10n.accountJobRecoveryTitle,
      AccountJobKind.deleteAccount => l10n.accountJobDeletionTitle,
    };
    final body = switch (job.kind) {
      AccountJobKind.recoveryCleanup => l10n.accountJobRecoveryBody,
      AccountJobKind.deleteAccount => l10n.accountJobDeletionBody,
    };
    final progressText = job.hasCountedProgress
        ? l10n.accountJobProgress(job.current!, job.total!)
        : l10n.accountJobProgressIndeterminate;
    final isFailed = job.status == AccountJobRunStatus.failed;

    return Positioned.fill(
      child: Material(
        key: const Key('accountJobOverlay.blocker'),
        color: colors.scaffoldBackground,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(spacing.space24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  isFailed ? Iconsax.warning_2 : Iconsax.shield_tick,
                  size: 44,
                  color: isFailed ? colors.error : colors.primary,
                ),
                SizedBox(height: spacing.space20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTypography.sans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                SizedBox(height: spacing.space8),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: AppTypography.sans(
                    fontSize: 14,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: spacing.space24),
                Center(
                  child: SizedBox.square(
                    dimension: 40,
                    child: isFailed
                        ? Icon(Iconsax.info_circle, color: colors.error)
                        : CircularProgressIndicator(color: colors.primary),
                  ),
                ),
                SizedBox(height: spacing.space16),
                Text(
                  job.phase.isEmpty
                      ? progressText
                      : '${job.phase} - $progressText',
                  key: const Key('accountJobOverlay.progress'),
                  textAlign: TextAlign.center,
                  style: AppTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
                if (blockedDeepLink) ...[
                  SizedBox(height: spacing.space16),
                  Text(
                    l10n.accountJobDeepLinkBlocked,
                    key: const Key('accountJobOverlay.deepLinkBlocked'),
                    textAlign: TextAlign.center,
                    style: AppTypography.sans(
                      fontSize: 13,
                      color: colors.error,
                      height: 1.35,
                    ),
                  ),
                ],
                if (isFailed) ...[
                  SizedBox(height: spacing.space24),
                  FilledButton.icon(
                    key: const Key('accountJobOverlay.retry'),
                    onPressed: job.retryable
                        ? () => ref
                              .read(accountJobCoordinatorProvider.notifier)
                              .retryActiveJob()
                        : null,
                    icon: const Icon(Iconsax.refresh),
                    label: Text(l10n.accountJobRetry),
                  ),
                  SizedBox(height: spacing.space8),
                  Text(
                    l10n.accountJobSupportCopy,
                    textAlign: TextAlign.center,
                    style: AppTypography.sans(
                      fontSize: 12,
                      color: colors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

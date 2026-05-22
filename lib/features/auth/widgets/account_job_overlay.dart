import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../models/account_job_status.dart';
import '../providers/account_job_coordinator_provider.dart';
import '../services/uid_change_listener.dart';

class AccountJobOverlay extends ConsumerWidget {
  const AccountJobOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountJobCoordinatorProvider);
    final cacheBarrier = ref.watch(uidCacheBarrierProvider);
    final job = state.activeJob;
    final cacheJob = cacheBarrier.isBlocking
        ? AccountJobStatusSnapshot(
            jobId: 'local-cache-wipe',
            kind: AccountJobKind.cacheWipe,
            status: cacheBarrier.phase == UidCacheBarrierPhase.failed
                ? AccountJobRunStatus.failed
                : AccountJobRunStatus.running,
            phase: '',
            retryable: cacheBarrier.phase == UidCacheBarrierPhase.failed,
            errorCode: cacheBarrier.error?.runtimeType.toString(),
          )
        : null;
    final activeJob = job ?? cacheJob;
    final isBlocking = state.isBlocking || cacheBarrier.isBlocking;

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(ignoring: isBlocking, child: child),
        if (activeJob != null && isBlocking)
          _BlockingJobPanel(
            job: activeJob,
            blockedDeepLink: state.blockedDeepLink,
            onRetry: activeJob.kind == AccountJobKind.cacheWipe
                ? () => ref.read(uidCacheBarrierProvider.notifier).retry()
                : () => ref
                      .read(accountJobCoordinatorProvider.notifier)
                      .retryActiveJob(),
          ),
      ],
    );
  }
}

class _BlockingJobPanel extends ConsumerWidget {
  const _BlockingJobPanel({
    required this.job,
    required this.blockedDeepLink,
    required this.onRetry,
  });

  final AccountJobStatusSnapshot job;
  final bool blockedDeepLink;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l10n = context.l10n;
    final title = switch (job.kind) {
      AccountJobKind.recoveryCleanup => l10n.accountJobRecoveryTitle,
      AccountJobKind.deleteAccount => l10n.accountJobDeletionTitle,
      AccountJobKind.cacheWipe => l10n.accountJobCacheWipeTitle,
    };
    final body = switch (job.kind) {
      AccountJobKind.recoveryCleanup => l10n.accountJobRecoveryBody,
      AccountJobKind.deleteAccount => l10n.accountJobDeletionBody,
      AccountJobKind.cacheWipe => l10n.accountJobCacheWipeBody,
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
                    onPressed: job.retryable ? onRetry : null,
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

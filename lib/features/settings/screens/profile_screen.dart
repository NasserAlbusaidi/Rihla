import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/utils/share_helper.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_links.dart';
import '../../../core/config/app_metadata.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/notification_settings_launcher.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/split_mode_display_name.dart';
import '../../../shared/widgets/directional_icon.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../../shared/widgets/skeleton_loader.dart';
import '../../../shared/widgets/skeleton_primitives.dart';
import '../../auth/providers/auth_email_link_bootstrap_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/providers/shell_emptiness_gate.dart';
import '../../auth/services/data_deletion_service.dart';
import '../../auth/services/durable_account_marker.dart';
import '../../auth/widgets/delete_account_dialog.dart';
import '../../auth/widgets/delete_account_retry_dialog.dart';
import '../../auth/widgets/durable_credential_sheet.dart';
import '../../auth/widgets/durable_shell_delete_dialog.dart';
import '../../auth/widgets/google_restore_action.dart';
import '../../auth/widgets/sign_out_confirm_dialog.dart';
import '../../groups/providers/group_provider.dart';
import '../keys/profile_keys.dart';
import '../providers/profile_stats_provider.dart';
import '../widgets/default_split_picker_sheet.dart';
import '../widgets/edit_name_bottom_sheet.dart';
import '../widgets/language_picker_sheet.dart';
import '../widgets/legal_links_sheet.dart';
import '../widgets/profile_display_section.dart';

/// Profile tab — saffron travel-journal direction.
///
/// Wireframe ref: `Wireframes/Rihla/hifi/screens-shell.jsx` → `Hi_Profile()`.
/// Layout top-to-bottom:
///   1. Top bar — settings (or back) · "Profile" title · share
///   2. Optional pending-recovery banner (when `pendingEmailLinkProvider` is
///      set — i.e. a magic link arrived but no pending email was primed)
///   3. Identity card — decorative corner flourish, 84dp avatar, italic name,
///      tagline, two action chips
///   4. 3-column stats grid (Journeys / Groups / Spent)
///   5. Preferences card (Notifications / Language / Default split)
///   6. Display section (theme picker)
///   7. Account card (linked email, sign out, delete)
///   8. About card (Help / Feedback / Terms)
///   9. Version stamp
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, this.showBack = false});

  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final isDurable = ref.watch(isDurableUserProvider);
    final l10n = context.l10n;

    return Scaffold(
      key: ProfileKeys.screen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(canPop: showBack),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: context.spacing.space32),
                child: Column(
                  children: [
                    const _PendingRecoveryBanner(),
                    SizedBox(height: context.spacing.space4),
                    _IdentityCard(
                          name: settings.deviceName,
                          onEditName: () =>
                              _openEditSheet(context, ref, settings.deviceName),
                        )
                        .animate()
                        .fadeIn(delay: 80.ms, duration: 400.ms)
                        .slideY(begin: 0.08),
                    // #487: anonymous users get a prominent prompt naming the
                    // stakes; durable users never see it.
                    if (!isDurable) ...[
                      const SizedBox(height: 14),
                      const _BackupAccountCard(),
                    ],
                    const SizedBox(height: 14),
                    const _StatsGrid()
                        .animate()
                        .fadeIn(delay: 160.ms, duration: 400.ms)
                        .slideY(begin: 0.08),
                    const SizedBox(height: 18),
                    _SectionLabel(label: l10n.profileSectionPreferences),
                    SizedBox(height: context.spacing.space8),
                    const _PreferencesCard().animate().fadeIn(
                      delay: 260.ms,
                      duration: 400.ms,
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      key: ProfileKeys.displaySection,
                      padding: EdgeInsets.symmetric(
                        horizontal: context.spacing.space20,
                      ),
                      child: const ProfileDisplaySection(),
                    ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
                    const SizedBox(height: 18),
                    _SectionLabel(label: l10n.profileSectionAccount),
                    SizedBox(height: context.spacing.space8),
                    const _AccountCard().animate().fadeIn(
                      delay: 320.ms,
                      duration: 400.ms,
                    ),
                    const SizedBox(height: 18),
                    _SectionLabel(label: l10n.profileSectionDanger),
                    SizedBox(height: context.spacing.space8),
                    const _DangerZoneCard().animate().fadeIn(
                      delay: 340.ms,
                      duration: 400.ms,
                    ),
                    const SizedBox(height: 18),
                    _SectionLabel(label: l10n.profileSectionAbout),
                    SizedBox(height: context.spacing.space8),
                    const _AboutCard().animate().fadeIn(
                      delay: 380.ms,
                      duration: 400.ms,
                    ),
                    const SizedBox(height: 18),
                    const _VersionStamp(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditSheet(BuildContext context, WidgetRef ref, String currentName) {
    HapticService.selection();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => EditNameBottomSheet(
        currentName: currentName,
        onSave: (name) async {
          await ref.read(settingsProvider.notifier).setDeviceName(name);
        },
      ),
    );
  }
}

// ──────────────────────────── Top bar

class _TopBar extends StatelessWidget {
  const _TopBar({required this.canPop});
  final bool canPop;

  void _back(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(AppRoutes.home);
      }
      return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (canPop)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _GhostIcon(
                  icon: Iconsax.arrow_left,
                  matchTextDirection: true,
                  onTap: () {
                    HapticService.lightClick();
                    _back(context);
                  },
                ),
              ),
            Text(
              context.l10n.profileTitle,
              style: AppTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _GhostIcon(
                icon: Iconsax.export_1,
                onTap: () {
                  HapticService.lightClick();
                  _shareApp(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GhostIcon extends StatelessWidget {
  const _GhostIcon({
    required this.icon,
    required this.onTap,
    this.matchTextDirection = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool matchTextDirection;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: SizedBox(
        width: 44,
        height: 44,
        child: matchTextDirection
            ? DirectionalIcon(icon, size: 20, color: colors.textPrimary)
            : Icon(icon, size: 20, color: colors.textPrimary),
      ),
    );
  }
}

// ──────────────────────────── Pending recovery banner

/// Renders only when `pendingEmailLinkProvider` holds a magic-link URL the
/// bootstrap could not auto-complete (no pending email was primed — e.g. the
/// link was opened on a fresh install or different device). Routes to
/// `/recover` so the user can enter the email and finish the flow.
class _PendingRecoveryBanner extends ConsumerWidget {
  const _PendingRecoveryBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingLink = ref.watch(pendingEmailLinkProvider);
    if (pendingLink == null) return const SizedBox.shrink();

    final colors = context.colors;
    return Padding(
      key: ProfileKeys.pendingRecoveryBanner,
      padding: EdgeInsets.fromLTRB(
        context.spacing.space20,
        context.spacing.space12,
        context.spacing.space20,
        context.spacing.space4,
      ),
      child: Material(
        color: colors.cardSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticService.selection();
            context.push('/recover');
          },
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: context.spacing.space12,
            ),
            child: Row(
              children: [
                Icon(Iconsax.sms_tracking, size: 18, color: colors.textPrimary),
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.profileFinishRecovery,
                        style: AppTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.profileRecoverySubtitle,
                        style: AppTypography.sans(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: context.spacing.space8),
                DirectionalIcon(
                  Iconsax.arrow_right_3,
                  size: 16,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────── Identity card

class _IdentityCard extends ConsumerWidget {
  const _IdentityCard({required this.name, required this.onEditName});
  final String name;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final l10n = context.l10n;
    final isDurable = ref.watch(isDurableUserProvider);
    final hasName = name.trim().isNotEmpty;
    final displayName = hasName ? name : l10n.profileSetYourName;
    // When no name is set there is no real @handle to share. A literal
    // '@traveller' fallback read like a truncated email ('traveller@'), so
    // show a plain, non-@ label instead (#163).
    final handle = hasName ? '@${_slug(name)}' : l10n.profileHandlePlaceholder;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      child: Container(
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: context.shadows.raised,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Decorative corner flourish — large saffron-soft disk that gets
            // clipped by the card's antiAlias to a quarter-circle bite.
            Positioned(
              top: -50,
              right: -50,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: colors.saffronSoft.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(22, context.spacing.space24, 22, 22),
              child: Column(
                children: [
                  RAvatar(
                    key: ProfileKeys.initialsCircle,
                    name: name,
                    size: 84,
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: onEditName,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          key: hasName
                              ? ProfileKeys.displayName
                              : ProfileKeys.setNamePrompt,
                          style: AppTypography.displayOf(
                            context,
                            fontSize: 28,
                            color: hasName
                                ? colors.textPrimary
                                : colors.primary,
                            letterSpacing: -0.5,
                            height: 1.1,
                          ),
                        ),
                        SizedBox(width: context.spacing.space8),
                        Icon(
                          Iconsax.edit_2,
                          size: 14,
                          color: colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: context.spacing.space8),
                  // #487: the hero tells the truth about backup state instead
                  // of an unconditional "Anonymous traveller".
                  _BackupStatusChip(isDurable: isDurable),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _IdentityChip(
                        leadingIcon: Iconsax.copy,
                        label: handle,
                        onTap: () async {
                          final handleCopied = l10n.profileSnackHandleCopied;
                          await Clipboard.setData(ClipboardData(text: handle));
                          if (!context.mounted) return;
                          _showSnack(context, handleCopied);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _slug(String name) {
    final cleaned = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return cleaned.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}

/// Hero pill that states whether the account is backed up (#487): sage when
/// durable (Google/email linked), amber when still anonymous.
class _BackupStatusChip extends StatelessWidget {
  const _BackupStatusChip({required this.isDurable});
  final bool isDurable;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final accent = isDurable ? colors.success : colors.warning;
    return Container(
      key: ProfileKeys.backupStatusChip,
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.space12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.spacing.radiusPill),
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDurable ? Iconsax.shield_tick : Iconsax.warning_2,
            size: 13,
            color: accent,
          ),
          SizedBox(width: context.spacing.space4),
          Text(
            isDurable
                ? l10n.profileBackupStatusBackedUp
                : l10n.profileBackupStatusNotBackedUp,
            style: AppTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Anonymous-only card that names the stakes of not being backed up and routes
/// to the durable-credential (Google/email) flow (#487). Hidden once durable.
class _BackupAccountCard extends StatelessWidget {
  const _BackupAccountCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      child: GestureDetector(
        onTap: () {
          HapticService.selection();
          showDurableCredentialSheet(context);
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          key: ProfileKeys.backupAccountCard,
          padding: EdgeInsets.all(context.spacing.space16),
          decoration: BoxDecoration(
            color: colors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
            border: Border.all(
              color: colors.warning.withValues(alpha: 0.35),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(Iconsax.warning_2, size: 20, color: colors.warning),
              ),
              SizedBox(width: context.spacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.profileBackupCardTitle,
                      style: AppTypography.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    SizedBox(height: context.spacing.space4),
                    Text(
                      l10n.profileBackupCardBody,
                      style: AppTypography.sans(
                        fontSize: 12,
                        color: colors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: context.spacing.space8),
              DirectionalIcon(
                Iconsax.arrow_right_3,
                size: 16,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IdentityChip extends StatelessWidget {
  const _IdentityChip({
    required this.leadingIcon,
    required this.label,
    required this.onTap,
  });
  final IconData leadingIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space12,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: colors.cardSoft,
          borderRadius: BorderRadius.circular(context.spacing.radiusPill),
          border: Border.all(color: colors.rule, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(leadingIcon, size: 12, color: colors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.sans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────── Stats grid

class _StatsGrid extends ConsumerWidget {
  const _StatsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // #488: explicit loading skeleton + error state — never an ambiguous "—"
    // that reads as zero / no-data when the stats actually failed or are still
    // loading.
    return ref
        .watch(profileStatsProvider)
        .when(
          loading: () => const _StatsGridSkeleton(),
          error: (_, _) => const _StatsErrorCard(),
          data: (stats) => Padding(
            key: ProfileKeys.statsSection,
            padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    statKey: ProfileKeys.statEvents,
                    keyLabel: l10n.profileStatsJourneysLabel,
                    value: '${stats.eventCount}',
                    sub: l10n.profileStatsAllTime,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    statKey: ProfileKeys.statGroups,
                    keyLabel: l10n.profileStatsGroupsLabel,
                    value: '${stats.groupCount}',
                    sub: l10n.profileStatsActive,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    statKey: ProfileKeys.statSpent,
                    keyLabel: l10n.profileStatsSpentLabel,
                    valueWidget: _SpentValue(spent: stats.spentByCurrency),
                    sub: l10n.profileStatsLifetime,
                  ),
                ),
              ],
            ),
          ),
        );
  }
}

/// Layout-matched skeleton for the 3-tile stats grid (#488).
class _StatsGridSkeleton extends StatelessWidget {
  const _StatsGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      itemCount: 1,
      itemBuilder: (context, _) => Padding(
        key: ProfileKeys.statsSection,
        padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
        child: const Row(
          children: [
            Expanded(
              child: SkeletonBlock(
                width: double.infinity,
                height: 88,
                borderRadius: 16,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: SkeletonBlock(
                width: double.infinity,
                height: 88,
                borderRadius: 16,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: SkeletonBlock(
                width: double.infinity,
                height: 88,
                borderRadius: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact, explicit error state for the stats grid with a retry (#488).
class _StatsErrorCard extends ConsumerWidget {
  const _StatsErrorCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      child: Container(
        key: ProfileKeys.statsErrorCard,
        padding: EdgeInsets.all(context.spacing.space16),
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: context.shadows.raised,
        ),
        child: Row(
          children: [
            Icon(Iconsax.warning_2, size: 18, color: colors.textSecondary),
            SizedBox(width: context.spacing.space12),
            Expanded(
              child: Text(
                context.l10n.profileStatsLoadFailed,
                style: AppTypography.sans(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(profileStatsProvider),
              child: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Spent stat value: per-currency lifetime spend (#378). No FX, so when a
/// user's groups span >1 currency we show one line per currency (hero-style)
/// rather than a nonsense cross-currency sum. Capped at 2 lines + a "+N"
/// overflow to keep the compact stat cell from growing unbounded.
class _SpentValue extends StatelessWidget {
  const _SpentValue({required this.spent});
  final List<CurrencySpend> spent;

  static const int _maxLines = 2;

  @override
  Widget build(BuildContext context) {
    // No spend yet (or no groups): preserve the original compact zero look —
    // there is no currency context, so render an OMR-precision zero.
    if (spent.isEmpty) {
      return RAmount(
        value: Decimal.zero,
        currency: 'OMR',
        showCurrency: false,
        size: 24,
      );
    }

    // Single currency is unambiguous → keep the large, code-less look.
    if (spent.length == 1) {
      final only = spent.first;
      return RAmount(
        value: only.amount,
        currency: only.currency,
        showCurrency: false,
        size: 24,
      );
    }

    // ≥2 currencies: stacked per-currency lines (code shown to disambiguate),
    // capped, with a "+N" overflow indicator for the rest.
    final colors = context.colors;
    final shown = spent.take(_maxLines).toList();
    final overflow = spent.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: RAmount(value: s.amount, currency: s.currency, size: 15),
          ),
        if (overflow > 0)
          Text(
            context.l10n.profileStatsSpentMore(overflow),
            style: AppTypography.sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.statKey,
    required this.keyLabel,
    required this.sub,
    this.value,
    this.valueWidget,
  }) : assert(
         value != null || valueWidget != null,
         'Provide either value or valueWidget',
       );

  final Key statKey;
  final String keyLabel;
  final String sub;
  final String? value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: statKey,
      padding: EdgeInsets.fromLTRB(14, 14, context.spacing.space12, 14),
      // #807: flat card + hairline, not raised — these are static stats with
      // no onTap; the raised treatment is the app's actionable-surface cue
      // (docs/DESIGN.md flat-vs-raised split).
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.rule2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            keyLabel,
            style: AppTypography.caption(
              context,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          if (valueWidget != null)
            valueWidget!
          else
            Text(
              value!,
              style: AppTypography.display(
                fontSize: 28,
                color: colors.textPrimary,
                height: 1.0,
              ),
            ),
          SizedBox(height: context.spacing.space4),
          Text(
            sub,
            style: AppTypography.sans(
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────── Section label (uppercase mono)

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      child: Row(
        children: [
          Text(
            label,
            style: AppTypography.caption(
              context,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────── Preferences card

class _PreferencesCard extends ConsumerWidget {
  const _PreferencesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifStatus = ref.watch(notificationStatusProvider);
    final isPermissionDenied =
        notifStatus == NotificationStatus.permissionDenied;
    // #482: a token-write failure leaves the user opted-in but undelivered. The
    // switch must read OFF (not a confident ON) and offer a retry.
    final isError = notifStatus == NotificationStatus.error;
    final notificationsOn =
        settings.pushNotificationsEnabled && !isPermissionDenied && !isError;
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      child: _RowsCard(
        rows: [
          _NotificationPrefRow(
            leading: _PrefIcon(
              icon: Iconsax.notification,
              bg: colors.paperDeep,
            ),
            value: notificationsOn,
            permissionDenied: isPermissionDenied,
            errored: isError,
            onChanged: (value) {
              HapticService.selection();
              ref
                  .read(settingsProvider.notifier)
                  .setPushNotificationsEnabled(value);
            },
            // #470: once OS permission is denied the in-app dialog can't
            // re-request it (Android 13+), so the only recovery is OS settings.
            onOpenSettings: () {
              HapticService.selection();
              ref.read(openNotificationSettingsProvider)();
            },
            // #482: registration failed (transient FCM/Firestore error) — retry
            // re-runs initialize() to attempt the token write again.
            onRetry: () {
              HapticService.selection();
              unawaited(ref.read(notificationServiceProvider).initialize());
            },
          ),
          // #61/#382: no global profile currency. Groups choose their default
          // currency at create time, expenses can carry their own supported
          // currency, and balances render per-currency buckets with no FX.
          _PrefRow(
            leading: _PrefIconLetter(letter: 'Aa', bg: colors.saffronTint),
            label: context.l10n.profilePreferencesLanguage,
            trailingText: _languageTrailing(settings.languageCode),
            onTap: () => LanguagePickerSheet.show(context),
          ),
          _PrefRow(
            leading: _PrefIcon(
              icon: Iconsax.percentage_square,
              bg: colors.cardSoft,
            ),
            label: context.l10n.profilePreferencesDefaultSplit,
            trailingText: splitModeDisplayName(
              settings.defaultSplitMode,
              context.l10n,
            ),
            onTap: () => DefaultSplitPickerSheet.show(context),
            divider: false,
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────── About card

class _AboutCard extends ConsumerWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      child: _RowsCard(
        rows: [
          _PrefRow(
            label: context.l10n.profileAboutHelpCenter,
            trailing: DirectionalIcon(
              Iconsax.arrow_right_3,
              size: 16,
              color: colors.textSecondary,
            ),
            onTap: () => _openExternalUrl(context, AppLinks.helpUrl),
          ),
          _PrefRow(
            tileKey: ProfileKeys.feedbackTile,
            label: context.l10n.profileAboutSendFeedbackRow,
            trailing: DirectionalIcon(
              Iconsax.arrow_right_3,
              size: 16,
              color: colors.textSecondary,
            ),
            onTap: () => _sendFeedback(context, ref),
          ),
          _PrefRow(
            tileKey: ProfileKeys.licensesTile,
            label: context.l10n.profileAboutTermsPrivacy,
            trailing: DirectionalIcon(
              Iconsax.arrow_right_3,
              size: 16,
              color: colors.textSecondary,
            ),
            onTap: () => LegalLinksSheet.show(context),
            divider: false,
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────── Account (Linked email)

class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  Future<void> _signOut(
    BuildContext context,
    WidgetRef ref,
    String? email,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final signedOut = context.l10n.profileSnackSignedOut;
    final signOutFailed = context.l10n.profileSnackSignOutFailed;
    final confirmed = await SignOutConfirmDialog.show(context, email: email);
    if (confirmed != true) return;
    try {
      await ref.read(authRecoveryServiceProvider).signOutCurrentDevice();
      messenger.showSnackBar(SnackBar(content: Text(signedOut)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(signOutFailed)));
    }
  }

  /// Advisory pre-check before the email-recover screen — mirrors the gate
  /// `triggerGoogleRestore` already runs (google_restore_action.dart). Without
  /// it, a data-holding user reaches the email screen, sends themselves a
  /// link, and is only blocked at link-open (#647's swap gate) — a downstream
  /// dead-end instead of an upfront answer. The swap gate stays authoritative.
  Future<void> _recoverWithEmail(BuildContext context, WidgetRef ref) async {
    final shellEmpty = await outgoingShellProvablyEmpty(
      readUser: () => ref.read(firebaseUserProvider.future),
      readGroups: () => ref.read(userGroupsProvider.future),
      timeout: ref.read(shellEmptinessGateTimeoutProvider),
    );
    if (!context.mounted) return;
    if (!shellEmpty) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.l10n.restoreBlockedHasData),
            duration: const Duration(seconds: 4),
          ),
        );
      return;
    }
    unawaited(context.push('/recover'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final linkedEmail = ref.watch(linkedEmailProvider);
    final isLinked = linkedEmail != null;
    final googleAccount = ref.watch(googleAccountProvider);
    final isDurable = ref.watch(isDurableUserProvider);
    final user = ref.watch(authUserChangesProvider).valueOrNull;
    final isAnonymous = user?.isAnonymous ?? false;
    // Restore rows stay VISIBLE for every anonymous user; the shell-emptiness
    // check moved from row visibility to TAP time (friction audit tranche 2 —
    // a hidden row with no explanation read as "restore doesn't exist"). A tap
    // with data present surfaces restoreBlockedHasData instead of a swap:
    // triggerGoogleRestore self-gates, and the email row gates via
    // _recoverWithEmail. The AUTHORITATIVE gate is unchanged and still runs at
    // the swap itself (#647/#648 — outgoingShellProvablyEmpty).
    final showRestore = isAnonymous;

    // #487 bullet 3: only the backup & recovery rows live here now; the
    // irreversible Delete moved to its own _DangerZoneCard below. The trailing
    // hairline is stripped because the last visible row varies by account state.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      child: _RowsCard(
        rows: _stripLastDivider([
          if (googleAccount != null)
            _PrefRow(
              tileKey: ProfileKeys.googleAccountTile,
              leading: _PrefIcon(
                icon: Iconsax.shield_tick,
                bg: colors.cardSoft,
              ),
              label: context.l10n.profileAccountGoogle,
              trailing: Text(
                googleAccount.email ?? context.l10n.profileAccountGoogleLinked,
                style: AppTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              onTap: null,
              divider: true,
            ),
          if (isAnonymous)
            _PrefRow(
              tileKey: ProfileKeys.googleLinkTile,
              leading: _PrefIcon(
                icon: Iconsax.shield_tick,
                bg: colors.cardSoft,
              ),
              label: context.l10n.profileAccountLinkGoogle,
              trailing: DirectionalIcon(
                Iconsax.arrow_right_3,
                size: 16,
                color: colors.textSecondary,
              ),
              onTap: () => showDurableCredentialSheet(context),
              divider: true,
            ),
          _PrefRow(
            tileKey: ProfileKeys.linkedEmailTile,
            leading: _PrefIcon(icon: Iconsax.sms, bg: colors.cardSoft),
            label: context.l10n.profileAccountLinkedEmail,
            trailing: isLinked
                ? Text(
                    linkedEmail,
                    style: AppTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.l10n.profileAccountNotSet,
                        style: AppTypography.sans(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      DirectionalIcon(
                        Iconsax.arrow_right_3,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                    ],
                  ),
            onTap: isLinked ? null : () => context.push(AppRoutes.linkEmail),
            divider: true,
          ),
          if (isDurable)
            _PrefRow(
              tileKey: ProfileKeys.signOutDeviceTile,
              leading: _PrefIcon(icon: Iconsax.logout, bg: colors.cardSoft),
              label: context.l10n.profileAccountSignOut,
              trailing: DirectionalIcon(
                Iconsax.arrow_right_3,
                size: 16,
                color: colors.error,
              ),
              onTap: () => _signOut(context, ref, linkedEmail),
              divider: true,
            ),
          if (showRestore) ...[
            _PrefRow(
              tileKey: ProfileKeys.profileRestoreGoogleTile,
              leading: _PrefIcon(icon: Iconsax.refresh, bg: colors.cardSoft),
              label: context.l10n.homeRestoreWithGoogle,
              trailing: DirectionalIcon(
                Iconsax.arrow_right_3,
                size: 16,
                color: colors.textSecondary,
              ),
              onTap: () => triggerGoogleRestore(context, ref),
              divider: true,
            ),
            _PrefRow(
              tileKey: ProfileKeys.profileRestoreEmailTile,
              leading: _PrefIcon(
                icon: Iconsax.sms_tracking,
                bg: colors.cardSoft,
              ),
              label: context.l10n.homeRestoreWithEmail,
              trailing: DirectionalIcon(
                Iconsax.arrow_right_3,
                size: 16,
                color: colors.textSecondary,
              ),
              onTap: () => unawaited(_recoverWithEmail(context, ref)),
              divider: true,
            ),
          ],
        ]),
      ),
    );
  }
}

// ──────────────────────────── Danger zone (delete) — #487 bullet 3

/// Delete account, isolated in its own labelled "Danger" block so the single
/// irreversible action never sits inline with the benign credential/recovery
/// rows (#487 bullet 3 — restore/recovery grouped above, delete fenced here).
class _DangerZoneCard extends ConsumerWidget {
  const _DangerZoneCard();

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    // #469: an anonymous shell delete only removes this guest session, not any
    // durable Google/email account (which lives under a different UID). Make
    // the confirm dialog honest about that.
    final isAnonymous =
        ref.read(authUserChangesProvider).valueOrNull?.isAnonymous ?? false;
    // #469 prevention: if a durable account was established on this device but
    // the live session is an anon shell, deleting now would silently leave that
    // account + its data intact under a different uid. Steer to sign-in first,
    // with an explicit informed escape — never call deleteAccount on the shell
    // unless the user picks "delete just this guest session".
    if (isAnonymous &&
        durableAccountEstablished(ref.read(sharedPreferencesProvider))) {
      final choice = await DurableShellDeleteDialog.show(context);
      if (choice == DurableShellDeleteChoice.deleteGuest && context.mounted) {
        await _runDeletion(context, ref);
      }
      return;
    }
    final confirmed = await DeleteAccountDialog.show(
      context,
      isAnonymous: isAnonymous,
    );
    if (confirmed != true || !context.mounted) return;
    await _runDeletion(context, ref);
  }

  /// Runs the deletion and reacts to the outcome. A [DeletionResult.partial]
  /// (server scrubbed some data but threw before finishing; convergent on
  /// retry) re-prompts with a durable retry dialog and recurses on confirm, so
  /// the user always has a guaranteed path to finish a torn deletion (#77).
  Future<void> _runDeletion(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final result = await ref.read(dataDeletionServiceProvider).deleteAccount();
    if (!context.mounted) return;
    switch (result) {
      case DeletionResult.ok:
        messenger.showSnackBar(SnackBar(content: Text(l10n.profileDeletionOk)));
        context.go(AppRoutes.home);
      case DeletionResult.noUser:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.profileDeletionNoUser)),
        );
      case DeletionResult.error:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.profileDeletionError)),
        );
      case DeletionResult.partial:
        final retry = await DeleteAccountRetryDialog.show(context);
        if (retry == true && context.mounted) {
          await _runDeletion(context, ref);
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      child: _RowsCard(
        key: ProfileKeys.dangerZoneCard,
        rows: [
          _PrefRow(
            tileKey: ProfileKeys.deleteAccountTile,
            leading: _PrefIcon(icon: Iconsax.trash, bg: colors.cardSoft),
            label: context.l10n.profileAccountDelete,
            trailing: Text(
              context.l10n.profileAccountDeletePermanent,
              style: AppTypography.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.error,
              ),
            ),
            onTap: () => _deleteAccount(context, ref),
            divider: false,
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────── Version stamp

class _VersionStamp extends ConsumerWidget {
  const _VersionStamp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final meta = ref.watch(appMetadataProvider).valueOrNull;
    final version = meta?.version ?? '';
    // Intentional brand lockup — stays English in every locale, including
    // Arabic (#162 decision: brand lockup, not localized). Do NOT route this
    // through l10n; pinned by profile_screen_test '#162'.
    return Padding(
      key: ProfileKeys.versionTile,
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        version.isEmpty
            ? 'RIHLA · BUILT FOR JOURNEYS'
            : 'RIHLA · v$version · BUILT FOR JOURNEYS',
        style: AppTypography.mono(
          fontSize: 9,
          color: colors.textSecondary,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

// ──────────────────────────── Rows + supporting

class _RowsCard extends StatelessWidget {
  const _RowsCard({required this.rows, super.key});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(context.spacing.radiusCard),
        boxShadow: context.shadows.raised,
      ),
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space16),
      child: Column(children: rows),
    );
  }
}

/// Returns [rows] with the last row's bottom divider removed, so an account
/// card never ends on a stray hairline no matter which conditional row is last
/// (#487 bullet 3 — the trailing row varies with account state).
List<Widget> _stripLastDivider(List<_PrefRow> rows) {
  if (rows.isEmpty) return rows;
  return [
    ...rows.sublist(0, rows.length - 1),
    rows.last.copyWith(divider: false),
  ];
}

class _NotificationPrefRow extends StatelessWidget {
  const _NotificationPrefRow({
    required this.leading,
    required this.value,
    required this.permissionDenied,
    required this.errored,
    required this.onChanged,
    required this.onOpenSettings,
    required this.onRetry,
  });

  final Widget leading;
  final bool value;

  /// OS permission is denied. The control stays interactive but routes to the
  /// OS settings page instead of toggling the pref — the toggle can't re-request
  /// permission itself on Android 13+ (#470).
  final bool permissionDenied;

  /// Registration failed (a transient FCM/Firestore token-write error): the
  /// user is opted-in but receives nothing. The switch reads OFF and a tap
  /// retries instead of toggling the pref (#482). Mutually exclusive with
  /// [permissionDenied]; denial takes precedence if both somehow hold.
  final bool errored;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Denied → deep-link to OS settings; errored → retry; otherwise toggle the
    // pref. In the first two the switch stays visually OFF (nothing is being
    // delivered), so a tap is a recovery action, not a value flip.
    final String subtitle;
    final VoidCallback onTap;
    if (permissionDenied) {
      subtitle = context.l10n.profileNotificationsDisabledHint;
      onTap = onOpenSettings;
    } else if (errored) {
      subtitle = context.l10n.profileNotificationsErrorHint;
      onTap = onRetry;
    } else {
      subtitle = context.l10n.profileNotificationsSubtitle;
      onTap = () => onChanged(!value);
    }
    return InkWell(
      key: ProfileKeys.notificationToggleTile,
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                leading,
                SizedBox(width: context.spacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.l10n.profilePreferencesNotifications,
                        style: AppTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.sans(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  key: ProfileKeys.notificationSwitch,
                  value: value,
                  onChanged: permissionDenied
                      ? (_) => onOpenSettings()
                      : errored
                      ? (_) => onRetry()
                      : onChanged,
                  activeThumbColor: colors.primary,
                  activeTrackColor: colors.primary,
                  inactiveTrackColor: colors.cardSoft,
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: colors.rule),
        ],
      ),
    );
  }
}

class _PrefRow extends StatelessWidget {
  const _PrefRow({
    required this.label,
    this.leading,
    this.trailingText,
    this.trailing,
    this.onTap,
    this.divider = true,
    this.tileKey,
  });

  final Widget? leading;
  final String label;
  final String? trailingText;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;
  final Key? tileKey;

  _PrefRow copyWith({bool? divider}) => _PrefRow(
    leading: leading,
    label: label,
    trailingText: trailingText,
    trailing: trailing,
    onTap: onTap,
    divider: divider ?? this.divider,
    tileKey: tileKey,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trailingWidget =
        trailing ??
        (trailingText != null
            ? Text(
                trailingText!,
                style: AppTypography.sans(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              )
            : const SizedBox.shrink());

    return InkWell(
      key: tileKey,
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                if (leading != null) ...[
                  leading!,
                  SizedBox(width: context.spacing.space12),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                trailingWidget,
              ],
            ),
          ),
          if (divider) Container(height: 0.5, color: colors.rule),
        ],
      ),
    );
  }
}

class _PrefIcon extends StatelessWidget {
  const _PrefIcon({required this.icon, required this.bg});
  final IconData icon;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 16, color: context.colors.textPrimary),
    );
  }
}

class _PrefIconLetter extends StatelessWidget {
  const _PrefIconLetter({required this.letter, required this.bg});
  final String letter;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: AppTypography.displayOf(
          context,
          fontSize: 15,
          color: context.colors.textPrimary,
          height: 1.0,
        ),
      ),
    );
  }
}

// ──────────────────────────── Preference row label helpers

String _languageTrailing(String code) {
  switch (code) {
    case 'ar':
      return 'العربية';
    case 'en':
    default:
      return 'English';
  }
}

// ──────────────────────────── Snack helper

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
}

// ──────────────────────────── Outbound action helpers

void _shareApp(BuildContext context) {
  shareText(context, context.l10n.profileShareMessage, subject: 'Rihla');
}

Future<void> _openExternalUrl(BuildContext context, String url) async {
  final openLinkFailed = context.l10n.profileSnackOpenLinkFailed;
  final uri = Uri.parse(url);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    _showSnack(context, openLinkFailed);
  }
}

Future<void> _sendFeedback(BuildContext context, WidgetRef ref) async {
  final metadata = ref.read(appMetadataProvider).valueOrNull;
  final versionLabel = metadata?.versionLabel ?? 'Unknown';
  final noEmailApp = context.l10n.profileSnackNoEmailApp;
  final uri = Uri(
    scheme: 'mailto',
    path: AppLinks.feedbackEmail,
    queryParameters: {'subject': 'Rihla feedback · v$versionLabel'},
  );
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    _showSnack(context, noEmailApp);
  }
}

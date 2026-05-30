import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_links.dart';
import '../../../core/config/app_metadata.dart';
import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/utils/split_mode_display_name.dart';
import '../../../shared/widgets/directional_icon.dart';
import '../../../shared/widgets/r_amount.dart';
import '../../../shared/widgets/r_avatar.dart';
import '../../auth/providers/auth_email_link_bootstrap_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/services/data_deletion_service.dart';
import '../../auth/widgets/delete_account_dialog.dart';
import '../../auth/widgets/sign_out_confirm_dialog.dart';
import '../keys/profile_keys.dart';
import '../providers/profile_stats_provider.dart';
import '../widgets/currency_picker_sheet.dart';
import '../widgets/default_split_picker_sheet.dart';
import '../widgets/edit_name_bottom_sheet.dart';
import '../widgets/language_picker_sheet.dart';
import '../widgets/legal_links_sheet.dart';
import '../widgets/profile_display_section.dart';
import '../widgets/profile_qr_sheet.dart';

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
///   5. Preferences card (Notifications / Currency / Language / Default split)
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
    final statsAsync = ref.watch(profileStatsProvider);
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
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  children: [
                    const _PendingRecoveryBanner(),
                    const SizedBox(height: 4),
                    _IdentityCard(
                          name: settings.deviceName,
                          onEditName: () =>
                              _openEditSheet(context, ref, settings.deviceName),
                        )
                        .animate()
                        .fadeIn(delay: 80.ms, duration: 400.ms)
                        .slideY(begin: 0.08),
                    const SizedBox(height: 14),
                    _StatsGrid(statsAsync: statsAsync)
                        .animate()
                        .fadeIn(delay: 160.ms, duration: 400.ms)
                        .slideY(begin: 0.08),
                    const SizedBox(height: 18),
                    _SectionLabel(label: l10n.profileSectionPreferences),
                    const SizedBox(height: 8),
                    const _PreferencesCard().animate().fadeIn(
                      delay: 260.ms,
                      duration: 400.ms,
                    ),
                    const SizedBox(height: 18),
                    const Padding(
                      key: ProfileKeys.displaySection,
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: ProfileDisplaySection(),
                    ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
                    const SizedBox(height: 18),
                    _SectionLabel(label: l10n.profileSectionAccount),
                    const SizedBox(height: 8),
                    const _AccountCard().animate().fadeIn(
                      delay: 320.ms,
                      duration: 400.ms,
                    ),
                    const SizedBox(height: 18),
                    _SectionLabel(label: l10n.profileSectionAbout),
                    const SizedBox(height: 8),
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
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Iconsax.sms_tracking, size: 18, color: colors.textPrimary),
                const SizedBox(width: 12),
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
                const SizedBox(width: 8),
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

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.name, required this.onEditName});
  final String name;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final hasName = name.trim().isNotEmpty;
    final displayName = hasName ? name : l10n.profileSetYourName;
    // When no name is set there is no real @handle to share. A literal
    // '@traveller' fallback read like a truncated email ('traveller@'), so
    // show a plain, non-@ label instead (#163).
    final handle = hasName ? '@${_slug(name)}' : l10n.profileHandlePlaceholder;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
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
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
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
                          style: AppTypography.display(
                            fontSize: 28,
                            color: hasName
                                ? colors.textPrimary
                                : colors.primary,
                            letterSpacing: -0.5,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Iconsax.edit_2,
                          size: 14,
                          color: colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.profileAnonymousTraveller,
                    style: AppTypography.sans(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _IdentityChip(
                        leadingIcon: Iconsax.scan_barcode,
                        label: 'QR',
                        onTap: () => showProfileQrSheet(
                          context,
                          displayName: displayName,
                          handle: handle,
                        ),
                      ),
                      const SizedBox(width: 8),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: colors.cardSoft,
          borderRadius: BorderRadius.circular(9999),
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

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.statsAsync});
  final AsyncValue<ProfileStats> statsAsync;

  @override
  Widget build(BuildContext context) {
    final stats = statsAsync.valueOrNull;
    final l10n = context.l10n;
    return Padding(
      key: ProfileKeys.statsSection,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              statKey: ProfileKeys.statEvents,
              keyLabel: l10n.profileStatsJourneysLabel,
              value: stats == null ? '—' : '${stats.eventCount}',
              sub: l10n.profileStatsAllTime,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              statKey: ProfileKeys.statGroups,
              keyLabel: l10n.profileStatsGroupsLabel,
              value: stats == null ? '—' : '${stats.groupCount}',
              sub: l10n.profileStatsActive,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              statKey: ProfileKeys.statSpent,
              keyLabel: l10n.profileStatsSpentLabel,
              valueWidget: stats == null
                  ? null
                  : RAmount(
                      value: stats.totalSpent,
                      currency: 'OMR',
                      showCurrency: false,
                      size: 24,
                    ),
              value: stats == null ? '—' : null,
              sub: l10n.profileStatsLifetime,
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.shadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            keyLabel,
            style: AppTypography.mono(
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
          const SizedBox(height: 4),
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            label,
            style: AppTypography.mono(
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
    final notificationsOn =
        settings.pushNotificationsEnabled && !isPermissionDenied;
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: _RowsCard(
        rows: [
          _NotificationPrefRow(
            leading: _PrefIcon(
              icon: Iconsax.notification,
              bg: colors.paperDeep,
            ),
            value: notificationsOn,
            disabled: isPermissionDenied,
            onChanged: isPermissionDenied
                ? null
                : (value) {
                    HapticService.selection();
                    ref
                        .read(settingsProvider.notifier)
                        .setPushNotificationsEnabled(value);
                  },
          ),
          _PrefRow(
            leading: _PrefIcon(icon: Iconsax.global, bg: colors.cardSoft),
            label: context.l10n.profilePreferencesCurrency,
            trailingText: _currencyTrailing(settings.currencyCode),
            onTap: () => CurrencyPickerSheet.show(context),
          ),
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
            trailingText:
                splitModeDisplayName(settings.defaultSplitMode, context.l10n),
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
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

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final confirmed = await DeleteAccountDialog.show(context);
    if (confirmed != true) return;
    final result = await ref.read(dataDeletionServiceProvider).deleteAccount();
    final message = switch (result) {
      DeletionResult.ok => l10n.profileDeletionOk,
      DeletionResult.noUser => l10n.profileDeletionNoUser,
      DeletionResult.error => l10n.profileDeletionError,
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
    if (result == DeletionResult.ok && context.mounted) {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _signOut(
    BuildContext context,
    WidgetRef ref,
    String email,
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
      messenger.showSnackBar(
        SnackBar(content: Text(signOutFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final linkedEmail = ref.watch(linkedEmailProvider);
    final isLinked = linkedEmail != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: _RowsCard(
        rows: [
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
            divider: isLinked,
          ),
          if (isLinked)
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
  const _RowsCard({required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: context.shadows.raised,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: rows),
    );
  }
}

class _NotificationPrefRow extends StatelessWidget {
  const _NotificationPrefRow({
    required this.leading,
    required this.value,
    required this.disabled,
    required this.onChanged,
  });

  final Widget leading;
  final bool value;
  final bool disabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      key: ProfileKeys.notificationToggleTile,
      onTap: disabled ? null : () => onChanged?.call(!value),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
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
                        disabled
                            ? context.l10n.profileNotificationsDisabledHint
                            : context.l10n.profileNotificationsSubtitle,
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
                  onChanged: onChanged,
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
                if (leading != null) ...[leading!, const SizedBox(width: 12)],
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
        style: AppTypography.display(
          fontSize: 15,
          color: context.colors.textPrimary,
          height: 1.0,
        ),
      ),
    );
  }
}

// ──────────────────────────── Preference row label helpers

String _currencyTrailing(String code) {
  // #144: ISO code only — no composite 'code · symbol'.
  return code;
}

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
  Share.share(
    context.l10n.profileShareMessage,
    subject: 'Rihla',
  );
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

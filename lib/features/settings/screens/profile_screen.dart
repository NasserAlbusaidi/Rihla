import 'dart:async';

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
import '../../../shared/widgets/r_avatar.dart';
import '../../../shared/widgets/scroll_under_header.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/providers/shell_emptiness_gate.dart';
import '../../auth/services/auth_recovery_service.dart';
import '../../auth/widgets/durable_credential_sheet.dart';
import '../../auth/widgets/google_restore_action.dart';
import '../../auth/widgets/sign_out_confirm_dialog.dart';
import '../../groups/providers/group_balance_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../keys/profile_keys.dart';
import '../widgets/default_split_picker_sheet.dart';
import '../widgets/edit_name_bottom_sheet.dart';
import '../widgets/language_picker_sheet.dart';
import '../widgets/legal_links_sheet.dart';
import '../widgets/profile/backup_account_card.dart';
import '../widgets/profile/backup_status_chip.dart';
import '../widgets/profile/danger_zone_card.dart';
import '../widgets/profile/ghost_icon.dart';
import '../widgets/profile/identity_chip.dart';
import '../widgets/profile/notification_pref_row.dart';
import '../widgets/profile/pending_recovery_banner.dart';
import '../widgets/profile/pref_icon.dart';
import '../widgets/profile/pref_icon_letter.dart';
import '../widgets/profile/pref_row.dart';
import '../widgets/profile/rows_card.dart';
import '../widgets/profile/section_label.dart';
import '../widgets/profile/stats_grid.dart';
import '../widgets/profile/version_stamp.dart';
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
        child: ScrollUnderHeader(
          header: _TopBar(canPop: showBack),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: context.spacing.space32),
            child: Column(
              children: [
                const PendingRecoveryBanner(),
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
                  const BackupAccountCard(),
                ],
                const SizedBox(height: 14),
                const StatsGrid()
                    .animate()
                    .fadeIn(delay: 160.ms, duration: 400.ms)
                    .slideY(begin: 0.08),
                const SizedBox(height: 18),
                SectionLabel(label: l10n.profileSectionPreferences),
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
                SectionLabel(label: l10n.profileSectionAccount),
                SizedBox(height: context.spacing.space8),
                const _AccountCard().animate().fadeIn(
                  delay: 320.ms,
                  duration: 400.ms,
                ),
                const SizedBox(height: 18),
                SectionLabel(label: l10n.profileSectionDanger),
                SizedBox(height: context.spacing.space8),
                const DangerZoneCard().animate().fadeIn(
                  delay: 340.ms,
                  duration: 400.ms,
                ),
                const SizedBox(height: 18),
                SectionLabel(label: l10n.profileSectionAbout),
                SizedBox(height: context.spacing.space8),
                const _AboutCard().animate().fadeIn(
                  delay: 380.ms,
                  duration: 400.ms,
                ),
                const SizedBox(height: 18),
                const VersionStamp(),
              ],
            ),
          ),
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
                child: GhostIcon(
                  icon: Iconsax.arrow_left,
                  matchTextDirection: true,
                  semanticLabel: context.l10n.commonBack,
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
              child: GhostIcon(
                icon: Iconsax.export_1,
                semanticLabel: context.l10n.profileShareA11yLabel,
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
    // #1168: key the avatar's palette slot on the stable uid, not the
    // localized/mutable name, so it matches this same person's color
    // everywhere else they're rendered (group member lists, ledger rosters).
    final currentUserId = ref.watch(currentUserIdProvider);
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
                    colorKey: currentUserId,
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: onEditName,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            key: hasName
                                ? ProfileKeys.displayName
                                : ProfileKeys.setNamePrompt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                  BackupStatusChip(isDurable: isDurable),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IdentityChip(
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
      child: RowsCard(
        rows: [
          NotificationPrefRow(
            leading: PrefIcon(
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
          PrefRow(
            leading: PrefIconLetter(letter: 'Aa', bg: colors.saffronTint),
            label: context.l10n.profilePreferencesLanguage,
            trailingText: _languageTrailing(settings.languageCode),
            onTap: () => LanguagePickerSheet.show(context),
          ),
          PrefRow(
            leading: PrefIcon(
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
      child: RowsCard(
        rows: [
          PrefRow(
            label: context.l10n.profileAboutHelpCenter,
            trailing: DirectionalIcon(
              Iconsax.arrow_right_3,
              size: 16,
              color: colors.textSecondary,
            ),
            onTap: () => _openExternalUrl(context, AppLinks.helpUrl),
          ),
          PrefRow(
            tileKey: ProfileKeys.feedbackTile,
            label: context.l10n.profileAboutSendFeedbackRow,
            trailing: DirectionalIcon(
              Iconsax.arrow_right_3,
              size: 16,
              color: colors.textSecondary,
            ),
            onTap: () => _sendFeedback(context, ref),
          ),
          PrefRow(
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
    final service = ref.read(authRecoveryServiceProvider);
    try {
      await service.signOutCurrentDevice();
      messenger.showSnackBar(SnackBar(content: Text(signedOut)));
    } on PendingWritesNotFlushedException {
      if (!context.mounted) return;
      final discard = await SignOutPendingWritesDialog.show(context);
      if (discard != true) return;
      try {
        await service.signOutCurrentDevice(discardPendingWrites: true);
        messenger.showSnackBar(SnackBar(content: Text(signedOut)));
      } catch (_) {
        messenger.showSnackBar(SnackBar(content: Text(signOutFailed)));
      }
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
      probeHasLiveData: ref.read(shellEmptinessServerProbeProvider),
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
    // irreversible Delete moved to its own DangerZoneCard below. The trailing
    // hairline is stripped because the last visible row varies by account state.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space20),
      child: RowsCard(
        rows: _stripLastDivider([
          if (googleAccount != null)
            PrefRow(
              tileKey: ProfileKeys.googleAccountTile,
              leading: PrefIcon(
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
            PrefRow(
              tileKey: ProfileKeys.googleLinkTile,
              leading: PrefIcon(
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
          PrefRow(
            tileKey: ProfileKeys.linkedEmailTile,
            leading: PrefIcon(icon: Iconsax.sms, bg: colors.cardSoft),
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
            PrefRow(
              tileKey: ProfileKeys.signOutDeviceTile,
              leading: PrefIcon(icon: Iconsax.logout, bg: colors.cardSoft),
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
            PrefRow(
              tileKey: ProfileKeys.profileRestoreGoogleTile,
              leading: PrefIcon(icon: Iconsax.refresh, bg: colors.cardSoft),
              label: context.l10n.homeRestoreWithGoogle,
              trailing: DirectionalIcon(
                Iconsax.arrow_right_3,
                size: 16,
                color: colors.textSecondary,
              ),
              onTap: () => triggerGoogleRestore(context, ref),
              divider: true,
            ),
            PrefRow(
              tileKey: ProfileKeys.profileRestoreEmailTile,
              leading: PrefIcon(
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

// ──────────────────────────── Rows + supporting

/// Returns [rows] with the last row's bottom divider removed, so an account
/// card never ends on a stray hairline no matter which conditional row is last
/// (#487 bullet 3 — the trailing row varies with account state).
List<Widget> _stripLastDivider(List<PrefRow> rows) {
  if (rows.isEmpty) return rows;
  return [
    ...rows.sublist(0, rows.length - 1),
    rows.last.copyWith(divider: false),
  ];
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

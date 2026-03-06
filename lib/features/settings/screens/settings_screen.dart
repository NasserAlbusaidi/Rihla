import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/app_metadata.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/models/app_settings_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/providers/profile_provider.dart';
import '../../auth/services/profile_service.dart';

/// Settings Screen with profile, theme, and about sections
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _notificationSubtitle(NotificationStatus status) {
    return switch (status) {
      NotificationStatus.enabled => 'Enabled on this device',
      NotificationStatus.permissionDenied =>
        'Permission denied. Enable it in system settings.',
      NotificationStatus.error => 'Could not register this device right now',
      NotificationStatus.off => 'Get notified about trip updates',
    };
  }

  Widget _getAvatarIcon(String avatar, {double size = 24, Color? color}) {
    switch (avatar) {
      case 'mountains':
        return Icon(Iconsax.mask, size: size, color: color);
      case 'tent':
        return Icon(Iconsax.house, size: size, color: color);
      case 'backpack':
        return Icon(Iconsax.bag_2, size: size, color: color);
      case 'compass':
        return Icon(Iconsax.radar, size: size, color: color);
      case 'map':
        return Icon(Iconsax.map, size: size, color: color);
      case 'fire':
        return Icon(Iconsax.flash, size: size, color: color);
      case 'tree':
        return Icon(Iconsax.tree, size: size, color: color);
      case 'car':
        return Icon(Iconsax.car, size: size, color: color);
      case 'camera':
        return Icon(Iconsax.camera, size: size, color: color);
      case 'stars':
        return Icon(Iconsax.magic_star, size: size, color: color);
      default:
        return Icon(Iconsax.user, size: size, color: color);
    }
  }

  void _showEditProfileDialog(BuildContext context) {
    final profileAsync = ref.read(profileNotifierProvider);
    final profile = profileAsync.valueOrNull;

    final nameController = TextEditingController(
      text: profile?.displayName ?? '',
    );
    String selectedAvatar =
        profile?.avatarUrl ?? ProfileService.availableAvatars.first;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Edit Profile'),
          content: SizedBox(
            width: 340, // Fixed width to satisfy IntrinsicWidth
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Avatar Selection
                  const Text(
                    'Choose Avatar',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: ProfileService.availableAvatars.length,
                      itemBuilder: (context, index) {
                        final avatar = ProfileService.availableAvatars[index];
                        final isSelected = selectedAvatar == avatar;
                        return GestureDetector(
                          onTap: () {
                            HapticService.selection();
                            setDialogState(() => selectedAvatar = avatar);
                          },
                          child: Container(
                            width: 56,
                            height: 56,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.surfaceLight,
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: _getAvatarIcon(
                                avatar,
                                size: 24,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: nameController,
                    inputFormatters: [LengthLimitingTextInputFormatter(50)],
                    decoration: const InputDecoration(
                      labelText: 'Display Name',
                      hintText: 'Enter your name',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await ref
                      .read(profileNotifierProvider.notifier)
                      .updateProfile(
                        displayName: nameController.text.trim(),
                        avatarUrl: selectedAvatar,
                      );
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showThemeDialog() {
    final currentTheme = ref.read(settingsProvider).themeMode;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Choose Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _themeOption(
              'System Default',
              Iconsax.setting_2,
              AppThemeMode.system,
              currentTheme,
            ),
            _themeOption(
              'Light Mode',
              Iconsax.sun_1,
              AppThemeMode.light,
              currentTheme,
            ),
            _themeOption(
              'Dark Mode',
              Iconsax.moon,
              AppThemeMode.dark,
              currentTheme,
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeOption(
    String title,
    IconData icon,
    AppThemeMode mode,
    AppThemeMode current,
  ) {
    final isSelected = mode == current;
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppColors.primary : null),
      title: Text(
        title,
        style: TextStyle(color: isSelected ? AppColors.primary : null),
      ),
      trailing: isSelected
          ? const Icon(Icons.check, color: AppColors.primary)
          : null,
      onTap: () {
        ref.read(settingsProvider.notifier).setThemeMode(mode);
        Navigator.pop(context);
      },
    );
  }

  void _showLanguageDialog() {
    final currentLang = ref.read(settingsProvider).languageCode;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Choose Language'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _langOption('English', 'en', currentLang),
            _langOption('العربية', 'ar', currentLang),
          ],
        ),
      ),
    );
  }

  Widget _langOption(String title, String code, String current) {
    final isSelected = code == current;
    return ListTile(
      title: Text(
        title,
        style: TextStyle(color: isSelected ? AppColors.primary : null),
      ),
      trailing: isSelected
          ? const Icon(Icons.check, color: AppColors.primary)
          : null,
      onTap: () {
        ref.read(settingsProvider.notifier).setLanguage(code);
        Navigator.pop(context);
      },
    );
  }

  void _showCurrencyDialog() {
    final currentCurrency = ref.read(settingsProvider).currencyCode;
    final currencies = AppFormatters.currencyConfig.entries.toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Choose Currency'),
        content: SizedBox(
          width: 300, // Fixed width instead of infinite
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: currencies.length,
            itemBuilder: (context, index) {
              final entry = currencies[index];
              final currency = entry.key;
              final config = entry.value;
              final isSelected = currency == currentCurrency;
              return ListTile(
                title: Text(
                  '${config.symbol} - $currency',
                  style: TextStyle(
                    color: isSelected ? AppColors.primary : null,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  ref.read(settingsProvider.notifier).setCurrency(currency);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Privacy Policy'),
        content: const SingleChildScrollView(
          child: Text(
            '${AppMetadata.visibleAppName} respects your privacy.\n\n'
            '• We collect minimal data needed to provide the service\n'
            '• Your trip and expense data is stored securely\n'
            '• We do not sell your data to third parties\n'
            '• You can delete your account and data at any time\n\n'
            'For questions, contact support@rihla.app',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showTermsOfService() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Terms of Service'),
        content: const SingleChildScrollView(
          child: Text(
            'By using ${AppMetadata.visibleAppName}, you agree to:\n\n'
            '• Use the app for lawful purposes only\n'
            '• Provide accurate information\n'
            '• Respect other users\' privacy\n'
            '• Not misuse the expense splitting features\n\n'
            'We reserve the right to suspend accounts that violate these terms.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final settings = ref.watch(settingsProvider);
    final notificationStatus = ref.watch(notificationStatusProvider);
    final appMetadata =
        ref.watch(appMetadataProvider).valueOrNull ?? AppMetadata.fallback();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // App Bar
            SliverToBoxAdapter(
              child: _buildAppBar(
                context,
              ).animate().fadeIn().slideY(begin: -0.2),
            ),

            // Profile Section
            SliverToBoxAdapter(
              child: _buildProfileSection(
                context,
                user,
              ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1),
            ),

            // Preferences Header
            SliverToBoxAdapter(
              child: _buildSectionHeader('PREFERENCES')
                  .animate()
                  .fadeIn(delay: 150.ms),
            ),

            // Preferences Section
            SliverToBoxAdapter(
              child: _buildPreferencesSection(settings)
                  .animate()
                  .fadeIn(delay: 200.ms)
                  .slideY(begin: 0.1),
            ),

            // Notifications Section
            SliverToBoxAdapter(
              child: _buildNotificationsSection(settings, notificationStatus)
                  .animate()
                  .fadeIn(delay: 300.ms)
                  .slideY(begin: 0.1),
            ),

            // About Header
            SliverToBoxAdapter(
              child: _buildSectionHeader('ABOUT')
                  .animate()
                  .fadeIn(delay: 350.ms),
            ),

            // About Section
            SliverToBoxAdapter(
              child: _buildAboutSection(appMetadata)
                  .animate()
                  .fadeIn(delay: 400.ms)
                  .slideY(begin: 0.1),
            ),

            // Sign Out
            SliverToBoxAdapter(
              child: _buildSignOutButton(
                context,
              ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.1),
            ),

            // Footer
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Text(
                  'Made with love in Oman',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted.withValues(alpha: 0.5),
                    letterSpacing: 0.5,
                  ),
                ),
              ).animate().fadeIn(delay: 600.ms),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: IconButton(
                  icon: const Icon(
                    Iconsax.arrow_left,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () => context.pop(),
                ),
              ),
              const Text(
                'SETTINGS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context, dynamic user) {
    final profileAsync = ref.watch(profileNotifierProvider);

    return profileAsync.when(
      data: (profile) {
        final email = user?.email ?? 'OFFLINE';
        final displayName = profile?.displayName ?? email.split('@').first;
        final avatar = profile?.avatarUrl ?? 'backpack';

        return Transform.translate(
          offset: const Offset(0, -20),
          child: Container(
            margin: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.borderLight, width: 1.5),
              boxShadow: AppColors.cardShadowLarge,
            ),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: _getAvatarIcon(
                      avatar,
                      size: 36,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _showEditProfileDialog(context),
                  icon: const Icon(
                    Iconsax.edit,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => Transform.translate(
        offset: const Offset(0, -20),
        child: Container(
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 4),
          height: 120,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.borderLight, width: 1.5),
          ),
        ),
      ),
      error: (e, _) => Center(child: Text('Error loading profile')),
    );
  }

  Widget _buildPreferencesSection(AppSettings settings) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight, width: 1.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.setting_2, size: 18, color: AppColors.primary),
              const SizedBox(width: 12),
              const Text(
                'PREFERENCES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textMuted,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSettingsItem(
            icon: Iconsax.money,
            title: 'Currency',
            subtitle: settings.currencyCode,
            onTap: () => _showCurrencyDialog(),
          ),
          _buildSettingsItem(
            icon: Iconsax.global,
            title: 'Language',
            subtitle: settings.languageCode == 'en' ? 'English' : 'العربية',
            onTap: () => _showLanguageDialog(),
          ),
          _buildSettingsItem(
            icon: Iconsax.moon,
            title: 'Theme',
            subtitle: settings.themeMode == AppThemeMode.system
                ? 'Follow system'
                : (settings.themeMode == AppThemeMode.light
                      ? 'Light'
                      : 'Dark'),
            onTap: () => _showThemeDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsSection(
    AppSettings settings,
    NotificationStatus notificationStatus,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight, width: 1.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Iconsax.notification_bing,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              const Text(
                'NOTIFICATIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textMuted,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSettingsToggle(
            icon: Iconsax.notification,
            title: 'Push Notifications',
            subtitle: _notificationSubtitle(notificationStatus),
            value: settings.pushNotificationsEnabled,
            onChanged: (value) async {
              final notifService = ref.read(notificationServiceProvider);
              if (value) {
                final enabled = await notifService.initialize();
                await ref
                    .read(settingsProvider.notifier)
                    .setPushNotificationsEnabled(enabled);
                if (!enabled && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Notifications are unavailable until permission is granted.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } else {
                await notifService.removeToken();
                await ref
                    .read(settingsProvider.notifier)
                    .setPushNotificationsEnabled(false);
              }
            },
          ),
          _buildSettingsToggle(
            icon: Iconsax.wallet_3,
            title: 'Expense Updates',
            subtitle: 'Payment and debt reminders',
            value: settings.expenseUpdatesEnabled,
            onChanged: (value) {
              ref.read(settingsProvider.notifier).setExpenseUpdatesEnabled(
                    value,
                  );
            },
          ),
          _buildSettingsToggle(
            icon: Iconsax.timer_1,
            title: 'Departure Countdown',
            subtitle: 'Reminders as your trip approaches',
            value: settings.departureCountdownEnabled,
            onChanged: (value) {
              ref
                  .read(settingsProvider.notifier)
                  .setDepartureCountdownEnabled(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection(AppMetadata appMetadata) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight, width: 1.5),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Iconsax.info_circle,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              const Text(
                'ABOUT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textMuted,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          _buildSettingsItem(
            icon: Iconsax.document_text,
            title: 'Privacy Policy',
            onTap: () => _showPrivacyPolicy(),
          ),
          _buildSettingsItem(
            icon: Iconsax.document,
            title: 'Terms of Service',
            onTap: () => _showTermsOfService(),
          ),
          const SizedBox(height: 16),
          // Version + Build Number
          Center(
            child: Text(
              'Version ${appMetadata.version} (${appMetadata.buildNumber})',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignOutButton(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Text(
                'Sign out?',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              content: const Text(
                'You can sign back in anytime.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    ref.read(authServiceProvider).signOut();
                  },
                  child: const Text(
                    'Sign Out',
                    style: TextStyle(
                      color: AppColors.rose,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: AppColors.rose.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.rose.withValues(alpha: 0.15),
              width: 1.5,
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Iconsax.logout, color: AppColors.rose, size: 20),
              SizedBox(width: 12),
              Text(
                'Sign Out',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.rose,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(
              Iconsax.arrow_right_3,
              size: 16,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsToggle({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.primary.withValues(alpha: 0.2),
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

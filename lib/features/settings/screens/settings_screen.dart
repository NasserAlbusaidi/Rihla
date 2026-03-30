import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/config/app_metadata.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_theme.dart';
// AppFormatters not needed for settings
import '../../../core/providers/settings_provider.dart';
import '../../../core/models/app_settings_model.dart';
import '../keys/settings_keys.dart';

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
        HapticService.selection();
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
        HapticService.selection();
        ref.read(settingsProvider.notifier).setLanguage(code);
        Navigator.pop(context);
      },
    );
  }

  void _showCurrencyDialog() {
    final currentCurrency = ref.read(settingsProvider).currencyCode;
    final currencies = {
      'OMR': 'ر.ع.',
      'USD': '\$',
      'EUR': '€',
      'GBP': '£',
      'AED': 'د.إ',
      'SAR': 'ر.س',
    };
    final entries = currencies.entries.toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Choose Currency'),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final currency = entry.key;
              final symbol = entry.value;
              final isSelected = currency == currentCurrency;
              return ListTile(
                title: Text(
                  '$symbol - $currency',
                  style: TextStyle(
                    color: isSelected ? AppColors.primary : null,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  HapticService.selection();
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

  void _showDeviceNameDialog() {
    final controller = TextEditingController(
      text: ref.read(settingsProvider).deviceName,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Your Name'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Ahmed',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(settingsProvider.notifier).setDeviceName(
                controller.text.trim(),
              );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
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
    final settings = ref.watch(settingsProvider);
    final notificationStatus = ref.watch(notificationStatusProvider);
    final appMetadata =
        ref.watch(appMetadataProvider).valueOrNull ?? AppMetadata.fallback();

    return Scaffold(
      key: SettingsKeys.screen,
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
              child: _buildProfileSection(settings)
                  .animate()
                  .fadeIn(delay: 150.ms)
                  .slideY(begin: 0.1),
            ),

            // Preferences Section
            SliverToBoxAdapter(
              child: _buildPreferencesSection(settings, notificationStatus)
                  .animate()
                  .fadeIn(delay: 250.ms)
                  .slideY(begin: 0.1),
            ),

            // About Section
            SliverToBoxAdapter(
              child: _buildAboutSection(appMetadata)
                  .animate()
                  .fadeIn(delay: 350.ms)
                  .slideY(begin: 0.1),
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
              ).animate().fadeIn(delay: 500.ms),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection(AppSettings settings) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Icon(Iconsax.user, size: 16, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'PROFILE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textMuted,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Iconsax.user_edit,
                  size: 18, color: AppColors.primary),
            ),
            title: const Text(
              'Your Name',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              settings.deviceName.isEmpty ? 'Not set' : settings.deviceName,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            trailing: const Icon(Iconsax.arrow_right_3,
                size: 16, color: AppColors.textMuted),
            onTap: _showDeviceNameDialog,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16,
              color: AppColors.border),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Iconsax.profile_circle,
                  size: 18, color: AppColors.primary),
            ),
            title: const Text(
              'App Version',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: const Text(
              AppMetadata.visibleAppName,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: IconButton(
              icon: const Icon(
                Iconsax.arrow_left,
                color: AppColors.textPrimary,
                size: 20,
              ),
              onPressed: () => context.pop(),
            ),
          ),
          const Text(
            'SETTINGS',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildPreferencesSection(
      AppSettings settings, NotificationStatus notificationStatus) {
    final isNotifEnabled = notificationStatus == NotificationStatus.enabled;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Icon(Iconsax.setting_2, size: 16, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
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
          ),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Iconsax.money,
                  size: 18, color: AppColors.primary),
            ),
            title: const Text(
              'Currency',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              settings.currencyCode,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            trailing: const Icon(Iconsax.arrow_right_3,
                size: 16, color: AppColors.textMuted),
            onTap: _showCurrencyDialog,
          ),
          const Divider(
              height: 1, indent: 16, endIndent: 16, color: AppColors.border),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Iconsax.global,
                  size: 18, color: AppColors.primary),
            ),
            title: const Text(
              'Language',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              settings.languageCode == 'en' ? 'English' : 'العربية',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            trailing: const Icon(Iconsax.arrow_right_3,
                size: 16, color: AppColors.textMuted),
            onTap: _showLanguageDialog,
          ),
          const Divider(
              height: 1, indent: 16, endIndent: 16, color: AppColors.border),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Iconsax.moon, size: 18, color: AppColors.primary),
            ),
            title: const Text(
              'Theme',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              settings.themeMode == AppThemeMode.system
                  ? 'Follow system'
                  : (settings.themeMode == AppThemeMode.light ? 'Light' : 'Dark'),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            trailing: const Icon(Iconsax.arrow_right_3,
                size: 16, color: AppColors.textMuted),
            onTap: _showThemeDialog,
          ),
          const Divider(
              height: 1, indent: 16, endIndent: 16, color: AppColors.border),
          SwitchListTile(
            secondary: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Iconsax.notification,
                  size: 18, color: AppColors.primary),
            ),
            title: const Text(
              'Push Notifications',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              _notificationSubtitle(notificationStatus),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            value: isNotifEnabled,
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
            onChanged: (value) async {
              final notifService = ref.read(notificationServiceProvider);
              if (value) {
                final enabled = await notifService.initialize();
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
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildAboutSection(AppMetadata appMetadata) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Icon(Iconsax.info_circle, size: 16, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
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
          ),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Iconsax.document_text,
                  size: 18, color: AppColors.primary),
            ),
            title: const Text(
              'Privacy Policy',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            trailing: const Icon(Iconsax.arrow_right_3,
                size: 16, color: AppColors.textMuted),
            onTap: _showPrivacyPolicy,
          ),
          const Divider(
              height: 1, indent: 16, endIndent: 16, color: AppColors.border),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Iconsax.document,
                  size: 18, color: AppColors.primary),
            ),
            title: const Text(
              'Terms of Service',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            trailing: const Icon(Iconsax.arrow_right_3,
                size: 16, color: AppColors.textMuted),
            onTap: _showTermsOfService,
          ),
          const Divider(
              height: 1, indent: 16, endIndent: 16, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
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
          ),
        ],
      ),
    );
  }

}

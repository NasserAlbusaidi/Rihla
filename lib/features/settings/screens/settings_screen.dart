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
            icon: Iconsax.user,
            title: 'Your Name',
            subtitle: settings.deviceName.isEmpty ? 'Not set' : settings.deviceName,
            onTap: () => _showDeviceNameDialog(),
          ),
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
    final isEnabled = notificationStatus == NotificationStatus.enabled;

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
            value: isEnabled,
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

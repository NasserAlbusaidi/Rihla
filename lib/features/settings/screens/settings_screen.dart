import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/models/app_settings_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/providers/profile_provider.dart';
import '../../auth/services/profile_service.dart';
// import '../../auth/models/user_profile_model.dart'; // Unused now

/// Settings Screen with profile, theme, and about sections
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _expenseReminders = true;
  bool _tripCountdown = true;

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature coming soon!'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.primary,
      ),
    );
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
                          onTap: () =>
                              setDialogState(() => selectedAvatar = avatar),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 30,
                              backgroundColor: AppColors.surfaceLight,
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
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
    const currencies = ['OMR', 'USD', 'EUR', 'GBP', 'AED', 'SAR'];

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
              final currency = currencies[index];
              final isSelected = currency == currentCurrency;
              return ListTile(
                title: Text(
                  currency,
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
            'Rihla respects your privacy.\n\n'
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
            'By using Rihla, you agree to:\n\n'
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

            // Preferences Section
            SliverToBoxAdapter(
              child: _buildPreferencesSection()
                  .animate()
                  .fadeIn(delay: 200.ms)
                  .slideY(begin: 0.1),
            ),

            // Notifications Section
            SliverToBoxAdapter(
              child: _buildNotificationsSection()
                  .animate()
                  .fadeIn(delay: 300.ms)
                  .slideY(begin: 0.1),
            ),

            // About Section
            SliverToBoxAdapter(
              child: _buildAboutSection()
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

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Iconsax.arrow_left),
            onPressed: () => context.pop(),
          ),
          const Expanded(
            child: Text(
              'Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context, dynamic user) {
    final profileAsync = ref.watch(profileNotifierProvider);

    return profileAsync.when(
      data: (profile) {
        final email = user?.email ?? 'Not signed in';
        final displayName = profile?.displayName ?? email.split('@').first;
        final avatar = profile?.avatarUrl ?? 'backpack';

        return Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: _getAvatarIcon(avatar, size: 32, color: Colors.white),
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),

              // Edit Button
              IconButton(
                icon: const Icon(Iconsax.edit_2, color: Colors.white),
                onPressed: () => _showEditProfileDialog(context),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        height: 160,
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Container(
        height: 160,
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildPreferencesSection() {
    final settings = ref.watch(settingsProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Iconsax.setting_2, size: 20, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Preferences',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Currency
          _buildSettingsItem(
            icon: Iconsax.money,
            title: 'Currency',
            subtitle: settings.currencyCode,
            onTap: () => _showCurrencyDialog(),
          ),

          const Divider(height: 24),

          // Language
          _buildSettingsItem(
            icon: Iconsax.global,
            title: 'Language',
            subtitle: settings.languageCode == 'en' ? 'English' : 'العربية',
            onTap: () => _showLanguageDialog(),
          ),

          const Divider(height: 24),

          // Theme
          _buildSettingsItem(
            icon: Iconsax.sun_1,
            title: 'Theme',
            subtitle: settings.themeMode == AppThemeMode.system
                ? 'System Default'
                : (settings.themeMode == AppThemeMode.light
                      ? 'Light Mode'
                      : 'Dark Mode'),
            onTap: () => _showThemeDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsSection() {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Iconsax.notification, size: 20, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Enable Notifications
          _buildSettingsToggle(
            icon: Iconsax.notification_bing,
            title: 'Push Notifications',
            subtitle: 'Receive updates on your phone',
            value: _notificationsEnabled,
            onChanged: (value) => setState(() => _notificationsEnabled = value),
          ),

          const Divider(height: 24),

          // Expense Reminders
          _buildSettingsToggle(
            icon: Iconsax.wallet_2,
            title: 'Expense Reminders',
            subtitle: 'Remind me about unpaid debts',
            value: _expenseReminders,
            onChanged: (value) => setState(() => _expenseReminders = value),
          ),

          const Divider(height: 24),

          // Trip Countdown
          _buildSettingsToggle(
            icon: Iconsax.timer_1,
            title: 'Trip Countdown',
            subtitle: 'Daily countdown notifications',
            value: _tripCountdown,
            onChanged: (value) => setState(() => _tripCountdown = value),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Iconsax.info_circle, size: 20, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'About',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildSettingsItem(
            icon: Iconsax.document_text,
            title: 'Privacy Policy',
            onTap: () => _showPrivacyPolicy(),
          ),

          const Divider(height: 24),

          _buildSettingsItem(
            icon: Iconsax.document,
            title: 'Terms of Service',
            onTap: () => _showTermsOfService(),
          ),

          const Divider(height: 24),

          _buildSettingsItem(
            icon: Iconsax.star,
            title: 'Rate the App',
            onTap: () => _showComingSoon('App Store rating'),
          ),

          const Divider(height: 24),

          // Version
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Iconsax.code,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Version',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '1.0.0 (Build 1)',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignOutButton(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      child: GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Sign Out'),
              content: const Text('Are you sure you want to sign out?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ref.read(authServiceProvider).signOut();
                  },
                  child: const Text(
                    'Sign Out',
                    style: TextStyle(color: AppColors.error),
                  ),
                ),
              ],
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Iconsax.logout, color: AppColors.error),
              SizedBox(width: 8),
              Text(
                'Sign Out',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
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
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(
            Iconsax.arrow_right_3,
            size: 18,
            color: AppColors.textMuted,
          ),
        ],
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
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
        ),
      ],
    );
  }
}

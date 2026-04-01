# Phase 26 Handoff — Patterns from settings_screen.dart

This document captures UI patterns from the deleted `lib/features/settings/screens/settings_screen.dart`
for reuse in Phase 26 (Settings/Preferences section inside `profile_screen.dart`).

## Section Header Pattern

```dart
// Icon + uppercase label. textMuted is DECORATIVE here (section overline).
Padding(
  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
  child: Row(
    children: [
      Icon(Iconsax.setting_2, size: 16, color: AppColorTokens.light.primary),
      SizedBox(width: 8),
      Text(
        'PREFERENCES',  // uppercase label
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: AppColorTokens.light.textMuted,
          letterSpacing: 1.5,
        ),
      ),
    ],
  ),
),
```

## List Tile Leading Icon Pattern (36px container)

```dart
// 36px Container with inputFill bg, borderRadius 10 — used as ListTile leading.
Container(
  width: 36,
  height: 36,
  decoration: BoxDecoration(
    color: AppColorTokens.light.inputFill,
    borderRadius: BorderRadius.circular(10),
  ),
  child: Icon(Iconsax.money, size: 18, color: AppColorTokens.light.primary),
),
```

## Preferences Section Patterns

### Notification Toggle (SwitchListTile)

```dart
SwitchListTile(
  secondary: Container(
    width: 36, height: 36,
    decoration: BoxDecoration(
      color: AppColorTokens.light.inputFill,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(Iconsax.notification, size: 18, color: AppColorTokens.light.primary),
  ),
  title: Text(
    'Push Notifications',
    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColorTokens.light.textPrimary),
  ),
  subtitle: Text(
    _notificationSubtitle(notificationStatus),
    style: TextStyle(fontSize: 12, color: AppColorTokens.light.textSecondary),
  ),
  value: isNotifEnabled,
  activeThumbColor: AppColorTokens.light.primary,
  activeTrackColor: AppColorTokens.light.primary.withValues(alpha: 0.3),
  onChanged: (value) async {
    final notifService = ref.read(notificationServiceProvider);
    if (value) {
      final enabled = await notifService.initialize();
      if (!enabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notifications are unavailable until permission is granted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      await notifService.removeToken();
    }
  },
),
```

Notification status helper:
```dart
String _notificationSubtitle(NotificationStatus status) {
  return switch (status) {
    NotificationStatus.enabled => 'Enabled on this device',
    NotificationStatus.permissionDenied => 'Permission denied. Enable it in system settings.',
    NotificationStatus.error => 'Could not register this device right now',
    NotificationStatus.off => 'Get notified about trip updates',
  };
}
```

### Currency Dialog

```dart
void _showCurrencyDialog() {
  final currentCurrency = ref.read(settingsProvider).currencyCode;
  final currencies = {
    'OMR': 'ر.ع.', 'USD': '\$', 'EUR': '€', 'GBP': '£', 'AED': 'د.إ', 'SAR': 'ر.س',
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
                style: TextStyle(color: isSelected ? AppColorTokens.light.primary : null),
              ),
              trailing: isSelected ? Icon(Icons.check, color: AppColorTokens.light.primary) : null,
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
```

### Language Dialog

```dart
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
      style: TextStyle(color: isSelected ? AppColorTokens.light.primary : null),
    ),
    trailing: isSelected ? Icon(Icons.check, color: AppColorTokens.light.primary) : null,
    onTap: () {
      HapticService.selection();
      ref.read(settingsProvider.notifier).setLanguage(code);
      Navigator.pop(context);
    },
  );
}
```

### Theme Dialog

```dart
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
          _themeOption('System Default', Iconsax.setting_2, AppThemeMode.system, currentTheme),
          _themeOption('Light Mode', Iconsax.sun_1, AppThemeMode.light, currentTheme),
          _themeOption('Dark Mode', Iconsax.moon, AppThemeMode.dark, currentTheme),
        ],
      ),
    ),
  );
}

Widget _themeOption(String title, IconData icon, AppThemeMode mode, AppThemeMode current) {
  final isSelected = mode == current;
  return ListTile(
    leading: Icon(icon, color: isSelected ? AppColorTokens.light.primary : null),
    title: Text(title, style: TextStyle(color: isSelected ? AppColorTokens.light.primary : null)),
    trailing: isSelected ? Icon(Icons.check, color: AppColorTokens.light.primary) : null,
    onTap: () {
      HapticService.selection();
      ref.read(settingsProvider.notifier).setThemeMode(mode);
      Navigator.pop(context);
    },
  );
}
```

## About Section Patterns

### Privacy Policy Dialog

```dart
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ),
  );
}
```

### Terms of Service Dialog

```dart
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ),
  );
}
```

### Version Display

```dart
// Inside About section card:
Padding(
  padding: const EdgeInsets.symmetric(vertical: 16),
  child: Center(
    child: Text(
      'Version ${appMetadata.version} (${appMetadata.buildNumber})',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColorTokens.light.textMuted,
      ),
      textAlign: TextAlign.center,
    ),
  ),
),
```

## Required Imports for Phase 26

```dart
import '../../../core/config/app_metadata.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/models/app_settings_model.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/shadow_tokens.dart';
```

Key providers:
- `notificationStatusProvider` — watches `NotificationStatus` enum
- `notificationServiceProvider` — provides `NotificationService` instance
- `appMetadataProvider` — `FutureProvider<AppMetadata>` for version/build number
- `settingsProvider` — `StateNotifierProvider<SettingsNotifier, AppSettings>`

## Section Card Container Pattern

All sections use the same card container:
```dart
Container(
  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
  decoration: BoxDecoration(
    color: AppColorTokens.light.cardSurface,
    borderRadius: BorderRadius.circular(24),
    boxShadow: AppShadowTokens.standard.raised,
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Section header (icon + uppercase label)
      // ListTile rows with Divider(height: 1, indent: 16, endIndent: 16) between them
      const SizedBox(height: 8),
    ],
  ),
)
```

## Footer Pattern

```dart
Padding(
  padding: const EdgeInsets.only(bottom: 40),
  child: Text(
    'Made with love in Oman',
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColorTokens.light.textMuted.withValues(alpha: 0.5),
      letterSpacing: 0.5,
    ),
  ),
).animate().fadeIn(delay: 500.ms),
```

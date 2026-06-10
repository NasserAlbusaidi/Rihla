import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../extensions/build_context_l10n.dart';
import '../router/app_router.dart';
import '../theme/tokens/domain_aliases.dart';
import '../theme/tokens/typography_tokens.dart';

/// Soft in-app rationale shown *before* the OS push-permission dialog (#352).
///
/// Returns `true` when the user taps [Turn on], `false` for [Not now] or a
/// barrier dismiss. The caller ([NotificationPrompt]) only proceeds to the OS
/// dialog on `true`.
Future<bool> showNotificationRationaleSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _NotificationRationaleSheet(),
  );
  return result ?? false;
}

/// Resolves a `bool?` permission decision for [NotificationPrompt] without the
/// service owning a `BuildContext`:
///
/// * `true`  — user opted in ([Turn on])
/// * `false` — user declined ([Not now] / dismissed)
/// * `null`  — the sheet could **not** be presented (no root navigator yet).
///   The prompt treats `null` as "ask again later" and leaves the once-only
///   `notificationPromptSeen` flag untouched, so a transient mid-navigation
///   null never silently burns the single lifetime ask.
typedef NotificationRationaleGate = Future<bool?> Function();

/// Default gate: shows the rationale on the **root** navigator (stable across
/// `pushReplacement`, so the modal stacks above whatever page is current).
final notificationRationaleGateProvider = Provider<NotificationRationaleGate>((
  ref,
) {
  return () async {
    final context =
        ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return null;
    return showNotificationRationaleSheet(context);
  };
});

class _NotificationRationaleSheet extends StatelessWidget {
  const _NotificationRationaleSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final l10n = context.l10n;

    return SafeArea(
      child: Container(
        margin: EdgeInsets.fromLTRB(
          spacing.space16,
          0,
          spacing.space16,
          spacing.space16,
        ),
        padding: EdgeInsets.all(spacing.space24),
        decoration: BoxDecoration(
          color: colors.cardSurface,
          borderRadius: BorderRadius.circular(spacing.radiusLarge),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: EdgeInsets.only(bottom: spacing.space20),
                decoration: BoxDecoration(
                  color: colors.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.saffronTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Iconsax.notification,
                color: colors.primary,
                size: 26,
              ),
            ),
            SizedBox(height: spacing.space16),
            Text(
              l10n.notificationRationaleTitle,
              style: AppTypography.sans(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            SizedBox(height: spacing.space8),
            Text(
              l10n.notificationRationaleBody,
              style: AppTypography.sans(
                fontSize: 14,
                height: 1.4,
                color: colors.textSecondary,
              ),
            ),
            SizedBox(height: spacing.space24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: colors.textSecondary,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(spacing.radiusMedium),
                      ),
                    ),
                    child: Text(
                      l10n.notificationRationaleNotNow,
                      style: AppTypography.sans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: spacing.space12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: colors.primary,
                      foregroundColor: colors.textOnPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(spacing.radiusMedium),
                      ),
                    ),
                    child: Text(
                      l10n.notificationRationaleTurnOn,
                      style: AppTypography.sans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

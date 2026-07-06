import 'package:flutter/material.dart';

import '../extensions/build_context_l10n.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../utils/error_message_translator.dart';

/// Brand splash screen — loading and error states from wireframe S_Splash_*.
///
/// Renders before theme is hydrated; uses [AppColorTokens.light] directly
/// to stay consistent with the pre-[MaterialApp] boot context.
class SplashScreen extends StatelessWidget {
  final bool hasError;

  /// The boot error, if any (#838). Purely used to pick offline-specific
  /// copy via [classifyError] — never displayed raw. Optional and unused by
  /// the [_CacheIsolationApp] call site, which shows the generic error copy.
  final Object? error;
  final VoidCallback? onRetry;

  /// When true (and [hasError] is true), renders the manual-restart copy
  /// (splashManualRestartTitle/Body) and hides the retry button entirely.
  /// Used by the iOS cache-isolation overlay, where a native restart is
  /// impossible (#946).
  final bool manualRestartRequired;

  const SplashScreen({
    super.key,
    this.hasError = false,
    this.error,
    this.onRetry,
    this.manualRestartRequired = false,
  });

  @override
  Widget build(BuildContext context) {
    const colors = AppColorTokens.light;
    final offline = error != null && classifyError(error!) == FriendlyError.network;
    return Scaffold(
      backgroundColor: colors.scaffoldBackground,
      body: SafeArea(
        child: hasError
            ? _ErrorBody(
                colors: colors,
                offline: offline,
                onRetry: onRetry,
                manualRestart: manualRestartRequired,
              )
            : const _LoadingBody(colors: AppColorTokens.light),
      ),
    );
  }
}

// ── Wireframe S_Splash_Loaded / S_Splash_Loading ─────────────────────────────

class _LoadingBody extends StatelessWidget {
  final AppColorTokens colors;
  const _LoadingBody({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _IconBox(
                  borderColor: colors.textPrimary,
                  backgroundColor: colors.saffronSoft,
                  child: Text(
                    'R',
                    style: AppTypography.display(
                      fontSize: 56,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Rihla',
                  style: AppTypography.display(
                    fontSize: 42,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  context.l10n.splashTagline,
                  style: AppTypography.sans(
                    fontSize: 14,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: SizedBox(
            width: 120,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: null,
                color: colors.primary,
                backgroundColor: colors.saffronSoft,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Wireframe S_Splash_Error ──────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final AppColorTokens colors;
  final bool offline;
  final VoidCallback? onRetry;

  /// Manual-restart instruction mode (#946): neutral refresh icon, manual
  /// relaunch copy, and no retry button — a retry cannot succeed where the
  /// native restart channel has no handler (iOS).
  final bool manualRestart;

  const _ErrorBody({
    required this.colors,
    this.offline = false,
    this.onRetry,
    this.manualRestart = false,
  });

  @override
  Widget build(BuildContext context) {
    // design-token-justified: no errorSoft token; #F2D6CF from wireframe negSoft
    const errorSoft = Color(0xFFF2D6CF);

    final l10n = context.l10n;
    final title = manualRestart
        ? l10n.splashManualRestartTitle
        : offline
            ? l10n.splashOfflineTitle
            : l10n.splashErrorTitle;
    final body = manualRestart
        ? l10n.splashManualRestartBody
        : offline
            ? l10n.splashOfflineBody
            : l10n.splashErrorBody;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (manualRestart)
              _IconBox(
                borderColor: colors.primary,
                backgroundColor: colors.saffronSoft,
                child: Icon(
                  Icons.refresh_rounded,
                  size: 42,
                  color: colors.primary,
                ),
              )
            else
              _IconBox(
                borderColor: colors.error,
                backgroundColor: errorSoft,
                child: Icon(Icons.close_rounded, size: 42, color: colors.error),
              ),
            const SizedBox(height: 14),
            Text(
              title,
              style: AppTypography.displayOf(
                context,
                fontSize: 26,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Text(
              body,
              style: AppTypography.sans(
                fontSize: 13,
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (!manualRestart) ...[
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.textOnPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  context.l10n.splashRetry,
                  style: AppTypography.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textOnPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Shared ────────────────────────────────────────────────────────────────────

class _IconBox extends StatelessWidget {
  final Color borderColor;
  final Color backgroundColor;
  final Widget child;
  const _IconBox({
    required this.borderColor,
    required this.backgroundColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor, width: 2),
        borderRadius: BorderRadius.circular(22),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

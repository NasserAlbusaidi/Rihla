import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/keys/shared_keys.dart';
import '../../core/theme/app_theme.dart';

class ModuleHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? bottom;
  final bool useDarkTheme;

  const ModuleHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.bottom,
    this.useDarkTheme = false,
  });

  @override
  Widget build(BuildContext context) {
    if (useDarkTheme) return _buildDark(context);
    return _buildLight(context);
  }

  Widget _buildLight(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppColors.space24,
            AppColors.space12,
            AppColors.space24,
            AppColors.space24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _LightBackButton(onTap: () => context.pop()),
                  if (actions != null) Row(children: actions!),
                ],
              ),
              const SizedBox(height: AppColors.space16),
              if (subtitle != null) ...[
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: AppColors.space4),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              if (bottom != null) ...[
                const SizedBox(height: AppColors.space16),
                bottom!,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDark(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.darkHeaderGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppColors.space24,
            AppColors.space12,
            AppColors.space24,
            AppColors.space32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _DarkBackButton(onTap: () => context.pop()),
                  if (actions != null) Row(children: actions!),
                ],
              ),
              const SizedBox(height: AppColors.space20),
              if (subtitle != null) ...[
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.5),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: AppColors.space4),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              if (bottom != null) ...[
                const SizedBox(height: AppColors.space16),
                bottom!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LightBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LightBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Go back',
      button: true,
      child: GestureDetector(
        key: SharedKeys.moduleHeaderBackButton,
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: const Icon(Iconsax.arrow_left, color: AppColors.textPrimary, size: 20),
        ),
      ),
    );
  }
}

class _DarkBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DarkBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Go back',
      button: true,
      child: GestureDetector(
        key: SharedKeys.moduleHeaderBackButton,
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppColors.radiusSmall + 2),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: const Icon(Iconsax.arrow_left, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

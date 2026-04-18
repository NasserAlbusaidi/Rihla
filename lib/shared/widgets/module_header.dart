import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../core/keys/shared_keys.dart';
import '../../core/theme/tokens/domain_aliases.dart';

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
      decoration: BoxDecoration(
        color: context.colors.scaffoldBackground,
        border: Border(
          bottom: BorderSide(color: context.colors.border, width: 0.5),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            context.spacing.space24,
            context.spacing.space12,
            context.spacing.space24,
            context.spacing.space24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _LightBackButton(onTap: () {
                if (GoRouter.of(context).canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              }),
                  if (actions != null) Row(children: actions!),
                ],
              ),
              SizedBox(height: context.spacing.space16),
              if (subtitle != null) ...[
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: context.spacing.space4),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: context.colors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              if (bottom != null) ...[
                SizedBox(height: context.spacing.space16),
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
      decoration: BoxDecoration(
        gradient: context.colors.headerGradient,
        image: DecorationImage(
          image: AssetImage('assets/textures/grain.png'),
          repeat: ImageRepeat.repeat,
          opacity: 0.02,
          fit: BoxFit.none,
          alignment: Alignment.topLeft,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            context.spacing.space24,
            context.spacing.space12,
            context.spacing.space24,
            context.spacing.space32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _DarkBackButton(onTap: () {
                  if (GoRouter.of(context).canPop()) {
                    context.pop();
                  } else {
                    context.go('/home');
                  }
                }),
                  if (actions != null) Row(children: actions!),
                ],
              ),
              SizedBox(height: context.spacing.space20),
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
                SizedBox(height: context.spacing.space4),
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
                SizedBox(height: context.spacing.space16),
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
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: Icon(Iconsax.arrow_left, color: context.colors.textPrimary, size: 20),
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
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8 + 2),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: const Icon(Iconsax.arrow_left, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

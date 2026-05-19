import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/widgets/wordmark_logo.dart';

/// Three-page first-launch onboarding flow.
///
/// Wireframe: `Wireframes/Rihla/hifi/screens-onboarding.jsx` — a hybrid sequence
/// of a full-bleed brand cover, a three-row "how it travels with you" page,
/// and a setup page (name + home currency + notifications).
///
/// Persists results into [settingsProvider] and flips `onboardingComplete`
/// before invoking [onComplete] (or `context.go('/home')` when null).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.onComplete, this.initialPage = 0});

  /// Called after the user finishes (or skips) onboarding. Defaults to
  /// `context.go(AppRoutes.home)` when null; injectable for tests.
  final VoidCallback? onComplete;

  /// Page index to render first. Defaults to 0 (brand cover). Tests inject
  /// this to skip past the page-view transition for in-page assertions.
  final int initialPage;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _pageCount = 3;
  static const _currencyChoices = <String>['OMR', 'USD', 'EUR', 'GBP', 'AED'];

  late final PageController _controller;
  late final TextEditingController _nameController;

  late int _page;
  String _selectedCurrency = 'OMR';
  bool _activitySettlesOn = true;
  bool _weeklyDigestOn = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage.clamp(0, _pageCount - 1);
    _controller = PageController(initialPage: _page);
    final settings = ref.read(settingsProvider);
    _nameController = TextEditingController(text: settings.deviceName);
    _selectedCurrency = settings.currencyCode.isEmpty
        ? 'OMR'
        : settings.currencyCode;
    _activitySettlesOn = settings.pushNotificationsEnabled;
    _weeklyDigestOn = settings.weeklyDigestEnabled;
  }

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _goToPage(int target) {
    final clamped = target.clamp(0, _pageCount - 1);
    _controller.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finishOnboarding() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final notifier = ref.read(settingsProvider.notifier);
    final trimmedName = _nameController.text.trim();

    await notifier.setCurrency(_selectedCurrency);
    await notifier.setPushNotificationsEnabled(_activitySettlesOn);
    await notifier.setWeeklyDigestEnabled(_weeklyDigestOn);
    if (trimmedName.isNotEmpty) {
      await notifier.setDeviceName(trimmedName);
    }
    await notifier.setOnboardingComplete(true);

    if (!mounted) return;
    final onComplete = widget.onComplete;
    if (onComplete != null) {
      onComplete();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.scaffoldBackground,
      body: PageView(
        controller: _controller,
        onPageChanged: (i) => setState(() => _page = i),
        children: [
          _BrandPage(onBegin: () => _goToPage(1)),
          _HowPage(onSkip: _finishOnboarding, onNext: () => _goToPage(2)),
          _SetupPage(
            nameController: _nameController,
            selectedCurrency: _selectedCurrency,
            onCurrencyChange: (c) => setState(() => _selectedCurrency = c),
            activitySettlesOn: _activitySettlesOn,
            onActivitySettlesChange: (v) =>
                setState(() => _activitySettlesOn = v),
            weeklyDigestOn: _weeklyDigestOn,
            onWeeklyDigestChange: (v) => setState(() => _weeklyDigestOn = v),
            currencyChoices: _currencyChoices,
            submitting: _submitting,
            onSkip: _finishOnboarding,
            onOpenRihla: _finishOnboarding,
          ),
        ],
      ),
    );
  }
}

// ── Page 1 ────────────────────────────────────────────────────────────────────

class _BrandPage extends StatelessWidget {
  const _BrandPage({required this.onBegin});

  final VoidCallback onBegin;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: colors.headerGradient),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              context.spacing.space24 + 4,
              context.spacing.space24,
              context.spacing.space24 + 4,
              context.spacing.space12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: AlignmentDirectional.topStart,
                  child: WordmarkLogo(
                    size: 32,
                    color: colors.cardSurface,
                    accentColor: colors.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  context.l10n.onboardingBrandKicker,
                  style: AppTypography.mono(
                    fontSize: 10,
                    color: colors.cardSurface.withValues(alpha: 0.85),
                    letterSpacing: 3,
                  ),
                ),
                SizedBox(height: context.spacing.space12),
                _BrandHeadline(colors: colors),
                SizedBox(height: context.spacing.space12),
                SizedBox(
                  width: 110,
                  height: 14,
                  child: CustomPaint(
                    painter: _UnderlineFlourishPainter(color: colors.primary),
                  ),
                ),
                SizedBox(height: context.spacing.space20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Text(
                    context.l10n.onboardingBrandBody,
                    style: AppTypography.sans(
                      fontSize: 14,
                      color: colors.cardSurface.withValues(alpha: 0.88),
                      height: 1.45,
                    ),
                  ),
                ),
                SizedBox(height: context.spacing.space24 + 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const _OnboardingDots(
                      active: 0,
                      count: 3,
                      onDarkBackground: true,
                    ),
                    _SaffronCta(
                      label: context.l10n.onboardingBegin,
                      onPressed: onBegin,
                      icon: Iconsax.arrow_right_3,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeadline extends StatelessWidget {
  const _BrandHeadline({required this.colors});

  final AppColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final baseStyle = AppTypography.display(
      fontSize: 56,
      color: colors.cardSurface,
      letterSpacing: -1.5,
      height: 0.95,
    );
    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: context.l10n.onboardingBrandHeadlineLead),
          TextSpan(
            text: context.l10n.onboardingBrandHeadlineAccent,
            style: baseStyle.copyWith(color: colors.primary),
          ),
          TextSpan(text: context.l10n.onboardingBrandHeadlineSuffix),
        ],
      ),
    );
  }
}

// ── Page 2 ────────────────────────────────────────────────────────────────────

class _HowPage extends StatelessWidget {
  const _HowPage({required this.onSkip, required this.onNext});

  final VoidCallback onSkip;
  final VoidCallback onNext;

  List<_HowRow> _rows(BuildContext context) => [
    _HowRow(
      number: '01',
      title: context.l10n.onboardingHowGroupsTitle,
      body: context.l10n.onboardingHowGroupsBody,
      icon: Iconsax.profile_2user,
    ),
    _HowRow(
      number: '02',
      title: context.l10n.onboardingHowEventsTitle,
      body: context.l10n.onboardingHowEventsBody,
      icon: Iconsax.location,
    ),
    _HowRow(
      number: '03',
      title: context.l10n.onboardingHowExpensesTitle,
      body: context.l10n.onboardingHowExpensesBody,
      icon: Iconsax.tick_circle,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepHeader(label: '02 / 03', onSkip: onSkip),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              context.spacing.space24 + 4,
              context.spacing.space24 + 4,
              context.spacing.space24 + 4,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.onboardingHowTitle,
                  style: AppTypography.display(
                    fontSize: 36,
                    color: colors.textPrimary,
                    letterSpacing: -0.5,
                    height: 1.05,
                  ),
                ),
                SizedBox(height: context.spacing.space8),
                SizedBox(
                  width: 80,
                  height: 14,
                  child: CustomPaint(
                    painter: _UnderlineFlourishPainter(color: colors.primary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsetsDirectional.fromSTEB(
                context.spacing.space24,
                context.spacing.space20 + 2,
                context.spacing.space24,
                context.spacing.space16,
              ),
              children: [
                for (final row in _rows(context)) ...[
                  _HowRowTile(row: row),
                  SizedBox(height: context.spacing.space20 + 2),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              context.spacing.space24,
              0,
              context.spacing.space24,
              context.spacing.space8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _OnboardingDots(active: 1, count: 3),
                _PrimaryInkCta(
                  label: context.l10n.onboardingNext,
                  onPressed: onNext,
                  icon: Iconsax.arrow_right_3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HowRow {
  const _HowRow({
    required this.number,
    required this.title,
    required this.body,
    required this.icon,
  });

  final String number;
  final String title;
  final String body;
  final IconData icon;
}

class _HowRowTile extends StatelessWidget {
  const _HowRowTile({required this.row});

  final _HowRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.saffronTint,
            borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
          ),
          alignment: Alignment.center,
          child: Icon(row.icon, size: 20, color: colors.primaryDark),
        ),
        SizedBox(width: context.spacing.space12 + 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    row.number,
                    style: AppTypography.mono(
                      fontSize: 10,
                      // textMuted-decorative-justified: Row number tag — small decorative numeric mono label (no semantic info).
                      color: colors.textMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(width: context.spacing.space8),
                  Expanded(
                    child: Text(
                      row.title,
                      style: AppTypography.sans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: context.spacing.space4),
              Text(
                row.body,
                style: AppTypography.sans(
                  fontSize: 13,
                  color: colors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Page 3 ────────────────────────────────────────────────────────────────────

class _SetupPage extends StatelessWidget {
  const _SetupPage({
    required this.nameController,
    required this.selectedCurrency,
    required this.onCurrencyChange,
    required this.activitySettlesOn,
    required this.onActivitySettlesChange,
    required this.weeklyDigestOn,
    required this.onWeeklyDigestChange,
    required this.currencyChoices,
    required this.submitting,
    required this.onSkip,
    required this.onOpenRihla,
  });

  final TextEditingController nameController;
  final String selectedCurrency;
  final ValueChanged<String> onCurrencyChange;
  final bool activitySettlesOn;
  final ValueChanged<bool> onActivitySettlesChange;
  final bool weeklyDigestOn;
  final ValueChanged<bool> onWeeklyDigestChange;
  final List<String> currencyChoices;
  final bool submitting;
  final VoidCallback onSkip;
  final VoidCallback onOpenRihla;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepHeader(label: '03 / 03', onSkip: onSkip),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              context.spacing.space24 + 4,
              context.spacing.space24 + 4,
              context.spacing.space24 + 4,
              0,
            ),
            child: Text(
              context.l10n.onboardingSetupTitle,
              style: AppTypography.display(
                fontSize: 36,
                color: colors.textPrimary,
                letterSpacing: -0.5,
                height: 1.05,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsetsDirectional.fromSTEB(
                context.spacing.space24,
                context.spacing.space24 + 2,
                context.spacing.space24,
                context.spacing.space16,
              ),
              children: [
                _SectionLabel(text: context.l10n.onboardingNameSection),
                SizedBox(height: context.spacing.space8 + 2),
                _NameField(controller: nameController),
                SizedBox(height: context.spacing.space24 - 2),
                _SectionLabel(text: context.l10n.onboardingCurrencySection),
                SizedBox(height: context.spacing.space8 + 2),
                Wrap(
                  spacing: context.spacing.space8,
                  runSpacing: context.spacing.space8,
                  children: [
                    for (final c in currencyChoices)
                      _PillChip(
                        label: c,
                        active: c == selectedCurrency,
                        onTap: () => onCurrencyChange(c),
                      ),
                  ],
                ),
                SizedBox(height: context.spacing.space8),
                Text(
                  context.l10n.onboardingCurrencyHelper,
                  style: AppTypography.sans(
                    fontSize: 11,
                    // textMuted-decorative-justified: Caption beneath inline label — non-essential helper copy.
                    color: colors.textMuted,
                  ),
                ),
                SizedBox(height: context.spacing.space24 + 4),
                _SectionLabel(
                  text: context.l10n.onboardingNotificationsSection,
                ),
                SizedBox(height: context.spacing.space8 + 2),
                _NotificationsCard(
                  activitySettlesOn: activitySettlesOn,
                  onActivitySettlesChange: onActivitySettlesChange,
                  weeklyDigestOn: weeklyDigestOn,
                  onWeeklyDigestChange: onWeeklyDigestChange,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              context.spacing.space24,
              0,
              context.spacing.space24,
              context.spacing.space8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _OnboardingDots(active: 2, count: 3),
                _SaffronCta(
                  label: context.l10n.onboardingOpenRihla,
                  onPressed: submitting ? null : onOpenRihla,
                  icon: Iconsax.arrow_right_3,
                  loading: submitting,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTypography.sans(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: context.colors.textSecondary,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  const _NameField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      style: AppTypography.sans(fontSize: 15, color: colors.textPrimary),
      decoration: InputDecoration(
        hintText: context.l10n.onboardingNameHint,
        // textMuted-decorative-justified: TextField hint placeholder — disappears once user types.
        hintStyle: AppTypography.sans(fontSize: 15, color: colors.textMuted),
        filled: true,
        fillColor: colors.inputFill,
        contentPadding: EdgeInsets.symmetric(
          horizontal: context.spacing.space16,
          vertical: context.spacing.space12 + 2,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
          borderSide: BorderSide(color: colors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
          borderSide: BorderSide(color: colors.focusBorderWarm, width: 1.5),
        ),
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = active ? colors.textPrimary : Colors.transparent;
    final fg = active ? colors.scaffoldBackground : colors.ink2;
    final borderColor = active ? colors.textPrimary : colors.rule2;
    return Semantics(
      button: true,
      selected: active,
      label: context.l10n.onboardingCurrencySemantics(label),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(
            horizontal: context.spacing.space12,
            vertical: context.spacing.space8 - 2,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            label,
            style: AppTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard({
    required this.activitySettlesOn,
    required this.onActivitySettlesChange,
    required this.weeklyDigestOn,
    required this.onWeeklyDigestChange,
  });

  final bool activitySettlesOn;
  final ValueChanged<bool> onActivitySettlesChange;
  final bool weeklyDigestOn;
  final ValueChanged<bool> onWeeklyDigestChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
        boxShadow: context.shadows.flat,
      ),
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space16),
      child: Column(
        children: [
          _ToggleRow(
            title: context.l10n.onboardingActivitySettlesTitle,
            subtitle: context.l10n.onboardingActivitySettlesSubtitle,
            value: activitySettlesOn,
            onChanged: onActivitySettlesChange,
            divider: true,
          ),
          _ToggleRow(
            title: context.l10n.onboardingWeeklyDigestTitle,
            subtitle: context.l10n.onboardingWeeklyDigestSubtitle,
            value: weeklyDigestOn,
            onChanged: onWeeklyDigestChange,
            divider: false,
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.divider,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        InkWell(
          onTap: () => onChanged(!value),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: context.spacing.space12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      SizedBox(height: context.spacing.space4 - 2),
                      Text(
                        subtitle,
                        style: AppTypography.sans(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: colors.textPrimary,
                ),
              ],
            ),
          ),
        ),
        if (divider) Divider(height: 1, color: colors.rule),
      ],
    );
  }
}

// ── Shared chrome ─────────────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.label, required this.onSkip});

  final String label;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        context.spacing.space24,
        context.spacing.space24,
        context.spacing.space16,
        0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: AppTypography.mono(
              fontSize: 10,
              // textMuted-decorative-justified: Field label tag above input — decorative mono uppercase, accompanied by adjacent functional label.
              color: colors.textMuted,
              letterSpacing: 2,
            ),
          ),
          TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(
              foregroundColor: colors.textSecondary,
              minimumSize: const Size(48, 36),
              padding: EdgeInsets.symmetric(horizontal: context.spacing.space8),
            ),
            child: Text(
              context.l10n.onboardingSkip,
              style: AppTypography.sans(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingDots extends StatelessWidget {
  const _OnboardingDots({
    required this.active,
    required this.count,
    this.onDarkBackground = false,
  });

  final int active;
  final int count;

  /// When true (brand page), dots invert to light-on-dark so they remain
  /// visible against the gradient header.
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeColor = onDarkBackground
        ? colors.cardSurface
        : colors.textPrimary;
    final inactiveColor = onDarkBackground
        ? colors.cardSurface.withValues(alpha: 0.30)
        : colors.rule2;
    return Semantics(
      label: context.l10n.onboardingStepSemantics(active + 1, count),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsetsDirectional.only(
                end: i == count - 1 ? 0 : context.spacing.space4 + 2,
              ),
              width: i == active ? 22 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == active ? activeColor : inactiveColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

class _SaffronCta extends StatelessWidget {
  const _SaffronCta({
    required this.label,
    required this.onPressed,
    required this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.textOnPrimary,
        disabledBackgroundColor: colors.primary.withValues(alpha: 0.6),
        disabledForegroundColor: colors.textOnPrimary,
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space20,
          vertical: context.spacing.space12 + 2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
        ),
        elevation: 0,
        textStyle: AppTypography.sans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      icon: loading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(colors.textOnPrimary),
              ),
            )
          : const SizedBox.shrink(),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          SizedBox(width: context.spacing.space8),
          Transform.scale(scaleX: isRtl ? -1 : 1, child: Icon(icon, size: 14)),
        ],
      ),
    );
  }
}

class _PrimaryInkCta extends StatelessWidget {
  const _PrimaryInkCta({
    required this.label,
    required this.onPressed,
    required this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.textPrimary,
        foregroundColor: colors.scaffoldBackground,
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.space20,
          vertical: context.spacing.space12 + 2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
        ),
        elevation: 0,
        textStyle: AppTypography.sans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          SizedBox(width: context.spacing.space8),
          Transform.scale(scaleX: isRtl ? -1 : 1, child: Icon(icon, size: 14)),
        ],
      ),
    );
  }
}

// ── Painters ──────────────────────────────────────────────────────────────────

/// Hand-drawn underline arc — mirrors `RFlourish` from the wireframe primitives.
class _UnderlineFlourishPainter extends CustomPainter {
  const _UnderlineFlourishPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final path = Path()
      ..moveTo(w * 0.025, 9)
      ..cubicTo(w * 0.225, 4, w * 0.450, 12, w * 0.650, 7)
      ..cubicTo(w * 0.800, 5, w * 0.950, 5, w * 0.975, 9);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _UnderlineFlourishPainter old) =>
      old.color != color;
}

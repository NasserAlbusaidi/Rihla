import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../shared/animations/tap_bounce.dart';
import '../models/event_model.dart';
import '../keys/event_keys.dart';
import '../models/event_type_config.dart';
import '../utils/event_display.dart';

/// Full-screen event type picker — Step 1 of the event creation flow.
///
/// Displays five visual type cards, stores the selected type locally, and
/// navigates to [CreateEventScreen] through the bottom continue action.
///
/// Per D-02 and UI-SPEC: EventTypePickerScreen.
class EventTypePickerScreen extends ConsumerStatefulWidget {
  final String groupId;

  const EventTypePickerScreen({super.key, required this.groupId});

  @override
  ConsumerState<EventTypePickerScreen> createState() =>
      _EventTypePickerScreenState();
}

class _EventTypePickerScreenState extends ConsumerState<EventTypePickerScreen> {
  EventType _selectedType = EventType.trip;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final types = EventTypeConfig.allTypes;
    final selectedLabel = _selectedType.localizedLabel(context.l10n);

    return Scaffold(
      key: EventKeys.eventTypePickerScreen,
      backgroundColor: context.colors.scaffoldBackground,
      body: SafeArea(
        child: Column(
          children: [
            _PickerTopBar(groupId: widget.groupId),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.eventPickerTitle,
                      key: EventKeys.eventTypePickerTitle,
                      style: AppTypography.display(
                        fontSize: 30,
                        color: context.colors.textPrimary,
                        height: 1.05,
                      ),
                    ),
                    SizedBox(height: context.spacing.space8),
                    Text(
                      context.l10n.eventPickerSubtitle,
                      style: AppTypography.sans(
                        fontSize: 13,
                        color: context.colors.textSecondary,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _TypeGrid(
                      types: types,
                      selectedType: _selectedType,
                      disableAnimations: disableAnimations,
                      onSelect: (type) {
                        HapticService.selection();
                        setState(() => _selectedType = type);
                      },
                    ),
                    SizedBox(height: context.spacing.space24),
                    _ContinueButton(
                      label: context.l10n.eventContinueWith(selectedLabel),
                      onPressed: () => context.push(
                        '/group/${widget.groupId}/create-event/${_selectedType.value}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerTopBar extends StatelessWidget {
  const _PickerTopBar({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 20, 8),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                tooltip: context.l10n.commonClose,
                icon: const Icon(Iconsax.close_circle, size: 20),
                color: context.colors.textPrimary,
                onPressed: () {
                  HapticService.lightClick();
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/group/$groupId');
                  }
                },
              ),
            ),
            Text(
              context.l10n.eventNew,
              style: AppTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeGrid extends StatelessWidget {
  const _TypeGrid({
    required this.types,
    required this.selectedType,
    required this.disableAnimations,
    required this.onSelect,
  });

  final List<EventTypeConfig> types;
  final EventType selectedType;
  final bool disableAnimations;
  final ValueChanged<EventType> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = context.spacing.space12;
        final itemWidth = (constraints.maxWidth - gap) / 2;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: List.generate(types.length, (index) {
            final config = types[index];
            final fullWidth = config.type == EventType.custom;
            final card = SizedBox(
              width: fullWidth ? constraints.maxWidth : itemWidth,
              child: _TypeCard(
                config: config,
                selected: config.type == selectedType,
                horizontal: fullWidth,
                onTap: () => onSelect(config.type),
              ),
            );

            if (disableAnimations) return card;

            return card
                .animate()
                .fadeIn(delay: (70 * index).ms, duration: 320.ms)
                .slideY(
                  begin: 0.04,
                  end: 0,
                  delay: (70 * index).ms,
                  duration: 320.ms,
                  curve: Curves.easeOutCubic,
                );
          }),
        );
      },
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.config,
    required this.selected,
    required this.horizontal,
    required this.onTap,
  });

  final EventTypeConfig config;
  final bool selected;
  final bool horizontal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typeColor = config.resolveColor(colors);

    return Semantics(
      label:
          '${config.type.localizedLabel(context.l10n)}: '
          '${config.type.localizedDescription(context.l10n)}',
      button: true,
      selected: selected,
      child: TapBounce(
        key: EventKeys.eventTypeCard(config.label),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: horizontal ? 84 : 168),
          padding: EdgeInsets.all(context.spacing.space16),
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(context.spacing.radiusLarge),
            border: Border.all(
              color: selected ? colors.textPrimary : Colors.transparent,
              width: 2,
            ),
            boxShadow: context.shadows.raised,
          ),
          child: horizontal
              ? Row(
                  children: [
                    _TypeGlyph(config: config, color: typeColor),
                    const SizedBox(width: 14),
                    Expanded(child: _TypeCopy(config: config)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TypeGlyph(config: config, color: typeColor),
                    const SizedBox(height: 14),
                    _TypeCopy(config: config),
                  ],
                ),
        ),
      ),
    );
  }
}

class _TypeGlyph extends StatelessWidget {
  const _TypeGlyph({required this.config, required this.color});

  final EventTypeConfig config;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final background = switch (config.type) {
      EventType.trip => colors.moduleLedgerLight,
      EventType.camping => colors.saffronSoft,
      EventType.travel => colors.cardSoft,
      EventType.nightDayOut => colors.moduleMemoriesLight,
      EventType.custom => colors.cardSoft,
    };

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
      ),
      child: Icon(config.icon, size: 22, color: color),
    );
  }
}

class _TypeCopy extends StatelessWidget {
  const _TypeCopy({required this.config});

  final EventTypeConfig config;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          config.type.localizedShortLabel(context.l10n),
          style: AppTypography.mono(
            fontSize: 9,
            letterSpacing: 1.5,
            color: context.colors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          config.type.localizedLabel(context.l10n),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.display(
            fontSize: 20,
            color: context.colors.textPrimary,
            height: 1.1,
          ),
        ),
        SizedBox(height: context.spacing.space4),
        Text(
          config.type.localizedDescription(context.l10n),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.sans(
            fontSize: 12,
            color: context.colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return SizedBox(
      width: double.infinity,
      height: context.spacing.buttonHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: context.colors.primaryGradient,
          borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
        ),
        child: ElevatedButton.icon(
          key: EventKeys.createEventButton,
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: context.colors.textOnPrimary,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.spacing.radiusMedium),
            ),
          ),
          label: Text(
            label,
            style: AppTypography.sans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: context.colors.textOnPrimary,
              height: 1.22,
            ),
          ),
          icon: Transform.scale(
            scaleX: isRtl ? -1 : 1,
            child: const Icon(Iconsax.arrow_right_3, size: 16),
          ),
        ),
      ),
    );
  }
}

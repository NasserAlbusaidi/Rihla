import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../home/widgets/group_glyph.dart';
import 'group_stamp_icon.dart';

/// A group's chosen stamp identity: an optional symbol [glyph] (one of
/// [kGroupGlyphIds]) and an optional [inkIndex] (0..5 into the category
/// palette). A `null` field means "defaulted" — the monogram glyph or the
/// name-derived ink; a non-null field is an explicit, persistable pick.
///
/// Exported from this file; the Create-Group screen imports it to hold picker
/// state.
typedef GroupStampSelection = ({String? glyph, int? inkIndex});

/// Live picker for a group's "trip stamp" — a hero preview, a row of six ink
/// swatches, and a symbol grid (monogram-first, then the 12 glyph family).
///
/// Pure and stateless: the current [value] is rendered and every tap calls
/// [onChanged] with a fresh record copy (the incoming [value] is never
/// mutated). Selection is shown as a saffron ring (+ tint on symbols) over the
/// unchanged cell — the ink colour is set separately and never used to signal
/// selection, so ink stays meaningful.
class GroupStampPicker extends StatelessWidget {
  const GroupStampPicker({
    super.key,
    required this.name,
    required this.value,
    required this.onChanged,
    this.showHero = true,
  });

  /// Live group name — drives the hero/monogram first letter (and the
  /// name-derived ink while [GroupStampSelection.inkIndex] is null).
  final String name;

  /// Current selection.
  final GroupStampSelection value;

  /// Emitted with an immutable record copy on every ink/symbol tap.
  final ValueChanged<GroupStampSelection> onChanged;

  /// Whether to render the leading hero [GroupGlyph] preview. The Create
  /// screen keeps it (`true`); the Edit sheet renders its OWN hero above a
  /// name field and passes `false`, so the picker shows only ink + symbol.
  final bool showHero;

  static const double _heroSize = 80;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    final inks = <Color>[
      colors.cat1,
      colors.cat2,
      colors.cat3,
      colors.cat4,
      colors.cat5,
      colors.cat6,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 1. Live hero — the exact tile that will render after create. The
        // Edit sheet supplies its own hero above the name field, so it passes
        // showHero:false and this leading preview (+ its gap) is omitted.
        if (showHero) ...[
          Center(
            child: GroupGlyph(
              name: name,
              glyph: value.glyph,
              inkIndex: value.inkIndex,
              size: _heroSize,
            ),
          ),
          SizedBox(height: spacing.space24),
        ],

        // ── 2. Ink row — six journal colours, fill the row equally. ──
        _RowLabel(context.l10n.groupStampInk),
        SizedBox(height: spacing.space12),
        Row(
          children: [
            for (var i = 0; i < inks.length; i++) ...[
              if (i > 0) SizedBox(width: spacing.space12),
              Expanded(
                child: _InkSwatch(
                  index: i,
                  color: inks[i],
                  selected: value.inkIndex == i,
                  onTap: () =>
                      onChanged((glyph: value.glyph, inkIndex: i)),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: spacing.space24),

        // ── 3. Symbol grid — monogram cell first, then the 12 glyphs. ──
        _RowLabel(context.l10n.groupStampSymbol),
        SizedBox(height: spacing.space12),
        GridView.count(
          crossAxisCount: 5,
          mainAxisSpacing: spacing.space12,
          crossAxisSpacing: spacing.space12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _MonogramCell(
              name: name,
              selected: value.glyph == null,
              onTap: () =>
                  onChanged((glyph: null, inkIndex: value.inkIndex)),
            ),
            for (final id in kGroupGlyphIds)
              _SymbolCell(
                id: id,
                selected: value.glyph == id,
                onTap: () =>
                    onChanged((glyph: id, inkIndex: value.inkIndex)),
              ),
          ],
        ),
        SizedBox(height: spacing.space8),
        // Muted caption: with no symbol chosen, the monogram cell renders the
        // name's first initial as the default stamp.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            context.l10n.groupStampMonogramHint,
            style: AppTypography.sans(
              fontSize: 11,
              color: colors.textSecondary,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// Mono uppercase row header ("INK" / "SYMBOL"), matching the mockup's
/// `.row-head`.
class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text.toUpperCase(),
        style: AppTypography.caption(
          context,
          fontSize: 11,
          color: colors.textSecondary,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// A square ink swatch filled with its colour. Selected → saffron ring with a
/// paper gap (mockup `box-shadow: 0 0 0 2px paper, 0 0 0 4px primary`),
/// implemented as an outer saffron border + inner paper padding so the fill
/// floats inside the ring.
class _InkSwatch extends StatelessWidget {
  const _InkSwatch({
    required this.index,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final radius = BorderRadius.circular(spacing.radiusPill);

    return GestureDetector(
      key: Key('stampInk_$index'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AspectRatio(
        aspectRatio: 1,
        // Ring container — keyed for tests. Border is saffron when selected,
        // transparent otherwise (constant box size → no layout shift).
        child: Container(
          key: Key('stampInk_${index}_ring'),
          padding: EdgeInsets.all(selected ? spacing.space4 : 0),
          decoration: BoxDecoration(
            color: selected ? colors.scaffoldBackground : null,
            borderRadius: radius,
            border: Border.all(
              color: selected ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: radius,
            ),
          ),
        ),
      ),
    );
  }
}

/// The no-symbol "monogram" cell — first letter of the name in serif, on the
/// soft cell surface. Selected → saffron ring + tint (same as a symbol cell).
class _MonogramCell extends StatelessWidget {
  const _MonogramCell({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '·' : trimmed.characters.first.toUpperCase();
    return _CellShell(
      keyId: 'monogram',
      selected: selected,
      onTap: onTap,
      child: Text(
        initial,
        style: AppTypography.displayOf(
          context,
          fontSize: 22,
          color: selected ? colors.primaryDark : colors.textSecondary,
          height: 1.0,
        ),
      ),
    );
  }
}

/// A symbol cell rendering one glyph in a consistent neutral ink (NOT the
/// would-be group ink — selection stays the only colour signal). Selected →
/// saffron ring + tint, recolouring the glyph to saffron-dark.
class _SymbolCell extends StatelessWidget {
  const _SymbolCell({
    required this.id,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _CellShell(
      keyId: id,
      selected: selected,
      onTap: onTap,
      child: GroupStampIcon(
        glyph: id,
        ink: selected ? colors.primaryDark : colors.textSecondary,
        size: 24,
      ),
    );
  }
}

/// Shared square-cell chrome for the symbol grid: a soft surface with a hairline
/// border, switching to a saffron ring + tint when [selected]. The ring
/// container is keyed `stampSym_<keyId>_ring`; the whole cell is the tappable
/// `stampSym_<keyId>`.
class _CellShell extends StatelessWidget {
  const _CellShell({
    required this.keyId,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String keyId;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    return GestureDetector(
      key: Key('stampSym_$keyId'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: Key('stampSym_${keyId}_ring'),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.saffronTint : colors.cardSoft,
          borderRadius: BorderRadius.circular(spacing.radiusInput),
          border: Border.all(
            color: selected ? colors.primary : colors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

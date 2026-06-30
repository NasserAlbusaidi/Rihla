import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/utils/share_helper.dart';
import '../../../core/utils/widget_to_image.dart';
import '../../../shared/widgets/loading_button.dart';
import '../keys/event_keys.dart';
import '../models/event_model.dart';
import '../models/event_recap.dart';
import 'recap_share_card.dart';

/// Opens the #722 share-recap preview: the [RecapShareCard] poster (WYSIWYG, in
/// a forced-light theme so the export looks the same in any app theme) above a
/// "Share image" CTA that captures the card's `RepaintBoundary` to a PNG and
/// hands it to the [shareImage] chokepoint. Modal sheet — no router/deep-link
/// surface. Only reached when the recap is non-empty.
Future<void> showRecapShareSheet(
  BuildContext context, {
  required EventRecap recap,
  required Map<String, String> roster,
  required EventType eventType,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.colors.cardSurface,
    builder: (_) => _RecapShareSheet(
      recap: recap,
      roster: roster,
      eventType: eventType,
    ),
  );
}

class _RecapShareSheet extends StatefulWidget {
  const _RecapShareSheet({
    required this.recap,
    required this.roster,
    required this.eventType,
  });

  final EventRecap recap;
  final Map<String, String> roster;
  final EventType eventType;

  @override
  State<_RecapShareSheet> createState() => _RecapShareSheetState();
}

class _RecapShareSheetState extends State<_RecapShareSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Capture before awaits. On error we POP first, then post to this messenger
    // (the recap screen's): a snackbar shown while the tall scroll-controlled
    // sheet + barrier are up renders behind them and is invisible.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = context.l10n;
    final eventName = widget.recap.eventName;
    try {
      final bytes = await captureBoundaryPng(_cardKey);
      if (!mounted) return;
      if (bytes == null) {
        navigator.pop();
        _showError(messenger, l10n.recapShareError);
        return;
      }
      await shareImage(context, bytes, text: l10n.recapShareText(eventName));
      if (mounted) navigator.pop();
    } catch (_) {
      if (mounted) navigator.pop();
      _showError(messenger, l10n.recapShareError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(
      // No action → auto-dismisses; explicit duration per the #411 snackbar trap.
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.spacing;
    return SafeArea(
      key: EventKeys.recapShareSheet,
      child: SingleChildScrollView(
        padding: EdgeInsetsDirectional.fromSTEB(
            s.space24, s.space8, s.space24, s.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.recapShareButton,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            SizedBox(height: s.space16),
            // The exact artifact that gets shared — captured at native 360px
            // width regardless of how FittedBox scales it to fit the sheet.
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RepaintBoundary(
                  key: _cardKey,
                  child: Theme(
                    data: AppTheme.lightTheme,
                    child: RecapShareCard(
                      recap: widget.recap,
                      roster: widget.roster,
                      eventType: widget.eventType,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: s.space20),
            LoadingButton(
              key: EventKeys.recapShareConfirmButton,
              onPressed: _share,
              isLoading: _busy,
              label: context.l10n.recapShareCta,
              icon: Iconsax.export_1,
            ),
          ],
        ),
      ),
    );
  }
}

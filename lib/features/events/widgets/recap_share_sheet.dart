import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens/domain_aliases.dart';
import '../../../core/types/event_ref.dart';
import '../../../core/utils/share_helper.dart';
import '../../../core/utils/widget_to_image.dart';
import '../../../shared/widgets/loading_button.dart';
import '../keys/event_keys.dart';
import '../models/event_model.dart';
import '../models/event_recap.dart';
import '../providers/trip_receipt_provider.dart';
import '../utils/trip_receipt_csv.dart';
import '../utils/trip_receipt_pdf.dart';
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
  required EventRef eventRef,
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
      eventRef: eventRef,
    ),
  );
}

class _RecapShareSheet extends ConsumerStatefulWidget {
  const _RecapShareSheet({
    required this.recap,
    required this.roster,
    required this.eventType,
    required this.eventRef,
  });

  final EventRecap recap;
  final Map<String, String> roster;
  final EventType eventType;
  final EventRef eventRef;

  @override
  ConsumerState<_RecapShareSheet> createState() => _RecapShareSheetState();
}

class _RecapShareSheetState extends ConsumerState<_RecapShareSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _busy = false;
  bool _csvBusy = false;
  bool _pdfBusy = false;

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

  Future<void> _exportCsv() async {
    if (_csvBusy) return;
    final receipt = ref.read(tripReceiptProvider(widget.eventRef)).value;
    if (receipt == null) return; // gated on AsyncData; defensive
    setState(() => _csvBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = context.l10n;
    try {
      final csv = tripReceiptToCsv(receipt, l10n);
      await shareCsv(context, csv);
      if (mounted) navigator.pop();
    } catch (_) {
      if (mounted) navigator.pop();
      _showError(messenger, l10n.recapShareError);
    } finally {
      if (mounted) setState(() => _csvBusy = false);
    }
  }

  Future<void> _exportPdf() async {
    if (_pdfBusy) return;
    final receipt = ref.read(tripReceiptProvider(widget.eventRef)).value;
    if (receipt == null) return; // gated on AsyncData; defensive
    setState(() => _pdfBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = context.l10n;
    try {
      // Building the PDF is async (font load + layout), unlike the sync CSV — so
      // re-check `mounted` before touching context again for the share origin.
      final bytes = await tripReceiptToPdf(receipt, l10n);
      if (!mounted) return;
      await sharePdf(context, bytes);
      if (mounted) navigator.pop();
    } catch (_) {
      if (mounted) navigator.pop();
      _showError(messenger, l10n.recapShareError);
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
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
    final receiptReady = ref
        .watch(tripReceiptProvider(widget.eventRef))
        .maybeWhen(data: (r) => !r.isEmpty, orElse: () => false);
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
            SizedBox(height: s.space8),
            // Secondary: the full data proof pack (#704). Both are disabled until
            // the receipt resolves (AsyncData) so an export never captures a
            // partially-loaded snapshot. CSV = raw data; PDF = formatted print.
            TextButton.icon(
              key: EventKeys.recapExportCsvButton,
              onPressed: (_csvBusy || !receiptReady) ? null : _exportCsv,
              icon: _csvBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Iconsax.document_download),
              label: Text(context.l10n.recapExportCsvButton),
            ),
            TextButton.icon(
              key: EventKeys.recapExportPdfButton,
              onPressed: (_pdfBusy || !receiptReady) ? null : _exportPdf,
              icon: _pdfBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Iconsax.document_text),
              label: Text(context.l10n.recapExportPdfButton),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/error_widgets.dart';

class ErrorState extends StatelessWidget {
  const ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // #358: adopt the shared NetworkErrorWidget for the generic
    // (non-permission) group-load error instead of a hand-rolled
    // EmptyStateView error variant.
    return SafeArea(
      child: NetworkErrorWidget.loadingError(
        customTitle: context.l10n.groupLoadFailedTitle,
        customMessage: context.l10n.activityLoadFailedMessage,
        onRetry: onRetry,
      ),
    );
  }
}

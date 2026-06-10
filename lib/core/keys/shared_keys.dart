import 'package:flutter/material.dart';

abstract final class SharedKeys {
  // ModuleHeader
  static const moduleHeaderBackButton = Key('shared_module_header_back_button');

  // OfflineBanner
  static const offlineBanner = Key('shared_offline_banner');

  // EmptyStateView
  static const emptyStateView = Key('shared_empty_state_view');
  static const emptyStateCtaButton = Key('shared_empty_state_cta_button');
  static const emptyStateSecondaryCta = Key('shared_empty_state_secondary_cta');

  // InviteCodeDisplay
  static const inviteCodeDisplay = Key('shared_invite_code_display');
  static const inviteCodeCopyButton = Key('shared_invite_code_copy_button');
  static const inviteCodeShareButton = Key('shared_invite_code_share_button');

  // LoadingButton — parameterized by label
  static Key loadingButton(String label) => Key('shared_loading_button_$label');
}

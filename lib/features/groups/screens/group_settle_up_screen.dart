import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group_model.dart';

/// Placeholder — full implementation in Plan 05-06.
///
/// Displays a group settle-up screen pre-filtered for a specific member
/// when [preSelectedMemberId] is provided (D-22 entry point 2).
class GroupSettleUpScreen extends ConsumerWidget {
  final String groupId;
  final Group group;

  /// D-22 entry point 2: pre-select a specific member to settle with.
  final String? preSelectedMemberId;

  const GroupSettleUpScreen({
    super.key,
    required this.groupId,
    required this.group,
    this.preSelectedMemberId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settle Up')),
      body: const Center(child: Text('Settle Up -- coming in Plan 06')),
    );
  }
}

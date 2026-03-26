import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Placeholder — full implementation in Plan 05-06.
///
/// Shows full paginated group activity log for a group.
class GroupActivityScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupActivityScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupActivityScreen> createState() =>
      _GroupActivityScreenState();
}

class _GroupActivityScreenState extends ConsumerState<GroupActivityScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group Activity')),
      body: const Center(child: Text('Group Activity -- coming in Plan 06')),
    );
  }
}

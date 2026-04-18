import 'package:flutter/material.dart';

import '../models/group_member_model.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

/// A tile widget for displaying a group member in a member list.
///
/// Shows the member's initial avatar, display name, and role badge.
/// The [isCurrentUser] flag appends "(You)" to the display name.
class GroupMemberTile extends StatelessWidget {
  final GroupMember member;
  final bool isCurrentUser;

  const GroupMemberTile({
    super.key,
    required this.member,
    this.isCurrentUser = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          // Avatar with initial
          CircleAvatar(
            radius: 20,
            backgroundColor: context.colors.inputFill,
            child: Text(
              member.displayName.isNotEmpty
                  ? member.displayName[0].toUpperCase()
                  : '?',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: context.colors.textSecondary,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          // Name and role badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCurrentUser
                      ? '${member.displayName} (You)'
                      : member.displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                // Role badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.inputFill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    member.role,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.colors.textSecondary,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

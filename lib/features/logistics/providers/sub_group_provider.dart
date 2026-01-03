import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../models/sub_group_model.dart';

/// Loading state for sub-group operations
final subGroupLoadingProvider = StateProvider<bool>((ref) => false);

/// Error state for sub-group operations
final subGroupErrorProvider = StateProvider<String?>((ref) => null);

/// Stream of sub-groups for a trip
final tripSubGroupsProvider = StreamProvider.family<List<SubGroup>, String>((
  ref,
  tripId,
) {
  SupabaseConfig.log('tripSubGroupsProvider: Starting stream for trip $tripId');

  return SupabaseConfig.client
      .from('sub_groups')
      .stream(primaryKey: ['id'])
      .eq('trip_id', tripId)
      .order('created_at', ascending: true)
      .asyncMap((data) async {
        SupabaseConfig.log(
          'tripSubGroupsProvider: Got ${data.length} sub_groups',
        );

        // For each sub-group, fetch members with profiles
        final subGroups = <SubGroup>[];
        for (final sg in data) {
          try {
            SupabaseConfig.log('Fetching members for sub_group ${sg['id']}');
            final membersData = await SupabaseConfig.client
                .from('sub_group_members')
                .select(
                  '*, participants!participant_id(*, profiles!user_id(display_name, avatar_url))',
                )
                .eq('sub_group_id', sg['id']);

            final members = (membersData as List)
                .map((m) => SubGroupMember.fromJson(m as Map<String, dynamic>))
                .toList();

            subGroups.add(SubGroup.fromJson(sg).copyWith(members: members));
          } catch (e) {
            SupabaseConfig.log(
              'Error fetching members for ${sg['id']}',
              error: e,
            );
            // Still add the sub-group without members
            subGroups.add(SubGroup.fromJson(sg));
          }
        }
        return subGroups;
      });
});

/// Sub-groups filtered by type
final subGroupsByTypeProvider =
    Provider.family<
      AsyncValue<List<SubGroup>>,
      ({String tripId, SubGroupType type})
    >((ref, params) {
      final allGroups = ref.watch(tripSubGroupsProvider(params.tripId));
      return allGroups.whenData(
        (groups) => groups.where((g) => g.type == params.type).toList(),
      );
    });

/// Sub-group service provider
final subGroupServiceProvider = Provider<SubGroupService>((ref) {
  return SubGroupService(ref);
});

/// Sub-group service for CRUD operations
class SubGroupService {
  final Ref _ref;

  SubGroupService(this._ref);

  SupabaseClient get _client => SupabaseConfig.client;

  /// Create a new sub-group
  Future<SubGroup?> createSubGroup({
    required String tripId,
    required String name,
    required SubGroupType type,
    int capacity = 4,
  }) async {
    _ref.read(subGroupLoadingProvider.notifier).state = true;
    _ref.read(subGroupErrorProvider.notifier).state = null;

    SupabaseConfig.log(
      'createSubGroup: $name (type: ${type.value}, capacity: $capacity)',
    );

    try {
      final data = await _client
          .from('sub_groups')
          .insert({
            'trip_id': tripId,
            'name': name,
            'type': type.value,
            'capacity': capacity,
          })
          .select()
          .single();

      SupabaseConfig.log('createSubGroup: SUCCESS - id: ${data['id']}');
      _ref.read(subGroupLoadingProvider.notifier).state = false;
      return SubGroup.fromJson(data);
    } catch (e) {
      SupabaseConfig.log('createSubGroup: FAILED', error: e);
      _ref.read(subGroupErrorProvider.notifier).state = e.toString();
      _ref.read(subGroupLoadingProvider.notifier).state = false;
      return null;
    }
  }

  /// Update a sub-group
  Future<bool> updateSubGroup(
    String subGroupId, {
    String? name,
    int? capacity,
  }) async {
    _ref.read(subGroupLoadingProvider.notifier).state = true;
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (capacity != null) updates['capacity'] = capacity;

      if (updates.isEmpty) return true;

      await _client.from('sub_groups').update(updates).eq('id', subGroupId);
      _ref.read(subGroupLoadingProvider.notifier).state = false;
      return true;
    } catch (e) {
      _ref.read(subGroupErrorProvider.notifier).state = e.toString();
      _ref.read(subGroupLoadingProvider.notifier).state = false;
      return false;
    }
  }

  /// Delete a sub-group
  Future<bool> deleteSubGroup(String subGroupId) async {
    SupabaseConfig.log('deleteSubGroup: $subGroupId');
    try {
      await _client.from('sub_groups').delete().eq('id', subGroupId);
      SupabaseConfig.log('deleteSubGroup: SUCCESS');
      return true;
    } catch (e) {
      SupabaseConfig.log('deleteSubGroup: FAILED', error: e);
      _ref.read(subGroupErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Add a member to a sub-group
  Future<bool> addMember({
    required String subGroupId,
    required String participantId,
  }) async {
    debugPrint(
      '>>> addMember START: participant $participantId to subgroup $subGroupId',
    );
    try {
      final response = await _client.from('sub_group_members').insert({
        'sub_group_id': subGroupId,
        'participant_id': participantId,
      }).select();
      debugPrint('>>> addMember SUCCESS: $response');
      return true;
    } on PostgrestException catch (e) {
      debugPrint('>>> addMember POSTGREST ERROR:');
      debugPrint('>>>   message: ${e.message}');
      debugPrint('>>>   code: ${e.code}');
      debugPrint('>>>   details: ${e.details}');
      debugPrint('>>>   hint: ${e.hint}');
      _ref.read(subGroupErrorProvider.notifier).state = e.message;
      return false;
    } catch (e, stackTrace) {
      debugPrint('>>> addMember GENERIC ERROR: $e');
      debugPrint('>>> Stack: $stackTrace');
      _ref.read(subGroupErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Remove a member from a sub-group
  Future<bool> removeMember(String memberId) async {
    SupabaseConfig.log('removeMember: $memberId');
    try {
      await _client.from('sub_group_members').delete().eq('id', memberId);
      SupabaseConfig.log('removeMember: SUCCESS');
      return true;
    } catch (e) {
      SupabaseConfig.log('removeMember: FAILED', error: e);
      _ref.read(subGroupErrorProvider.notifier).state = e.toString();
      return false;
    }
  }

  /// Get members of a sub-group
  Future<List<SubGroupMember>> getMembers(String subGroupId) async {
    SupabaseConfig.log('getMembers: for subgroup $subGroupId');
    try {
      final data = await _client
          .from('sub_group_members')
          .select(
            '*, participants!participant_id(*, profiles!user_id(display_name, avatar_url))',
          )
          .eq('sub_group_id', subGroupId);

      SupabaseConfig.log('getMembers: Got ${data.length} members');
      return data.map((m) => SubGroupMember.fromJson(m)).toList();
    } catch (e) {
      SupabaseConfig.log('getMembers: FAILED', error: e);
      return [];
    }
  }

  /// Get sub-groups for a user in a trip
  Future<List<SubGroup>> getUserSubGroups(String tripId, String userId) async {
    SupabaseConfig.log('getUserSubGroups: trip $tripId, user $userId');
    try {
      // Get all sub-group memberships for this user
      final memberships = await _client
          .from('sub_group_members')
          .select('sub_group_id')
          .eq(
            'participant_id',
            userId,
          ); // userId here is actually participantId in this context

      if ((memberships as List).isEmpty) {
        SupabaseConfig.log('getUserSubGroups: No memberships found');
        return [];
      }

      final subGroupIds = memberships.map((m) => m['sub_group_id']).toList();

      // Get sub-groups for this trip that user is a member of
      final data = await _client
          .from('sub_groups')
          .select()
          .eq('trip_id', tripId)
          .inFilter('id', subGroupIds);

      SupabaseConfig.log('getUserSubGroups: Found ${data.length} sub-groups');
      return data.map((sg) => SubGroup.fromJson(sg)).toList();
    } catch (e) {
      SupabaseConfig.log('getUserSubGroups: FAILED', error: e);
      return [];
    }
  }
}

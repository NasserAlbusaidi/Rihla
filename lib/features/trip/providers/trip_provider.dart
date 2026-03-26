import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/services/cache_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/trip_model.dart';

/// Trip loading state
final tripLoadingProvider = StateProvider<bool>((ref) => false);

/// Trip error state
final tripErrorProvider = StateProvider<String?>((ref) => null);

/// Current selected trip
final currentTripProvider = StateProvider<Trip?>((ref) => null);

/// User's trips — reads from SQLite cache.
///
/// @Deprecated('Will be migrated to Firestore stream in 04-05.')
final userTripsProvider = StreamProvider<List<Trip>>((ref) async* {
  yield await CacheService.getCachedTrips();
});

/// Trip participants — reads from SQLite cache.
///
/// @Deprecated('Will be migrated to Firestore stream in 04-05.')
final tripLogisticsParticipantsProvider =
    StreamProvider.family<List<Participant>, String>((ref, tripId) async* {
  yield await CacheService.getCachedParticipants(tripId);
});

/// Provider for the current user's participant record in a trip
final currentParticipantProvider = Provider.family<Participant?, String>((
  ref,
  tripId,
) {
  final user = ref.watch(currentUserProvider);
  debugPrint('[PARTICIPANT] currentParticipantProvider: tripId=$tripId, '
      'supabaseUser=${user?.id}');
  if (user == null) {
    debugPrint('[PARTICIPANT]   → user is null, returning null');
    return null;
  }

  final participantsAsync = ref.watch(
    tripLogisticsParticipantsProvider(tripId),
  );
  return participantsAsync.maybeWhen(
    data: (participants) {
      debugPrint('[PARTICIPANT]   participants loaded: ${participants.length}');
      for (final p in participants) {
        debugPrint('[PARTICIPANT]     id=${p.id}, userId=${p.userId}, '
            'name=${p.displayName}, role=${p.role}');
      }
      final match = participants.where((p) => p.userId == user.id).firstOrNull;
      debugPrint('[PARTICIPANT]   → match for userId=${user.id}: '
          '${match != null ? "FOUND (${match.id})" : "NOT FOUND"}');
      return match;
    },
    orElse: () {
      debugPrint('[PARTICIPANT]   → participants not loaded yet');
      return null;
    },
  );
});

/// @Deprecated('Supabase sync removed — Firestore handles offline persistence.')
/// Provider retained for backward compat with screens that watch it.
/// Will be removed in 04-05 when screens are fully migrated.
final tripSeedProvider = FutureProvider<void>((ref) async {
  // No-op: Firestore offline persistence replaces Supabase sync queue.
  // This provider is retained so screens that watch it continue to compile.
});

/// Trip service provider
final tripServiceProvider = Provider<TripService>((ref) {
  return TripService(ref);
});

/// Trip service for CRUD operations
class TripService {
  final Ref _ref;

  TripService(this._ref);

  SupabaseClient get _client => SupabaseConfig.client;

  /// Generate a unique 6-character invite code
  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Removed confusing chars
    final random = Random.secure();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Create a new trip
  Future<Trip?> createTrip({
    required String name,
    required List<String> memberNames,
    required int creatorIndex,
    TripModules modules = const TripModules(),
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _ref.read(tripLoadingProvider.notifier).state = true;
    _ref.read(tripErrorProvider.notifier).state = null;

    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Generate unique invite code with retry
      String inviteCode = _generateInviteCode();
      bool isUnique = false;
      int attempts = 0;

      while (!isUnique && attempts < 10) {
        final existing = await _client
            .from('trips')
            .select('id')
            .eq('invite_code', inviteCode)
            .maybeSingle();

        if (existing == null) {
          isUnique = true;
        } else {
          inviteCode = _generateInviteCode();
          attempts++;
        }
      }

      if (!isUnique) {
        throw Exception('Could not generate unique invite code');
      }

      // Create trip
      final tripData = await _client
          .from('trips')
          .insert({
            'name': name,
            'invite_code': inviteCode,
            'leader_id': userId,
            'modules': modules.toJson(),
            if (startDate != null)
              'start_date': startDate.toIso8601String().split('T').first,
            if (endDate != null)
              'end_date': endDate.toIso8601String().split('T').first,
          })
          .select()
          .single();

      final trip = Trip.fromJson(tripData);

      // Insert all members as participants
      for (int i = 0; i < memberNames.length; i++) {
        final isCreator = i == creatorIndex;
        await _client.from('participants').insert({
          'trip_id': trip.id,
          'user_id': isCreator ? userId : null,
          'role': isCreator ? 'LEADER' : 'MEMBER',
          'display_name': memberNames[i],
        });
      }

      // Cache the new trip locally
      await CacheService.cacheTrip(trip);

      _ref.read(tripLoadingProvider.notifier).state = false;
      _ref.read(currentTripProvider.notifier).state = trip;

      return trip;
    } catch (e) {
      _ref.read(tripErrorProvider.notifier).state = e.toString();
      _ref.read(tripLoadingProvider.notifier).state = false;
      return null;
    }
  }

  /// Join a trip by invite code
  Future<Trip?> joinTrip(String inviteCode) async {
    _ref.read(tripLoadingProvider.notifier).state = true;
    _ref.read(tripErrorProvider.notifier).state = null;

    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Find trip by invite code
      final tripData = await _client
          .from('trips')
          .select()
          .eq('invite_code', inviteCode.toUpperCase())
          .maybeSingle();

      if (tripData == null) {
        throw Exception('Trip not found. Please check the invite code.');
      }

      final trip = Trip.fromJson(tripData);

      // Check if already a participant
      final existing = await _client
          .from('participants')
          .select('id')
          .eq('trip_id', trip.id)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        // Already a member — cache and return the trip
        await CacheService.cacheTrip(trip);
        _ref.read(tripLoadingProvider.notifier).state = false;
        _ref.read(currentTripProvider.notifier).state = trip;
        return trip;
      }

      // Add user as participant
      await _client.from('participants').insert({
        'trip_id': trip.id,
        'user_id': userId,
        'role': 'MEMBER',
      });

      // Cache the trip locally
      await CacheService.cacheTrip(trip);

      _ref.read(tripLoadingProvider.notifier).state = false;
      _ref.read(currentTripProvider.notifier).state = trip;

      return trip;
    } catch (e) {
      _ref.read(tripErrorProvider.notifier).state = e.toString();
      _ref.read(tripLoadingProvider.notifier).state = false;
      return null;
    }
  }

  /// Find trip and return unclaimed participant names
  Future<({Trip trip, List<Participant> unclaimed})?> findTripForJoin(String inviteCode) async {
    _ref.read(tripLoadingProvider.notifier).state = true;
    _ref.read(tripErrorProvider.notifier).state = null;

    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final tripData = await _client
          .from('trips')
          .select()
          .eq('invite_code', inviteCode.toUpperCase())
          .maybeSingle();

      if (tripData == null) {
        throw Exception('Trip not found. Please check the invite code.');
      }

      final trip = Trip.fromJson(tripData);

      // Check if already a participant
      final existing = await _client
          .from('participants')
          .select('id')
          .eq('trip_id', trip.id)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        _ref.read(tripLoadingProvider.notifier).state = false;
        _ref.read(currentTripProvider.notifier).state = trip;
        return null; // Already a member — caller should navigate directly
      }

      // Get unclaimed participants
      final participantsData = await _client
          .from('participants')
          .select()
          .eq('trip_id', trip.id)
          .isFilter('user_id', null);

      final unclaimed = participantsData
          .map((json) => Participant.fromJson(json))
          .toList();

      _ref.read(tripLoadingProvider.notifier).state = false;
      return (trip: trip, unclaimed: unclaimed);
    } catch (e) {
      _ref.read(tripErrorProvider.notifier).state = e.toString();
      _ref.read(tripLoadingProvider.notifier).state = false;
      return null;
    }
  }

  /// Claim a participant name in a trip
  Future<Trip?> claimParticipant(String tripId, String participantId) async {
    _ref.read(tripLoadingProvider.notifier).state = true;
    _ref.read(tripErrorProvider.notifier).state = null;

    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      await _client
          .from('participants')
          .update({'user_id': userId})
          .eq('id', participantId);

      final trip = await getTripById(tripId);
      // Cache trip locally after claiming
      if (trip != null) {
        await CacheService.cacheTrip(trip);
      }
      _ref.read(tripLoadingProvider.notifier).state = false;
      _ref.read(currentTripProvider.notifier).state = trip;
      return trip;
    } catch (e) {
      _ref.read(tripErrorProvider.notifier).state = e.toString();
      _ref.read(tripLoadingProvider.notifier).state = false;
      return null;
    }
  }

  /// Get trip by ID
  Future<Trip?> getTripById(String tripId) async {
    try {
      final tripData = await _client
          .from('trips')
          .select()
          .eq('id', tripId)
          .single();

      return Trip.fromJson(tripData);
    } catch (e) {
      return null;
    }
  }

  /// Update trip details (leader only)
  Future<bool> updateTrip(
    String tripId, {
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    String? icon,
  }) async {
    try {
      // Verify current user is the leader
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;
      final trip = await getTripById(tripId);
      if (trip == null || trip.leaderId != userId) {
        _ref.read(tripErrorProvider.notifier).state =
            'Only the trip leader can edit this trip';
        return false;
      }

      final updates = <String, dynamic>{};
      if (name != null && name.isNotEmpty) {
        updates['name'] = name;
      }
      if (startDate != null) {
        updates['start_date'] = startDate.toIso8601String().split('T').first;
      }
      if (endDate != null) {
        updates['end_date'] = endDate.toIso8601String().split('T').first;
      }
      if (icon != null && icon.isNotEmpty) {
        updates['icon'] = icon;
      }

      if (updates.isEmpty) return true;

      SupabaseConfig.log('Updating trip $tripId with: $updates');

      await _client.from('trips').update(updates).eq('id', tripId);
      // Re-fetch and cache updated trip
      final updated = await getTripById(tripId);
      if (updated != null) {
        await CacheService.cacheTrip(updated);
      }
      SupabaseConfig.log('Trip update successful');
      return true;
    } catch (e) {
      SupabaseConfig.log('Trip update error', error: e);
      return false;
    }
  }

  /// Update trip modules
  Future<bool> updateModules(String tripId, TripModules modules) async {
    try {
      await _client
          .from('trips')
          .update({'modules': modules.toJson()})
          .eq('id', tripId);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Delete a trip (leader only)
  Future<bool> deleteTrip(String tripId) async {
    try {
      // Verify current user is the leader
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;
      final trip = await getTripById(tripId);
      if (trip == null || trip.leaderId != userId) {
        _ref.read(tripErrorProvider.notifier).state =
            'Only the trip leader can delete this trip';
        return false;
      }

      SupabaseConfig.log('deleteTrip: $tripId');
      await _client.from('trips').delete().eq('id', tripId);

      // Remove from local cache
      await CacheService.deleteTrip(tripId);

      SupabaseConfig.log('deleteTrip: SUCCESS');
      return true;
    } catch (e) {
      SupabaseConfig.log('deleteTrip: FAILED', error: e);
      return false;
    }
  }

  /// Get participants of a trip
  Future<List<Participant>> getParticipants(String tripId) async {
    try {
      final data = await _client
          .from('participants')
          .select('*')
          .eq('trip_id', tripId);

      return (data).map((json) => Participant.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Check if current user is the leader of a trip
  Future<bool> isLeader(String tripId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final trip = await getTripById(tripId);
      return trip?.leaderId == userId;
    } catch (e) {
      return false;
    }
  }
}

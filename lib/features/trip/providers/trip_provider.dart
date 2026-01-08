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

/// User's trips stream with offline caching
final userTripsProvider = StreamProvider<List<Trip>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value([]);

  return SupabaseConfig.client
      .from('participants')
      .stream(primaryKey: ['id'])
      .eq('user_id', user.id)
      .asyncMap((participations) async {
        if (participations.isEmpty) {
          // Try to get cached trips if no online data
          return await CacheService.getCachedTrips();
        }

        final tripIds = participations
            .map((p) => p['trip_id'] as String)
            .toList();

        final tripsData = await SupabaseConfig.client
            .from('trips')
            .select()
            .inFilter('id', tripIds)
            .order('created_at', ascending: false);

        final trips = (tripsData).map((json) => Trip.fromJson(json)).toList();

        // Cache trips for offline access
        for (final trip in trips) {
          await CacheService.cacheTrip(trip);
        }

        return trips;
      })
      .handleError((error) async {
        // On error (offline), return cached trips
        debugPrint('📡 Network error, using cached trips: $error');
        return await CacheService.getCachedTrips();
      });
});

/// Trip participants stream for logistics (with profiles)
final tripLogisticsParticipantsProvider =
    StreamProvider.family<List<Participant>, String>((ref, tripId) {
      return SupabaseConfig.client
          .from('participants')
          .stream(primaryKey: ['id'])
          .eq('trip_id', tripId)
          .asyncMap((data) async {
            if (data.isEmpty) return <Participant>[];

            final result = await SupabaseConfig.client
                .from('participants')
                .select('*, profiles!user_id(display_name, avatar_url)')
                .eq('trip_id', tripId);

            return (result).map((json) => Participant.fromJson(json)).toList();
          });
    });

/// Provider for the current user's participant record in a trip
final currentParticipantProvider = Provider.family<Participant?, String>((
  ref,
  tripId,
) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final participantsAsync = ref.watch(
    tripLogisticsParticipantsProvider(tripId),
  );
  return participantsAsync.maybeWhen(
    data: (participants) {
      return participants.where((p) => p.userId == user.id).firstOrNull;
    },
    orElse: () => null,
  );
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

      // Add creator as participant with LEADER role
      await _client.from('participants').insert({
        'trip_id': trip.id,
        'user_id': userId,
        'role': 'LEADER',
      });

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
        // Already a member, just return the trip
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

  /// Update trip details
  Future<bool> updateTrip(
    String tripId, {
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    String? icon,
  }) async {
    try {
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
      SupabaseConfig.log('deleteTrip: $tripId');
      // Trip deletion cascades to all related tables (participants, expenses, etc.)
      // based on ON DELETE CASCADE in schema.
      await _client.from('trips').delete().eq('id', tripId);

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
          .select('*, profiles!user_id(display_name, avatar_url)')
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

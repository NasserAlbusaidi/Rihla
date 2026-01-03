import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase client configuration and initialization
class SupabaseConfig {
  static SupabaseClient get client => Supabase.instance.client;

  /// Initialize Supabase with environment variables
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: const String.fromEnvironment('SUPABASE_URL'),
      anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
      debug: kDebugMode, // Only enable debug logging in debug builds
    );
    log('Supabase initialized');
  }

  /// Get the current authenticated user
  static User? get currentUser => client.auth.currentUser;

  /// Check if user is authenticated
  static bool get isAuthenticated => currentUser != null;

  /// Auth state changes stream
  static Stream<AuthState> get authStateChanges =>
      client.auth.onAuthStateChange;

  /// Log helper for database operations (only logs in debug mode)
  static void log(String message, {Object? error, StackTrace? stackTrace}) {
    if (!kDebugMode) return;

    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    dev.log('[$timestamp] 🗄️ $message', name: 'Supabase');
    if (error != null) {
      dev.log('[$timestamp] ❌ Error: $error', name: 'Supabase');
      if (stackTrace != null) {
        dev.log('Stack: $stackTrace', name: 'Supabase');
      }
    }
  }
}

/// Extension for logging Supabase operations
extension SupabaseLogging on SupabaseClient {
  /// Log and execute a query
  Future<T> logQuery<T>(String operation, Future<T> Function() query) async {
    SupabaseConfig.log('$operation - starting...');
    try {
      final result = await query();
      SupabaseConfig.log('$operation - success');
      return result;
    } catch (e, stack) {
      SupabaseConfig.log('$operation - FAILED', error: e, stackTrace: stack);
      rethrow;
    }
  }
}

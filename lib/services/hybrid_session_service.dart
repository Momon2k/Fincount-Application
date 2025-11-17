import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/session.dart';
import 'api_service.dart';
import 'session_service.dart';

/// Hybrid service that handles both local and remote data storage
/// Falls back to local storage when API is unavailable
class HybridSessionService {
  static const String _syncStatusKey = 'sync_status';
  static const String _lastSyncKey = 'last_sync';

  final SessionService _localService = SessionService();

  /// Save session with automatic sync attempt
  Future<void> saveSession(Session session) async {
    print('=== Starting saveSession ===');
    print('Session ID: ${session.id}');
    print('Batch ID: ${session.batchId}');

    // Always save locally first
    await _localService.saveSession(session);
    print('✓ Session saved locally');

    // Try to sync with API
    try {
      print('Checking connection...');
      final isConnected = await ApiService.checkConnection();
      print('Connection status: $isConnected');

      if (isConnected) {
        print('Attempting to create session on API...');
        final result = await ApiService.createSession(session);
        print('✓ Session created on API: $result');
        await _markAsSynced(session.id);
        print('✓ Session marked as synced');
      } else {
        print('⚠ Device is offline, marking as unsynced');
        await _markAsUnsynced(session.id);
      }
    } catch (e, stackTrace) {
      print('❌ Failed to sync session to API: $e');
      print('Stack trace: $stackTrace');
      await _markAsUnsynced(session.id);
      rethrow; // Re-throw to see the error in the UI
    }
  }

  /// Get all sessions (prioritize API if available, fallback to local)
  Future<List<Session>> getAllSessions() async {
    try {
      final isConnected = await ApiService.checkConnection();
      if (isConnected) {
        final apiSessions = await ApiService.getAllSessions();
        // Update local storage with API data
        await _updateLocalFromApi(apiSessions);
        return apiSessions;
      }
    } catch (e) {
      print('Failed to fetch from API, using local data: $e');
    }

    // Fallback to local data
    return await _localService.getAllSessions();
  }

  /// Get sessions for a specific batch
  Future<List<Session>> getBatchSessions(String batchId) async {
    try {
      final isConnected = await ApiService.checkConnection();
      if (isConnected) {
        return await ApiService.getBatchSessions(batchId);
      }
    } catch (e) {
      print('Failed to fetch batch sessions from API: $e');
    }

    // Fallback to local data
    return await _localService.getBatchSessions(batchId);
  }

  /// Get all batches
  Future<dynamic> getAllBatches() async {
    try {
      final isConnected = await ApiService.checkConnection();
      if (isConnected) {
        // API now returns List<Batch>
        return await ApiService.getAllBatches();
      }
    } catch (e) {
      print('Failed to fetch batches from API: $e');
    }

    // Fallback to local data (returns Map<String, dynamic>)
    return await _localService.getAllBatches();
  }

  /// Sync all local data with the API
  Future<bool> syncAllData() async {
    try {
      final isConnected = await ApiService.checkConnection();
      if (!isConnected) {
        return false;
      }

      // Get all local sessions
      final localSessions = await _localService.getAllSessions();
      final unsyncedSessions = await _getUnsyncedSessions(localSessions);

      if (unsyncedSessions.isNotEmpty) {
        // Sync unsynced sessions
        for (final session in unsyncedSessions) {
          try {
            await ApiService.createSession(session);
            await _markAsSynced(session.id);
          } catch (e) {
            print('Failed to sync session ${session.id}: $e');
          }
        }
      }

      // Get latest data from API and update local storage
      final apiSessions = await ApiService.getAllSessions();
      await _updateLocalFromApi(apiSessions);

      await _updateLastSyncTime();
      return true;
    } catch (e) {
      print('Sync failed: $e');
      return false;
    }
  }

  /// Check if device is online and can connect to API
  Future<bool> isOnline() async {
    return await ApiService.checkConnection();
  }

  /// Get sync status information
  Future<Map<String, dynamic>> getSyncStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_lastSyncKey);
    final localSessions = await _localService.getAllSessions();
    final unsyncedSessions = await _getUnsyncedSessions(localSessions);

    return {
      'lastSync': lastSync,
      'totalSessions': localSessions.length,
      'unsyncedSessions': unsyncedSessions.length,
      'isOnline': await isOnline(),
    };
  }

  /// Force refresh from API (useful for manual refresh)
  Future<List<Session>> refreshFromApi() async {
    final apiSessions = await ApiService.getAllSessions();
    await _updateLocalFromApi(apiSessions);
    return apiSessions;
  }

  // Private helper methods

  Future<void> _markAsSynced(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final syncedIds = prefs.getStringList('synced_sessions') ?? [];
    if (!syncedIds.contains(sessionId)) {
      syncedIds.add(sessionId);
      await prefs.setStringList('synced_sessions', syncedIds);
    }
  }

  Future<void> _markAsUnsynced(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final syncedIds = prefs.getStringList('synced_sessions') ?? [];
    syncedIds.remove(sessionId);
    await prefs.setStringList('synced_sessions', syncedIds);
  }

  Future<List<Session>> _getUnsyncedSessions(List<Session> allSessions) async {
    final prefs = await SharedPreferences.getInstance();
    final syncedIds = prefs.getStringList('synced_sessions') ?? [];
    return allSessions
        .where((session) => !syncedIds.contains(session.id))
        .toList();
  }

  Future<void> _updateLocalFromApi(List<Session> apiSessions) async {
    // This is a simplified approach - in production you might want more sophisticated merging
    final prefs = await SharedPreferences.getInstance();
    final sessionStrings =
        apiSessions.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList('sessions', sessionStrings);

    // Mark all API sessions as synced
    final syncedIds = apiSessions.map((s) => s.id).toList();
    await prefs.setStringList('synced_sessions', syncedIds);
  }

  Future<void> _updateLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }
}
